module Hazard_unit #(
    parameter XLEN = 32,
    parameter ADDR_SIZE = 5,
    parameter MUL_STALLS = 4
)(
    input  wire                 clk,
    input  wire                 rst,

    input  wire [4:0]           D_rd,
    input  wire [ADDR_SIZE-1:0] D_ra,
    input  wire [ADDR_SIZE-1:0] D_rb,

    input  wire [XLEN-1:0]      EX_alu_out,
    input  wire [4:0]           EX_rd,
    input  wire                 EX_we,
    input  wire                 EX_ld,
    input  wire                 EX_mul,
    input  wire                 EX_jlx,

    input  wire [4:0]           MEM_rd,
    input  wire                 MEM_we,
    input  wire                 MEM_jlx,

    input  wire [4:0]           WB_rd,
    input  wire                 WB_we,
    input  wire                 WB_jlx,

    output wire                 stall_D,
    output wire [2:0]           EX_D_bp,
    output wire [2:0]           MEM_D_bp,
    output wire [2:0]           WB_D_bp
);

  reg  [2:0] mul_cnt;

  wire mul_start = EX_mul && (mul_cnt == 3'd0);

  always @(posedge clk) begin
    if (rst)
      mul_cnt <= 3'd0;
    else if (mul_start)
      mul_cnt <= MUL_STALLS[2:0];
    else if (mul_cnt != 3'd0)
      mul_cnt <= mul_cnt - 3'd1;
  end

  wire mul_stall = (mul_cnt != 3'd0);

  wire ex_hit_ra  = (EX_we  && (EX_rd  == D_ra)) || (EX_jlx  && (D_ra == 5'd31));
  wire ex_hit_rb  = (EX_we  && (EX_rd  == D_rb)) || (EX_jlx  && (D_rb == 5'd31));

  wire mem_hit_ra = (MEM_we && (MEM_rd == D_ra)) || (MEM_jlx && (D_ra == 5'd31));
  wire mem_hit_rb = (MEM_we && (MEM_rd == D_rb)) || (MEM_jlx && (D_rb == 5'd31));

  wire wb_hit_ra  = (WB_we  && (WB_rd  == D_ra)) || (WB_jlx  && (D_ra == 5'd31));
  wire wb_hit_rb  = (WB_we  && (WB_rd  == D_rb)) || (WB_jlx  && (D_rb == 5'd31));

  assign stall_D = (EX_ld && (ex_hit_ra || ex_hit_rb)) || mul_stall;

  assign EX_D_bp  = { (ex_hit_ra  && !EX_ld),
                      (ex_hit_rb  && !EX_ld),
                       EX_jlx };

  assign MEM_D_bp = {  mem_hit_ra,
                       mem_hit_rb,
                       MEM_jlx };

  assign WB_D_bp  = {   wb_hit_ra,
                        wb_hit_rb,
                        WB_jlx };

endmodule
