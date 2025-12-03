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
  wire [VPC_BITS-1:0] F_pc;            // current PC (Fetch stage)
  wire [XLEN-1:0]    F_inst;          // fetched instruction

  // Branch Predictor / buffer
  wire                 F_BP_taken;
  wire [VPC_BITS-1:0]  F_BP_target_pc;
  wire                 F_stall;

  // Decode stage / F→D reg
  wire [XLEN-1:0]    D_inst;
  wire [VPC_BITS-1:0] D_pc;
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
  wire               D_addi;
  wire               D_mul;
  wire               D_byt;

  // Hazard unit
  wire               stall_D;
  wire [1:0]         EX_D_bp;
  wire [1:0]         MEM_D_bp;
  wire [1:0]         WB_D_bp;

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
  wire               MEM_stall;

  // I-Cache <-> Instruction Memory
  wire               Ic_mem_req;
  wire [PC_BITS-5:0] Ic_mem_addr;
  wire [127:0]       F_mem_inst;
  wire               F_mem_valid;

  // D-cache <-> Backing Data Memory
  wire               Dc_mem_req;
  wire [PC_BITS-5:0] Dc_mem_addr;      // 16 lines in backing memory
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
  // PC Register
  // =======================
  pc #(
    .PCLEN   (VPC_BITS),
    .RESET_PC(RESET_PC)
  ) u_pc (
    .clk            (clk),
    .rst            (rst),
    .EX_taken       (EX_taken),
    .EX_alt_pc      (EX_alu_out),
    .F_BP_target_pc (F_BP_target_pc),
    .stall_D        (stall_D),
    .F_pc           (F_pc)
  );

  // =======================
  // Branch Buffer / Predictor
  // =======================
  branch_buffer #(
    .PC_BITS (VPC_BITS)
  ) u_branch_buffer (
    .clk            (clk),
    .rst            (rst),
    .F_pc           (F_pc),
    .EX_brn         (EX_brn),
    .F_stall        (F_stall),
    .MEM_stall      (MEM_stall),
    .EX_pc          (EX_a),
    .EX_alu_out     (EX_alu_out),
    .EX_true_taken  (EX_true_taken),
    .F_BP_target_pc (F_BP_target_pc),
    .F_BP_taken     (F_BP_taken)
  );

  // =======================
  // I-Cache
  // =======================
  icache u_icache (
    .clk         (clk),
    .rst         (rst),

    .F_pc        (F_pc),        // PC from F stage

    .F_mem_inst  (F_mem_inst),  // data from instruction memory
    .F_mem_valid (F_mem_valid), // valid from instruction memory

    .Ic_mem_req  (Ic_mem_req),   // request to instruction memory
    .Ic_mem_addr (Ic_mem_addr),  // address to instruction memory

    .F_inst      (F_inst),      // instruction to F stage
    .F_stall     (F_stall)      // stall signal to F-stage/pipeline
  );

  // =======================
  // F → D pipeline register
  // =======================
  f_to_d_reg #(
    .XLEN    (XLEN),
    .PC_BITS (PC_BITS),
    .VPC_BITS (VPC_BITS)
  ) u_f2d (
    .clk            (clk),
    .rst            (rst),
    .F_pc           (F_pc),
    .F_inst         (F_inst),
    .F_BP_taken     (F_BP_taken),
    .F_BP_target_pc (F_BP_target_pc),
    .stall_D        (stall_D),
    .MEM_stall      (MEM_stall),
    .EX_taken       (EX_taken),
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
    .D_brn    (D_brn),
    .D_addi   (D_addi),
    .D_mul    (D_mul)
  );

  // =======================
  // Hazard Unit
  // =======================
  Hazard_unit #(
    .XLEN     (XLEN),
    .ADDR_SIZE(ADDR_SIZE)   // use reg address size, not PC bits
  ) u_Hazard_unit (
    .clk        (clk),
    .rst        (rst),

    // Decode stage
    .D_ra       (D_ra),
    .D_rb       (D_rb),
    .D_rd       (D_rd),

    // EX stage
    .EX_alu_out (EX_alu_out),
    .EX_rd      (EX_rd),
    .EX_we      (EX_we),
    .EX_ld      (EX_ld),
    .EX_mul     (EX_mul),

    // MEM stage
    .MEM_rd     (MEM_rd),
    .MEM_we     (MEM_we),

    // WB stage
    .WB_rd      (WB_rd),
    .WB_we      (WB_we),

    // Outputs
    .stall_D    (stall_D),
    .EX_D_bp    (EX_D_bp),     // {ra, rb}
    .MEM_D_bp   (MEM_D_bp),    // {ra, rb}
    .WB_D_bp    (WB_D_bp)      // {ra, rb}
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
    // From Decode
    .clk          (clk),
    .D_ra         (D_ra),      // first register to read
    .D_rb         (D_rb),      // second register to read
    .D_imd        (D_imd),
    .D_pc         (D_pc),
    .D_ld         (D_ld),
    .D_str        (D_str),
    .D_brn        (D_brn),
    .D_addi       (D_addi),

    // From Hazard_unit
    .EX_D_bp      (EX_D_bp),
    .MEM_D_bp     (MEM_D_bp),
    .WB_D_bp      (WB_D_bp),

    .EX_alu_out   (EX_alu_out),   // EX result (valid when EX_D_bp used and not a load-use)
    .MEM_data_mem (MEM_data_mem), // data a

    // From Writeback stage
    .WB_we        (WB_we),
    .WB_rd        (WB_rd),
    .WB_data_mem  (WB_data_mem),

    // Outputs to Execute
    .D_a          (D_a),
    .D_b          (D_b),
    .D_a2         (D_a2),
    .D_b2         (D_b2)
  );

  // =======================
  // D → EX pipeline register
  // =======================
  d_to_ex_reg #(
    .XLEN   (XLEN),
    .PC_BITS(PC_BITS),
    .VPC_BITS (VPC_BITS)
  ) u_d_to_ex_reg (
    .clk            (clk),
    .rst            (rst),

    // From Decode/Regfile (D stage)
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
    .D_BP_taken     (D_BP_taken),
    .D_BP_target_pc (D_BP_target_pc),

    .stall_D        (stall_D),
    .MEM_stall      (MEM_stall),
    .EX_taken       (EX_taken),

    // To Execute stage (EX)
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
    .EX_BP_taken    (EX_BP_taken),
    .EX_BP_target_pc(EX_BP_target_pc)
  );

  // =======================
  // ALU
  // =======================
  alu #(
    .XLEN   (XLEN),
    .PC_BITS(PC_BITS),
    .VPC_BITS(VPC_BITS)
  ) u_alu (
    .EX_a           (EX_a),
    .EX_a2          (EX_a2),
    .EX_b           (EX_b),
    .EX_b2          (EX_b2),
    .EX_alu_op      (EX_alu_op),
    .EX_brn         (EX_brn),
    .EX_BP_taken    (EX_BP_taken),
    .EX_BP_target_pc(EX_BP_target_pc),
    .EX_alu_out     (EX_alu_out),
    .EX_taken       (EX_taken),
    .EX_true_taken  (EX_true_taken)
  );

  // =======================
  // EX → MEM pipeline register
  // =======================
  ex_to_mem_reg #(
    .XLEN(XLEN)
  ) u_ex_to_mem_reg (
    .clk         (clk),
    .rst         (rst),

    // From Execute stage (EX)
    .EX_alu_out  (EX_alu_out),
    .EX_taken    (EX_taken),
    .EX_b2       (EX_b2),
    .EX_a2       (EX_a2),
    .EX_rd       (EX_rd),
    .EX_we       (EX_we),
    .EX_ld       (EX_ld),
    .EX_str      (EX_str),
    .EX_byt      (EX_byt),
    .MEM_stall   (MEM_stall),

    // To Memory stage (MEM)
    .MEM_alu_out (MEM_alu_out),
    .MEM_taken   (MEM_taken),
    .MEM_b2      (MEM_b2),
    .MEM_a2      (MEM_a2),
    .MEM_rd      (MEM_rd),
    .MEM_we      (MEM_we),
    .MEM_ld      (MEM_ld),
    .MEM_str     (MEM_str),
    .MEM_byt     (MEM_byt)
  );

  // =======================
  // D-Cache
  // =======================
  dcache #(
    .XLEN(XLEN)
  ) u_dcache (
    .clk          (clk),
    .rst          (rst),
    .MEM_ld       (MEM_ld),
    .MEM_str      (MEM_str),
    .MEM_byt      (MEM_byt),
    .MEM_alu_out  (MEM_alu_out),
    .MEM_b2       (MEM_b2),

    // To MEM stage
    .MEM_data_mem (MEM_data_mem),
    .MEM_stall    (MEM_stall),

    // Backing memory: line read
    .Dc_mem_req   (Dc_mem_req),
    .Dc_mem_addr  (Dc_mem_addr),
    .MEM_data_line(MEM_data_line),
    .MEM_mem_valid(MEM_mem_valid),

    // Backing memory: line write-back
    .Dc_wb_we     (Dc_wb_we),
    .Dc_wb_addr   (Dc_wb_addr),
    .Dc_wb_wline  (Dc_wb_wline)
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

    // Instruction side
    .Ic_mem_req    (Ic_mem_req),
    .Ic_mem_addr   (Ic_mem_addr),
    .F_mem_inst    (F_mem_inst),
    .F_mem_valid   (F_mem_valid),

    // Data side - line read
    .Dc_mem_req    (Dc_mem_req),
    .Dc_mem_addr   (Dc_mem_addr),
    .MEM_data_line (MEM_data_line),
    .MEM_mem_valid (MEM_mem_valid),

    // Data side - line write-back
    .Dc_wb_we      (Dc_wb_we),
    .Dc_wb_addr    (Dc_wb_addr),
    .Dc_wb_wline   (Dc_wb_wline)
  );

  // =======================
  // MEM → WB pipeline register
  // =======================
  mem_to_wb_reg #(
    .XLEN(XLEN)
  ) u_mem_to_wb_reg (
    .clk         (clk),
    .rst         (rst),

    // From Memory stage (MEM)
    .MEM_data_mem(MEM_data_mem),
    .MEM_rd      (MEM_rd),
    .MEM_we      (MEM_we),

    // To Writeback stage (WB)
    .WB_data_mem (WB_data_mem),
    .WB_rd       (WB_rd),
    .WB_we       (WB_we)
  );

endmodule
