`timescale 1ns/1ps

module cpu #(
  parameter integer XLEN      = 32,
  parameter integer REG_NUM   = 32,
  parameter integer ADDR_SIZE = 5,
  parameter integer PC_BITS   = 5,
  parameter [PC_BITS-1:0] RESET_PC = {PC_BITS{1'b0}}
)(
  input  wire clk,
  input  wire rst
);

  // ===== Program Counter =====
  wire [PC_BITS-1:0] F_pc;                         // current PC
  wire [PC_BITS-1:0] pc_plus_1 = F_pc + {{(PC_BITS-1){1'b0}}, 1'b1};

  pc #(
    .XLEN(PC_BITS),
    .RESET_PC(RESET_PC)
  ) u_pc (
    .clk       (clk),
    .rst       (rst),
    .EX_taken  (EX_taken),
    .EX_alt_pc (EX_alu_out[PC_BITS-1:0]),          // target from ALU
    .pc        (pc_plus_1),
    .F_pc      (F_pc)
  );

  // ===== Instruction Memory =====
  wire [XLEN-1:0] F_inst;

  instruct_reg #(
    .XLEN(XLEN),
    .REG_NUM(REG_NUM),
    .ADDR_SIZE(PC_BITS)
  ) u_instruct_reg (
    .clk    (clk),
    .F_pc   (F_pc),
    .F_inst (F_inst)
  );

  // ===== Decode =====
  wire [5:0]   D_opc;
  wire [4:0]   D_ra, D_rb, D_rd;
  wire [10:0]  D_imd;
  wire         D_we;
  wire [3:0]   D_alu_op;
  wire         D_ld, D_str, D_brn, D_addi;

  // In no-pipe mode, D_pc is just F_pc (useful if your regfile uses it)
  wire [PC_BITS-1:0] D_pc = F_pc;
  wire [XLEN-1:0]    D_inst = F_inst;

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
    .D_brn    (D_brn),
    .D_addi   (D_addi)
  );

  // ===== Register File =====
  wire [XLEN-1:0] D_a, D_b, D_a2, D_b2;

  // Writeback wires (from MEM in single cycle)
  wire [XLEN-1:0] WB_data_mem;
  wire [4:0]      WB_rd;
  wire            WB_we;

  regfile #(
    .XLEN(XLEN),
    .REG_NUM(REG_NUM),
    .ADDR_SIZE(PC_BITS)
  ) u_regfile (
    .clk         (clk),
    .D_ra        (D_ra),
    .D_rb        (D_rb),
    .D_imd       (D_imd),
    .D_pc        (D_pc),
    .D_ld        (D_ld),
    .D_str       (D_str),
    .D_brn       (D_brn),
    .D_addi      (D_addi),

    // Writeback (no pipe: direct from MEM/WB signals below)
    .WB_we       (WB_we),
    .WB_rd       (WB_rd),
    .WB_data_mem (WB_data_mem),

    // Read outputs to ALU/MEM
    .D_a         (D_a),
    .D_b         (D_b),
    .D_a2        (D_a2),
    .D_b2        (D_b2)
  );

  // ===== ALU (Execute) =====
  wire [XLEN-1:0] EX_alu_out;
  wire            EX_taken;

  alu #(
    .XLEN(XLEN)
  ) u_alu (
    .EX_a       (D_a),          // from regfile
    .EX_a2      (D_a2),
    .EX_b       (D_b),
    .EX_b2      (D_b2),
    .EX_alu_op  (D_alu_op),     // from decode
    .EX_brn     (D_brn),
    .EX_alu_out (EX_alu_out),
    .EX_taken   (EX_taken)
  );

  // ===== Memory =====
  wire [XLEN-1:0] MEM_data_mem;

  memory #(
    .XLEN(XLEN),
    .REG_NUM(REG_NUM),
    .ADDR_SIZE(ADDR_SIZE)
  ) u_memory (
    .clk          (clk),
    .MEM_ld       (D_ld),          // from decode
    .MEM_str      (D_str),
    .MEM_alu_out  (EX_alu_out),    // address or pass-through result
    .MEM_b2       (D_b2),          // store data
    .MEM_data_mem (MEM_data_mem)   // data to WB (load data or ALU result)
  );

  // ===== Writeback (direct) =====
  assign WB_data_mem = MEM_data_mem;
  assign WB_rd       = D_rd;
  assign WB_we       = D_we;

endmodule
