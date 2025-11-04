////MISSING:  Branch/Jumps , Store Load hazards , Mul



module Hazard_unit #(
    parameter XLEN = 32,
    parameter ADDR_SIZE=5

)(
    input  wire [4:0]           D_rd,     
    input  wire [ADDR_SIZE-1:0] D_ra,      // first register to read
    input  wire [ADDR_SIZE-1:0] D_rb,      // second register to read  

    input wire [XLEN-1:0]  EX_alu_out,
    input wire [4:0]       EX_rd,
    input wire             EX_we,
    input wire             EX_ld,

    input  wire [4:0]       MEM_rd,
    input  wire             MEM_we,


    input wire [4:0]       WB_rd,
    input wire             WB_we,


    output wire            stall_D,     // stall F/D;
    output wire [1:0]      EX_D_bp,     // [forward ra , forward rb]
    output wire [1:0]      MEM_D_bp,
    output wire [1:0]      WB_D_bp
    );
    

  // RAW matches
  wire ex_hit_ra  = EX_we  && (EX_rd  == D_ra);
  wire ex_hit_rb  = EX_we  && (EX_rd  == D_rb);
  wire mem_hit_ra = MEM_we && (MEM_rd == D_ra);
  wire mem_hit_rb = MEM_we && (MEM_rd == D_rb);
  wire wb_hit_ra  = WB_we  && (WB_rd  == D_ra);
  wire wb_hit_rb  = WB_we  && (WB_rd  == D_rb);

  // Load-use stall (EX load needed by D’s sources)
  assign stall_D = EX_ld && (ex_hit_ra || ex_hit_rb);

  // Forwarding enables per stage (don’t forward from EX if it’s a load)
  assign EX_D_bp  = { (ex_hit_ra && !EX_ld), (ex_hit_rb && !EX_ld) };
  assign MEM_D_bp = {  mem_hit_ra,            mem_hit_rb           };
  assign WB_D_bp  = {   wb_hit_ra,             wb_hit_rb           };

endmodule