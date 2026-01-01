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
  wire F_admin = 1'b0;

  wire               Itlb_ptw_valid;
  wire [7:0]         Itlb_ptw_pa;

  wire               Itlb_stall;
  wire               Itlb_pa_request;
  wire [19:0]        Itlb_va;

  // ===== DTLB / PTW wires =====
  wire               Dtlb_ptw_valid;
  wire [7:0]         Dtlb_ptw_pa;

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

  // Decode stage / F→D reg
  wire [XLEN-1:0]     D_inst;
  wire [VPC_BITS-1:0] D_pc;
  wire [VPC_BITS-1:0] EX_pc;
  wire [VPC_BITS-1:0] MEM_pc;
  wire [VPC_BITS-1:0] WB_pc;

  wire D_jlx;
  wire EX_jlx;
  wire MEM_jlx;
  wire WB_jlx;

  wire               D_BP_taken;
  wire [VPC_BITS-1:0] D_BP_target_pc;

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
  // MUL pipe wires (NEW)
  // =======================
  wire                 mul_result_valid;        // M5 valid
  wire [XLEN-1:0]       mul_result;
  wire                 mul_busy;
  wire [ADDR_SIZE-1:0]  mul_busy_rd;

  wire                 mul_wb_conflict_stall;   // M5 wants WB but MEM wants WB too
  wire                 mul_issue_stall;         // D_mul while mul_busy



  // ============================================================
  // PC Register
  // ============================================================
  pc #(
    .PCLEN   (VPC_BITS),
    .RESET_PC(RESET_PC)
  ) u_pc (
    .clk            (clk),
    .rst            (rst),
    .EX_taken       (EX_taken),
    .EX_alt_pc      (EX_alu_out),
    .F_BP_target_pc (F_BP_target_pc),

    .stall_D ( stall_D
             | dcache_stall
             | Dtlb_stall
             | Itlb_stall
             | F_stall
             | sb_stall
             |mul_wb_conflict_stall
             |mul_issue_stall
             ),

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
    .F_admin        (F_admin),

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

    .Dtlb_pa_request (Dtlb_pa_request),
    .Dtlb_va         (Dtlb_va),

    .Dtlb_ptw_valid  (Dtlb_ptw_valid),
    .Dtlb_ptw_pa     (Dtlb_ptw_pa),

    .Ptw_mem_req     (Ptw_mem_req),
    .Ptw_mem_addr    (Ptw_mem_addr),
    .Ptw_mem_rdata   (Ptw_mem_rdata),
    .Ptw_mem_valid   (Ptw_mem_valid),

    .dcache_stall    (dcache_stall)
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
  // F → D pipeline register (UPDATED)
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

    .stall_D        (stall_D),
    .dcache_stall   (dcache_stall),
    .sb_stall       (sb_stall),
    .Itlb_stall     (Itlb_stall),
    .Dtlb_stall     (Dtlb_stall),

    .EX_taken       (EX_taken),

    .mul_wb_conflict_stall (mul_wb_conflict_stall),
    .mul_issue_stall       (mul_issue_stall),

    .D_pc           (D_pc),
    .D_inst         (D_inst),
    .D_BP_taken     (D_BP_taken),
    .D_BP_target_pc (D_BP_target_pc)
  );

  // =======================
  // Decoder
  // =======================
  decode #(
    .XLEN(XLEN)
  ) u_decode (
    .clk      (clk),
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
    .D_brn    (D_brn),
    .D_addi   (D_addi),
    .D_mul    (D_mul)
  );

  // =======================
  // Hazard Unit (UPDATED with mul_busy)
  // =======================
  Hazard_unit #(
    .XLEN     (XLEN),
    .ADDR_SIZE(ADDR_SIZE)
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

    .mul_busy   (mul_busy),
    .mul_busy_rd(mul_busy_rd),

    .stall_D    (stall_D),
    .EX_D_bp    (EX_D_bp),
    .MEM_D_bp   (MEM_D_bp),
    .WB_D_bp    (WB_D_bp)
  );

  // =======================
  // Regfile
  // =======================
  regfile #(
    .XLEN     (XLEN),
    .REG_NUM  (REG_NUM),
    .ADDR_SIZE(ADDR_SIZE),
    .PC_BITS  (PC_BITS),
    .VPC_BITS (VPC_BITS)
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

    .EX_D_bp      (EX_D_bp),
    .MEM_D_bp     (MEM_D_bp),
    .WB_D_bp      (WB_D_bp),

    .EX_alu_out   (EX_alu_out),
    .MEM_data_mem (MEM_data_mem),

    .WB_we        (WB_we),
    .WB_rd        (WB_rd),
    .WB_data_mem  (WB_data_mem),
    .WB_pc        (WB_pc),
    .WB_jlx       (WB_jlx),

    .D_a          (D_a),
    .D_b          (D_b),
    .D_a2         (D_a2),
    .D_b2         (D_b2)
  );

  // =======================
  // D → EX pipeline register (UPDATED)
  // =======================
  d_to_ex_reg #(
    .XLEN     (XLEN),
    .PC_BITS  (PC_BITS),
    .VPC_BITS (VPC_BITS)
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

    .stall_D        (stall_D),
    .dcache_stall   (dcache_stall),
    .sb_stall       (sb_stall),
    .Dtlb_stall     (Dtlb_stall),
    .EX_taken       (EX_taken),

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
    .EX_BP_target_pc(EX_BP_target_pc)
  );

  // =======================
  // MUL pipe (NEW)
  // =======================
  mul_pipe_single #(
    .XLEN    (XLEN),
    .RD_BITS (ADDR_SIZE)
  ) u_mul_pipe (
    .clk          (clk),
    .rst          (rst),

    .EX_mul_a     (EX_a2),
    .EX_mul_b     (EX_b2),
    .EX_mul_rd    (EX_rd),

    .MEM_we       (MEM_we),
    .MEM_jlx      (MEM_jlx),

    .EX_mul        (EX_mul),

    .mul_result_valid       (mul_result_valid),
    .mul_result             (mul_result),

    .mul_busy               (mul_busy),
    .mul_busy_rd            (mul_busy_rd),

    .mul_wb_conflict_stall  (mul_wb_conflict_stall),
    .mul_issue_stall        (mul_issue_stall)
  );

  // =======================
  // ALU (UPDATED: EX_mul input)
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
  // EX → MEM pipeline register (UPDATED)
  // =======================
  ex_to_mem_reg #(
    .XLEN    (XLEN),
    .PC_BITS (PC_BITS)
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
    .MEM_jlx     (MEM_jlx)
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
    .Ptw_valid      (Ptw_mem_valid)
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
  // MEM → WB pipeline register (UPDATED for MUL override)
  // =======================
  mem_to_wb_reg #(
    .XLEN    (XLEN),
    .PC_BITS (PC_BITS)
  ) u_mem_to_wb_reg (
    .clk          (clk),
    .rst          (rst),

    .MEM_data_mem (MEM_data_mem),
    .MEM_rd       (MEM_rd),
    .MEM_we       (MEM_we),
    .MEM_pc       (MEM_pc),
    .MEM_jlx      (MEM_jlx),

    .sb_hit       (sb_hit),
    .sb_data      (sb_data),

    .mul_done     (mul_result_valid),
    .mul_result   (mul_result),
    .mul_rd       (mul_busy_rd),

    .WB_data_mem  (WB_data_mem),
    .WB_rd        (WB_rd),
    .WB_we        (WB_we),
    .WB_pc        (WB_pc),
    .WB_jlx       (WB_jlx)
  );

endmodule
