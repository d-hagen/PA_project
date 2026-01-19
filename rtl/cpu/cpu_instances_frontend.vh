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
    .Itlb_stall     (Itlb_stall),

    // unified flush squash
    .EX_taken       (unified_flush_valid),


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
