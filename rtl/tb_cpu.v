`timescale 1ns/1ps

module tb_cpu_fix;

  // clock/reset
  reg clk = 1'b0;
  reg rst = 1'b1;
  always #5 clk = ~clk;  // 100 MHz

  // DUT
  cpu dut (.clk(clk), .rst(rst));

  // ===== opcodes (match your decode) =====
  localparam [5:0] OPC_ADD   = 6'b000000;
  localparam [5:0] OPC_SUB   = 6'b000001;
  localparam [5:0] OPC_AND   = 6'b000010;
  localparam [5:0] OPC_OR    = 6'b000011;
  localparam [5:0] OPC_XOR   = 6'b000100;
  localparam [5:0] OPC_NOT   = 6'b000101;
  localparam [5:0] OPC_SHL   = 6'b000110;
  localparam [5:0] OPC_SHR   = 6'b000111;

  localparam [5:0] OPC_EQ    = 6'b001000;
  localparam [5:0] OPC_LT    = 6'b001001;
  localparam [5:0] OPC_GT    = 6'b001010;

  localparam [5:0] OPC_LOAD  = 6'b001011;
  localparam [5:0] OPC_STORE = 6'b001100;

  localparam [5:0] OPC_CTRL  = 6'b001101;
  localparam [4:0] RD_JMP    = 5'b00000;

  // ===== simple encoders =====
  function [31:0] enc_inst;
    input [5:0]  opc;
    input [4:0]  ra;
    input [4:0]  rb;
    input [4:0]  rd;
    input [10:0] imd;
    begin enc_inst = {opc, ra, rb, rd, imd}; end
  endfunction

  function [31:0] enc_jmp;
    input [4:0] target_pc;
    begin enc_jmp = {OPC_CTRL, 5'd0, 5'd0, RD_JMP, 6'd0, target_pc}; end
  endfunction

  // ===== tiny ALU-only program =====
  localparam integer PROG_LEN = 11;
  reg [31:0] prog [0:PROG_LEN-1];

  integer i;
  initial begin
    for (i = 0; i < PROG_LEN; i = i + 1) prog[i] = 32'h0;

    prog[0]  = enc_inst(OPC_NOT, 5'd0, 5'd0, 5'd1, 11'd0); // r1 = ~r0 = 0xFFFF_FFFF
    prog[1]  = enc_inst(OPC_SHR, 5'd1, 5'd1, 5'd2, 11'd0); // r2 = 1
    prog[2]  = enc_inst(OPC_ADD, 5'd2, 5'd2, 5'd3, 11'd0); // r3 = 2
    prog[3]  = enc_inst(OPC_ADD, 5'd3, 5'd2, 5'd4, 11'd0); // r4 = 3
    prog[4]  = enc_inst(OPC_SHL, 5'd2, 5'd3, 5'd5, 11'd0); // r5 = 4
    prog[5]  = enc_inst(OPC_ADD, 5'd5, 5'd4, 5'd6, 11'd0); // r6 = 7
    prog[6]  = enc_inst(OPC_XOR, 5'd6, 5'd3, 5'd7, 11'd0); // r7 = 5
    prog[7]  = enc_inst(OPC_AND, 5'd6, 5'd5, 5'd8, 11'd0); // r8 = 4
    prog[8]  = enc_inst(OPC_OR,  5'd6, 5'd3, 5'd9, 11'd0); // r9 = 7
    prog[9]  = enc_inst(OPC_EQ,  5'd6, 5'd9, 5'd10,11'd0); // r10 = (r6==r9)
    prog[10] = enc_jmp(5'd10);                             // spin
  end

  // ===== VCD, reset, program load =====
  initial begin
    $dumpfile("tb_cpu.vcd");
    $dumpvars(0, tb_cpu_fix);

    // Optionally emit a hex for your ROM to read
    $writememh("program.hex", prog);
    $display("[TB] Wrote program.hex (PROG_LEN=%0d).", PROG_LEN);

    // Load program one of three ways:
    // 1) Use FAKE ROM/RAM compiled below (define TB_FAKE_MEMS)
    // 2) Poke your ROM array by path: +define+TB_ROM_PATH=dut.u_instruct_reg.rom (or .mem)
    // 3) Let your own instruct_reg $readmemh(\"program.hex\") at time 0

`ifdef TB_FAKE_MEMS
    begin : load_fake
      integer j;
      for (j = 0; j < PROG_LEN; j = j + 1)
        dut.u_instruct_reg.rom[j] = prog[j];
      $display("[TB] Loaded FAKE ROM.");
    end
`elsif TB_ROM_PATH
    begin : load_real
      integer j;
      for (j = 0; j < PROG_LEN; j = j + 1)
        `TB_ROM_PATH[j] = prog[j];
      $display("[TB] Loaded program into `TB_ROM_PATH[*].");
    end
`else
      $display("[TB] Not loading via hierarchy. Ensure your instruct_reg reads program.hex or has its own content.");
`endif

    // reset sequence
    repeat (4) @(posedge clk);
    rst = 1'b0;

    // run then finish
    repeat (200) @(posedge clk);
    $display("[TB] done.");
    $finish;
  end

  // Optional trace
  always @(posedge clk) if (!rst) begin
    $display("t=%0t PC=%0d inst=0x%08x EX_out=0x%08x taken=%0b",
             $time, dut.F_pc, dut.F_inst, dut.EX_alu_out, dut.EX_taken);
  end

endmodule

// ====== SIM-ONLY memories (only if you WANT to replace yours) ======
`ifdef TB_FAKE_MEMS
module instruct_reg #(
  parameter integer XLEN      = 32,
  parameter integer REG_NUM   = 32,
  parameter integer ADDR_SIZE = 5
)(
  input  wire                 clk,
  input  wire [ADDR_SIZE-1:0] F_pc,
  output reg  [XLEN-1:0]      F_inst
);
  localparam integer DEPTH = (1 << ADDR_SIZE);
  reg [XLEN-1:0] rom [0:DEPTH-1];
  integer k;
  initial begin
    for (k = 0; k < DEPTH; k = k + 1) rom[k] = {XLEN{1'b0}};
    F_inst = {XLEN{1'b0}};
  end
  always @(*) F_inst = rom[F_pc];
endmodule

module memory #(
  parameter integer XLEN      = 32,
  parameter integer REG_NUM   = 32,
  parameter integer ADDR_SIZE = 5
)(
  input  wire                 clk,
  input  wire                 MEM_ld,
  input  wire                 MEM_str,
  input  wire [XLEN-1:0]      MEM_alu_out,
  input  wire [XLEN-1:0]      MEM_b2,
  output reg  [XLEN-1:0]      MEM_data_mem
);
  localparam integer DEPTH = (1 << ADDR_SIZE);
  reg [XLEN-1:0] ram [0:DEPTH-1];
  integer m;
  initial begin
    for (m = 0; m < DEPTH; m = m + 1) ram[m] = {XLEN{1'b0}};
    MEM_data_mem = {XLEN{1'b0}};
  end
  wire [ADDR_SIZE-1:0] addr = MEM_alu_out[ADDR_SIZE-1:0];
  always @(posedge clk) begin
    if (MEM_str) ram[addr] <= MEM_b2;
    if (MEM_ld)  MEM_data_mem <= ram[addr];
  end
endmodule
`endif
