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
    input  wire                 sb_hit,

    // Store-buffer drain request (lowest priority)
    input  wire                 store_request,
    input  wire [19:0]          store_request_address, // FULL PA[19:0] (name kept!)
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

    output wire                 Dc_busy,

    // NEW: "valid wire": 0 only when op_active_load && output not valid, else always 1
    output reg                  dcache_data_valid
);

    // Tiny 4-line fully-associative cache
    reg                     valid [0:3];
    reg                     dirty [0:3];
    reg [LINE_BITS-1:0]     tag   [0:3];
    reg [31:0]              data  [0:3][0:3];

    // Replacement pointer
    reg [1:0]               fifo_ptr;

    // Load lookup
    reg                     hit;
    reg [1:0]               hit_idx;
    reg [31:0]              tmp_load_word;

    // Address decode for MEM load (expects translated PA in MEM_alu_out[19:0])
    wire [LINE_BITS-1:0] addr_line = MEM_alu_out[19:4];
    wire [1:0]           addr_word = MEM_alu_out[3:2];
    wire [1:0]           addr_byte = MEM_alu_out[1:0];

    // PTW
    reg                   ptw_busy;
    reg [19:0]            ptw_addr_q;
    wire [LINE_BITS-1:0]  ptw_line  = Ptw_addr[19:4];

    // Only do cache load when SB says miss
    wire op_active_load        = MEM_ld && !sb_hit && Dtlb_addr_valid;
    wire do_cache_access_load  = op_active_load && Dtlb_addr_valid;
    wire mem_needs_translation = op_active_load && !Dtlb_addr_valid;

    assign Dc_busy = dcache_stall | ptw_busy;

    integer i;

    // ------------------------------------------------------------
    // Decode store request FULL address
    // ------------------------------------------------------------
    wire [LINE_BITS-1:0] store_line = store_request_address[19:4];
    wire [1:0]           store_word = store_request_address[3:2];
    wire [1:0]           store_bsel = store_request_address[1:0];

    // ------------------------------------------------------------
    // Store hit detection (by line tag)
    // ------------------------------------------------------------
    reg       store_hit;
    reg [1:0] store_hit_idx;

    always @(*) begin
        store_hit     = 1'b0;
        store_hit_idx = 2'd0;
        for (i = 0; i < 4; i = i + 1) begin
            if (valid[i] && (tag[i] == store_line)) begin
                store_hit     = 1'b1;
                store_hit_idx = i[1:0];
            end
        end
    end

    // Store miss we want to service (lowest priority)
    wire store_need_service = store_request && !store_hit;

    // ------------------------------------------------------------
    // Track in-flight store-miss line fetch (write-allocate)
    // ------------------------------------------------------------
    reg                 sb_store_wait;
    reg [LINE_BITS-1:0] sb_store_line_q;

    // Latch offsets/value/size for store miss so refill uses stable info
    reg [1:0]           sb_store_word_q;
    reg [1:0]           sb_store_bsel_q;
    reg [XLEN-1:0]      sb_store_val_q;
    reg                 sb_store_byte_q;

    // Track load miss line for refill
    reg [LINE_BITS-1:0] load_miss_line_q;
    reg                 load_wait;

    // ===================== Sequential logic ==========================
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 4; i = i + 1) begin
                valid[i] <= 1'b0;
                dirty[i] <= 1'b0;
                tag[i]   <= {LINE_BITS{1'b0}};
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
            sb_store_word_q <= 2'd0;
            sb_store_bsel_q <= 2'd0;
            sb_store_val_q  <= {XLEN{1'b0}};
            sb_store_byte_q <= 1'b0;

            load_wait        <= 1'b0;
            load_miss_line_q <= {LINE_BITS{1'b0}};
        end else begin
            // default pulses
            Dc_wb_we    <= 1'b0;
            Ptw_valid   <= 1'b0;
            store_valid <= 1'b0;

            // -------------------------
            // PTW bookkeeping (only if nothing else needs memory)
            // -------------------------
            if (!ptw_busy && !MEM_mem_valid && Ptw_req &&
                (!op_active_load || mem_needs_translation) &&
                !sb_store_wait && !load_wait) begin
                ptw_busy   <= 1'b1;
                ptw_addr_q <= Ptw_addr;
            end

            // -------------------------
            // Latch when we launch memory requests
            // -------------------------
            if (Dc_mem_req && !MEM_mem_valid) begin
                // Load miss request launched
                if (op_active_load && Dtlb_addr_valid && !hit) begin
                    load_wait        <= 1'b1;
                    load_miss_line_q <= addr_line;
                end

                // Store miss request launched
                if (!op_active_load && !ptw_busy && store_need_service && !sb_store_wait && !load_wait) begin
                    sb_store_wait   <= 1'b1;
                    sb_store_line_q <= store_line;

                    sb_store_word_q <= store_word;
                    sb_store_bsel_q <= store_bsel;
                    sb_store_val_q  <= store_request_value;
                    sb_store_byte_q <= store_byte;
                end
            end

            // -------------------------
            // Handle returned memory line
            // -------------------------
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
                    // Write back victim if dirty
                    if (valid[fifo_ptr] && dirty[fifo_ptr]) begin
                        Dc_wb_we            <= 1'b1;
                        Dc_wb_addr          <= tag[fifo_ptr];
                        Dc_wb_wline[31:0]   <= data[fifo_ptr][0];
                        Dc_wb_wline[63:32]  <= data[fifo_ptr][1];
                        Dc_wb_wline[95:64]  <= data[fifo_ptr][2];
                        Dc_wb_wline[127:96] <= data[fifo_ptr][3];
                    end

                    // If waiting on store-miss: refill line and then apply store
                    if (sb_store_wait) begin
                        valid[fifo_ptr] <= 1'b1;
                        dirty[fifo_ptr] <= 1'b1;
                        tag[fifo_ptr]   <= sb_store_line_q;

                        data[fifo_ptr][0] <= MEM_data_line[31:0];
                        data[fifo_ptr][1] <= MEM_data_line[63:32];
                        data[fifo_ptr][2] <= MEM_data_line[95:64];
                        data[fifo_ptr][3] <= MEM_data_line[127:96];

                        // Apply latched store into the filled line
                        if (sb_store_byte_q) begin
                            case (sb_store_bsel_q)
                                2'b00: data[fifo_ptr][sb_store_word_q][7:0]   <= sb_store_val_q[7:0];
                                2'b01: data[fifo_ptr][sb_store_word_q][15:8]  <= sb_store_val_q[7:0];
                                2'b10: data[fifo_ptr][sb_store_word_q][23:16] <= sb_store_val_q[7:0];
                                2'b11: data[fifo_ptr][sb_store_word_q][31:24] <= sb_store_val_q[7:0];
                            endcase
                        end else begin
                            data[fifo_ptr][sb_store_word_q] <= sb_store_val_q[31:0];
                        end

                        store_valid   <= 1'b1;   // acknowledge SB head store done
                        sb_store_wait <= 1'b0;

                        fifo_ptr <= fifo_ptr + 1'b1;
                    end else begin
                        // Otherwise: load refill
                        valid[fifo_ptr] <= 1'b1;
                        dirty[fifo_ptr] <= 1'b0;
                        tag[fifo_ptr]   <= load_miss_line_q;

                        data[fifo_ptr][0] <= MEM_data_line[31:0];
                        data[fifo_ptr][1] <= MEM_data_line[63:32];
                        data[fifo_ptr][2] <= MEM_data_line[95:64];
                        data[fifo_ptr][3] <= MEM_data_line[127:96];

                        load_wait <= 1'b0;
                        fifo_ptr  <= fifo_ptr + 1'b1;
                    end
                end
            end

            // -------------------------
            // Store-hit case (complete immediately)
            // -------------------------
            if (!op_active_load && !mem_needs_translation && !ptw_busy &&
                store_request && !MEM_mem_valid && !sb_store_wait && !load_wait) begin
                if (store_hit) begin
                    if (store_byte) begin
                        case (store_bsel)
                            2'b00: data[store_hit_idx][store_word][7:0]   <= store_request_value[7:0];
                            2'b01: data[store_hit_idx][store_word][15:8]  <= store_request_value[7:0];
                            2'b10: data[store_hit_idx][store_word][23:16] <= store_request_value[7:0];
                            2'b11: data[store_hit_idx][store_word][31:24] <= store_request_value[7:0];
                        endcase
                    end else begin
                        data[store_hit_idx][store_word] <= store_request_value[31:0];
                    end
                    dirty[store_hit_idx] <= 1'b1;
                    store_valid          <= 1'b1;
                end
            end
        end
    end

    // ===================== Combinational logic =======================
    always @(*) begin
        hit     = 1'b0;
        hit_idx = 2'd0;

        // defaults
        dcache_stall      = 1'b0;
        MEM_data_mem      = MEM_alu_out;

        Dc_mem_req        = 1'b0;
        Dc_mem_addr       = addr_line;

        // default: ALWAYS 1, except the one bad case you described
        dcache_data_valid = 1'b1;

        // Load cache lookup
        if (do_cache_access_load && !MEM_mem_valid) begin
            for (i = 0; i < 4; i = i + 1) begin
                if (valid[i] && (tag[i] == addr_line)) begin
                    hit     = 1'b1;
                    hit_idx = i[1:0];
                end
            end
        end

        // ---------------- Loads (highest priority) ----------------
        if (op_active_load) begin
            if (!Dtlb_addr_valid) begin
                dcache_stall = 1'b0; // DTLB stalls elsewhere
            end else begin
                if (hit) begin
                    tmp_load_word = data[hit_idx][addr_word];
                    if (MEM_byt) begin
                        case (addr_byte)
                            2'b00: MEM_data_mem = {24'b0, tmp_load_word[7:0]};
                            2'b01: MEM_data_mem = {24'b0, tmp_load_word[15:8]};
                            2'b10: MEM_data_mem = {24'b0, tmp_load_word[23:16]};
                            2'b11: MEM_data_mem = {24'b0, tmp_load_word[31:24]};
                        endcase
                    end else begin
                        MEM_data_mem = tmp_load_word;
                    end
                end else begin
                    // load miss: request line
                    dcache_stall = 1'b1;
                    Dc_mem_req   = (!MEM_mem_valid) ? 1'b1 : 1'b0;
                    Dc_mem_addr  = addr_line;
                end
            end
        end else begin
            // ---------------- PTW (middle priority) ----------------
            if (!MEM_mem_valid && !ptw_busy && Ptw_req && !sb_store_wait && !load_wait) begin
                Dc_mem_req  = 1'b1;
                Dc_mem_addr = ptw_line;
            end
            // ---------------- Store miss fetch (lowest priority) ----------------
            else if (!MEM_mem_valid && store_need_service && !sb_store_wait && !ptw_busy && !load_wait) begin
                Dc_mem_req  = 1'b1;
                Dc_mem_addr = store_line; // request the line of the store
            end
        end

        // ----------------------------------------------------------
        // VALID FLAG (your exact rule):
        // 0 only when op_active_load AND the output isn't valid.
        // Otherwise ALWAYS 1.
        //
        // Here, "valid output" for loads means: translated addr valid AND hit.
        // ----------------------------------------------------------
        if (op_active_load && !(Dtlb_addr_valid && hit))
            dcache_data_valid = 1'b0;
        else
            dcache_data_valid = 1'b1;
    end

endmodule
