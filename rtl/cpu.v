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

  // ===== Program Counter wires =====
  wire [PC_BITS-1:0] F_pc;            // current PC (Fetch stage)
  wire [PC_BITS-1:0] pc_plus_1 = F_pc + {{(PC_BITS-1){1'b0}}, 1'b1};

  // ===== Instruction fetch output =====
  wire [XLEN-1:0] F_inst;             // fetched instruction

  // Hazard_unit
  wire        stall_D;



  // ===== ALU output wires =====
  wire [XLEN-1:0]  EX_alu_out;
  wire             EX_taken;

  // ===== PC Register =====
  pc #(
    .XLEN(PC_BITS),
    .RESET_PC(RESET_PC)
  ) u_pc (
    .clk       (clk),
    .rst       (rst),
    .EX_taken  (EX_taken),
    .EX_alt_pc (EX_alu_out[4:0]),
    .stall_D   (stall_D),
    .pc        (pc_plus_1),
    .F_pc      (F_pc)
  );

  // ===== Instruction Register (Instruction Memory) =====
  instruct_reg #(
    .XLEN(XLEN),
    .REG_NUM(REG_NUM),
    .ADDR_SIZE(PC_BITS)
  ) u_instruct_reg (
    .clk   (clk),
    .F_pc  (F_pc),
    .F_inst(F_inst)
  );


  wire [XLEN-1:0] D_inst;
  wire [PC_BITS-1:0] D_pc;

  f_to_d_reg #(
    .XLEN(XLEN),
    .PC_BITS(PC_BITS)
  ) u_f2d (
    .clk      (clk),
    .rst      (rst),
    .F_pc     (F_pc),
    .F_inst   (F_inst),
    .stall_D  (stall_D),
    .D_pc     (D_pc),
    .D_inst   (D_inst)
  );


  //Decoder 

  wire [5:0]        D_opc;
  wire [4:0]        D_ra;
  wire [4:0]        D_rb;
  wire [4:0]        D_rd;
  wire [10:0]       D_imd;
  wire              D_we;
  wire [3:0]        D_alu_op;       // 4-bit ALU op
  wire              D_ld;
  wire              D_str;
  wire              D_brn;
  wire              D_addi;

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

  // ----- Hazard unit wires -----
  wire [1:0]  EX_D_bp;
  wire [1:0]  MEM_D_bp;
  wire [1:0]  WB_D_bp;

  // ----- Hazard unit instance -----
  Hazard_unit #(
    .XLEN(XLEN),
    .ADDR_SIZE(ADDR_SIZE)   // use reg address size, not PC bits
  ) u_Hazard_unit (
    // Decode stage
    .D_ra      (D_ra),
    .D_rb      (D_rb),
    .D_rd      (D_rd),

    // EX stage
    .EX_alu_out(EX_alu_out),  // (not used for detection but fine to pass)
    .EX_rd     (EX_rd),
    .EX_we     (EX_we),
    .EX_ld     (EX_ld),

    // MEM stage
    .MEM_rd    (MEM_rd),
    .MEM_we    (MEM_we),

    // WB stage
    .WB_rd     (WB_rd),
    .WB_we     (WB_we),

    // Outputs
    .stall_D   (stall_D),
    .EX_D_bp   (EX_D_bp),     // {ra, rb}
    .MEM_D_bp  (MEM_D_bp),    // {ra, rb}
    .WB_D_bp   (WB_D_bp)      // {ra, rb}
  );

  //Regfile 
  
                                    
  wire [XLEN-1:0]      D_a;      // value of raddr1
  wire [XLEN-1:0]      D_b;       // value of raddr2
  wire [XLEN-1:0]      D_a2;       // value of raddr2
  wire [XLEN-1:0]      D_b2;       // value of raddr2


  regfile #(
    .XLEN(XLEN),
    .REG_NUM(REG_NUM),
    .ADDR_SIZE(PC_BITS)
  ) u_regfile (
    // From Decode
    .clk        (clk),
    .D_ra       (D_ra),      // first register to read
    .D_rb       (D_rb),      // second register to read
    .D_imd      (D_imd),
    .D_pc       (D_pc),
    .D_ld       (D_ld),
    .D_str      (D_str),
    .D_brn      (D_brn),
    .D_addi     (D_addi),

    //From Hazard_unit
    .EX_D_bp    (EX_D_bp),
    .MEM_D_bp   (MEM_D_bp),
    .WB_D_bp    (WB_D_bp),

    .EX_alu_out (EX_alu_out),   // EX result (valid when EX_D_bp used and not a load-use)
    .MEM_data_mem  (MEM_data_mem), // data a


    // From Writeback stage
    .WB_we      (WB_we),
    .WB_rd      (WB_rd),
    .WB_data_mem(WB_data_mem),


    // Outputs to Execute
    .D_a        (D_a),
    .D_b        (D_b),
    .D_a2       (D_a2),
    .D_b2       (D_b2)
  );



  // ===== D → EX pipeline register =====


  wire [XLEN-1:0] EX_a;
  wire [XLEN-1:0] EX_a2;
  wire [XLEN-1:0] EX_b;
  wire [XLEN-1:0] EX_b2;
  wire [3:0]       EX_alu_op;
  wire [4:0]       EX_rd;
  wire             EX_ld;
  wire             EX_str;
  wire             EX_we;
  wire             EX_brn;

  d_to_ex_reg #(
    .XLEN(XLEN)
  ) u_d_to_ex_reg (
    .clk      (clk),
    .rst      (rst),

    // From Decode/Regfile (D stage)
    .D_a      (D_a),
    .D_a2     (D_a2),
    .D_b      (D_b),
    .D_b2     (D_b2),
    .D_alu_op (D_alu_op),
    .D_brn    (D_brn),
    .D_rd     (D_rd),
    .D_ld     (D_ld),
    .D_str    (D_str),
    .D_we     (D_we),

    .stall_D  (stall_D),


    // To Execute stage (EX)
    .EX_a     (EX_a),
    .EX_a2    (EX_a2),
    .EX_b     (EX_b),
    .EX_b2    (EX_b2),
    .EX_alu_op(EX_alu_op),
    .EX_rd    (EX_rd),
    .EX_ld    (EX_ld),
    .EX_str   (EX_str),
    .EX_we    (EX_we),
    .EX_brn   (EX_brn)
  );


  // ===== ALU stage =====

 


  alu #(
    .XLEN(XLEN)
  ) u_alu (
    .EX_a      (EX_a),
    .EX_a2     (EX_a2),
    .EX_b      (EX_b),
    .EX_b2     (EX_b2),
    .EX_alu_op (EX_alu_op),
    .EX_brn    (EX_brn),
    .EX_alu_out(EX_alu_out),
    .EX_taken  (EX_taken)
  );


  // ===== EX → MEM pipeline register wires =====
  wire [XLEN-1:0] MEM_alu_out;
  wire             MEM_taken;
  wire [XLEN-1:0] MEM_b2;
  wire [XLEN-1:0] MEM_a2;
  wire [4:0]       MEM_rd;
  wire             MEM_we;
  wire             MEM_ld;
  wire             MEM_str;

  // ===== EX → MEM pipeline register =====
  ex_to_mem_reg #(
    .XLEN(XLEN)
  ) u_ex_to_mem_reg (
    .clk        (clk),
    .rst        (rst),

    // From Execute stage (EX)
    .EX_alu_out (EX_alu_out),
    .EX_taken   (EX_taken),
    .EX_b2      (EX_b2),
    .EX_a2      (EX_a2),
    .EX_rd      (EX_rd),
    .EX_we      (EX_we),
    .EX_ld      (EX_ld),
    .EX_str     (EX_str),

    // To Memory stage (MEM)
    .MEM_alu_out(MEM_alu_out),
    .MEM_taken  (MEM_taken),
    .MEM_b2     (MEM_b2),
    .MEM_a2     (MEM_a2),
    .MEM_rd     (MEM_rd),
    .MEM_we     (MEM_we),
    .MEM_ld     (MEM_ld),
    .MEM_str    (MEM_str)
  );



  // ===== Memory stage output wires =====
  wire [XLEN-1:0] MEM_data_mem;

  // ===== Memory stage =====
  memory #(
    .XLEN(XLEN),
    .REG_NUM(REG_NUM),
    .ADDR_SIZE(ADDR_SIZE)
  ) u_memory (
    .clk         (clk),
    .MEM_ld      (MEM_ld),
    .MEM_str     (MEM_str),
    .MEM_alu_out (MEM_alu_out),
    .MEM_b2      (MEM_b2),
    .MEM_data_mem(MEM_data_mem)
  );



  // ===== MEM → WB pipeline register wires =====
  wire [XLEN-1:0] WB_data_mem;
  wire [4:0]       WB_rd;
  wire             WB_we;

  // ===== MEM → WB pipeline register =====
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
