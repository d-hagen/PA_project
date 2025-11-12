module alu #(parameter XLEN = 32) (
  input  wire [XLEN-1:0] EX_a,
  input  wire [XLEN-1:0] EX_a2,
  input  wire [XLEN-1:0] EX_b,
  input  wire [XLEN-1:0] EX_b2,
  input  wire [3:0]      EX_alu_op,   // 4-bit opcode
  input  wire            EX_brn,      // branch mode
  output reg  [XLEN-1:0] EX_alu_out,
  output reg             EX_taken
);

  // Width of shift amount for parameterized XLEN
  localparam SHW = (XLEN <= 1) ? 1 : $clog2(XLEN);

  always @(*) begin
    EX_taken = 0;

    if (EX_brn) begin
      // In branch mode, compute target and set 'EX_taken' based on compares
      EX_alu_out = EX_a + EX_b;  // e.g., PC + offset

      case (EX_alu_op)
        4'b1000: EX_taken = (EX_a2 == EX_b2); // EQ
        4'b1001: EX_taken = (EX_a2 <  EX_b2); // LT (unsigned)
        4'b1010: EX_taken = (EX_a2 >  EX_b2); // GT (unsigned)
        default: EX_taken = 1;       // e.g., unconditional jump
      endcase

    end else begin
      // Regular ALU operations
      case (EX_alu_op)
        4'b0000: EX_alu_out = EX_a + EX_b;                                  // ADD
        4'b0001: EX_alu_out = EX_a - EX_b;                                  // SUB
        4'b0010: EX_alu_out = EX_a & EX_b;                                  // AND
        4'b0011: EX_alu_out = EX_a | EX_b;                                  // OR
        4'b0100: EX_alu_out = EX_a ^ EX_b;                                  // XOR
        4'b0101: EX_alu_out = ~EX_a;                                     // NOT
        4'b0110: EX_alu_out = EX_a << EX_b[SHW-1:0];                        // SHL
        4'b0111: EX_alu_out = EX_a >> EX_b[SHW-1:0];                        // SHR (logical)
        4'b1000: EX_alu_out = {{(XLEN-1){1'b0}}, (EX_a == EX_b)};           // EQ -> boolean in LSB
        4'b1001: EX_alu_out = {{(XLEN-1){1'b0}}, (EX_a <  EX_b)};           // LT (unsigned)
        4'b1010: EX_alu_out = {{(XLEN-1){1'b0}}, (EX_a >  EX_b)};           // GT (unsigned)
        4'b1011: EX_alu_out = EX_a * EX_b;        
        default: EX_alu_out = EX_a + EX_b;
      endcase

      EX_taken = 1'b0; // not in branch mode
    end
  end

endmodule
