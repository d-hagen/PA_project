module mem_to_wb_reg #(
    parameter XLEN    = 32,
    parameter PC_BITS = 32,
    parameter TAG_W   = 4   // NEW: ROB tag width
)(
    input  wire                 clk,
    input  wire                 rst,

    // MEM stage inputs
    input  wire [XLEN-1:0]      MEM_data_mem,
    input  wire [4:0]           MEM_rd,
    input  wire                 MEM_we,
    input  wire [XLEN-1:0]      MEM_pc,
    input  wire                 MEM_jlx,

    // NEW: ROB tag for this MEM-stage instruction
    input  wire [TAG_W-1:0]     MEM_tag,

    // From Store Buffer forwarding
    input  wire                 sb_hit,
    input  wire [XLEN-1:0]      sb_data,

    // ---- MUL completion inputs (from M5) ----
    input  wire                 mul_done,
    input  wire [XLEN-1:0]      mul_result,
    input  wire [4:0]           mul_rd,
    input  wire [TAG_W-1:0]     mul_tag,     // NEW: ROB tag of the completed MUL

    // WB stage outputs
    output wire [XLEN-1:0]      WB_data_mem,
    output wire [4:0]           WB_rd,
    output wire                 WB_we,
    output wire [XLEN-1:0]      WB_pc,
    output wire                 WB_jlx,

    // NEW: ROB tag at WB (must match WB_data_mem/WB_we producer)
    output wire [TAG_W-1:0]     WB_tag
);

    reg [XLEN-1:0]      wb_data_mem_r;
    reg [4:0]           wb_rd_r;
    reg                 wb_we_r;
    reg [XLEN-1:0]      wb_pc_r;
    reg                 wb_jlx_r;
    reg [TAG_W-1:0]     wb_tag_r;

    always @(posedge clk) begin
        if (rst) begin
            wb_data_mem_r <= {XLEN{1'b0}};
            wb_rd_r       <= 5'd0;
            wb_we_r       <= 1'b0;
            wb_pc_r       <= {PC_BITS{1'b0}};
            wb_jlx_r      <= 1'b0;
            wb_tag_r      <= {TAG_W{1'b0}};
        end else begin
            if (mul_done) begin
                // MUL overrides MEM->WB this cycle
                wb_data_mem_r <= mul_result;
                wb_rd_r       <= mul_rd;
                wb_we_r       <= 1'b1;

                wb_pc_r       <= {PC_BITS{1'b0}};
                wb_jlx_r      <= 1'b0;

                wb_tag_r      <= mul_tag;     // IMPORTANT
            end else begin
                // Normal MEM->WB
                wb_data_mem_r <= sb_hit ? sb_data : MEM_data_mem;
                wb_rd_r       <= MEM_rd;
                wb_we_r       <= MEM_we;
                wb_pc_r       <= MEM_pc;
                wb_jlx_r      <= MEM_jlx;

                wb_tag_r      <= MEM_tag;     // IMPORTANT
            end
        end
    end

    assign WB_data_mem = wb_data_mem_r;
    assign WB_rd       = wb_rd_r;
    assign WB_we       = wb_we_r;
    assign WB_pc       = wb_pc_r;
    assign WB_jlx      = wb_jlx_r;
    assign WB_tag      = wb_tag_r;

endmodule
