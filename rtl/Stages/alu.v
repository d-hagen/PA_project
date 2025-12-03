module alu #(
  parameter XLEN = 32,
  parameter integer PC_BITS = 20,
  parameter integer VPC_BITS = 32
) (
  input  wire [XLEN-1:0]     EX_a,
  input  wire [XLEN-1:0]     EX_a2,
  input  wire [XLEN-1:0]     EX_b,
  input  wire [XLEN-1:0]     EX_b2,
  input  wire [3:0]          EX_alu_op,
  input  wire                EX_brn,
  input  wire                EX_BP_taken,
  input wire [VPC_BITS-1:0]   EX_BP_target_pc, // BP: Flopped target PC


  output reg  [XLEN-1:0]     EX_alu_out,
  output reg                 EX_taken, //flush or no flush 
  output reg                 EX_true_taken //true taken independent of flushing
);

  localparam SHW = (XLEN <= 1) ? 1 : $clog2(XLEN);

  reg [XLEN-1:0] next_pc;

  always @(*) begin
    EX_alu_out     = {XLEN{1'b0}};
    EX_taken       = 1'b0;
    EX_true_taken  = 1'b0;
    next_pc       = {XLEN{1'b0}};

    if (EX_brn) begin
     
      case (EX_alu_op)
        4'b1000: EX_true_taken = (EX_a2 == EX_b2);
        4'b1001: EX_true_taken = (EX_a2 <  EX_b2);
        4'b1010: EX_true_taken = (EX_a2 >  EX_b2);
        default: EX_true_taken = 1'b1;
      endcase

      if (EX_true_taken)                        
        next_pc = EX_a + EX_b;   ///branch target
      else
        next_pc = EX_a + {{(XLEN-3){1'b0}}, 3'b100}; //next instruction after branch

      EX_alu_out =  next_pc;     /// correct location to jump to
      EX_taken   = (EX_BP_taken ^ EX_true_taken || EX_BP_target_pc ^  EX_alu_out);   /// if they dont match -> flush the pipeline

    end else begin   // non jump operations
      case (EX_alu_op)
        4'b0000: EX_alu_out = EX_a + EX_b;
        4'b0001: EX_alu_out = EX_a - EX_b;
        4'b0010: EX_alu_out = EX_a & EX_b;
        4'b0011: EX_alu_out = EX_a | EX_b;
        4'b0100: EX_alu_out = EX_a ^ EX_b;
        4'b0101: EX_alu_out = ~EX_a;
        4'b0110: EX_alu_out = EX_a << EX_b[SHW-1:0];
        4'b0111: EX_alu_out = EX_a >> EX_b[SHW-1:0];
        4'b1000: EX_alu_out = {{(XLEN-1){1'b0}}, (EX_a == EX_b)};
        4'b1001: EX_alu_out = {{(XLEN-1){1'b0}}, (EX_a <  EX_b)};
        4'b1010: EX_alu_out = {{(XLEN-1){1'b0}}, (EX_a >  EX_b)};
        4'b1011: EX_alu_out = EX_a * EX_b;
        default: EX_alu_out = EX_a + EX_b;
      endcase

      EX_taken      = 1'b0;
      EX_true_taken = 1'b0;
    end
  end
endmodule
