`timescale 1ns/1ps

module rob #(
  parameter integer XLEN      = 32,
  parameter integer ADDR_SIZE = 5,
  parameter integer ROB_DEPTH = 16,
  parameter integer TAG_W     = $clog2(ROB_DEPTH)
)(
  input  wire                   clk,
  input  wire                   rst,

  // Allocate (from rename)
  input  wire                   alloc_valid,
  input  wire [TAG_W-1:0]       alloc_tag,
  input  wire                   alloc_we,
  input  wire [ADDR_SIZE-1:0]   alloc_rd_arch,
  input  wire                   alloc_jlx,

  // Writeback
  input  wire                   wb_valid,
  input  wire [TAG_W-1:0]       wb_tag,
  input  wire [XLEN-1:0]        wb_value,

  // NEW: mispredict flush (flush younger-than flush_tag)
  input  wire                   flush_valid,
  input  wire [TAG_W-1:0]       flush_tag,

  // Operand read ports (for renamed operands)
  input  wire [TAG_W-1:0]       ra_tag,
  output wire                   ra_ready,
  output wire [XLEN-1:0]        ra_value,

  input  wire [TAG_W-1:0]       rb_tag,
  output wire                   rb_ready,
  output wire [XLEN-1:0]        rb_value,

  // Commit out
  output reg                    C_valid,
  output reg                    C_we,
  output reg  [ADDR_SIZE-1:0]   C_rd_arch,
  output reg  [XLEN-1:0]        C_value,
  output reg  [TAG_W-1:0]       C_tag,

  output wire                   rob_full,
  output wire                   rob_empty
);

  localparam integer CNT_W = $clog2(ROB_DEPTH+1);

  reg                   valid [0:ROB_DEPTH-1];
  reg                   ready [0:ROB_DEPTH-1];
  reg                   we    [0:ROB_DEPTH-1];
  reg [ADDR_SIZE-1:0]   rd    [0:ROB_DEPTH-1];
  reg [XLEN-1:0]        value [0:ROB_DEPTH-1];

  reg [TAG_W-1:0] head;
  reg [TAG_W-1:0] tail;   // NEW: next-free slot (internal tail)
  reg [CNT_W-1:0] count;

  integer i;

  assign rob_empty = (count == 0);
  assign rob_full  = (count == ROB_DEPTH);

  assign ra_ready = valid[ra_tag] & ready[ra_tag];
  assign ra_value = value[ra_tag];

  assign rb_ready = valid[rb_tag] & ready[rb_tag];
  assign rb_value = value[rb_tag];

  wire head_can_commit = !rob_empty && valid[head] && ready[head];

  wire                  alloc_we_eff = alloc_we | alloc_jlx;
  wire [ADDR_SIZE-1:0]  alloc_rd_eff = alloc_jlx ? 5'd31 : alloc_rd_arch;

  // helper: increment tag modulo ROB_DEPTH (TAG_W bits)
  function [TAG_W-1:0] inc_tag(input [TAG_W-1:0] t);
    inc_tag = t + {{(TAG_W-1){1'b0}},1'b1};
  endfunction

  always @(posedge clk) begin
    if (rst) begin
      head  <= {TAG_W{1'b0}};
      tail  <= {TAG_W{1'b0}};
      count <= {CNT_W{1'b0}};

      C_valid   <= 1'b0;
      C_we      <= 1'b0;
      C_rd_arch <= {ADDR_SIZE{1'b0}};
      C_value   <= {XLEN{1'b0}};
      C_tag     <= {TAG_W{1'b0}};

      for (i = 0; i < ROB_DEPTH; i = i + 1) begin
        valid[i] <= 1'b0;
        ready[i] <= 1'b0;
        we[i]    <= 1'b0;
        rd[i]    <= {ADDR_SIZE{1'b0}};
        value[i] <= {XLEN{1'b0}};
      end
    end else begin
      C_valid <= 1'b0;

      // ------------------------------------------------------------
      // 1) Apply WB first (older instructions may still be completing)
      // ------------------------------------------------------------
      if (wb_valid) begin
        if (valid[wb_tag]) begin
          value[wb_tag] <= wb_value;
          ready[wb_tag] <= 1'b1;
        end
      end

      // ------------------------------------------------------------
      // 2) Mispredict flush: drop all entries younger than flush_tag
      //    Keep: everything <= flush_tag in program order
      // ------------------------------------------------------------
      if (flush_valid) begin
        // Invalidate tags (flush_tag+1) .. (tail-1)
        // tail is next-free, so stop when idx == tail
        reg [TAG_W-1:0] idx;
        idx = inc_tag(flush_tag);

        while (idx != tail) begin
          valid[idx] <= 1'b0;
          ready[idx] <= 1'b0;
          we[idx]    <= 1'b0;
          rd[idx]    <= {ADDR_SIZE{1'b0}};
          value[idx] <= {XLEN{1'b0}};
          idx = inc_tag(idx);
        end

        // Move tail back to just-after the branch
        tail <= inc_tag(flush_tag);

        // Recompute count (small ROB_DEPTH => safe)
        // Keep head where it is (older instructions still commit)
        begin : recount_block
          integer j;
          integer tmp;
          tmp = 0;
          for (j = 0; j < ROB_DEPTH; j = j + 1) begin
            if (valid[j]) tmp = tmp + 1;
          end
          count <= tmp[CNT_W-1:0];
        end

        // Optional: you can also suppress commit on a flush cycle
        // (recommended to keep things simple)
      end
      else begin
        // ------------------------------------------------------------
        // 3) Normal allocate
        // ------------------------------------------------------------
        if (alloc_valid && !rob_full) begin
          valid[alloc_tag] <= 1'b1;
          ready[alloc_tag] <= (alloc_we_eff == 1'b0);
          we[alloc_tag]    <= alloc_we_eff;
          rd[alloc_tag]    <= alloc_rd_eff;

          // Track tail (expected to match alloc_tag sequencing)
          tail  <= inc_tag(alloc_tag);
          count <= count + {{(CNT_W-1){1'b0}},1'b1};
        end

        // ------------------------------------------------------------
        // 4) Normal commit (1 per cycle)
        // ------------------------------------------------------------
        if (head_can_commit) begin
          C_valid   <= 1'b1;
          C_we      <= we[head];
          C_rd_arch <= rd[head];
          C_value   <= value[head];
          C_tag     <= head;

          valid[head] <= 1'b0;
          ready[head] <= 1'b0;

          head  <= inc_tag(head);
          count <= count - {{(CNT_W-1){1'b0}},1'b1};
        end
      end
    end
  end

endmodule
