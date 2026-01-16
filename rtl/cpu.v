`timescale 1ns/1ps

module cpu #(
  parameter integer XLEN      = 32,
  parameter integer REG_NUM   = 32,
  parameter integer ADDR_SIZE = 5,
  parameter integer PC_BITS   = 20,
  parameter integer VPC_BITS  = 32,
  parameter [VPC_BITS-1:0] RESET_PC = {VPC_BITS{1'b0}}
)(
  input  wire clk,
  input  wire rst
);

  // ============================================================
  // Parameters
  // ============================================================
  localparam integer ROB_DEPTH = 16;
  localparam integer TAG_W     = 4; // since ROB_DEPTH=16

  // =======================
  // Wire declarations
  // =======================

  // ----- Program Counter / Fetch -----
  wire [VPC_BITS-1:0] F_pc_va;
  wire [PC_BITS-1:0]  F_pc;
  wire [XLEN-1:0]     F_inst;

  // Branch Predictor / buffer
  wire                 F_BP_taken;
  wire [VPC_BITS-1:0]  F_BP_target_pc;
  wire                 F_stall;

  // ===== ITLB / PTW wires =====
  wire               Itlb_ptw_valid;
  wire [7:0]         Itlb_ptw_pa;
  wire               Itlb_ptw_fault;        // NEW: PTW says ITLB walk faulted

  wire               Itlb_stall;
  wire               Itlb_pa_request;
  wire [19:0]        Itlb_va;

  // ===== DTLB / PTW wires =====
  wire               Dtlb_ptw_valid;
  wire [7:0]         Dtlb_ptw_pa;
  wire               Dtlb_ptw_fault;        // NEW: PTW says DTLB walk faulted

  wire               Dtlb_pa_request;
  wire [19:0]        Dtlb_va;

  wire [31:0]        Dtlb_addr_out;
  wire               Dtlb_addr_valid;
  wire               Dtlb_stall;

  // PTW <-> dcache interface
  wire        Ptw_mem_req;
  wire [19:0] Ptw_mem_addr;
  wire [31:0] Ptw_mem_rdata;
  wire        Ptw_mem_valid;
  wire        Ptw_accepted;                 // NEW: handshake from dcache

  // Decode stage / F→D reg
  wire [XLEN-1:0]     D_inst;
  wire [VPC_BITS-1:0] D_pc;
  wire [VPC_BITS-1:0] EX_pc;
  wire [VPC_BITS-1:0] MEM_pc;
  wire [VPC_BITS-1:0] WB_pc;

  wire D_exc;
  wire D_jlx;
  wire EX_jlx;
  wire MEM_jlx;
  wire WB_jlx;

  // NEW: iret decoded signal (separate opcode)
  wire D_iret;

  wire               D_BP_taken;
  wire [VPC_BITS-1:0] D_BP_target_pc;

  // NEW: carry ITLB PTW fault into D stage
  wire               D_itlb_ptw_fault;

  // Decoder outputs
  wire [5:0]         D_opc;
  wire [4:0]         D_ra;
  wire [4:0]         D_rb;
  wire [4:0]         D_rd;
  wire [10:0]        D_imd;
  wire               D_we;
  wire [3:0]         D_alu_op;
  wire               D_ld;
  wire               D_str;
  wire               D_brn;
  wire               D_jmp;
  wire               D_addi;
  wire               D_mul;
  wire               D_byt;

  // Hazard unit
  wire               stall_D;
  wire [2:0]         EX_D_bp;
  wire [2:0]         MEM_D_bp;
  wire [2:0]         WB_D_bp;

  // Regfile outputs
  wire [XLEN-1:0]    D_a;
  wire [XLEN-1:0]    D_b;
  wire [XLEN-1:0]    D_a2;
  wire [XLEN-1:0]    D_b2;

  // Execute stage / D→EX reg
  wire [XLEN-1:0]    EX_a;
  wire [XLEN-1:0]    EX_a2;
  wire [XLEN-1:0]    EX_b;
  wire [XLEN-1:0]    EX_b2;
  wire [3:0]         EX_alu_op;
  wire [4:0]         EX_rd;
  wire               EX_ld;
  wire               EX_str;
  wire               EX_byt;
  wire               EX_we;
  wire               EX_brn;
  wire               EX_mul;
  wire               EX_BP_taken;
  wire [VPC_BITS-1:0] EX_BP_target_pc;

  // ALU outputs
  wire [XLEN-1:0]    EX_alu_out;
  wire               EX_taken;
  wire               EX_true_taken;

  // EX → MEM pipeline register wires
  wire [XLEN-1:0]    MEM_alu_out;
  wire               MEM_taken;
  wire [XLEN-1:0]    MEM_b2;
  wire [XLEN-1:0]    MEM_a2;
  wire [4:0]         MEM_rd;
  wire               MEM_we;
  wire               MEM_ld;
  wire               MEM_str;
  wire               MEM_byt;
  wire               MEM_mul;

  // Global stall from D-cache
  wire               dcache_stall;

  // I-Cache <-> Instruction Memory
  wire               Ic_mem_req;
  wire [PC_BITS-5:0] Ic_mem_addr;
  wire [127:0]       F_mem_inst;
  wire               F_mem_valid;

  // D-cache <-> Backing Data Memory
  wire               Dc_mem_req;
  wire [PC_BITS-5:0] Dc_mem_addr;
  wire [127:0]       MEM_data_line;
  wire               MEM_mem_valid;

  wire               Dc_wb_we;
  wire [PC_BITS-5:0] Dc_wb_addr;
  wire [127:0]       Dc_wb_wline;
  wire [XLEN-1:0]    MEM_data_mem;

  // MEM → WB pipeline register wires
  wire [XLEN-1:0]    WB_data_mem;
  wire [4:0]         WB_rd;
  wire               WB_we;
  wire               dcache_data_valid;

  // =======================
  // Store Buffer <-> D$ wires
  // =======================
  wire                 sb_load_miss;

  wire                 store_request;
  wire [19:0]          store_request_address;
  wire [XLEN-1:0]      store_request_value;
  wire                 store_byte;
  wire                 store_valid;

  // Store-buffer load forwarding -> WB mux
  wire                 sb_hit;
  wire [XLEN-1:0]      sb_data;

  // Store buffer stall
  wire                 sb_stall;

  // =======================
  // MUL pipe wires
  // =======================
  wire                 mul_result_valid;
  wire [XLEN-1:0]      mul_result;
  wire                 mul_busy;
  wire [ADDR_SIZE-1:0] mul_busy_rd;

  wire                 mul_wb_conflict_stall;
  wire                 mul_issue_stall;

  // ============================================================
  // ROB + Rename wires
  // ============================================================
  wire                  RN_ra_is_rob, RN_rb_is_rob;
  wire [TAG_W-1:0]      RN_ra_tag, RN_rb_tag;
  wire [TAG_W-1:0]      RN_dst_tag;
  wire                  RN_alloc;
  wire [TAG_W-1:0]      RN_alloc_tag;

  wire                  ROB_ra_ready, ROB_rb_ready;
  wire [XLEN-1:0]       ROB_ra_value, ROB_rb_value;

  wire                  rob_full, rob_empty;

  wire                  C_valid;
  wire                  C_we;
  wire [ADDR_SIZE-1:0]  C_rd_arch;
  wire [XLEN-1:0]       C_value;
  wire [TAG_W-1:0]      C_tag;

  wire                  RF_stall;

  // Tag wires through pipeline regs
  wire [TAG_W-1:0]      D_tag = RN_dst_tag;
  wire [TAG_W-1:0]      EX_tag;
  wire [TAG_W-1:0]      MEM_tag;
  wire [TAG_W-1:0]      WB_tag;

  // MUL tag at completion
  wire [TAG_W-1:0]      mul_result_tag;
  wire [4:0]            mul_rd_done;

  // ============================================================
  // Tag-bypass wires from Hazard_unit -> regfile
  // ============================================================
  wire                  RA_tag_bp_valid;
  wire [XLEN-1:0]       RA_tag_bp_value;
  wire                  RB_tag_bp_valid;
  wire [XLEN-1:0]       RB_tag_bp_value;

  // ============================================================
  // Producer tag/value wires (EX/MEM/WB)
  // ============================================================
  wire EX_tag_we;
  wire [XLEN-1:0] EX_tag_value;

  wire MEM_tag_we;
  wire [XLEN-1:0] MEM_tag_value;

  wire WB_tag_we;
  wire [XLEN-1:0] WB_tag_value;

  // ============================================================
  // Exception handler / unified flush wires (branch + exceptions)
  // ============================================================
  wire                  eh_flush_valid;
  wire [TAG_W-1:0]      eh_flush_tag;

  wire                  exc_set_valid;
  wire [TAG_W-1:0]      exc_set_tag;
  wire [XLEN-1:0]       exc_set_pc;

  wire                  F_flush, D_flush, EX_flush, MEM_flush, WB_flush;

  // ============================================================
  // ROB exception outputs + stall + IRET commit
  // ============================================================
  wire                  rob_stall;

  wire                  EXC_we;
  wire [XLEN-1:0]       EXC_pc;
  wire [3:0]            EXC_type;
  wire [TAG_W-1:0]      EXC_tag;

  wire                  IRET_we;
  wire [TAG_W-1:0]      IRET_tag;

  // regfile exception registers (rm1/rm2)
  wire [XLEN-1:0]       rm1;
  wire [31:0]           rm2;

  // ============================================================
  // Global admin (CPU-owned): set on exception commit, clear on iret commit
  // ============================================================
  reg admin;
  always @(posedge clk) begin
    if (rst) admin <= 1'b0;
    else if (EXC_we) admin <= 1'b1;
    else if (IRET_we) admin <= 1'b0;
  end

  // ============================================================
  // Unified flush used by rename/ROB/pipeline regs
  // (iret commit also flushes younger instructions)
  // ============================================================
  wire                  unified_flush_valid = eh_flush_valid | IRET_we;
  wire [TAG_W-1:0]      unified_flush_tag   = IRET_we ? IRET_tag : eh_flush_tag;

  // ============================================================
  // PC redirect mux:
  //  - exception commit -> 0x0FA0
  //  - iret commit      -> rm1 + 4
  // ============================================================
  wire                  redir_valid = EXC_we | IRET_we;
  wire [VPC_BITS-1:0]   redir_pc    = EXC_we ? 32'h0000_0FA0 : rm1 + 32'd4;

  // ============================================================
  // Global stall with ROB/RF
  // ============================================================
  wire stall_rob = rob_full | RF_stall | rob_stall;

  wire stall_allD = stall_D
                  | dcache_stall
                  | Dtlb_stall
                  | Itlb_stall
                  | F_stall
                  | sb_stall
                  | mul_wb_conflict_stall
                  | mul_issue_stall
                  | stall_rob;

  // Decode accept: only when D truly advances (block on any unified flush)
  wire D_fire = (~stall_allD) & (~unified_flush_valid);

  wire WB_ld_valid;

  // ============================================================
  // PC Register (UPDATED: redirect interface)
  // ============================================================
  pc #(
    .PCLEN   (VPC_BITS),
    .RESET_PC(RESET_PC)
  ) u_pc (
    .clk            (clk),
    .rst            (rst),

    .redir_valid    (redir_valid),
    .redir_pc       (redir_pc),

    .EX_taken       (EX_taken),
    .EX_alt_pc      (EX_alu_out),

    .F_BP_target_pc (F_BP_target_pc),
    .stall_D        (stall_allD),

    .F_pc_va        (F_pc_va)
  );

  // =======================
  // Branch Buffer / Predictor
  // =======================
  branch_buffer #(
    .PC_BITS (VPC_BITS)
  ) u_branch_buffer (
    .clk            (clk),
    .rst            (rst),
    .F_pc_va        (F_pc_va),
    .EX_brn         (EX_brn),
    .F_stall        (F_stall),
    .dcache_stall   (dcache_stall),
    .Itlb_stall     (Itlb_stall),
    .sb_stall       (sb_stall),
    .Dtlb_stall     (Dtlb_stall),
    .mul_wb_conflict_stall (mul_wb_conflict_stall),
    .mul_issue_stall       (mul_issue_stall),

    .EX_pc          (EX_pc),
    .EX_alu_out     (EX_alu_out),
    .EX_true_taken  (EX_true_taken),
    .F_BP_target_pc (F_BP_target_pc),
    .F_BP_taken     (F_BP_taken)
  );

  // =======================
  // ITLB
  // =======================
  itlb u_itlb(
    .clk            (clk),
    .rst            (rst),
    .va_in          (F_pc_va),
    .admin          (admin),

    .Itlb_ptw_valid    (Itlb_ptw_valid),
    .Itlb_ptw_pa       (Itlb_ptw_pa),

    .F_pc           (F_pc),
    .Itlb_stall     (Itlb_stall),
    .Itlb_pa_request(Itlb_pa_request),
    .Itlb_va        (Itlb_va)
  );

  // =======================
  // DTLB (MEM stage)
  // =======================
  dtlb #(
    .VA_WIDTH          (32),
    .PA_BITS           (20),
    .PAGE_OFFSET_WIDTH (12),
    .NUM_ENTRIES       (16)
  ) u_dtlb (
    .clk             (clk),
    .rst             (rst),

    .admin           (admin),

    .va_in           (MEM_alu_out),
    .MEM_ld          (MEM_ld),
    .MEM_str         (MEM_str),

    .MEM_ptw_valid   (Dtlb_ptw_valid),
    .MEM_ptw_pa      (Dtlb_ptw_pa),

    .Dtlb_addr_out   (Dtlb_addr_out),
    .Dtlb_addr_valid (Dtlb_addr_valid),
    .Dtlb_stall      (Dtlb_stall),

    .Dtlb_pa_request (Dtlb_pa_request),
    .Dtlb_va         (Dtlb_va)
  );

  // =======================
  // PTW (2-port)
  // =======================
  ptw_2level #(
    .VA_WIDTH          (32),
    .PC_BITS           (20),
    .PAGE_OFFSET_WIDTH (12)
  ) u_ptw (
    .clk             (clk),
    .rst             (rst),

    .Itlb_pa_request (Itlb_pa_request),
    .Itlb_va         (Itlb_va),

    .Itlb_ptw_valid  (Itlb_ptw_valid),
    .Itlb_ptw_pa     (Itlb_ptw_pa),
    .Itlb_ptw_fault  (Itlb_ptw_fault),   // FIXED: wire to ITLB fault

    .Dtlb_pa_request (Dtlb_pa_request),
    .Dtlb_va         (Dtlb_va),

    .Dtlb_ptw_valid  (Dtlb_ptw_valid),
    .Dtlb_ptw_pa     (Dtlb_ptw_pa),
    .Dtlb_ptw_fault  (Dtlb_ptw_fault),

    .Ptw_mem_req     (Ptw_mem_req),
    .Ptw_mem_addr    (Ptw_mem_addr),
    .Ptw_mem_rdata   (Ptw_mem_rdata),
    .Ptw_mem_valid   (Ptw_mem_valid),

    .accepted        (Ptw_accepted)
  );

  // =======================
  // I-Cache
  // =======================
  icache u_icache (
    .clk         (clk),
    .rst         (rst),

    .F_pc        (F_pc),
    .F_mem_inst  (F_mem_inst),
    .F_mem_valid (F_mem_valid),

    .Ic_mem_req  (Ic_mem_req),
    .Ic_mem_addr (Ic_mem_addr),

    .F_inst      (F_inst),
    .F_stall     (F_stall)
  );

  // =======================
  // F → D pipeline register
  // =======================
  f_to_d_reg #(
    .XLEN     (XLEN),
    .PC_BITS  (PC_BITS),
    .VPC_BITS (VPC_BITS)
  ) u_f2d (
    .clk            (clk),
    .rst            (rst),
    .F_pc           (F_pc_va),
    .F_inst         (F_inst),
    .F_BP_taken     (F_BP_taken),
    .F_BP_target_pc (F_BP_target_pc),

    // NEW: pass the ITLB PTW fault into D stage
    .Itlb_ptw_fault (Itlb_ptw_fault),

    .stall_D        (stall_allD),
    .dcache_stall   (dcache_stall),
    .sb_stall       (sb_stall),
    .Itlb_stall     (Itlb_stall),
    .Dtlb_stall     (Dtlb_stall),

    // unified flush squash
    .EX_taken       (unified_flush_valid),

    .mul_wb_conflict_stall (mul_wb_conflict_stall),
    .mul_issue_stall       (mul_issue_stall),

    .D_pc           (D_pc),
    .D_inst         (D_inst),
    .D_BP_taken     (D_BP_taken),
    .D_BP_target_pc (D_BP_target_pc),

    // NEW: registered fault output
    .D_itlb_ptw_fault (D_itlb_ptw_fault)
  );

  // =======================
  // Decoder (UPDATED: separate D_iret output)
  // =======================
  decode #(
    .XLEN(XLEN)
  ) u_decode (
    .clk      (clk),
    .admin    (admin),
    .D_inst   (D_inst),
    .D_opc    (D_opc),
    .D_ra     (D_ra),
    .D_rb     (D_rb),
    .D_rd     (D_rd),
    .D_imd    (D_imd),
    .D_we     (D_we),
    .D_alu_op (D_alu_op),
    .D_ld     (D_ld),
    .D_str    (D_str),
    .D_byt    (D_byt),
    .D_jmp    (D_jmp),
    .D_jlx    (D_jlx),
    .D_iret   (D_iret),
    .D_brn    (D_brn),
    .D_addi   (D_addi),
    .D_mul    (D_mul),
    .D_exc    (D_exc)
  );

  // ============================================================
  // Define producer tag/value signals
  // ============================================================
  assign EX_tag_we    = (EX_we | EX_jlx) && !EX_ld && !EX_mul;
  assign EX_tag_value = EX_jlx ? (EX_pc + 32'd4) : EX_alu_out;

  wire MEM_writes  = (MEM_we | MEM_jlx);
  wire MEM_is_load = MEM_ld;

  assign MEM_tag_we =
      MEM_writes &&
      ( MEM_is_load ? (!dcache_stall && !Dtlb_stall) : 1'b1 );

  assign MEM_tag_value =
    MEM_jlx ? (MEM_pc + 32'd4) :
    MEM_is_load ? (sb_hit ? sb_data : MEM_data_mem) :
    MEM_alu_out;

  assign WB_tag_we    = (WB_we | WB_jlx);
  assign WB_tag_value = WB_jlx ? (WB_pc + 32'd4) : WB_data_mem;

  // =======================
  // Hazard Unit (Option B)
  // =======================
  Hazard_unit #(
    .XLEN     (XLEN),
    .ADDR_SIZE(ADDR_SIZE),
    .ROB_DEPTH(ROB_DEPTH),
    .TAG_W    (TAG_W)
  ) u_Hazard_unit (
    .clk        (clk),
    .rst        (rst),

    .D_ra       (D_ra),
    .D_rb       (D_rb),
    .D_rd       (D_rd),

    .EX_alu_out (EX_alu_out),
    .EX_rd      (EX_rd),
    .EX_we      (EX_we),
    .EX_ld      (EX_ld),
    .EX_mul     (EX_mul),
    .EX_jlx     (EX_jlx),

    .MEM_rd     (MEM_rd),
    .MEM_we     (MEM_we),
    .MEM_jlx    (MEM_jlx),

    .WB_rd      (WB_rd),
    .WB_we      (WB_we),
    .WB_jlx     (WB_jlx),

    .RN_ra_is_rob (RN_ra_is_rob),
    .RN_rb_is_rob (RN_rb_is_rob),
    .RN_ra_tag    (RN_ra_tag),
    .RN_rb_tag    (RN_rb_tag),

    .EX_tag_we     (EX_tag_we),
    .EX_dst_tag    (EX_tag),
    .EX_tag_value  (EX_tag_value),

    .MEM_tag_we    (MEM_tag_we),
    .MEM_dst_tag   (MEM_tag),
    .MEM_tag_value (MEM_tag_value),

    .WB_tag_we     (WB_tag_we),
    .WB_dst_tag    (WB_tag),
    .WB_tag_value  (WB_tag_value),

    .mul_result_valid (mul_result_valid),
    .mul_result_tag   (mul_result_tag),
    .mul_result_value (mul_result),

    .stall_D    (stall_D),
    .EX_D_bp    (EX_D_bp),
    .MEM_D_bp   (MEM_D_bp),
    .WB_D_bp    (WB_D_bp),

    .RA_tag_bp_valid (RA_tag_bp_valid),
    .RA_tag_bp_value (RA_tag_bp_value),
    .RB_tag_bp_valid (RB_tag_bp_valid),
    .RB_tag_bp_value (RB_tag_bp_value)
  );

  // =======================
  // Exception handler (branch flush goes through here)
  // =======================
  wire [TAG_W-1:0] D_exc_tag = RN_alloc_tag;

  // Only assert decode-exception when the instruction is actually being allocated
  wire rob_do_alloc = RN_alloc & D_fire & ~stall_rob;
  wire D_exc_fire = D_exc & rob_do_alloc;

  exc_handler #(
    .XLEN (XLEN),
    .TAG_W(TAG_W)
  ) u_exc_handler (
    .EX_exc  (EX_exc), .EX_tag  (EX_tag),   .EX_pc  (EX_pc),
    .MEM_exc (Dtlb_ptw_fault), .MEM_tag (MEM_tag), .MEM_pc (MEM_pc),
    .WB_exc  (1'b0),   .WB_tag  (WB_tag),   .WB_pc  (WB_pc),

    .EX_taken  (EX_taken),
    .EX_br_tag (EX_tag),

    .exc_set_valid(exc_set_valid),
    .exc_set_tag  (exc_set_tag),
    .exc_set_pc   (exc_set_pc),

    .flush_valid(eh_flush_valid),
    .flush_tag  (eh_flush_tag),

    .F_flush  (F_flush),
    .D_flush  (D_flush),
    .EX_flush (EX_flush),
    .MEM_flush(MEM_flush),
    .WB_flush (WB_flush)
  );

  // =======================
  // Rename
  // =======================
  rename #(
    .REG_NUM   (REG_NUM),
    .ADDR_SIZE (ADDR_SIZE),
    .ROB_DEPTH (ROB_DEPTH),
    .TAG_W     (TAG_W)
  ) u_rename (
    .clk          (clk),
    .rst          (rst),

    .D_ra         (D_ra),
    .D_rb         (D_rb),
    .D_rd         (D_rd),
    .D_we         (D_we),
    .D_jlx        (D_jlx),

    .D_fire       (D_fire),

    .ra_is_rob    (RN_ra_is_rob),
    .rb_is_rob    (RN_rb_is_rob),
    .ra_tag       (RN_ra_tag),
    .rb_tag       (RN_rb_tag),

    .dst_tag      (RN_dst_tag),
    .rob_alloc    (RN_alloc),
    .rob_alloc_tag(RN_alloc_tag),

    .rob_full_in  (rob_full),

    // unified flush
    .flush_valid  (unified_flush_valid),
    .flush_tag    (unified_flush_tag),

    .C_valid      (C_valid),
    .C_we         (C_we),
    .C_rd_arch    (C_rd_arch),
    .C_tag        (C_tag)
  );

  // =======================
  // Regfile with ROB
  // =======================
  regfile_rob #(
    .XLEN      (XLEN),
    .REG_NUM   (REG_NUM),
    .ADDR_SIZE (ADDR_SIZE),
    .VPC_BITS  (VPC_BITS),
    .ROB_DEPTH (ROB_DEPTH),
    .TAG_W     (TAG_W)
  ) u_regfile (
    .clk          (clk),

    .D_ra         (D_ra),
    .D_rb         (D_rb),
    .D_imd        (D_imd),
    .D_pc         (D_pc),
    .D_ld         (D_ld),
    .D_str        (D_str),
    .D_brn        (D_brn),
    .D_jmp        (D_jmp),
    .D_addi       (D_addi),
    .D_iret       (D_iret),

    .RN_ra_is_rob (RN_ra_is_rob),
    .RN_rb_is_rob (RN_rb_is_rob),
    .RN_ra_tag    (RN_ra_tag),
    .RN_rb_tag    (RN_rb_tag),

    .ROB_ra_ready (ROB_ra_ready),
    .ROB_ra_value (ROB_ra_value),
    .ROB_rb_ready (ROB_rb_ready),
    .ROB_rb_value (ROB_rb_value),

    .EX_D_bp      (EX_D_bp),
    .MEM_D_bp     (MEM_D_bp),
    .WB_D_bp      (WB_D_bp),

    .EX_alu_out   (EX_alu_out),
    .MEM_data_mem (MEM_data_mem),
    .EX_pc        (EX_pc),
    .MEM_pc       (MEM_pc),

    .WB_data_mem  (WB_data_mem),
    .WB_pc        (WB_pc),
    .WB_jlx       (WB_jlx),

    .C_we         (C_valid & C_we),
    .C_rd         (C_rd_arch),
    .C_value      (C_value),

    .RA_tag_bp_valid (RA_tag_bp_valid),
    .RA_tag_bp_value (RA_tag_bp_value),
    .RB_tag_bp_valid (RB_tag_bp_valid),
    .RB_tag_bp_value (RB_tag_bp_value),

    .EXC_we       (EXC_we),
    .EXC_pc       (EXC_pc),
    .EXC_type     (EXC_type),

    .rm1          (rm1),
    .rm2          (rm2),

    .D_a          (D_a),
    .D_b          (D_b),
    .D_a2         (D_a2),
    .D_b2         (D_b2),

    .RF_stall     (RF_stall)
  );

  // =======================
  // D → EX pipeline register (tag + EX_exc ORed with D_itlb_ptw_fault inside)
  // =======================
  d_to_ex_reg #(
    .XLEN     (XLEN),
    .PC_BITS  (PC_BITS),
    .VPC_BITS (VPC_BITS),
    .TAG_W    (TAG_W)
  ) u_d_to_ex_reg (
    .clk            (clk),
    .rst            (rst),

    .D_a            (D_a),
    .D_a2           (D_a2),
    .D_b            (D_b),
    .D_b2           (D_b2),
    .D_alu_op       (D_alu_op),
    .D_brn          (D_brn),
    .D_rd           (D_rd),
    .D_ld           (D_ld),
    .D_str          (D_str),
    .D_byt          (D_byt),
    .D_we           (D_we),
    .D_mul          (D_mul),
    .D_jlx          (D_jlx),

    .D_pc           (D_pc),
    .D_BP_taken     (D_BP_taken),
    .D_BP_target_pc (D_BP_target_pc),

    .D_tag          (D_tag),
    .D_exc          (D_exc),

    // NEW: ITLB PTW fault from D stage
    .D_itlb_ptw_fault (D_itlb_ptw_fault),

    .stall_D        (stall_allD),
    .dcache_stall   (dcache_stall),
    .sb_stall       (sb_stall),
    .Dtlb_stall     (Dtlb_stall),

    // unified flush squash
    .EX_taken       (unified_flush_valid),

    .mul_wb_conflict_stall (mul_wb_conflict_stall),
    .mul_issue_stall       (mul_issue_stall),

    .EX_a           (EX_a),
    .EX_a2          (EX_a2),
    .EX_b           (EX_b),
    .EX_b2          (EX_b2),
    .EX_alu_op      (EX_alu_op),
    .EX_rd          (EX_rd),
    .EX_ld          (EX_ld),
    .EX_str         (EX_str),
    .EX_byt         (EX_byt),
    .EX_we          (EX_we),
    .EX_brn         (EX_brn),
    .EX_mul         (EX_mul),
    .EX_jlx         (EX_jlx),
    .EX_pc          (EX_pc),
    .EX_BP_taken    (EX_BP_taken),
    .EX_BP_target_pc(EX_BP_target_pc),

    .EX_tag         (EX_tag),
    .EX_exc         (EX_exc)
  );

  // =======================
  // MUL pipe (tag)
  // =======================
  mul_pipe_single #(
    .XLEN    (XLEN),
    .RD_BITS (ADDR_SIZE),
    .TAG_W   (TAG_W)
  ) u_mul_pipe (
    .clk          (clk),
    .rst          (rst),

    .EX_mul        (EX_mul),
    .EX_mul_a      (EX_a2),
    .EX_mul_b      (EX_b2),
    .EX_mul_rd     (EX_rd),
    .EX_mul_tag    (EX_tag),

    .MEM_we        (MEM_we),
    .MEM_jlx       (MEM_jlx),

    .mul_result_valid      (mul_result_valid),
    .mul_result            (mul_result),
    .mul_rd                (mul_rd_done),
    .mul_result_tag        (mul_result_tag),

    .mul_busy              (mul_busy),
    .mul_busy_rd           (mul_busy_rd),
    .mul_busy_tag          (/* unused */),

    .mul_wb_conflict_stall (mul_wb_conflict_stall),
    .mul_issue_stall       (mul_issue_stall)
  );

  // =======================
  // ALU
  // =======================
  alu #(
    .XLEN     (XLEN),
    .PC_BITS  (PC_BITS),
    .VPC_BITS (VPC_BITS)
  ) u_alu (
    .EX_a            (EX_a),
    .EX_a2           (EX_a2),
    .EX_b            (EX_b),
    .EX_b2           (EX_b2),
    .EX_alu_op       (EX_alu_op),
    .EX_brn          (EX_brn),
    .EX_BP_taken     (EX_BP_taken),
    .EX_BP_target_pc (EX_BP_target_pc),

    .EX_mul          (EX_mul),

    .EX_alu_out      (EX_alu_out),
    .EX_taken        (EX_taken),
    .EX_true_taken   (EX_true_taken)
  );

  // =======================
  // EX → MEM pipeline register (tag)
  // =======================
  ex_to_mem_reg #(
    .XLEN    (XLEN),
    .PC_BITS (PC_BITS),
    .TAG_W   (TAG_W)
  ) u_ex_to_mem_reg (
    .clk         (clk),
    .rst         (rst),

    .EX_alu_out  (EX_alu_out),
    .EX_taken    (EX_taken),
    .EX_b2       (EX_b2),
    .EX_a2       (EX_a2),
    .EX_rd       (EX_rd),
    .EX_we       (EX_we),
    .EX_ld       (EX_ld),
    .EX_str      (EX_str),
    .EX_byt      (EX_byt),
    .EX_mul      (EX_mul),

    .dcache_stall   (dcache_stall),
    .sb_stall       (sb_stall),
    .Dtlb_stall     (Dtlb_stall),

    .mul_wb_conflict_stall (mul_wb_conflict_stall),

    .EX_pc       (EX_pc),
    .EX_jlx      (EX_jlx),

    .EX_tag      (EX_tag),

    .MEM_alu_out (MEM_alu_out),
    .MEM_taken   (MEM_taken),
    .MEM_b2      (MEM_b2),
    .MEM_a2      (MEM_a2),
    .MEM_rd      (MEM_rd),
    .MEM_we      (MEM_we),
    .MEM_ld      (MEM_ld),
    .MEM_str     (MEM_str),
    .MEM_byt     (MEM_byt),
    .MEM_pc      (MEM_pc),
    .MEM_jlx     (MEM_jlx),

    .MEM_tag     (MEM_tag)
  );

  // =======================
  // Store Buffer
  // =======================
  store_buffer #(
    .XLEN(XLEN)
  ) u_store_buffer (
    .clk                  (clk),
    .rst                  (rst),

    .Dtlb_addr            (Dtlb_addr_out),
    .Dtlb_addr_valid      (Dtlb_addr_valid),
    .MEM_b2               (MEM_b2),
    .MEM_ld               (MEM_ld),
    .MEM_str              (MEM_str),
    .MEM_byt              (MEM_byt),

    .store_valid          (store_valid),
    .sb_load_miss         (sb_load_miss),
    .store_request        (store_request),
    .store_request_address(store_request_address),
    .store_request_value  (store_request_value),
    .store_byte           (store_byte),

    .sb_hit               (sb_hit),
    .sb_data              (sb_data),

    .Dtlb_stall           (Dtlb_stall),
    .dcache_stall         (dcache_stall),
    .sb_stall             (sb_stall)
  );

  // =======================
  // D-Cache
  // =======================
  dcache #(
    .XLEN(XLEN)
  ) u_dcache (
    .clk            (clk),
    .rst            (rst),

    .MEM_ld         (MEM_ld),
    .MEM_byt        (MEM_byt),

    .MEM_alu_out    (Dtlb_addr_out),
    .MEM_b2         (MEM_b2),
    .MEM_data_mem   (MEM_data_mem),
    .dcache_stall   (dcache_stall),

    .sb_load_miss    (sb_load_miss),
    .store_request   (store_request),
    .store_request_address (store_request_address),
    .store_request_value (store_request_value),
    .store_byte      (store_byte),
    .store_valid     (store_valid),

    .Dtlb_addr_valid(Dtlb_addr_valid),

    .Dc_mem_req     (Dc_mem_req),
    .Dc_mem_addr    (Dc_mem_addr),
    .MEM_data_line  (MEM_data_line),
    .MEM_mem_valid  (MEM_mem_valid),

    .Dc_wb_we       (Dc_wb_we),
    .Dc_wb_addr     (Dc_wb_addr),
    .Dc_wb_wline    (Dc_wb_wline),

    .Ptw_req        (Ptw_mem_req),
    .Ptw_addr       (Ptw_mem_addr),
    .Ptw_rdata      (Ptw_mem_rdata),
    .Ptw_valid      (Ptw_mem_valid),

    .dcache_data_valid (dcache_data_valid),

    .Ptw_accepted   (Ptw_accepted)
  );

  // =======================
  // Unified instruction + data memory
  // =======================
  unified_mem #(
    .XLEN    (XLEN),
    .LATENCY (3)
  ) u_unified_mem (
    .clk           (clk),
    .rst           (rst),

    .Ic_mem_req    (Ic_mem_req),
    .Ic_mem_addr   (Ic_mem_addr),
    .F_mem_inst    (F_mem_inst),
    .F_mem_valid   (F_mem_valid),

    .Dc_mem_req    (Dc_mem_req),
    .Dc_mem_addr   (Dc_mem_addr),
    .MEM_data_line (MEM_data_line),
    .MEM_mem_valid (MEM_mem_valid),

    .Dc_wb_we      (Dc_wb_we),
    .Dc_wb_addr    (Dc_wb_addr),
    .Dc_wb_wline   (Dc_wb_wline)
  );

  // =======================
  // MEM → WB pipeline register (tag mux)
  // =======================
  wire load_valid = ((sb_hit || (sb_load_miss && dcache_data_valid)) || !MEM_ld);

  mem_to_wb_reg #(
    .XLEN    (XLEN),
    .PC_BITS (PC_BITS),
    .TAG_W   (TAG_W)
  ) u_mem_to_wb_reg (
    .clk          (clk),
    .rst          (rst),

    .MEM_data_mem (MEM_ld ? MEM_data_mem : MEM_alu_out),
    .MEM_rd       (MEM_rd),
    .MEM_we       (MEM_we),
    .MEM_pc       (MEM_pc),
    .MEM_jlx      (MEM_jlx),

    .MEM_tag      (MEM_tag),

    .dcache_stall (dcache_stall),
    .Dtlb_stall   (Dtlb_stall),
    .sb_stall     (sb_stall),

    .MEM_ld_valid (load_valid || mul_result_valid),

    .sb_hit       (sb_hit),
    .sb_data      (sb_data),

    .mul_done     (mul_result_valid),
    .mul_result   (mul_result),
    .mul_rd       (mul_rd_done),
    .mul_tag      (mul_result_tag),

    .WB_data_mem  (WB_data_mem),
    .WB_rd        (WB_rd),
    .WB_we        (WB_we),
    .WB_pc        (WB_pc),
    .WB_jlx       (WB_jlx),

    .WB_tag       (WB_tag),
    .WB_ld_valid  (WB_ld_valid)
  );

  // ============================================================
  // ROB instance (UPDATED: alloc_iret + IRET_we/tag)
  // ============================================================
  wire        WB_wb_valid     = (WB_we | WB_jlx) && WB_ld_valid;
  wire [XLEN-1:0] WB_wb_value = WB_jlx ? (WB_pc + 32'd4) : WB_data_mem;

  wire rec_active;

  rob #(
    .XLEN(XLEN), .ADDR_SIZE(ADDR_SIZE), .ROB_DEPTH(ROB_DEPTH), .TAG_W(TAG_W)
  ) u_rob (
    .clk(clk),
    .rst(rst),

    .alloc_valid   (rob_do_alloc),
    .alloc_tag     (RN_alloc_tag),
    .alloc_we      (D_we  & D_fire),
    .alloc_rd_arch (D_rd),
    .alloc_jlx     (D_jlx & D_fire),
    .alloc_iret    (D_iret & D_fire),

    .wb_valid      (WB_wb_valid),
    .wb_tag        (WB_tag),
    .wb_value      (WB_wb_value),

    // unified flush
    .flush_valid   (unified_flush_valid),
    .flush_tag     (unified_flush_tag),

    .ra_tag        (RN_ra_tag),
    .ra_ready      (ROB_ra_ready),
    .ra_value      (ROB_ra_value),

    .rb_tag        (RN_rb_tag),
    .rb_ready      (ROB_rb_ready),
    .rb_value      (ROB_rb_value),

    .C_valid       (C_valid),
    .C_we          (C_we),
    .C_rd_arch     (C_rd_arch),
    .C_value       (C_value),
    .C_tag         (C_tag),

    // exception mark-in
    .exc_set_valid (exc_set_valid),
    .exc_set_tag   (exc_set_tag),
    .exc_set_pc    (exc_set_pc),

    // exception commit out
    .EXC_we        (EXC_we),
    .EXC_pc        (EXC_pc),
    .EXC_type      (EXC_type),
    .EXC_tag       (EXC_tag),

    // iret commit out
    .IRET_we       (IRET_we),
    .IRET_tag      (IRET_tag),

    // stall out
    .rob_stall     (rob_stall),

    .rob_full      (rob_full),
    .rob_empty     (rob_empty),
    .recovering    (rec_active)
  );

endmodule