module unified_mem #(
    parameter XLEN          = 32,
    parameter LATENCY       = 3,
    parameter LINE_BITS     = 16,                 // upper 16 bits of the 20-bit address
    parameter WORDS_PER_LINE= 4
)(
    input  wire                     clk,
    input  wire                     rst,

    // ---------- Instruction side (I-cache) ----------
    input  wire                     Ic_mem_req,    // start memory fetch
    input  wire [LINE_BITS-1:0]     Ic_mem_addr,   // line index (upper 16 bits of 20-bit addr)

    output reg  [XLEN*WORDS_PER_LINE-1:0] F_mem_inst,   // full line: 4×32 bits
    output reg                      F_mem_valid,

    // ---------- Data side (D-cache) ----------
    // Line read (for cache misses)
    input  wire                     Dc_mem_req,    // start line read
    input  wire [LINE_BITS-1:0]     Dc_mem_addr,   // line index

    output reg  [XLEN*WORDS_PER_LINE-1:0] MEM_data_line, // full line: 4×32 bits
    output reg                      MEM_mem_valid,       // line ready

    // Line write-back (on eviction)
    input  wire                     Dc_wb_we,      // 1 = write line
    input  wire [LINE_BITS-1:0]     Dc_wb_addr,    // line index to write
    input  wire [XLEN*WORDS_PER_LINE-1:0] Dc_wb_wline // line data from cache
);

    localparam NUM_LINES = (1 << LINE_BITS);

    // Shared memory: NUM_LINES lines, each WORDS_PER_LINE words of XLEN bits
    reg [XLEN-1:0] line [0:NUM_LINES-1][0:WORDS_PER_LINE-1];   // [line][word]

    // Separate pipelines for I-side and D-side reads
    reg [$clog2(LATENCY+1)-1:0] I_counter;
    reg [LINE_BITS-1:0]         I_saved_line;

    reg [$clog2(LATENCY+1)-1:0] D_counter;
    reg [LINE_BITS-1:0]         D_saved_line;

    integer i, j;

    // ---------- Initialization ----------
    initial begin
        // Clear everything
        for (i = 0; i < NUM_LINES; i = i + 1) begin
            for (j = 0; j < WORDS_PER_LINE; j = j + 1) begin
                line[i][j] = {XLEN{1'b0}};
            end
        end

        // Initialize program into memory.
        // This assumes program.hex is formatted to match the 2D array.
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
                    // Pack 4 words into F_mem_inst (assuming WORDS_PER_LINE == 4)
                    F_mem_inst[XLEN*1-1:XLEN*0] <= line[I_saved_line][0];
                    F_mem_inst[XLEN*2-1:XLEN*1] <= line[I_saved_line][1];
                    F_mem_inst[XLEN*3-1:XLEN*2] <= line[I_saved_line][2];
                    F_mem_inst[XLEN*4-1:XLEN*3] <= line[I_saved_line][3];
                    F_mem_valid                  <= 1'b1;
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
                    MEM_data_line[XLEN*1-1:XLEN*0] <= line[D_saved_line][0];
                    MEM_data_line[XLEN*2-1:XLEN*1] <= line[D_saved_line][1];
                    MEM_data_line[XLEN*3-1:XLEN*2] <= line[D_saved_line][2];
                    MEM_data_line[XLEN*4-1:XLEN*3] <= line[D_saved_line][3];
                    MEM_mem_valid                   <= 1'b1;
                end
            end
        end
    end

    // ---------- Data-side write-back (single-cycle line store) ----------
    always @(posedge clk) begin
        if (Dc_wb_we) begin
            line[Dc_wb_addr][0] <= Dc_wb_wline[XLEN*1-1:XLEN*0];
            line[Dc_wb_addr][1] <= Dc_wb_wline[XLEN*2-1:XLEN*1];
            line[Dc_wb_addr][2] <= Dc_wb_wline[XLEN*3-1:XLEN*2];
            line[Dc_wb_addr][3] <= Dc_wb_wline[XLEN*4-1:XLEN*3];
        end
    end

endmodule
