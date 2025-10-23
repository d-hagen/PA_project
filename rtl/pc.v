`timescale 1ns/1ps
// `default_nettype none

module pc #(
    parameter integer XLEN = 5,
    parameter [XLEN-1:0] RESET_PC = {XLEN{1'b0}}
)(
    input  wire                 clk,
    input  wire                 rst,         // async reset, active high
    input  wire                 EX_taken,    // branch/jump taken
    input  wire [XLEN-1:0]      EX_alt_pc,   // alternate PC when taken
    input  wire [XLEN-1:0]      pc,          // sequential next PC when not taken
    output reg  [XLEN-1:0]      F_pc         // current/fetch PC
);

    always @(posedge clk or posedge rst) begin
        if (rst)
            F_pc <= RESET_PC;
        else
            F_pc <= EX_taken ? EX_alt_pc : pc;
    end

endmodule
