module dcache #(
    parameter XLEN      = 32,
    parameter LINE_BITS = 16
)(
    input  wire                 clk,
    input  wire                 rst,

    // MEM stage interface (loads only)
    input  wire                 MEM_ld,
    input  wire                 MEM_byt,
    input  wire [XLEN-1:0]      MEM_alu_out,
    input  wire [XLEN-1:0]      MEM_b2,
    output reg  [XLEN-1:0]      MEM_data_mem,
    output reg                  dcache_stall,

    // From Store Buffer (line-filter)
    input  wire                 sb_load_miss,

    // Store-buffer drain request (lowest priority)
    input  wire                 store_request,
    input  wire [19:0]          store_request_address, // FULL PA[19:0]
    input  wire [XLEN-1:0]      store_request_value,
    input  wire                 store_byte,
    output reg                  store_valid,

    // From DTLB (for load side)
    input  wire                 Dtlb_addr_valid,

    // Backing memory read interface (line read)
    output reg                  Dc_mem_req,
    output reg  [LINE_BITS-1:0] Dc_mem_addr,
    input  wire [127:0]         MEM_data_line,
    input  wire                 MEM_mem_valid,

    // Backing memory write-back interface (eviction)
    output reg                  Dc_wb_we,
    output reg  [LINE_BITS-1:0] Dc_wb_addr,
    output reg  [127:0]         Dc_wb_wline,

    // PTW (word read via line interface)
    input  wire                 Ptw_req,
    input  wire [19:0]          Ptw_addr,
    output reg  [31:0]          Ptw_rdata,
    output reg                  Ptw_valid,

    // Busy indicator
    output wire                 Dc_busy,

    // PTW accepted pulse when we latch PTW req
    output wire                 Ptw_accepted,

    // "valid wire": 0 only when op_active_load && output not valid, else always 1
    output reg                  dcache_data_valid
);

    // ============================================================
    // Tiny 4-line fully-associative cache (16B line => 16 bytes)
    // ============================================================
    reg                     valid [0:3];
    reg                     dirty [0:3];
    reg [LINE_BITS-1:0]     tag   [0:3];
    reg [7:0]               data_b[0:3][0:15]; // byte storage

    reg [1:0] fifo_ptr;

    integer i;
    integer b;

    // ============================================================
    // PTW
    // ============================================================
    reg                   ptw_busy;
    reg [19:0]            ptw_addr_q;
    wire [LINE_BITS-1:0]  ptw_line  = Ptw_addr[19:4];

    // ============================================================
    // Only do cache load when SB says miss
    // ============================================================
    wire op_active_load        = MEM_ld && Dtlb_addr_valid && sb_load_miss;
    wire mem_needs_translation = MEM_ld && !Dtlb_addr_valid;

    // ============================================================
    // Mask store address to avoid X propagation when store_request=0
    // ============================================================
    wire [19:0] store_addr_safe = store_request ? store_request_address : 20'd0;
    wire [LINE_BITS-1:0] store_line = store_addr_safe[19:4];
    wire [3:0]           store_off  = store_addr_safe[3:0];

    // ============================================================
    // Store miss tracking (write allocate)
    // ============================================================
    reg                 sb_store_wait;
    reg [LINE_BITS-1:0] sb_store_line_q;
    reg [3:0]           sb_store_off_q;
    reg [XLEN-1:0]      sb_store_val_q;
    reg                 sb_store_byte_q;

    // ============================================================
    // LOAD MISS FSM (fixes cross-line deadlock)
    // ============================================================
    localparam LD_IDLE  = 2'd0;
    localparam LD_WAIT0 = 2'd1; // waiting return for line0
    localparam LD_WAIT1 = 2'd2; // waiting return for line1
    reg [1:0] ld_state;

    // latch load request context when issuing a miss
    reg [19:0] ld_addr_q;   // full PA[19:0] start address
    reg        ld_byt_q;    // 1=byte, 0=word

    // effective address used for hit/assemble while stalled
    wire [19:0] eff_addr20 =
        (ld_state == LD_IDLE) ? MEM_alu_out[19:0] : ld_addr_q;

    wire [LINE_BITS-1:0] eff_line0 = eff_addr20[19:4];
    wire [LINE_BITS-1:0] eff_line1 = eff_addr20[19:4] + 1'b1;
    wire [3:0]           eff_off   = eff_addr20[3:0];

    wire eff_cross_line = (/*word*/ !((ld_state==LD_IDLE)?MEM_byt:ld_byt_q)) && (eff_off > 4'd12);

    // ============================================================
    // Hit detection (for effective load lines + store line)
    // ============================================================
    reg       hit0, hit1;
    reg [1:0] hit0_idx, hit1_idx;

    reg       store_hit;
    reg [1:0] store_hit_idx;

    always @(*) begin
        hit0     = 1'b0;
        hit1     = 1'b0;
        hit0_idx = 2'd0;
        hit1_idx = 2'd0;

        store_hit     = 1'b0;
        store_hit_idx = 2'd0;

        for (i = 0; i < 4; i = i + 1) begin
            if (valid[i] && (tag[i] == eff_line0)) begin
                hit0     = 1'b1;
                hit0_idx = i[1:0];
            end
            if (valid[i] && (tag[i] == eff_line1)) begin
                hit1     = 1'b1;
                hit1_idx = i[1:0];
            end
            if (valid[i] && (tag[i] == store_line)) begin
                store_hit     = 1'b1;
                store_hit_idx = i[1:0];
            end
        end
    end

    wire store_need_service = store_request && !store_hit;

    // ============================================================
    // Which load line is missing?
    // ============================================================
    wire need_fetch_line0 = op_active_load && !hit0;
    wire need_fetch_line1 = op_active_load && eff_cross_line && !hit1;

    // ============================================================
    // Dc_busy
    // ============================================================
    wire mem_waiting = ptw_busy | sb_store_wait | (ld_state != LD_IDLE);
    assign Dc_busy   = Dc_mem_req | mem_waiting | MEM_mem_valid;

    // ============================================================
    // Arbitration intent signals (PTW highest)
    // ============================================================
    wire ptw_can_issue =
        (!MEM_mem_valid) &&
        (!ptw_busy) &&
        Ptw_req &&
        (!sb_store_wait) &&
        (ld_state == LD_IDLE);

    // Load can issue ONLY in LD_IDLE (single-pulse request),
    // then ld_state moves to WAIT0/WAIT1 until memory returns.
    wire load_can_issue =
        (!MEM_mem_valid) &&
        (!ptw_can_issue) &&
        (ld_state == LD_IDLE) &&
        op_active_load &&
        (need_fetch_line0 || need_fetch_line1) &&
        (!sb_store_wait) &&
        (!ptw_busy);

    wire store_can_issue =
        (!MEM_mem_valid) &&
        (!ptw_can_issue) &&
        (!load_can_issue) &&
        store_need_service &&
        (!sb_store_wait) &&
        (ld_state == LD_IDLE) &&
        (!ptw_busy);

    // ============================================================
    // PTW accepted pulse
    // ============================================================
    reg ptw_accepted_r;
    assign Ptw_accepted = ptw_accepted_r;

    // ============================================================
    // Pack victim line for writeback
    // ============================================================
    reg [127:0] victim_line_pack;
    always @(*) begin
        victim_line_pack = 128'd0;
        for (b = 0; b < 16; b = b + 1) begin
            victim_line_pack[8*b +: 8] = data_b[fifo_ptr][b];
        end
    end

    // ============================================================
    // Sequential logic
    // ============================================================
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 4; i = i + 1) begin
                valid[i] <= 1'b0;
                dirty[i] <= 1'b0;
                tag[i]   <= {LINE_BITS{1'b0}};
                for (b = 0; b < 16; b = b + 1) begin
                    data_b[i][b] <= 8'd0;
                end
            end
            fifo_ptr        <= 2'd0;

            Dc_wb_we        <= 1'b0;
            Dc_wb_addr      <= {LINE_BITS{1'b0}};
            Dc_wb_wline     <= 128'd0;

            ptw_busy        <= 1'b0;
            ptw_addr_q      <= 20'd0;
            Ptw_rdata       <= 32'd0;
            Ptw_valid       <= 1'b0;

            store_valid     <= 1'b0;

            sb_store_wait   <= 1'b0;
            sb_store_line_q <= {LINE_BITS{1'b0}};
            sb_store_off_q  <= 4'd0;
            sb_store_val_q  <= {XLEN{1'b0}};
            sb_store_byte_q <= 1'b0;

            ld_state        <= LD_IDLE;
            ld_addr_q       <= 20'd0;
            ld_byt_q        <= 1'b0;

            ptw_accepted_r  <= 1'b0;
        end else begin
            // default pulses
            Dc_wb_we       <= 1'b0;
            Ptw_valid      <= 1'b0;
            store_valid    <= 1'b0;
            ptw_accepted_r <= 1'b0;

            // -------------------------
            // Accept PTW when it wins arbitration
            // -------------------------
            if (ptw_can_issue) begin
                ptw_busy       <= 1'b1;
                ptw_addr_q     <= Ptw_addr;
                ptw_accepted_r <= 1'b1;
            end

            // -------------------------
            // Launch memory requests (single-cycle pulse)
            // -------------------------
            if (Dc_mem_req && !MEM_mem_valid) begin
                if (load_can_issue) begin
                    // latch the load context so it stays stable while stalled
                    ld_addr_q <= MEM_alu_out[19:0];
                    ld_byt_q  <= MEM_byt;

                    // choose which line we requested
                    if (need_fetch_line0)
                        ld_state <= LD_WAIT0;
                    else
                        ld_state <= LD_WAIT1;
                end

                if (store_can_issue) begin
                    sb_store_wait   <= 1'b1;
                    sb_store_line_q <= store_line;
                    sb_store_off_q  <= store_off;
                    sb_store_val_q  <= store_request_value;
                    sb_store_byte_q <= store_byte;
                end
            end

            // -------------------------
            // Handle returned memory line
            // -------------------------
            if (MEM_mem_valid) begin
                if (ptw_busy) begin
                    // PTW: extract word from returned 16B line
                    case (ptw_addr_q[3:2])
                        2'b00: Ptw_rdata <= MEM_data_line[31:0];
                        2'b01: Ptw_rdata <= MEM_data_line[63:32];
                        2'b10: Ptw_rdata <= MEM_data_line[95:64];
                        2'b11: Ptw_rdata <= MEM_data_line[127:96];
                    endcase
                    Ptw_valid <= 1'b1;
                    ptw_busy  <= 1'b0;
                end else begin
                    // write back victim if dirty
                    if (valid[fifo_ptr] && dirty[fifo_ptr]) begin
                        Dc_wb_we    <= 1'b1;
                        Dc_wb_addr  <= tag[fifo_ptr];
                        Dc_wb_wline <= victim_line_pack;
                    end

                    // store refill
                    if (sb_store_wait) begin
                        valid[fifo_ptr] <= 1'b1;
                        dirty[fifo_ptr] <= 1'b1;
                        tag[fifo_ptr]   <= sb_store_line_q;

                        for (b = 0; b < 16; b = b + 1)
                            data_b[fifo_ptr][b] <= MEM_data_line[8*b +: 8];

                        if (sb_store_byte_q) begin
                            data_b[fifo_ptr][sb_store_off_q] <= sb_store_val_q[7:0];
                        end else begin
                            data_b[fifo_ptr][sb_store_off_q + 4'd0] <= sb_store_val_q[7:0];
                            data_b[fifo_ptr][sb_store_off_q + 4'd1] <= sb_store_val_q[15:8];
                            data_b[fifo_ptr][sb_store_off_q + 4'd2] <= sb_store_val_q[23:16];
                            data_b[fifo_ptr][sb_store_off_q + 4'd3] <= sb_store_val_q[31:24];
                        end

                        store_valid   <= 1'b1;
                        sb_store_wait <= 1'b0;
                        fifo_ptr      <= fifo_ptr + 1'b1;
                    end else begin
                        // load refill
                        if (ld_state != LD_IDLE) begin
                            valid[fifo_ptr] <= 1'b1;
                            dirty[fifo_ptr] <= 1'b0;

                            // store the correct tag for the line we requested
                            if (ld_state == LD_WAIT0)
                                tag[fifo_ptr] <= ld_addr_q[19:4];
                            else
                                tag[fifo_ptr] <= (ld_addr_q[19:4] + 1'b1);

                            for (b = 0; b < 16; b = b + 1)
                                data_b[fifo_ptr][b] <= MEM_data_line[8*b +: 8];

                            fifo_ptr <= fifo_ptr + 1'b1;

                            // IMPORTANT: return to IDLE so we can issue the second-line miss next cycle
                            ld_state <= LD_IDLE;
                        end
                    end
                end
            end

            // -------------------------
            // Store-hit case (complete immediately)
            // -------------------------
            if (!op_active_load && !mem_needs_translation && !ptw_busy &&
                store_request && !MEM_mem_valid && !sb_store_wait && (ld_state==LD_IDLE)) begin
                if (store_hit) begin
                    if (store_byte) begin
                        data_b[store_hit_idx][store_off] <= store_request_value[7:0];
                    end else begin
                        data_b[store_hit_idx][store_off + 4'd0] <= store_request_value[7:0];
                        data_b[store_hit_idx][store_off + 4'd1] <= store_request_value[15:8];
                        data_b[store_hit_idx][store_off + 4'd2] <= store_request_value[23:16];
                        data_b[store_hit_idx][store_off + 4'd3] <= store_request_value[31:24];
                    end
                    dirty[store_hit_idx] <= 1'b1;
                    store_valid          <= 1'b1;
                end
            end
        end
    end

    // ============================================================
    // Combinational logic: arbitration + load data assembly
    // ============================================================
    reg [31:0] assembled_word;
    reg [7:0]  b0, b1, b2, b3;

    always @(*) begin
        // defaults
        dcache_stall      = 1'b0;
        MEM_data_mem      = MEM_alu_out;

        Dc_mem_req        = 1'b0;
        Dc_mem_addr       = eff_line0;

        dcache_data_valid = 1'b1;

        assembled_word    = 32'd0;
        b0 = 8'd0; b1 = 8'd0; b2 = 8'd0; b3 = 8'd0;

        // ----------------------------------------------------------
        // Memory port arbitration (PTW FIRST)
        // ----------------------------------------------------------
        if (ptw_can_issue) begin
            Dc_mem_req  = 1'b1;
            Dc_mem_addr = ptw_line;
        end else if (load_can_issue) begin
            Dc_mem_req = 1'b1;
            // fetch missing line0 first, else line1
            if (need_fetch_line0)
                Dc_mem_addr = eff_line0;
            else
                Dc_mem_addr = eff_line1;
        end else if (store_can_issue) begin
            Dc_mem_req  = 1'b1;
            Dc_mem_addr = store_line;
        end

        // ----------------------------------------------------------
        // Load datapath behavior (supports cross-line word loads)
        // ----------------------------------------------------------
        if (op_active_load) begin
            if (MEM_byt) begin
                if (hit0) begin
                    MEM_data_mem = {24'b0, data_b[hit0_idx][eff_off]};
                    dcache_stall = 1'b0;
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
                        assembled_word = {b3, b2, b1, b0};
                        MEM_data_mem   = assembled_word;
                        dcache_stall   = 1'b0;
                    end else begin
                        dcache_stall = 1'b1;
                    end
                end else begin
                    // offsets 13..15
                    if (hit0 && hit1) begin
                        case (eff_off)
                            4'd13: begin
                                b0 = data_b[hit0_idx][13];
                                b1 = data_b[hit0_idx][14];
                                b2 = data_b[hit0_idx][15];
                                b3 = data_b[hit1_idx][0];
                            end
                            4'd14: begin
                                b0 = data_b[hit0_idx][14];
                                b1 = data_b[hit0_idx][15];
                                b2 = data_b[hit1_idx][0];
                                b3 = data_b[hit1_idx][1];
                            end
                            4'd15: begin
                                b0 = data_b[hit0_idx][15];
                                b1 = data_b[hit1_idx][0];
                                b2 = data_b[hit1_idx][1];
                                b3 = data_b[hit1_idx][2];
                            end
                            default: begin
                                b0 = data_b[hit0_idx][eff_off + 4'd0];
                                b1 = data_b[hit0_idx][eff_off + 4'd1];
                                b2 = data_b[hit0_idx][eff_off + 4'd2];
                                b3 = data_b[hit0_idx][eff_off + 4'd3];
                            end
                        endcase
                        assembled_word = {b3, b2, b1, b0};
                        MEM_data_mem   = assembled_word;
                        dcache_stall   = 1'b0;
                    end else begin
                        dcache_stall = 1'b1;
                    end
                end
            end
        end

        // VALID FLAG:
        if (op_active_load) begin
            if (MEM_byt) begin
                dcache_data_valid = (Dtlb_addr_valid && hit0);
            end else if (!eff_cross_line) begin
                dcache_data_valid = (Dtlb_addr_valid && hit0);
            end else begin
                dcache_data_valid = (Dtlb_addr_valid && hit0 && hit1);
            end
        end else begin
            dcache_data_valid = 1'b1;
        end
    end

endmodule
