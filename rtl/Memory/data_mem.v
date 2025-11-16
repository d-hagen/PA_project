module data_mem #(
    parameter XLEN    = 32,
    parameter LATENCY = 3
)(
    input  wire         clk,
    input  wire         rst,

    // ---------- Line read (for cache misses) ----------
    input  wire         Dc_rd_req,     // start line read
    input  wire [3:0]   Dc_rd_addr,    // line index 0..15

    output reg  [127:0] Dc_rline,      // full line: 4×32
    output reg          Dc_rd_valid,   // line ready

    // ---------- Line write-back (on eviction) ----------
    input  wire         Dc_wb_we,      // 1 = write line
    input  wire [3:0]   Dc_wb_addr,    // line index to write 0..15
    input  wire [127:0] Dc_wb_wline    // line data from cache
);

    // 16 lines, each 4 words of 32 bits
    reg [XLEN-1:0] line [0:15][0:3];   // [line][word]

    reg [$clog2(LATENCY+1)-1:0] counter;
    reg [3:0]                   saved_line;

    integer i, j;

    initial begin
        // Init to zero (or read from file)
        for (i = 0; i < 16; i = i + 1) begin
            for (j = 0; j < 4; j = j + 1) begin
                line[i][j] = {XLEN{1'b0}};
            end
        end

        // Example:
        // $readmemh("data.hex", line);
    end

    // Line read path (same idea as instruct_mem)
    always @(posedge clk) begin
        if (rst) begin
            Dc_rd_valid <= 1'b0;
            counter     <= {($clog2(LATENCY+1)){1'b0}};
        end else begin
            Dc_rd_valid <= 1'b0;

            // Start only when idle
            if (Dc_rd_req && (counter == 0)) begin
                saved_line <= Dc_rd_addr;
                counter    <= LATENCY[$clog2(LATENCY+1)-1:0];
            end

            if (counter != 0) begin
                counter <= counter - 1'b1;

                if (counter == 1) begin
                    Dc_rline[31:0]    <= line[saved_line][0];
                    Dc_rline[63:32]   <= line[saved_line][1];
                    Dc_rline[95:64]   <= line[saved_line][2];
                    Dc_rline[127:96]  <= line[saved_line][3];
                    Dc_rd_valid       <= 1'b1;
                end
            end
        end
    end

    // Line write-back path: single-cycle line store
    always @(posedge clk) begin
        if (Dc_wb_we) begin
            line[Dc_wb_addr][0] <= Dc_wb_wline[31:0];
            line[Dc_wb_addr][1] <= Dc_wb_wline[63:32];
            line[Dc_wb_addr][2] <= Dc_wb_wline[95:64];
            line[Dc_wb_addr][3] <= Dc_wb_wline[127:96];
        end
    end

endmodule