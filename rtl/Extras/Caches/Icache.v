module icache #(
  parameter integer PC_BITS = 12
  )(
    input  wire        clk,
    input  wire        rst,

    input  wire [PC_BITS-1:0]   F_pc,         // 0..31, word index
    input  wire [127:0] F_mem_inst,  // full line from memory
    input  wire         F_mem_valid,

    output reg          Ic_mem_req,
    output reg  [9:0]   Ic_mem_addr,  // line index 0..7

    output reg  [31:0]  F_inst,
    output reg          F_stall
);

    // 4-entry direct-mapped-ish FIFO cache
    reg        valid [0:3];
    reg [2:0]  tag   [0:3];           // line tag
    reg [31:0] data  [0:3][0:3];      // [entry][word]

    reg [1:0] fifo_ptr;
    reg       hit;
    reg [1:0] hit_idx;

    // line index for which the current miss request was issued
    reg [9:0] miss_line;

    integer i;

    wire [PC_BITS-1:0] pc_line = F_pc[PC_BITS-1:2];   // 0..7, which 128-bit line
    wire [1:0] pc_word = F_pc[1:0];   // 0..3, which 32-bit word in the line

    // reset + sequential state
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 4; i = i + 1) begin
                valid[i] <= 1'b0;
            end
            fifo_ptr  <= 2'd0;
            miss_line <= 3'd0;
        end else begin
            // latch line index at time of miss request
            // (assumes F_pc is held constant while F_stall=1)
            if (Ic_mem_req && !hit) begin
                miss_line <= pc_line;
            end

            // refill whole line on memory return
            if (F_mem_valid) begin
                fifo_ptr          <= fifo_ptr + 1'b1;

                valid[fifo_ptr]   <= 1'b1;
                tag[fifo_ptr]     <= miss_line;  // use stored line index

                data[fifo_ptr][0] <= F_mem_inst[31:0];
                data[fifo_ptr][1] <= F_mem_inst[63:32];
                data[fifo_ptr][2] <= F_mem_inst[95:64];
                data[fifo_ptr][3] <= F_mem_inst[127:96];

            end
        end
    end

    // lookup + mem request (combinational)
    always @(*) begin
        hit       = 1'b0;
        hit_idx   = 2'd0;
        F_stall   = 1'b0;
        F_inst    = 32'h2000_0000;  // default NOP (or whatever)
        Ic_mem_addr = pc_line;

        Ic_mem_req = 1'b0;

        // ask memory for the line corresponding to current PC

        // tag lookup
        if (!F_mem_valid) begin
            for (i = 0; i < 4; i = i + 1) begin
                if (valid[i] && (tag[i] == pc_line)) begin
                    hit     = 1'b1;
                    hit_idx = i[1:0];
                end
            end
        end

        if (hit) begin
            F_inst = data[hit_idx][pc_word];
        end else begin
            F_stall   = 1'b1;
            Ic_mem_req = F_mem_valid ? 1'b0 : 1'b1 ;
            Ic_mem_addr = pc_line ;

        end
    end

endmodule
