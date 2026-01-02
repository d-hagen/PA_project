module Hazard_unit #(
    parameter XLEN = 32,
    parameter ADDR_SIZE = 5
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

    // NEW: MUL dependency tracking (from your mul_pipe_single)
    input  wire                 mul_busy,
    input  wire [4:0]           mul_busy_rd,

    output wire                 stall_D,
    output wire [2:0]           EX_D_bp,
    output wire [2:0]           MEM_D_bp,
    output wire [2:0]           WB_D_bp
);



  wire ex_hit_ra  = (EX_we  && (EX_rd  == D_ra)) || (EX_jlx  && (D_ra == 5'd31));
  wire ex_hit_rb  = (EX_we  && (EX_rd  == D_rb)) || (EX_jlx  && (D_rb == 5'd31));

  wire mem_hit_ra = (MEM_we && (MEM_rd == D_ra)) || (MEM_jlx && (D_ra == 5'd31));
  wire mem_hit_rb = (MEM_we && (MEM_rd == D_rb)) || (MEM_jlx && (D_rb == 5'd31));

  wire wb_hit_ra  = (WB_we  && (WB_rd  == D_ra)) || (WB_jlx  && (D_ra == 5'd31));
  wire wb_hit_rb  = (WB_we  && (WB_rd  == D_rb)) || (WB_jlx  && (D_rb == 5'd31));

  // NEW: RAW dependency on in-flight MUL result (treat like "not ready yet")
  wire mul_hit_ra = mul_busy && (mul_busy_rd == D_ra) && (D_ra != {ADDR_SIZE{1'b0}});
  wire mul_hit_rb = mul_busy && (mul_busy_rd == D_rb) && (D_rb != {ADDR_SIZE{1'b0}});

  // Stall on: load-use hazard OR MUL operand needed OR your existing mul_cnt stall
  assign stall_D = (EX_ld && (ex_hit_ra || ex_hit_rb)) ||
                   mul_hit_ra || mul_hit_rb;

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
