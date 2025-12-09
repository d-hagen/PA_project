module instruct_mem #(
    parameter XLEN    = 32,
    parameter LATENCY = 3
)(
    input  wire         clk,
    input  wire         rst,

    input  wire         Ic_mem_req,    // start memory fetch
    input  wire [9:0]   Ic_mem_addr,   // LINE index 0..7

    output reg  [127:0] F_mem_inst,   // full line: 4×32 bits
    output reg          F_mem_valid
);

    // 8 lines, each 4 words of 32 bits
    reg [XLEN-1:0] line [0:1024][0:3];   // [line][word]

    reg [$clog2(LATENCY+1)-1:0] counter;
    reg [9:0]                   saved_line;

    integer i, j;
    
    initial begin
        // Initialize whole memory to 0
        for (i = 0; i <= 1024; i = i + 1) begin
            for (j = 0; j < 4; j = j + 1) begin
                line[i][j] = {XLEN{1'b0}};
            end
        end

        // Now load only the first 32 words from the hex file
        // (i.e. locations 0 .. 31 in the flattened array)
        $readmemh("program.hex", line, 0, 31);
    end

    always @(posedge clk) begin
        if (rst) begin
            F_mem_valid <= 1'b0;
            counter     <= {($clog2(LATENCY+1)){1'b0}};
        end else begin
            F_mem_valid <= 1'b0;

            // start only when idle
            if (Ic_mem_req && (counter == 0)) begin
                saved_line <= Ic_mem_addr;
                counter    <= LATENCY[$clog2(LATENCY+1)-1:0];
            end

            if (counter != 0) begin
                counter <= counter - 1'b1;

                if (counter == 1) begin
                    F_mem_inst[31:0]    <= line[saved_line][0];
                    F_mem_inst[63:32]   <= line[saved_line][1];
                    F_mem_inst[95:64]   <= line[saved_line][2];
                    F_mem_inst[127:96]  <= line[saved_line][3];
                    F_mem_valid         <= 1'b1;
                end
            end
        end
    end

endmodule
