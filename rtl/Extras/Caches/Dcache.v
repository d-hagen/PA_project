module dcache #(
    parameter XLEN      = 32,
    parameter LINE_BITS = 16
)(
    input  wire                 clk,
    input  wire                 rst,

    // MEM stage (load)
    input  wire                 MEM_ld,
    input  wire                 MEM_byt,        // 1=byte, 0=word
    input  wire [XLEN-1:0]      MEM_alu_out,
    input  wire [XLEN-1:0]      MEM_b2,
    output reg  [XLEN-1:0]      MEM_data_mem,
    output reg                  dcache_stall,

    // Store buffer forward
    input  wire [3:0]           sb_fwd_mask,
    input  wire [31:0]          sb_fwd_data,
    input  wire                 sb_all_hit,

    // Store-buffer drain
    input  wire                 store_request,
    input  wire [19:0]          store_request_address, // PA[19:0], word-aligned
    input  wire [31:0]          store_request_wdata,
    input  wire [3:0]           store_request_wmask,
    output reg                  store_valid,

    // DTLB (load)
    input  wire                 Dtlb_addr_valid,

    // Backing memory (read line)
    output reg                  Dc_mem_req,
    output reg  [LINE_BITS-1:0] Dc_mem_addr,
    input  wire [127:0]         MEM_data_line,
    input  wire                 MEM_mem_valid,

    // Writeback
    output reg                  Dc_wb_we,
    output reg  [LINE_BITS-1:0] Dc_wb_addr,
    output reg  [127:0]         Dc_wb_wline,

    // PTW
    input  wire                 Ptw_req,
    input  wire [19:0]          Ptw_addr,
    output reg  [31:0]          Ptw_rdata,
    output reg                  Ptw_valid,

    // Status
    output wire                 Dc_busy,

    // PTW latch
    output wire                 Ptw_accepted,

    // Data valid
    output reg                  dcache_data_valid
);

    // ============================================================
    // Cache arrays
    // ============================================================
    reg                     valid [0:3];
    reg                     dirty [0:3];
    reg [LINE_BITS-1:0]     tag   [0:3];
    reg [7:0]               data_b[0:3][0:15];

    reg [1:0] fifo_ptr;

    integer i;
    integer b;

    // ============================================================
    // PTW state
    // ============================================================
    reg                   ptw_busy;
    reg [19:0]            ptw_addr_q;
    wire [LINE_BITS-1:0]  ptw_line  = Ptw_addr[19:4];

    // ============================================================
    // Load modes
    // ============================================================
    wire load_bypass        = MEM_ld && Dtlb_addr_valid && sb_all_hit;
    wire op_active_load     = MEM_ld && Dtlb_addr_valid && !sb_all_hit;
    wire mem_needs_xlate    = MEM_ld && !Dtlb_addr_valid;

    // ============================================================
    // Store addr safe
    // ============================================================
    wire [19:0] store_addr_safe   = store_request ? store_request_address : 20'd0;
    wire [LINE_BITS-1:0] store_line = store_addr_safe[19:4];
    wire [3:0]           store_off0 = store_addr_safe[3:0];

    // ============================================================
    // Store miss state
    // ============================================================
    reg                 sb_store_wait;
    reg [LINE_BITS-1:0] sb_store_line_q;
    reg [3:0]           sb_store_off_q;
    reg [31:0]          sb_store_wdata_q;
    reg [3:0]           sb_store_wmask_q;

    // ============================================================
    // Load miss FSM
    // ============================================================
    localparam LD_IDLE  = 2'd0;
    localparam LD_WAIT0 = 2'd1;
    localparam LD_WAIT1 = 2'd2;
    reg [1:0] ld_state;

    reg [19:0] ld_addr_q;
    reg        ld_byt_q;

    // ============================================================
    // Effective addr
    // ============================================================
    wire [19:0] eff_addr20 =
        (ld_state == LD_IDLE) ? MEM_alu_out[19:0] : ld_addr_q;

    wire [LINE_BITS-1:0] eff_line0 = eff_addr20[19:4];
    wire [LINE_BITS-1:0] eff_line1 = eff_addr20[19:4] + 1'b1;
    wire [3:0]           eff_off   = eff_addr20[3:0];

    wire eff_is_word    = !((ld_state==LD_IDLE) ? MEM_byt : ld_byt_q);
    wire eff_cross_line = eff_is_word && (eff_off > 4'd12);

    // ============================================================
    // Hit check
    // ============================================================
    reg       hit0, hit1;
    reg [1:0] hit0_idx, hit1_idx;

    reg       store_hit;
    reg [1:0] store_hit_idx;

    always @(*) begin
        hit0 = 1'b0; hit1 = 1'b0;
        hit0_idx = 2'd0; hit1_idx = 2'd0;
        store_hit = 1'b0; store_hit_idx = 2'd0;

        for (i = 0; i < 4; i = i + 1) begin
            if (valid[i] && tag[i] == eff_line0) begin
                hit0 = 1'b1;
                hit0_idx = i[1:0];
            end
            if (valid[i] && tag[i] == eff_line1) begin
                hit1 = 1'b1;
                hit1_idx = i[1:0];
            end
            if (valid[i] && tag[i] == store_line) begin
                store_hit = 1'b1;
                store_hit_idx = i[1:0];
            end
        end
    end

    wire store_need_service = store_request && !store_hit;

    // ============================================================
    // Miss needs
    // ============================================================
    wire need_fetch_line0 = op_active_load && !hit0;
    wire need_fetch_line1 = op_active_load && eff_cross_line && !hit1;

    // ============================================================
    // Busy
    // ============================================================
    wire mem_waiting = ptw_busy | sb_store_wait | (ld_state != LD_IDLE);
    assign Dc_busy   = Dc_mem_req | mem_waiting | MEM_mem_valid;

    // ============================================================
    // Who uses memory
    // ============================================================
    wire ptw_can_issue =
        !MEM_mem_valid && !ptw_busy && Ptw_req &&
        !sb_store_wait && (ld_state == LD_IDLE);

    wire load_can_issue =
        !MEM_mem_valid && !ptw_can_issue &&
        (ld_state == LD_IDLE) && op_active_load &&
        (need_fetch_line0 || need_fetch_line1) &&
        !sb_store_wait && !ptw_busy;

    wire store_can_issue =
        !MEM_mem_valid && !ptw_can_issue && !load_can_issue &&
        store_need_service && !sb_store_wait &&
        (ld_state == LD_IDLE) && !ptw_busy;

    // ============================================================
    // PTW accepted
    // ============================================================
    reg ptw_accepted_r;
    assign Ptw_accepted = ptw_accepted_r;

    // ============================================================
    // Evict pack
    // ============================================================
    reg [127:0] evict_line_pack;
    always @(*) begin
        evict_line_pack = 128'd0;
        for (b = 0; b < 16; b = b + 1)
            evict_line_pack[8*b +: 8] = data_b[fifo_ptr][b];
    end

    // ============================================================
    // Store helper
    // ============================================================
    task automatic apply_masked_store(
        input [1:0] idx_line,
        input [3:0] lane0_off,
        input [31:0] wdata,
        input [3:0]  wmask
    );
    begin
        if (wmask[0]) data_b[idx_line][lane0_off + 4'd0] <= wdata[7:0];
        if (wmask[1]) data_b[idx_line][lane0_off + 4'd1] <= wdata[15:8];
        if (wmask[2]) data_b[idx_line][lane0_off + 4'd2] <= wdata[23:16];
        if (wmask[3]) data_b[idx_line][lane0_off + 4'd3] <= wdata[31:24];
    end
    endtask

    // ============================================================
    // Sequential
    // ============================================================
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 4; i = i + 1) begin
                valid[i] <= 1'b0;
                dirty[i] <= 1'b0;
                tag[i]   <= {LINE_BITS{1'b0}};
                for (b = 0; b < 16; b = b + 1)
                    data_b[i][b] <= 8'd0;
            end
            fifo_ptr <= 2'd0;

            Dc_wb_we    <= 1'b0;
            Dc_wb_addr  <= {LINE_BITS{1'b0}};
            Dc_wb_wline <= 128'd0;

            ptw_busy   <= 1'b0;
            ptw_addr_q <= 20'd0;
            Ptw_valid  <= 1'b0;
            Ptw_rdata  <= 32'd0;

            store_valid <= 1'b0;

            sb_store_wait    <= 1'b0;
            sb_store_line_q  <= {LINE_BITS{1'b0}};
            sb_store_off_q   <= 4'd0;
            sb_store_wdata_q <= 32'd0;
            sb_store_wmask_q <= 4'd0;

            ld_state   <= LD_IDLE;
            ld_addr_q  <= 20'd0;
            ld_byt_q   <= 1'b0;

            ptw_accepted_r <= 1'b0;

        end else begin
            Dc_wb_we       <= 1'b0;
            Ptw_valid      <= 1'b0;
            store_valid    <= 1'b0;
            ptw_accepted_r <= 1'b0;

            // PTW latch
            if (ptw_can_issue) begin
                ptw_busy       <= 1'b1;
                ptw_addr_q     <= Ptw_addr;
                ptw_accepted_r <= 1'b1;
            end

            // Mem req launch
            if (Dc_mem_req && !MEM_mem_valid) begin
                if (load_can_issue) begin
                    ld_addr_q <= MEM_alu_out[19:0];
                    ld_byt_q  <= MEM_byt;
                    ld_state  <= need_fetch_line0 ? LD_WAIT0 : LD_WAIT1;
                end
                if (store_can_issue) begin
                    sb_store_wait    <= 1'b1;
                    sb_store_line_q  <= store_line;
                    sb_store_off_q   <= store_off0;
                    sb_store_wdata_q <= store_request_wdata;
                    sb_store_wmask_q <= store_request_wmask;
                end
            end

            // Mem return
            if (MEM_mem_valid) begin
                if (ptw_busy) begin
                    case (ptw_addr_q[3:2])
                        2'b00: Ptw_rdata <= MEM_data_line[31:0];
                        2'b01: Ptw_rdata <= MEM_data_line[63:32];
                        2'b10: Ptw_rdata <= MEM_data_line[95:64];
                        2'b11: Ptw_rdata <= MEM_data_line[127:96];
                    endcase
                    Ptw_valid <= 1'b1;
                    ptw_busy  <= 1'b0;
                end else begin
                    // evict wb
                    if (valid[fifo_ptr] && dirty[fifo_ptr]) begin
                        Dc_wb_we    <= 1'b1;
                        Dc_wb_addr  <= tag[fifo_ptr];
                        Dc_wb_wline <= evict_line_pack;
                    end

                    // store refill
                    if (sb_store_wait) begin
                        valid[fifo_ptr] <= 1'b1;
                        dirty[fifo_ptr] <= 1'b1;
                        tag[fifo_ptr]   <= sb_store_line_q;

                        for (b = 0; b < 16; b = b + 1)
                            data_b[fifo_ptr][b] <= MEM_data_line[8*b +: 8];

                        apply_masked_store(
                            fifo_ptr,
                            sb_store_off_q,
                            sb_store_wdata_q,
                            sb_store_wmask_q
                        );

                        store_valid   <= 1'b1;
                        sb_store_wait <= 1'b0;
                        fifo_ptr      <= fifo_ptr + 1'b1;

                    end else if (ld_state != LD_IDLE) begin
                        valid[fifo_ptr] <= 1'b1;
                        dirty[fifo_ptr] <= 1'b0;
                        tag[fifo_ptr]   <= (ld_state == LD_WAIT0)
                                           ? ld_addr_q[19:4]
                                           : ld_addr_q[19:4] + 1'b1;

                        for (b = 0; b < 16; b = b + 1)
                            data_b[fifo_ptr][b] <= MEM_data_line[8*b +: 8];

                        fifo_ptr <= fifo_ptr + 1'b1;
                        ld_state <= LD_IDLE;
                    end
                end
            end

            // Store hit
            if (!op_active_load && !load_bypass && !mem_needs_xlate &&
                store_request && !MEM_mem_valid &&
                !sb_store_wait && !ptw_busy &&
                (ld_state == LD_IDLE) && store_hit) begin

                apply_masked_store(
                    store_hit_idx,
                    store_off0,
                    store_request_wdata,
                    store_request_wmask
                );
                dirty[store_hit_idx] <= 1'b1;
                store_valid          <= 1'b1;
            end
        end
    end

    // ============================================================
    // Combinational
    // ============================================================
    reg [31:0] assembled_word;
    reg [31:0] merged_word;
    reg [7:0]  b0, b1, b2, b3;
    integer j;

    always @(*) begin
        dcache_stall      = 1'b0;
        MEM_data_mem      = MEM_alu_out;
        Dc_mem_req        = 1'b0;
        Dc_mem_addr       = eff_line0;
        dcache_data_valid = 1'b1;

        assembled_word = 32'd0;
        merged_word    = 32'd0;
        b0 = 8'd0; b1 = 8'd0; b2 = 8'd0; b3 = 8'd0;

        // Mem pick
        if (ptw_can_issue) begin
            Dc_mem_req  = 1'b1;
            Dc_mem_addr = ptw_line;
        end else if (load_can_issue) begin
            Dc_mem_req  = 1'b1;
            Dc_mem_addr = need_fetch_line0 ? eff_line0 : eff_line1;
        end else if (store_can_issue) begin
            Dc_mem_req  = 1'b1;
            Dc_mem_addr = store_line;
        end

        // SB bypass
        if (load_bypass) begin
            if (MEM_byt)
                MEM_data_mem = {24'b0, sb_fwd_data[7:0]};
            else
                MEM_data_mem = sb_fwd_data;

            dcache_data_valid = Dtlb_addr_valid;
        end

        // Load data
        if (op_active_load) begin
            if (MEM_byt) begin
                if (hit0) begin
                    assembled_word = {24'b0, data_b[hit0_idx][eff_off]};
                    MEM_data_mem   = sb_fwd_mask[0]
                                     ? {24'b0, sb_fwd_data[7:0]}
                                     : assembled_word;
                end else begin
                    dcache_stall = 1'b1;
                end
            end else begin
                if (!eff_cross_line) begin
                    if (hit0) begin
                        b0 = data_b[hit0_idx][eff_off + 4'd0];
                        b1 = data_b[hit0_idx][eff_off + 4'd1];
                        b2 = data_b[hit0_idx][eff_off + 4'd2];
                        b3 = data_b[hit0_idx][eff_off + 4'd3];
                        assembled_word = {b3,b2,b1,b0};

                        merged_word = assembled_word;
                        for (j = 0; j < 4; j = j + 1)
                            if (sb_fwd_mask[j])
                                merged_word[8*j +: 8] = sb_fwd_data[8*j +: 8];

                        MEM_data_mem = merged_word;
                    end else begin
                        dcache_stall = 1'b1;
                    end
                end else begin
                    if (hit0 && hit1) begin
                        case (eff_off)
                            4'd13: begin
                                b0=data_b[hit0_idx][13];
                                b1=data_b[hit0_idx][14];
                                b2=data_b[hit0_idx][15];
                                b3=data_b[hit1_idx][0];
                            end
                            4'd14: begin
                                b0=data_b[hit0_idx][14];
                                b1=data_b[hit0_idx][15];
                                b2=data_b[hit1_idx][0];
                                b3=data_b[hit1_idx][1];
                            end
                            4'd15: begin
                                b0=data_b[hit0_idx][15];
                                b1=data_b[hit1_idx][0];
                                b2=data_b[hit1_idx][1];
                                b3=data_b[hit1_idx][2];
                            end
                        endcase

                        assembled_word = {b3,b2,b1,b0};

                        merged_word = assembled_word;
                        for (j = 0; j < 4; j = j + 1)
                            if (sb_fwd_mask[j])
                                merged_word[8*j +: 8] = sb_fwd_data[8*j +: 8];

                        MEM_data_mem = merged_word;
                    end else begin
                        dcache_stall = 1'b1;
                    end
                end
            end
        end

        // Data valid
        if (load_bypass)
            dcache_data_valid = Dtlb_addr_valid;
        else if (op_active_load)
            dcache_data_valid = MEM_byt
                ? (Dtlb_addr_valid && hit0)
                : (!eff_cross_line
                    ? (Dtlb_addr_valid && hit0)
                    : (Dtlb_addr_valid && hit0 && hit1));
    end

endmodule
