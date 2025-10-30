module memory #(parameter XLEN=32, parameter REG_NUM=32, parameter ADDR_SIZE=5)(
  input  wire                 clk,          // clock
  input  wire                 MEM_ld,
  input  wire                 MEM_str,
  input  wire [XLEN-1:0]      MEM_alu_out,      // data to write
  input  wire [XLEN-1:0]      MEM_b2, 
  output wire [XLEN-1:0]      MEM_data_mem    // value of raddr1
);

  reg [XLEN-1:0] regs [0:REG_NUM-1];
  wire [ADDR_SIZE-1:0] addr = MEM_alu_out[ADDR_SIZE-1:0];
  integer i;

  initial begin
    for (i = 0; i < REG_NUM; i = i + 1)
      regs[i] = {XLEN{1'b0}};
  end

  // write value rd if we is true and not onto reg 0
  always @(posedge clk) begin
      if (MEM_str)
        regs[addr] <= MEM_b2;
  end

  assign MEM_data_mem = MEM_ld ? regs[addr] : MEM_alu_out;

endmodule