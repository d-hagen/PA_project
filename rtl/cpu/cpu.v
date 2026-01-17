`timescale 1ns/1ps

module cpu #(
  parameter integer XLEN      = 32,
  parameter integer REG_NUM   = 32,
  parameter integer ADDR_SIZE = 5,
  parameter integer PC_BITS   = 20,
  parameter integer VPC_BITS  = 32,
  parameter [VPC_BITS-1:0] RESET_PC = 32'h0000_1000
)(
  input  wire clk,
  input  wire rst
);

  `include "cpu_localparams.vh"
  `include "cpu_wires.vh"
  `include "cpu_control.vh"
  `include "cpu_instances_frontend.vh"
  `include "cpu_instances_backend_mem.vh"


endmodule
