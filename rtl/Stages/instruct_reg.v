module instruct_mem #(
    parameter XLEN    = 32,
    parameter LATENCY = 3
)(
    input  wire         clk,
    input  wire         rst,

    input  wire         F_mem_req,    // start memory fetch
    input  wire [2:0]   F_mem_addr,   // LINE index 0..7

    output reg  [127:0] F_mem_inst,   // full line: 4×32 bits
    output reg          F_mem_valid
);

    // 8 lines, each 4 words of 32 bits
    reg [XLEN-1:0] line [0:7][0:3];   // [line][word]

    reg [$clog2(LATENCY+1)-1:0] counter;
    reg [2:0]                   saved_line;


    initial begin
        $readmemh("program.hex", line);
    end

    always @(posedge clk) begin
        if (rst) begin
            F_mem_valid <= 1'b0;
            counter     <= {($clog2(LATENCY+1)){1'b0}};
        end else begin
            F_mem_valid <= 1'b0;

            // start only when idle
            if (F_mem_req && (counter == 0)) begin
                saved_line <= F_mem_addr;
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
