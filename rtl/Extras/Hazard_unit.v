module Hazard_unit #(
    parameter XLEN = 32,
    parameter ADDR_SIZE = 5,
    parameter ROB_DEPTH = 16,
    parameter TAG_W = $clog2(ROB_DEPTH)
)(
    input  wire                 clk,
    input  wire                 rst,

    // Arch regs (for your existing rd-based forwarding bits)
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

    // ---------------------------
    // NEW: Renamed operand info (from rename/RAT)
    // ---------------------------
    input  wire                 RN_ra_is_rob,
    input  wire                 RN_rb_is_rob,
    input  wire [TAG_W-1:0]     RN_ra_tag,
    input  wire [TAG_W-1:0]     RN_rb_tag,

    // ---------------------------
    // NEW: Producer tags/values in the pipe (carry dst_tag in pipeline regs)
    // These are "this stage is producing a result for ROB tag X"
    // ---------------------------
    input  wire                 EX_tag_we,
    input  wire [TAG_W-1:0]     EX_dst_tag,
    input  wire [XLEN-1:0]      EX_tag_value,

    input  wire                 MEM_tag_we,
    input  wire [TAG_W-1:0]     MEM_dst_tag,
    input  wire [XLEN-1:0]      MEM_tag_value,

    input  wire                 WB_tag_we,
    input  wire [TAG_W-1:0]     WB_dst_tag,
    input  wire [XLEN-1:0]      WB_tag_value,

    // ---------------------------
    // NEW: MUL late result (tag + value)
    // You said you already have mul_result_valid; you must also output its ROB tag.
    // ---------------------------
    input  wire                 mul_result_valid,
    input  wire [TAG_W-1:0]     mul_result_tag,
    input  wire [XLEN-1:0]      mul_result_value,

    output wire                 stall_D,
    output wire [2:0]           EX_D_bp,
    output wire [2:0]           MEM_D_bp,
    output wire [2:0]           WB_D_bp,

    // ---------------------------
    // NEW: Tag-bypass outputs to regfile
    // ---------------------------
    output wire                 RA_tag_bp_valid,
    output wire [XLEN-1:0]      RA_tag_bp_value,
    output wire                 RB_tag_bp_valid,
    output wire [XLEN-1:0]      RB_tag_bp_value
);

  // ============================================================
  // Existing arch-reg forwarding detect (rd compares)
  // ============================================================
  wire ex_hit_ra  = (EX_we  && (EX_rd  == D_ra)) || (EX_jlx  && (D_ra == 5'd31));
  wire ex_hit_rb  = (EX_we  && (EX_rd  == D_rb)) || (EX_jlx  && (D_rb == 5'd31));

  wire mem_hit_ra = (MEM_we && (MEM_rd == D_ra)) || (MEM_jlx && (D_ra == 5'd31));
  wire mem_hit_rb = (MEM_we && (MEM_rd == D_rb)) || (MEM_jlx && (D_rb == 5'd31));

  wire wb_hit_ra  = (WB_we  && (WB_rd  == D_ra)) || (WB_jlx  && (D_ra == 5'd31));
  wire wb_hit_rb  = (WB_we  && (WB_rd  == D_rb)) || (WB_jlx  && (D_rb == 5'd31));

  // Load-use stall (keep this)
  // NOTE: For renamed operands, you should rely on regfile's RF_stall instead.
  assign stall_D = (EX_ld && (ex_hit_ra || ex_hit_rb));

  assign EX_D_bp  = { (ex_hit_ra  && !EX_ld),
                      (ex_hit_rb  && !EX_ld),
                       EX_jlx };

  assign MEM_D_bp = {  mem_hit_ra,
                       mem_hit_rb,
                       MEM_jlx };

  assign WB_D_bp  = {   wb_hit_ra,
                        wb_hit_rb,
                        WB_jlx };

  // ============================================================
  // Tag-based bypass selection for renamed operands
  // Priority: MUL(done-now) > EX > MEM > WB
  // (MUL can finish "out of band", so it gets top priority)
  // ============================================================

  // RA matches
  wire ra_hit_mul = RN_ra_is_rob && mul_result_valid && (mul_result_tag == RN_ra_tag);
  wire ra_hit_ex  = RN_ra_is_rob && EX_tag_we        && (EX_dst_tag     == RN_ra_tag);
  wire ra_hit_mem = RN_ra_is_rob && MEM_tag_we       && (MEM_dst_tag    == RN_ra_tag);
  wire ra_hit_wb  = RN_ra_is_rob && WB_tag_we        && (WB_dst_tag     == RN_ra_tag);

  // RB matches
  wire rb_hit_mul = RN_rb_is_rob && mul_result_valid && (mul_result_tag == RN_rb_tag);
  wire rb_hit_ex  = RN_rb_is_rob && EX_tag_we        && (EX_dst_tag     == RN_rb_tag);
  wire rb_hit_mem = RN_rb_is_rob && MEM_tag_we       && (MEM_dst_tag    == RN_rb_tag);
  wire rb_hit_wb  = RN_rb_is_rob && WB_tag_we        && (WB_dst_tag     == RN_rb_tag);

  assign RA_tag_bp_valid = ra_hit_mul | ra_hit_ex | ra_hit_mem | ra_hit_wb;
  assign RB_tag_bp_valid = rb_hit_mul | rb_hit_ex | rb_hit_mem | rb_hit_wb;

  assign RA_tag_bp_value =
      ra_hit_mul ? mul_result_value :
      ra_hit_ex  ? EX_tag_value     :
      ra_hit_mem ? MEM_tag_value    :
      ra_hit_wb  ? WB_tag_value     :
                   {XLEN{1'b0}};

  assign RB_tag_bp_value =
      rb_hit_mul ? mul_result_value :
      rb_hit_ex  ? EX_tag_value     :
      rb_hit_mem ? MEM_tag_value    :
      rb_hit_wb  ? WB_tag_value     :
                   {XLEN{1'b0}};

endmodule
