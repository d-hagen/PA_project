module mem_to_wb_reg #(
    parameter XLEN    = 32,
    parameter PC_BITS = 32,
    parameter TAG_W   = 4
)(
    input  wire                 clk,
    input  wire                 rst,

    // MEM stage inputs
    input  wire [XLEN-1:0]      MEM_data_mem,
    input  wire [4:0]           MEM_rd,
    input  wire                 MEM_we,
    input  wire [XLEN-1:0]      MEM_pc,
    input  wire                 MEM_jlx,

    // load-valid from MEM stage
    input  wire                 MEM_ld_valid,

    // ROB tag
    input  wire [TAG_W-1:0]     MEM_tag,

    // MUL completion inputs
    input  wire                 mul_done,
    input  wire [XLEN-1:0]      mul_result,
    input  wire [4:0]           mul_rd,
    input  wire [TAG_W-1:0]     mul_tag,

    input  wire                 dcache_stall,
    input  wire                 Dtlb_stall,

    // WB stage outputs
    output wire [XLEN-1:0]      WB_data_mem,
    output wire [4:0]           WB_rd,
    output wire                 WB_we,
    output wire [XLEN-1:0]      WB_pc,
    output wire                 WB_jlx,

    // flopped load-valid to WB
    output wire                 WB_ld_valid,

    // ROB tag at WB
    output wire [TAG_W-1:0]     WB_tag
);

    reg [XLEN-1:0]      wb_data_mem_r;
    reg [4:0]           wb_rd_r;
    reg                 wb_we_r;
    reg [XLEN-1:0]      wb_pc_r;
    reg                 wb_jlx_r;
    reg [TAG_W-1:0]     wb_tag_r;
    reg                 wb_ld_valid_r;

    // If MEM stage is stalled (or translation), prevent advancing this reg.
    // (Your design uses "insertNOP" rather than hold; keep your behavior.)
    wire insertNOP = (dcache_stall || Dtlb_stall) && !mul_done;

    always @(posedge clk) begin
        if (rst || insertNOP) begin
            wb_data_mem_r <= {XLEN{1'b0}};
            wb_rd_r       <= 5'd0;
            wb_we_r       <= 1'b0;
            wb_pc_r       <= {PC_BITS{1'b0}};
            wb_jlx_r      <= 1'b0;
            wb_tag_r      <= {TAG_W{1'b0}};
            wb_ld_valid_r <= 1'b0;
        end else begin
            if (mul_done) begin
                // MUL overrides MEM->WB
                wb_data_mem_r <= mul_result;
                wb_rd_r       <= mul_rd;
                wb_we_r       <= 1'b1;

                wb_pc_r       <= {PC_BITS{1'b0}};
                wb_jlx_r      <= 1'b0;

                wb_tag_r      <= mul_tag;

                // MUL result is valid
                wb_ld_valid_r <= 1'b1;
            end else begin
                // Normal MEM->WB (dcache already merged any SB forwarding)
                wb_data_mem_r <= MEM_data_mem;
                wb_rd_r       <= MEM_rd;
                wb_we_r       <= MEM_we;
                wb_pc_r       <= MEM_pc;
                wb_jlx_r      <= MEM_jlx;

                wb_tag_r      <= MEM_tag;
                wb_ld_valid_r <= MEM_ld_valid;
            end
        end
    end

    assign WB_data_mem = wb_data_mem_r;
    assign WB_rd       = wb_rd_r;
    assign WB_we       = wb_we_r;
    assign WB_pc       = wb_pc_r;
    assign WB_jlx      = wb_jlx_r;
    assign WB_tag      = wb_tag_r;
    assign WB_ld_valid = wb_ld_valid_r;

endmodule
