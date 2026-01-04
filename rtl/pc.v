`timescale 1ns/1ps

module pc #(
  parameter integer PCLEN = 32,
  parameter [PCLEN-1:0] RESET_PC = {PCLEN{1'b0}}
)(
  input  wire                clk,
  input  wire                rst,

  // NEW: highest-priority redirect (exception vector or iret target)
  input  wire                redir_valid,
  input  wire [PCLEN-1:0]    redir_pc,

  // existing branch redirect
  input  wire                EX_taken,
  input  wire [PCLEN-1:0]    EX_alt_pc,

  // predictor / sequential next
  input  wire [PCLEN-1:0]    F_BP_target_pc,

  // global stall
  input  wire                stall_D,

  output reg  [PCLEN-1:0]    F_pc_va
);

 always @(posedge clk) begin
  if (rst) begin
    F_pc_va <= RESET_PC;

  // highest priority: redirects ignore stall
  end else if (redir_valid) begin
    F_pc_va <= redir_pc;

  end else if (EX_taken) begin
    F_pc_va <= EX_alt_pc;

  // stall only applies if no redirect/taken
  end else if (stall_D) begin
    F_pc_va <= F_pc_va;   // explicit hold

  // normal sequential / predictor
  end else begin
    F_pc_va <= F_BP_target_pc;
  end
end

endmodule

