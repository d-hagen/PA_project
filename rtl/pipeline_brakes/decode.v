module d_to_ex_reg #(
    parameter XLEN    = 32,
    parameter PC_BITS = 20,
    parameter integer VPC_BITS = 32
)(
    input  wire             clk,
    input  wire             rst,

    // D stage inputs (Source)
    input  wire [XLEN-1:0]      D_a,
    input  wire [XLEN-1:0]      D_a2,
    input  wire [XLEN-1:0]      D_b,
    input  wire [XLEN-1:0]      D_b2,
    input  wire [3:0]           D_alu_op,
    input  wire                 D_brn,
    input  wire [4:0]           D_rd,
    input  wire                 D_ld,
    input  wire                 D_str,
    input  wire                 D_byt,
    input  wire                 D_we,
    input  wire                 D_mul,
    input  wire                 D_jlx,

    input  wire [VPC_BITS-1:0]  D_pc,

    input  wire                 D_BP_taken,
    input  wire [VPC_BITS-1:0]  D_BP_target_pc,

    // Stall/Flush/Taken Signals
    input wire                  stall_D,
    input wire                  MEM_stall,
    input                       EX_taken,

    // EX stage outputs (Destination)
    output wire [XLEN-1:0]      EX_a,
    output wire [XLEN-1:0]      EX_a2,
    output wire [XLEN-1:0]      EX_b,
    output wire [XLEN-1:0]      EX_b2,
    output wire [3:0]           EX_alu_op,
    output wire [4:0]           EX_rd,
    output wire                 EX_ld,
    output wire                 EX_str,
    output wire                 EX_byt,
    output wire                 EX_we,
    output wire                 EX_brn,
    output wire                 EX_BP_taken,
    output wire [VPC_BITS-1:0]  EX_BP_target_pc,
    output wire                 EX_mul,
    output wire [VPC_BITS-1:0]  EX_pc,
    output wire                 EX_jlx
);

    reg [XLEN-1:0]      ex_a_r, ex_a2_r, ex_b_r, ex_b2_r;
    reg [3:0]           ex_alu_op_r;
    reg                 ex_brn_r, ex_bp_taken_r;
    reg [4:0]           ex_rd_r;
    reg                 ex_ld_r, ex_str_r, ex_byt_r, ex_we_r, ex_mul_r;

    reg [VPC_BITS-1:0]  ex_bp_target_pc_r;
    reg [VPC_BITS-1:0]  ex_pc_r;
    reg                 ex_jlx_r;

    always @(posedge clk) begin
        if (rst || stall_D || EX_taken) begin
            ex_a_r            <= {XLEN{1'b0}};
            ex_a2_r           <= {XLEN{1'b0}};
            ex_b_r            <= {XLEN{1'b0}};
            ex_b2_r           <= {XLEN{1'b0}};
            ex_alu_op_r       <= 4'd0;
            ex_brn_r          <= 1'b0;
            ex_bp_taken_r     <= 1'b0;
            ex_rd_r           <= 5'd0;
            ex_ld_r           <= 1'b0;
            ex_str_r          <= 1'b0;
            ex_byt_r          <= 1'b0;
            ex_we_r           <= 1'b0;
            ex_mul_r          <= 1'b0;
            ex_bp_target_pc_r <= {VPC_BITS{1'b0}};
            ex_pc_r           <= {VPC_BITS{1'b0}};
            ex_jlx_r          <= 1'b0;
        end
        else if (!MEM_stall) begin
            ex_a_r            <= D_a;
            ex_a2_r           <= D_a2;
            ex_b_r            <= D_b;
            ex_b2_r           <= D_b2;
            ex_alu_op_r       <= D_alu_op;
            ex_brn_r          <= D_brn;
            ex_bp_taken_r     <= D_BP_taken;
            ex_rd_r           <= D_rd;
            ex_ld_r           <= D_ld;
            ex_str_r          <= D_str;
            ex_byt_r          <= D_byt;
            ex_we_r           <= D_we;
            ex_mul_r          <= D_mul;
            ex_bp_target_pc_r <= D_BP_target_pc;
            ex_pc_r           <= D_pc;
            ex_jlx_r          <= D_jlx;
        end
    end

    assign EX_a            = ex_a_r;
    assign EX_a2           = ex_a2_r;
    assign EX_b            = ex_b_r;
    assign EX_b2           = ex_b2_r;
    assign EX_alu_op       = ex_alu_op_r;
    assign EX_brn          = ex_brn_r;
    assign EX_BP_taken     = ex_bp_taken_r;
    assign EX_rd           = ex_rd_r;
    assign EX_ld           = ex_ld_r;
    assign EX_str          = ex_str_r;
    assign EX_byt          = ex_byt_r;
    assign EX_we           = ex_we_r;
    assign EX_mul          = ex_mul_r;
    assign EX_BP_target_pc = ex_bp_target_pc_r;
    assign EX_pc           = ex_pc_r;
    assign EX_jlx          = ex_jlx_r;

endmodule
