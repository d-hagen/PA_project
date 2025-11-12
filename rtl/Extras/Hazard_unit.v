module Hazard_unit #(
    parameter XLEN = 32,
    parameter ADDR_SIZE=5,
    parameter MUL_STALLS = 4
)(
    input  wire                 clk,
    input  wire                 rst,   
    input  wire [4:0]           D_rd,     
    input  wire [ADDR_SIZE-1:0] D_ra,      // first register to read
    input  wire [ADDR_SIZE-1:0] D_rb,      // second register to read  
    

    input wire [XLEN-1:0]  EX_alu_out,
    input wire [4:0]       EX_rd,
    input wire             EX_we,
    input wire             EX_ld,
    input  wire            EX_mul,

    input  wire [4:0]       MEM_rd,
    input  wire             MEM_we,

    input wire [4:0]       WB_rd,
    input wire             WB_we,
    

    output wire            stall_D,     // stall F/D;
    output wire [1:0]      EX_D_bp,     // [forward ra , forward rb]
    output wire [1:0]      MEM_D_bp,
    output wire [1:0]      WB_D_bp
    );


  reg  [2:0] mul_cnt;

  wire mul_start  = EX_mul && (mul_cnt == 3'd0); // check if first cycle of mull

  // Count down to 0; load 5 on first sight of MUL
  always @(posedge clk) begin
    if (rst) begin
      mul_cnt <= 3'd0;
    end else if (mul_start) begin
      mul_cnt <= MUL_STALLS;   // load 5
    end else if (mul_cnt != 3'd0) begin
      mul_cnt <= mul_cnt - 3'd1;    
    end
  end

  wire mul_stall = (mul_cnt != 3'd0);
    

  // RAW matches
  wire ex_hit_ra  = EX_we  && (EX_rd  == D_ra);
  wire ex_hit_rb  = EX_we  && (EX_rd  == D_rb);
  wire mem_hit_ra = MEM_we && (MEM_rd == D_ra);
  wire mem_hit_rb = MEM_we && (MEM_rd == D_rb);
  wire wb_hit_ra  = WB_we  && (WB_rd  == D_ra);
  wire wb_hit_rb  = WB_we  && (WB_rd  == D_rb);

  // Load-use stall (EX load needed by D’s sources)
  assign stall_D = (EX_ld && (ex_hit_ra || ex_hit_rb )) || mul_stall;

  // Forwarding enables per stage (don’t forward from EX if it’s a load)
  assign EX_D_bp  = { (ex_hit_ra && !EX_ld), (ex_hit_rb && !EX_ld) };
  assign MEM_D_bp = {  mem_hit_ra,            mem_hit_rb           };
  assign WB_D_bp  = {   wb_hit_ra,             wb_hit_rb           };

endmodule
