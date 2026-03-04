`timescale 1ns/1ps

module decode #(
  parameter XLEN = 32
)(
  input  wire              clk,
  input  wire              admin,     
  input  wire [XLEN-1:0]   D_inst,

  output wire [5:0]        D_opc,
  output wire [4:0]        D_ra,
  output wire [4:0]        D_rb,
  output wire [4:0]        D_rd,
  output wire [10:0]       D_imd,
  output wire              D_we,
  output wire [3:0]        D_alu_op,

  output wire              D_ld,
  output wire              D_str,
  output wire              D_byt,

  output wire              D_brn,
  output wire              D_jmp,
  output wire              D_jlx,
  output wire              D_iret,   
  output wire              D_addi,
  output wire              D_mul,

  output wire              D_exc     // (illegal iret)
);

  assign D_opc    = D_inst[31:26];
  assign D_ra     = D_inst[25:21];
  assign D_rb     = D_inst[20:16];
  assign D_rd     = D_inst[15:11];
  assign D_imd    = D_inst[10:0];
  // CHECK : exc for unknown
  localparam OPC_ADD   = 6'b000000;
  localparam OPC_SUB   = 6'b000001;
  localparam OPC_AND   = 6'b000010;
  localparam OPC_OR    = 6'b000011;
  localparam OPC_XOR   = 6'b000100;
  localparam OPC_NOT   = 6'b000101;
  localparam OPC_SHL   = 6'b000110;
  localparam OPC_SHR   = 6'b000111;
  localparam OPC_ADDI  = 6'b001000;
  localparam OPC_LT    = 6'b001001;
  localparam OPC_GT    = 6'b001010;

  localparam OPC_LOAD  = 5'b01011;
  localparam OPC_STORE = 5'b01100;

  localparam OPC_CTRL  = 6'b001101;
  localparam OPC_MUL   = 6'b001110;

  // IRET opcode
  localparam OPC_IRET  = 6'b111111;

  localparam RD_JMP    = 4'b0000;
  localparam RD_BEQ    = 5'b00001;
  localparam RD_BLT    = 5'b00010;
  localparam RD_BGT    = 5'b00011;

  wire is_ctrl = (D_opc == OPC_CTRL);
  wire is_jmp  = is_ctrl && (D_rd[3:0] == RD_JMP);
  wire is_beq  = is_ctrl && (D_rd == RD_BEQ);
  wire is_blt  = is_ctrl && (D_rd == RD_BLT);
  wire is_bgt  = is_ctrl && (D_rd == RD_BGT);
  wire is_jlx  = is_jmp && D_rd[4];

  wire is_iret = (D_opc == OPC_IRET);

  // memory
  assign D_ld   = (D_opc[4:0] == OPC_LOAD);
  assign D_str  = (D_opc[4:0] == OPC_STORE);
  assign D_byt  =  D_opc[5];

  // control
  assign D_jmp  = is_jmp;
  assign D_jlx  = is_jlx;
  assign D_iret = is_iret;

  assign D_mul  = (D_opc == OPC_MUL);

  // write-enable: normal ALU ops, loads, MUL 
  assign D_we   = ((D_opc <= OPC_GT) || D_ld || D_mul);

  // D_brn true for CTRL-family only (branches/jmp/jlx)
  assign D_brn  = is_ctrl;

  assign D_addi = (D_opc == OPC_ADDI);

  // illegal iret ?
  assign D_exc  = is_iret && !admin;

  // ALU op decode
  assign D_alu_op =
         (D_opc == OPC_ADD)                 ? 4'b0000 :
         (D_opc == OPC_SUB)                 ? 4'b0001 :
         (D_opc == OPC_AND)                 ? 4'b0010 :
         (D_opc == OPC_OR )                 ? 4'b0011 :
         (D_opc == OPC_XOR)                 ? 4'b0100 :
         (D_opc == OPC_NOT)                 ? 4'b0101 :
         (D_opc == OPC_SHL)                 ? 4'b0110 :
         (D_opc == OPC_SHR)                 ? 4'b0111 :
         (is_beq)                           ? 4'b1000 :
         (D_opc == OPC_LT || is_blt)        ? 4'b1001 :
         (D_opc == OPC_GT || is_bgt)        ? 4'b1010 :
                                              4'b0000;

endmodule
