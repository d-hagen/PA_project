// mul_pipe_single.v
`timescale 1ns/1ps

module mul_pipe_single #(
  parameter XLEN    = 32,
  parameter RD_BITS = 5
) (
  input  wire                 clk,
  input  wire                 rst,

  // Start MUL (from EX/Issue)
  input  wire                 EX_mul,
  input  wire [XLEN-1:0]      EX_mul_a,
  input  wire [XLEN-1:0]      EX_mul_b,
  input  wire [RD_BITS-1:0]   EX_mul_rd,

  // Non-MUL WB usage indicators (i.e., "normal" pipeline wants WB this cycle)
  input  wire                 MEM_we,    // normal reg writeback
  input  wire                 MEM_jlx,   // link writeback

  // Current decoded instruction is a MUL (used to stall issue while pipe busy)

  // Result to WB mux
  output wire                 mul_result_valid,
  output wire [XLEN-1:0]      mul_result,

  // Hazard/status
  output wire                 mul_busy,
  output wire [RD_BITS-1:0]   mul_busy_rd,

  // Stall request when WB conflict (MUL has priority, so freeze main pipe)
  output wire                 mul_wb_conflict_stall,

  // Stall request when trying to issue a MUL but MUL pipe already busy
  output wire                 mul_issue_stall
);

  // ----------------------------
  // Pipeline valids (5-stage MUL)
  // ----------------------------
  reg v1, v2, v3, v4, v5;

  // Pipeline data
  reg [XLEN-1:0] p1, p2, p3, p4, p5;

  // Destination register (single in-flight MUL)
  reg [RD_BITS-1:0] mul_rd;

  // Busy if any stage valid
  assign mul_busy    = v1 | v2 | v3 | v4 | v5;
  assign mul_busy_rd = mul_rd;

  // Completion is stage 5 valid
  assign mul_result_valid = v5;
  assign mul_result       = p5;

  // WB conflict: MUL finishes (v5) AND normal pipe also wants WB in same cycle.
  // IMPORTANT: MUL must NOT freeze; main pipe must stall so MEM result isn't lost.
  assign mul_wb_conflict_stall = v5 && (MEM_we || MEM_jlx);

  // Issue conflict: decode wants MUL while one is already in-flight
  assign mul_issue_stall = EX_mul && mul_busy;

  // Accept a new MUL only if idle (single in-flight allowed)
  wire accept_new = EX_mul && !mul_busy;

  // ----------------------------
  // MUL pipeline: NEVER FREEZE
  // ----------------------------
  always @(posedge clk) begin
    if (rst) begin
      v1 <= 1'b0; v2 <= 1'b0; v3 <= 1'b0; v4 <= 1'b0; v5 <= 1'b0;
      p1 <= {XLEN{1'b0}}; p2 <= {XLEN{1'b0}};
      p3 <= {XLEN{1'b0}}; p4 <= {XLEN{1'b0}}; p5 <= {XLEN{1'b0}};
      mul_rd <= {RD_BITS{1'b0}};
    end else begin
      // Shift every cycle (no hold on WB conflict)
      v5 <= v4;  p5 <= p4;
      v4 <= v3;  p4 <= p3;
      v3 <= v2;  p3 <= p2;
      v2 <= v1;  p2 <= p1;

      // Insert new MUL or bubble
      if (accept_new) begin
        v1     <= 1'b1;
        p1     <= EX_mul_a * EX_mul_b;
        mul_rd <= EX_mul_rd;
      end else begin
        v1 <= 1'b0;
        p1 <= {XLEN{1'b0}};
      end
    end
  end

endmodule
