module instruct_reg #(parameter XLEN=32, parameter REG_NUM=32, parameter ADDR_SIZE= 5)(

  input  wire             clk,          // clock
  input  wire [4:0]       F_pc,    // which instruction to read
  output wire [XLEN-1:0]  F_inst     // oop code
);
 

reg [XLEN-1:0] regs [0:REG_NUM-1];
initial begin
  $readmemh("program.hex", regs);
end

assign F_inst = regs[F_pc];


endmodule
