`timescale 1ns/1ps

module rename #(
  parameter integer REG_NUM   = 32,
  parameter integer ADDR_SIZE = 5,
  parameter integer ROB_DEPTH = 16,
  parameter integer TAG_W     = $clog2(ROB_DEPTH)
)(
  input  wire                   clk,
  input  wire                   rst,

  // Decode regs
  input  wire [ADDR_SIZE-1:0]   D_ra,
  input  wire [ADDR_SIZE-1:0]   D_rb,
  input  wire [ADDR_SIZE-1:0]   D_rd,
  input  wire                   D_we,
  input  wire                   D_jlx,

  // NEW: instruction really issues/advances this cycle
  input  wire                   D_fire,

  // Rename outputs (combinational)
  output wire                   ra_is_rob,
  output wire                   rb_is_rob,
  output wire [TAG_W-1:0]       ra_tag,
  output wire [TAG_W-1:0]       rb_tag,

  // Alloc/tag for this instruction
  output wire [TAG_W-1:0]       dst_tag,
  output wire                   rob_alloc,
  output wire [TAG_W-1:0]       rob_alloc_tag,

  // Stall when ROB full
  input  wire                   rob_full_in,

  // Commit feedback to clear RAT mapping
  input  wire                   C_valid,
  input  wire                   C_we,
  input  wire [ADDR_SIZE-1:0]   C_rd_arch,
  input  wire [TAG_W-1:0]       C_tag
);

  // Effective dest: JLX -> r31 and force write
  wire [ADDR_SIZE-1:0] dest_arch = D_jlx ? 5'd31 : D_rd;
  wire                 dest_we   = D_we | D_jlx;

  // RAT
  reg                  rat_valid [0:REG_NUM-1];
  reg [TAG_W-1:0]       rat_tag   [0:REG_NUM-1];

  // Tail pointer (next tag to allocate)
  reg [TAG_W-1:0] tail_tag;

  integer i;

  // --------------------------
  // COMBINATIONAL LOOKUP
  // --------------------------
  assign ra_is_rob = rat_valid[D_ra];
  assign rb_is_rob = rat_valid[D_rb];

  assign ra_tag    = rat_tag[D_ra];
  assign rb_tag    = rat_tag[D_rb];

  // The tag this instruction will use if it allocates this cycle
  assign dst_tag       = tail_tag;
  assign rob_alloc_tag = tail_tag;

  // Allocate only when instruction actually fires and ROB isn't full
  assign rob_alloc = D_fire && !rob_full_in;

  // --------------------------
  // SEQUENTIAL UPDATE
  // --------------------------
  always @(posedge clk) begin
    if (rst) begin
      tail_tag <= {TAG_W{1'b0}};
      for (i = 0; i < REG_NUM; i = i + 1) begin
        rat_valid[i] <= 1'b0;
        rat_tag[i]   <= {TAG_W{1'b0}};
      end
    end else begin
      // Commit clears mapping if it still points to committing tag
      if (C_valid && C_we && (C_rd_arch != {ADDR_SIZE{1'b0}})) begin
        if (rat_valid[C_rd_arch] && (rat_tag[C_rd_arch] == C_tag)) begin
          rat_valid[C_rd_arch] <= 1'b0;
          rat_tag[C_rd_arch]   <= {TAG_W{1'b0}};
        end
      end

      // On issue: allocate new tag and update RAT for dest
      if (D_fire && !rob_full_in) begin
        if (dest_we && (dest_arch != {ADDR_SIZE{1'b0}})) begin
          rat_valid[dest_arch] <= 1'b1;
          rat_tag[dest_arch]   <= tail_tag;
        end
        tail_tag <= tail_tag + {{(TAG_W-1){1'b0}}, 1'b1};
      end
    end
  end

endmodule
