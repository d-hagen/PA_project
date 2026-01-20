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
    .rst          (rst),

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
  

    // unified flush squash
    .EX_taken       (unified_flush_valid),


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
    .EX_b2       (EX_b2),
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
    .MEM_b2      (MEM_b2),
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
    .clk             (clk),
    .rst             (rst),

    .Dtlb_addr       (Dtlb_addr_out),
    .Dtlb_addr_valid (Dtlb_addr_valid),

    .MEM_b2          (MEM_b2),
    .MEM_ld          (MEM_ld),
    .MEM_str         (MEM_str),
    .MEM_byt         (MEM_byt),

    .store_valid     (store_valid),

    // drain to dcache (masked word store)
    .store_request          (store_request),
    .store_request_addr_w   (store_request_address),
    .store_request_wdata    (store_request_wdata),
    .store_request_wmask    (store_request_wmask),

    // forwarding to dcache
    .sb_fwd_mask      (sb_fwd_mask),
    .sb_fwd_data      (sb_fwd_data),
    .sb_all_hit       (sb_all_hit),

    .Dtlb_stall      (Dtlb_stall),
    .dcache_stall    (dcache_stall),

    .sb_stall        (sb_stall)
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

    // NEW: SB forwarding inputs
    .sb_fwd_mask    (sb_fwd_mask),
    .sb_fwd_data    (sb_fwd_data),
    .sb_all_hit     (sb_all_hit),

    // NEW: masked store drain inputs
    .store_request          (store_request),
    .store_request_address  (store_request_address),
    .store_request_wdata    (store_request_wdata),
    .store_request_wmask    (store_request_wmask),
    .store_valid            (store_valid),

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
  wire load_valid = (!MEM_ld) || dcache_data_valid;

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

    .MEM_ld_valid (load_valid || mul_result_valid),

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
