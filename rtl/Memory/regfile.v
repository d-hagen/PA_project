`timescale 1ns/1ps

module regfile_rob #(
  parameter integer XLEN      = 32,
  parameter integer REG_NUM   = 32,
  parameter integer ADDR_SIZE = 5,
  parameter integer VPC_BITS  = 32,
  parameter integer ROB_DEPTH = 16,
  parameter integer TAG_W     = $clog2(ROB_DEPTH)
)(
  input  wire                   clk,
  input  wire                   rst,

  input  wire [ADDR_SIZE-1:0]   D_ra,
  input  wire [ADDR_SIZE-1:0]   D_rb,
  input  wire [10:0]            D_imd,
  input  wire [VPC_BITS-1:0]    D_pc,
  input  wire                   D_ld,
  input  wire                   D_str,
  input  wire                   D_brn,
  input  wire                   D_jmp,
  input  wire                   D_iret,  
  input  wire                   D_addi,

  input  wire                   RN_ra_is_rob,
  input  wire                   RN_rb_is_rob,
  input  wire [TAG_W-1:0]       RN_ra_tag,
  input  wire [TAG_W-1:0]       RN_rb_tag,

  input  wire                   ROB_ra_ready,
  input  wire [XLEN-1:0]        ROB_ra_value,
  input  wire                   ROB_rb_ready,
  input  wire [XLEN-1:0]        ROB_rb_value,

  input  wire [2:0]             EX_D_bp,
  input  wire [2:0]             MEM_D_bp,
  input  wire [2:0]             WB_D_bp,

  input  wire [XLEN-1:0]        EX_alu_out,
  input  wire [XLEN-1:0]        MEM_data_mem,
  input  wire [XLEN-1:0]        EX_pc,
  input  wire [XLEN-1:0]        MEM_pc,

  input  wire [XLEN-1:0]        WB_data_mem,
  input  wire [VPC_BITS-1:0]    WB_pc,
  input  wire                   WB_jlx,

  // Commit write to architectural regfile
  input  wire                   C_we,
  input  wire [ADDR_SIZE-1:0]   C_rd,
  input  wire [XLEN-1:0]        C_value,

  // Tag-bypass from Hazard_unit
  input  wire                   RA_tag_bp_valid,
  input  wire [XLEN-1:0]        RA_tag_bp_value,
  input  wire                   RB_tag_bp_valid,
  input  wire [XLEN-1:0]        RB_tag_bp_value,

  // Exception commit inputs
  input  wire                   EXC_we,
  input  wire [XLEN-1:0]        EXC_pc,
  input  wire [3:0]             EXC_type,

  // Exception registers
  output wire [XLEN-1:0]        rm1,
  output wire [31:0]            rm2,

  output wire [XLEN-1:0]        D_a,
  output wire [XLEN-1:0]        D_b,
  output wire [XLEN-1:0]        D_a2,
  output wire [XLEN-1:0]        D_b2,

  output wire                   RF_stall
);

  // ------------------------------------
  // Architectural register file
  // ------------------------------------
  reg [XLEN-1:0] regs [0:REG_NUM-1];
  integer i;
  initial begin
    for (i = 0; i < REG_NUM; i = i + 1)
      regs[i] = {XLEN{1'b0}};
  end

  // ------------------------------------
  // Exception registers (rm1 / rm2)
  // ------------------------------------
  reg [XLEN-1:0] rm1_r;
  reg [31:0]     rm2_r;

  assign rm1 = rm1_r;
  assign rm2 = rm2_r;

  always @(posedge clk) begin
    if (C_we && (C_rd != {ADDR_SIZE{1'b0}}))
      regs[C_rd] <= C_value;

    regs[0] <= {XLEN{1'b0}};

    if (EXC_we) begin
      rm1_r <= EXC_pc;
      rm2_r <= {28'd0, EXC_type};
    end
    if (rst) begin
      rm1_r <= 32'h0000_1000;
    end

  end

  wire [XLEN-1:0] ra_raw = regs[D_ra];
  wire [XLEN-1:0] rb_raw = regs[D_rb];

  // ------------------------------------
  // Forwarding network
  // ------------------------------------
  wire [XLEN-1:0] EX_fwd_val  = EX_D_bp[0]  ? (EX_pc  + 32'd4) : EX_alu_out;
  wire [XLEN-1:0] MEM_fwd_val = MEM_D_bp[0] ? (MEM_pc + 32'd4) : MEM_data_mem;
  wire [XLEN-1:0] WB_fwd_val  = WB_jlx      ? (WB_pc  + 32'd4) : WB_data_mem;

  wire [XLEN-1:0] ra_arch_fwd =
      EX_D_bp[2]  ? EX_fwd_val  :
      MEM_D_bp[2] ? MEM_fwd_val :
      WB_D_bp[2]  ? WB_fwd_val  :
                    ra_raw;

  wire [XLEN-1:0] rb_arch_fwd =
      EX_D_bp[1]  ? EX_fwd_val  :
      MEM_D_bp[1] ? MEM_fwd_val :
      WB_D_bp[1]  ? WB_fwd_val  :
                    rb_raw;

  // ------------------------------------
  // Rename / ROB resolution
  // ------------------------------------
  wire ra_satisfied = !RN_ra_is_rob ? 1'b1 : (RA_tag_bp_valid | ROB_ra_ready);
  wire rb_satisfied = !RN_rb_is_rob ? 1'b1 : (RB_tag_bp_valid | ROB_rb_ready);

  wire [XLEN-1:0] ra_rob_or_bp = RA_tag_bp_valid ? RA_tag_bp_value : ROB_ra_value;
  wire [XLEN-1:0] rb_rob_or_bp = RB_tag_bp_valid ? RB_tag_bp_value : ROB_rb_value;

  wire [XLEN-1:0] ra_final = RN_ra_is_rob ? ra_rob_or_bp : ra_arch_fwd;
  wire [XLEN-1:0] rb_final = RN_rb_is_rob ? rb_rob_or_bp : rb_arch_fwd;

  assign D_a2 = ra_final;
  assign D_b2 = rb_final;

  // ------------------------------------
  // FINAL OPERAND SELECTION
  // ------------------------------------
  assign D_a =   (D_brn & !D_jmp)    ? D_pc :
                            ra_final;
  //CHECK: use rd rb to extend offset sizes (str, ld, addi)
  assign D_b =
      (D_str || D_ld || D_addi || D_brn)
        ? {{(XLEN-11){D_imd[10]}}, D_imd}
        : rb_final;

  assign RF_stall = !ra_satisfied || !rb_satisfied;

endmodule
