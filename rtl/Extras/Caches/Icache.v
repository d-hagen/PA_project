module icache #(
    parameter integer PC_BITS   = 20,   // PC is 20 bits: [19:4]=line, [3:2]=word, [1:0]=byte
    parameter integer LINE_BITS = 16    // upper 16 bits of 20-bit address = line index
)(
    input  wire                  clk,
    input  wire                  rst,

    input  wire [PC_BITS-1:0]    F_pc,         // 20-bit PC (byte address, word-aligned)
    input  wire [127:0]          F_mem_inst,   // full 128-bit line from memory
    input  wire                  F_mem_valid,

    output reg                   Ic_mem_req,
    output reg  [LINE_BITS-1:0]  Ic_mem_addr,  // line index [19:4]

    output reg  [31:0]           F_inst,
    output reg                   F_stall
);

    // 4-entry FIFO, fully-associative instruction cache
    reg                     valid [0:3];
    reg [LINE_BITS-1:0]     tag   [0:3];       // line tag = full line index
    reg [31:0]              data  [0:3][0:3];  // [entry][word-in-line]

    reg [1:0]               fifo_ptr;
    reg                     hit;
    reg [1:0]               hit_idx;

    // line index for which the current miss request was issued
    reg [LINE_BITS-1:0]     miss_line;

    integer i;

    // -----------------------------------------------------------
    // Address decode for 20-bit layout:
    //   F_pc[19:4] = line index (16 bits)
    //   F_pc[3:2]  = word index in line (0..3)
    //   F_pc[1:0]  = byte index (always 2'b00 for aligned PC)
    // -----------------------------------------------------------
    wire [LINE_BITS-1:0] pc_line = F_pc[19:4];
    wire [1:0]           pc_word = F_pc[3:2];

    // ====================== Sequential state ======================
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 4; i = i + 1) begin
                valid[i] <= 1'b0;
                tag[i]   <= {LINE_BITS{1'b0}};
            end
            fifo_ptr  <= 2'd0;
            miss_line <= {LINE_BITS{1'b0}};
        end else begin
            // Latch line index at time of miss request
            // (assumes F_pc is held constant while F_stall=1)
            if (Ic_mem_req && !hit) begin
                miss_line <= pc_line;
            end

            // Refill whole line on memory return
            if (F_mem_valid) begin
                // Install into FIFO-selected entry
                valid[fifo_ptr]   <= 1'b1;
                tag[fifo_ptr]     <= miss_line;

                data[fifo_ptr][0] <= F_mem_inst[31:0];
                data[fifo_ptr][1] <= F_mem_inst[63:32];
                data[fifo_ptr][2] <= F_mem_inst[95:64];
                data[fifo_ptr][3] <= F_mem_inst[127:96];

                fifo_ptr          <= fifo_ptr + 1'b1;
            end
        end
    end

    // =================== Lookup + mem request =====================
    always @(*) begin
        hit        = 1'b0;
        hit_idx    = 2'd0;
        F_stall    = 1'b0;
        F_inst     = 32'h2000_0000;   // default NOP (or whatever you use)
        Ic_mem_req = 1'b0;
        Ic_mem_addr= pc_line;

        // Tag lookup (fully associative across 4 entries)
        if (!F_mem_valid) begin
            for (i = 0; i < 4; i = i + 1) begin
                if (valid[i] && (tag[i] == pc_line)) begin
                    hit     = 1'b1;
                    hit_idx = i[1:0];
                end
            end
        end

        if (hit) begin
            // Cache hit: just return the word for this PC
            F_inst = data[hit_idx][pc_word];
        end else begin
            // Cache miss: stall and request the line
            F_stall    = 1'b1;
            Ic_mem_req = F_mem_valid ? 1'b0 : 1'b1;
            Ic_mem_addr= pc_line;
        end
    end

endmodule
