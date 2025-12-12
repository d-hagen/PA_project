module mem_to_wb_reg #(
    parameter XLEN    = 32,
    parameter PC_BITS = 32
)(
    input  wire                 clk,
    input  wire                 rst,

    // MEM stage inputs
    input  wire [XLEN-1:0]      MEM_data_mem,
    input  wire [4:0]           MEM_rd,
    input  wire                 MEM_we,
    input  wire [XLEN-1:0]   MEM_pc,
    input  wire                 MEM_jlx,

    // WB stage outputs
    output wire [XLEN-1:0]      WB_data_mem,
    output wire [4:0]           WB_rd,
    output wire                 WB_we,
    output wire [XLEN-1:0]   WB_pc,
    output wire                 WB_jlx
);

    reg [XLEN-1:0]      wb_data_mem_r;
    reg [4:0]           wb_rd_r;
    reg                 wb_we_r;
    reg [XLEN-1:0]   wb_pc_r;
    reg                 wb_jlx_r;

    always @(posedge clk) begin
        if (rst) begin
            wb_data_mem_r <= {XLEN{1'b0}};
            wb_rd_r       <= 5'd0;
            wb_we_r       <= 1'b0;
            wb_pc_r       <= {PC_BITS{1'b0}};
            wb_jlx_r      <= 1'b0;
        end else begin
            wb_data_mem_r <= MEM_data_mem;
            wb_rd_r       <= MEM_rd;
            wb_we_r       <= MEM_we;
            wb_pc_r       <= MEM_pc;
            wb_jlx_r      <= MEM_jlx;
        end
    end

    assign WB_data_mem = wb_data_mem_r;
    assign WB_rd       = wb_rd_r;
    assign WB_we       = wb_we_r;
    assign WB_pc       = wb_pc_r;
    assign WB_jlx      = wb_jlx_r;

endmodule
