module unified_mem #(
    parameter XLEN    = 32,
    parameter LATENCY = 3
)(
    input  wire         clk,
    input  wire         rst,

    // ---------- Instruction side (I-cache) ----------
    input  wire         Ic_mem_req,    // start memory fetch
    input  wire [9:0]   Ic_mem_addr,   // line index

    output reg  [127:0] F_mem_inst,    // full line: 4×32 bits
    output reg          F_mem_valid,

    // ---------- Data side (D-cache) ----------
    // Line read (for cache misses)
    input  wire         Dc_mem_req,    // start line read
    input  wire [9:0]   Dc_mem_addr,   // line index

    output reg  [127:0] MEM_data_line, // full line: 4×32 bits
    output reg          MEM_mem_valid, // line ready

    // Line write-back (on eviction)
    input  wire         Dc_wb_we,      // 1 = write line
    input  wire [9:0]   Dc_wb_addr,    // line index to write
    input  wire [127:0] Dc_wb_wline    // line data from cache
);

    // Shared memory: N lines, each 4 words of XLEN bits
    // (you can change 1024 to the depth you actually want)
    reg [XLEN-1:0] line [0:1023][0:3];   // [line][word]

    // Separate pipelines for I-side and D-side reads
    reg [$clog2(LATENCY+1)-1:0] I_counter;
    reg [9:0]                   I_saved_line;

    reg [$clog2(LATENCY+1)-1:0] D_counter;
    reg [9:0]                   D_saved_line;

    integer i, j;

    // ---------- Initialization ----------
    initial begin
        // Clear everything
        for (i = 0; i < 1024; i = i + 1) begin
            for (j = 0; j < 4; j = j + 1) begin
                line[i][j] = {XLEN{1'b0}};
            end
        end
        $readmemh("program.hex", line);
    end

    // ---------- Instruction-side read pipeline ----------
    always @(posedge clk) begin
        if (rst) begin
            F_mem_valid <= 1'b0;
            I_counter   <= {($clog2(LATENCY+1)){1'b0}};
        end else begin
            F_mem_valid <= 1'b0;

            // Start only when idle
            if (Ic_mem_req && (I_counter == 0)) begin
                I_saved_line <= Ic_mem_addr;
                I_counter    <= LATENCY[$clog2(LATENCY+1)-1:0];
            end

            if (I_counter != 0) begin
                I_counter <= I_counter - 1'b1;

                if (I_counter == 1) begin
                    F_mem_inst[31:0]    <= line[I_saved_line][0];
                    F_mem_inst[63:32]   <= line[I_saved_line][1];
                    F_mem_inst[95:64]   <= line[I_saved_line][2];
                    F_mem_inst[127:96]  <= line[I_saved_line][3];
                    F_mem_valid         <= 1'b1;
                end
            end
        end
    end

    // ---------- Data-side read pipeline ----------
    always @(posedge clk) begin
        if (rst) begin
            MEM_mem_valid <= 1'b0;
            D_counter     <= {($clog2(LATENCY+1)){1'b0}};
        end else begin
            MEM_mem_valid <= 1'b0;

            // Start only when idle
            if (Dc_mem_req && (D_counter == 0)) begin
                D_saved_line <= Dc_mem_addr;
                D_counter    <= LATENCY[$clog2(LATENCY+1)-1:0];
            end

            if (D_counter != 0) begin
                D_counter <= D_counter - 1'b1;

                if (D_counter == 1) begin
                    MEM_data_line[31:0]    <= line[D_saved_line][0];
                    MEM_data_line[63:32]   <= line[D_saved_line][1];
                    MEM_data_line[95:64]   <= line[D_saved_line][2];
                    MEM_data_line[127:96]  <= line[D_saved_line][3];
                    MEM_mem_valid          <= 1'b1;
                end
            end
        end
    end

    // ---------- Data-side write-back (single-cycle line store) ----------
    always @(posedge clk) begin
        if (Dc_wb_we) begin
            line[Dc_wb_addr][0] <= Dc_wb_wline[31:0];
            line[Dc_wb_addr][1] <= Dc_wb_wline[63:32];
            line[Dc_wb_addr][2] <= Dc_wb_wline[95:64];
            line[Dc_wb_addr][3] <= Dc_wb_wline[127:96];
        end
    end

endmodule
