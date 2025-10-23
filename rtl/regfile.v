module regfile #(parameter XLEN=32, parameter REG_NUM=32, parameter ADDR_SIZE=5)(
  input  wire                 clk,          // clock

  //From decode operation
  input  wire [ADDR_SIZE-1:0] D_ra,      // first register to read
  input  wire [ADDR_SIZE-1:0] D_rb,      // second register to read
  input  wire [10:0]          D_imd,
  input  wire [4:0]           D_pc,
  input wire                  D_ld,
  input wire                  D_str,
  input wire                  D_brn,



  //From WB Flops
  input  wire                 WB_we,           // write enable (1 = write happens)
  input  wire [ADDR_SIZE-1:0] WB_rd,      // which register to write
  input  wire [XLEN-1:0]      WB_data_mem,      // data to write *
                                    
  output wire [XLEN-1:0]      D_a,      // value of raddr1
  output wire [XLEN-1:0]      D_b,       // value of raddr2
  output wire [XLEN-1:0]      D_a2,       // value of raddr2
  output wire [XLEN-1:0]      D_b2     // value of raddr2


);

  wire [XLEN-1:0] offset = {{(XLEN-11){1'b0}}, D_imd};
  wire [XLEN-1:0] pc_extended = {{(XLEN-5){1'b0}}, D_pc};

  

  reg [XLEN-1:0] regs [0:REG_NUM-1];
  integer i;

  initial begin
    for (i = 0; i < REG_NUM; i = i + 1)
      regs[i] = {XLEN{1'b0}};
  end

  // write value rd if we is true and not onto reg 0
  always @(posedge clk) begin
    if (WB_we && WB_rd != {ADDR_SIZE{1'b0}})   // register 0 is read-only (always 0)
        regs[WB_rd] <= WB_data_mem;

    regs[0] <= {XLEN{1'b0}};                  // make sure r0 always stays 0
  end

  // read values from addr_ra and addr_rb onto ra and rb wire 

  assign D_a2 = regs[D_ra];
  assign D_b2 = regs[D_rb];
  assign D_b  = (D_str || D_ld ||D_brn) ? offset : regs[D_rb];
  assign D_a  = D_brn ? pc_extended : regs[D_ra];

endmodule
