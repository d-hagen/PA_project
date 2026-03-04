  // ============================================================
  // Global admin (CPU-owned): set on exception commit, clear on iret commit
  // ============================================================
  always @(posedge clk) begin
    if (rst) admin <= 1'b1;
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
                  | Icache_stall
                  | sb_stall
                  | mul_wb_conflict_stall
                  | mul_issue_stall
                  | stall_rob;

  // Decode accept: only when D truly advances (block on any unified flush)
  wire D_fire = (~stall_allD) & (~unified_flush_valid);

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
  MEM_is_load ? MEM_data_mem :
  MEM_alu_out;

  assign WB_tag_we    = (WB_we | WB_jlx);
  assign WB_tag_value = WB_jlx ? (WB_pc + 32'd4) : WB_data_mem;
