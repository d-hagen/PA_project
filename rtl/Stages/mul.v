`timescale 1ns/1ps

module mul_pipe_single #(
  parameter XLEN    = 32,
  parameter RD_BITS = 5,
  parameter TAG_W   = 4   
) (
  input  wire                 clk,
  input  wire                 rst,

  input  wire                 EX_mul,
  input  wire [XLEN-1:0]      EX_mul_a,
  input  wire [XLEN-1:0]      EX_mul_b,
  input  wire [RD_BITS-1:0]   EX_mul_rd,
  input  wire [TAG_W-1:0]     EX_mul_tag,     

  input  wire                 MEM_we,    // normal reg writeback
  input  wire                 MEM_jlx,   // link writeback

  output wire                 mul_result_valid,
  output wire [XLEN-1:0]      mul_result,
  output wire [RD_BITS-1:0]   mul_rd,          // rd at completion
  output wire [TAG_W-1:0]     mul_result_tag,  // tag at completion

  output wire                 mul_busy,
  output wire [RD_BITS-1:0]   mul_busy_rd,
  output wire [TAG_W-1:0]     mul_busy_tag,    

  output wire                 mul_wb_conflict_stall,
  output wire                 mul_issue_stall
);

  reg v1, v2, v3, v4, v5;
  reg [XLEN-1:0] p1, p2, p3, p4, p5;

  reg [RD_BITS-1:0] rd1, rd2, rd3, rd4, rd5;
  reg [TAG_W-1:0]   t1,  t2,  t3,  t4,  t5;

  assign mul_busy    = v1 | v2 | v3 | v4 | v5;
  assign mul_busy_rd = rd5;         
  assign mul_busy_tag= t5;

  assign mul_result_valid = v5;
  assign mul_result       = p5;
  assign mul_rd           = rd5;
  assign mul_result_tag   = t5;

  assign mul_wb_conflict_stall = v5 && (MEM_we || MEM_jlx);
  assign mul_issue_stall = EX_mul && mul_busy;

  wire accept_new = EX_mul && !mul_busy;

  always @(posedge clk) begin
    if (rst) begin
      v1 <= 1'b0; v2 <= 1'b0; v3 <= 1'b0; v4 <= 1'b0; v5 <= 1'b0;
      p1 <= {XLEN{1'b0}}; p2 <= {XLEN{1'b0}};
      p3 <= {XLEN{1'b0}}; p4 <= {XLEN{1'b0}}; p5 <= {XLEN{1'b0}};

      rd1 <= {RD_BITS{1'b0}}; rd2 <= {RD_BITS{1'b0}}; rd3 <= {RD_BITS{1'b0}};
      rd4 <= {RD_BITS{1'b0}}; rd5 <= {RD_BITS{1'b0}};

      t1  <= {TAG_W{1'b0}}; t2  <= {TAG_W{1'b0}}; t3  <= {TAG_W{1'b0}};
      t4  <= {TAG_W{1'b0}}; t5  <= {TAG_W{1'b0}};
    end else begin
      // shift pipeline
      v5 <= v4;  p5 <= p4;  rd5 <= rd4;  t5 <= t4;
      v4 <= v3;  p4 <= p3;  rd4 <= rd3;  t4 <= t3;
      v3 <= v2;  p3 <= p2;  rd3 <= rd2;  t3 <= t2;
      v2 <= v1;  p2 <= p1;  rd2 <= rd1;  t2 <= t1;

      if (accept_new) begin
        v1  <= 1'b1;
        p1  <= EX_mul_a * EX_mul_b;
        rd1 <= EX_mul_rd;
        t1  <= EX_mul_tag;
      end else begin
        v1  <= 1'b0;
        p1  <= {XLEN{1'b0}};
        rd1 <= {RD_BITS{1'b0}};
        t1  <= {TAG_W{1'b0}};
      end
    end
  end

endmodule
