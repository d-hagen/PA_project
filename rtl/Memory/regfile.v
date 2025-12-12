module regfile #(
  parameter XLEN=32,
  parameter REG_NUM=32,
  parameter ADDR_SIZE=5,
  parameter PC_BITS = 20,
  parameter VPC_BITS = 32
)(
  input  wire                 clk,

  // Decode register IDs and control
  input  wire [ADDR_SIZE-1:0] D_ra,
  input  wire [ADDR_SIZE-1:0] D_rb,
  input  wire [10:0]          D_imd,
  input  wire [VPC_BITS-1:0]   D_pc,
  input  wire                 D_ld,
  input  wire                 D_str,
  input  wire                 D_brn,
  input wire                  D_jmp,
  input  wire                 D_addi,

  // Bypass enables (encoding: {forward_ra, forward_rb})
  input  wire [1:0]           EX_D_bp,
  input  wire [1:0]           MEM_D_bp,
  input  wire [1:0]           WB_D_bp,

  // Bypass data sources
  input  wire [XLEN-1:0]      EX_alu_out,   // EX result (valid when EX_D_bp used and not a load-use)
  input  wire [XLEN-1:0]      MEM_data_mem, // data available at MEM stage (ALU result or load data, per your design)

  // Writeback
  input  wire                 WB_we,
  input  wire [ADDR_SIZE-1:0] WB_rd,
  input  wire [XLEN-1:0]      WB_data_mem, 

  // Outputs after decode
  output wire [XLEN-1:0]      D_a,
  output wire [XLEN-1:0]      D_b,
  output wire [XLEN-1:0]      D_a2,
  output wire [XLEN-1:0]      D_b2
);

 

  // Register file storage
  reg [XLEN-1:0] regs [0:REG_NUM-1];
  integer i;
  initial begin
    for (i = 0; i < REG_NUM; i = i + 1) regs[i] = {XLEN{1'b0}};
  end

  // Write port (x0 hardwired to 0)
  always @(posedge clk) begin
    if (WB_we && (WB_rd != {ADDR_SIZE{1'b0}}))
      regs[WB_rd] <= WB_data_mem;
    regs[0] <= {XLEN{1'b0}};
  end

  // Raw regfile reads
  wire [XLEN-1:0] ra_raw = regs[D_ra];
  wire [XLEN-1:0] rb_raw = regs[D_rb];

  // Forwarding priority: EX > MEM > WB
  // Bit mapping for each bus: {ra, rb} = {MSB, LSB}
  wire [XLEN-1:0] ra_fwd =
      EX_D_bp[1]  ? EX_alu_out   :
      MEM_D_bp[1] ? MEM_data_mem :
      WB_D_bp[1]  ? WB_data_mem  :
                    ra_raw;

  wire [XLEN-1:0] rb_fwd =
      EX_D_bp[0]  ? EX_alu_out   :
      MEM_D_bp[0] ? MEM_data_mem :
      WB_D_bp[0]  ? WB_data_mem  :
                    rb_raw;

  // Outputs
  assign D_a2 = ra_fwd;
  assign D_b2 = rb_fwd;

  assign D_a  = (D_brn & !D_jmp) ? D_pc : ra_fwd;
  assign D_b  = (D_str || D_ld || D_addi || D_brn)
                ? {{(XLEN-11){D_imd[10]}}, D_imd}  //{{(XLEN-11){D_imd[10]}}
                : rb_fwd;

endmodule
