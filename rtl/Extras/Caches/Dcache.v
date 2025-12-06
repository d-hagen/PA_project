module dcache #(
    parameter XLEN      = 32,
    parameter LINE_BITS = 16       // upper 16 bits of the 20-bit address
)(
    input  wire                 clk,
    input  wire                 rst,

    // MEM stage interface
    input  wire                 MEM_ld,
    input  wire                 MEM_str,
    input  wire                 MEM_byt,         // 1 = byte, 0 = word
    input  wire [XLEN-1:0]      MEM_alu_out,     // full 32-bit addr, we use low 20 bits
    input  wire [XLEN-1:0]      MEM_b2,
    output reg  [XLEN-1:0]      MEM_data_mem,
    output reg                  MEM_stall,

    // Backing memory read interface (line read)
    output reg                  Dc_mem_req,
    output reg  [LINE_BITS-1:0] Dc_mem_addr,     // line index [19:4]
    input  wire [127:0]         MEM_data_line,   // 4×32-bit words
    input  wire                 MEM_mem_valid,

    // Backing memory write-back interface (eviction)
    output reg                  Dc_wb_we,
    output reg  [LINE_BITS-1:0] Dc_wb_addr,      // line index
    output reg  [127:0]         Dc_wb_wline,

    input  wire                 Ptw_req,
    input  wire [19:0]          Ptw_addr,
    output reg  [31:0]          Ptw_rdata,
    output reg                  Ptw_valid,

    output wire                 Dc_busy
);

    // Tiny 4-line fully-associative cache
    reg                     valid [0:3];
    reg                     dirty [0:3];
    reg [LINE_BITS-1:0]     tag   [0:3];         // full line index
    reg [31:0]              data  [0:3][0:3];    // [entry][word-in-line]

    // Control state
    reg [1:0]               fifo_ptr;
    reg                     hit;
    reg [1:0]               hit_idx;
    reg [LINE_BITS-1:0]     miss_line;

    // temporaries for byte store/load
    reg [31:0]              tmp_store_word;
    reg [31:0]              tmp_load_word;

    reg                     ptw_busy;
    reg [19:0]              ptw_addr_q;

    integer i;

    // ----------------------------------------------------------------
    // Address decode for 20-bit scheme:
    // addr[19:4] = line index (16 bits)
    // addr[3:2]  = word index in line (0..3)
    // addr[1:0]  = byte index in word (0..3)
    // ----------------------------------------------------------------
    wire [LINE_BITS-1:0] addr_line = MEM_alu_out[19:4];
    wire [1:0]           addr_word = MEM_alu_out[3:2];
    wire [1:0]           addr_byte = MEM_alu_out[1:0];

    wire [LINE_BITS-1:0] ptw_line  = Ptw_addr[19:4];

    wire op_active = MEM_ld | MEM_str;

    assign Dc_busy = MEM_stall | ptw_busy;

    // ===================== Sequential logic ==========================
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 4; i = i + 1) begin
                valid[i] <= 1'b0;
                dirty[i] <= 1'b0;
                tag[i]   <= {LINE_BITS{1'b0}};
            end
            fifo_ptr    <= 2'd0;
            miss_line   <= {LINE_BITS{1'b0}};
            Dc_wb_we    <= 1'b0;
            Dc_wb_addr  <= {LINE_BITS{1'b0}};
            Dc_wb_wline <= 128'd0;

            ptw_busy    <= 1'b0;
            ptw_addr_q  <= 20'd0;
            Ptw_rdata   <= 32'd0;
            Ptw_valid   <= 1'b0;
        end else begin
            Dc_wb_we  <= 1'b0;
            Ptw_valid <= 1'b0;

            if (Dc_mem_req && !hit && op_active)
                miss_line <= addr_line;

            if (!ptw_busy && !op_active && !MEM_mem_valid && Ptw_req) begin
                ptw_busy   <= 1'b1;
                ptw_addr_q <= Ptw_addr;
            end

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
                    if (valid[fifo_ptr] && dirty[fifo_ptr]) begin
                        Dc_wb_we            <= 1'b1;
                        Dc_wb_addr          <= tag[fifo_ptr];  // full line index
                        Dc_wb_wline[31:0]   <= data[fifo_ptr][0];
                        Dc_wb_wline[63:32]  <= data[fifo_ptr][1];
                        Dc_wb_wline[95:64]  <= data[fifo_ptr][2];
                        Dc_wb_wline[127:96] <= data[fifo_ptr][3];
                    end

                    valid[fifo_ptr] <= 1'b1;
                    dirty[fifo_ptr] <= 1'b0;
                    tag[fifo_ptr]   <= miss_line;

                    data[fifo_ptr][0] <= MEM_data_line[31:0];
                    data[fifo_ptr][1] <= MEM_data_line[63:32];
                    data[fifo_ptr][2] <= MEM_data_line[95:64];
                    data[fifo_ptr][3] <= MEM_data_line[127:96];

                    fifo_ptr <= fifo_ptr + 1'b1;
                end
            end

            if (MEM_str && hit) begin
                if (MEM_byt) begin
                    tmp_store_word = data[hit_idx][addr_word];
                    case (addr_byte)
                        2'b00: tmp_store_word[7:0]   = MEM_b2[7:0];
                        2'b01: tmp_store_word[15:8]  = MEM_b2[7:0];
                        2'b10: tmp_store_word[23:16] = MEM_b2[7:0];
                        2'b11: tmp_store_word[31:24] = MEM_b2[7:0];
                    endcase
                    data[hit_idx][addr_word] <= tmp_store_word;
                end else begin
                    data[hit_idx][addr_word] <= MEM_b2;
                end

                dirty[hit_idx] <= 1'b1;
            end
        end
    end

    // ===================== Combinational logic =======================
    always @(*) begin
        hit          = 1'b0;
        hit_idx      = 2'd0;
        MEM_stall    = 1'b0;
        MEM_data_mem = MEM_alu_out;   // default passthrough on non-loads

        Dc_mem_req   = 1'b0;
        Dc_mem_addr  = addr_line;

        if (op_active && !MEM_mem_valid) begin
            for (i = 0; i < 4; i = i + 1) begin
                if (valid[i] && (tag[i] == addr_line)) begin
                    hit     = 1'b1;
                    hit_idx = i[1:0];
                end
            end
        end

        // ---------------- Loads ----------------
        if (MEM_ld) begin
            if (hit) begin
                tmp_load_word = data[hit_idx][addr_word];
                if (MEM_byt) begin
                    // Byte load, zero-extend
                    case (addr_byte)
                        2'b00: MEM_data_mem = {24'b0, tmp_load_word[7:0]};
                        2'b01: MEM_data_mem = {24'b0, tmp_load_word[15:8]};
                        2'b10: MEM_data_mem = {24'b0, tmp_load_word[23:16]};
                        2'b11: MEM_data_mem = {24'b0, tmp_load_word[31:24]};
                    endcase
                end else begin
                    // Word load (assumed aligned)
                    MEM_data_mem = tmp_load_word;
                end
            end else begin
                // Miss: stall and request line from memory
                MEM_stall   = 1'b1;
                Dc_mem_req  = MEM_mem_valid ? 1'b0 : 1'b1;
                Dc_mem_addr = addr_line;
            end
        end

        // ---------------- Stores ----------------
        if (MEM_str) begin
            if (!hit) begin
                // Miss on store: fetch line first (write-allocate)
                MEM_stall   = 1'b1;
                Dc_mem_req  = MEM_mem_valid ? 1'b0 : 1'b1;
                Dc_mem_addr = addr_line;
            end
        end

        if (!op_active && !MEM_mem_valid && !ptw_busy && Ptw_req) begin
            Dc_mem_req  = 1'b1;
            Dc_mem_addr = ptw_line;
        end
    end

endmodule
