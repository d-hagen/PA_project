`timescale 1ns/1ps

module rob #(
  parameter integer XLEN      = 32,
  parameter integer ADDR_SIZE = 5,
  parameter integer ROB_DEPTH = 16,
  parameter integer TAG_W     = $clog2(ROB_DEPTH)
)(
  input  wire                   clk,
  input  wire                   rst,

  input  wire                   alloc_valid,
  input  wire [TAG_W-1:0]       alloc_tag,
  input  wire                   alloc_we,
  input  wire [ADDR_SIZE-1:0]   alloc_rd_arch,
  input  wire                   alloc_jlx,

  input  wire                   wb_valid,
  input  wire [TAG_W-1:0]       wb_tag,
  input  wire [XLEN-1:0]        wb_value,

  input  wire                   flush_valid,
  input  wire [TAG_W-1:0]       flush_tag,

  input  wire [TAG_W-1:0]       ra_tag,
  output wire                   ra_ready,
  output wire [XLEN-1:0]        ra_value,

  input  wire [TAG_W-1:0]       rb_tag,
  output wire                   rb_ready,
  output wire [XLEN-1:0]        rb_value,

  output reg                    C_valid,
  output reg                    C_we,
  output reg  [ADDR_SIZE-1:0]   C_rd_arch,
  output reg  [XLEN-1:0]        C_value,
  output reg  [TAG_W-1:0]       C_tag,

  output wire                   rob_full,
  output wire                   rob_empty,
  output wire                   recovering
);

  localparam integer CNT_W = $clog2(ROB_DEPTH+1);

  reg                   valid [0:ROB_DEPTH-1];
  reg                   ready [0:ROB_DEPTH-1];
  reg                   we    [0:ROB_DEPTH-1];
  reg [ADDR_SIZE-1:0]   rd    [0:ROB_DEPTH-1];
  reg [XLEN-1:0]        value [0:ROB_DEPTH-1];

  reg [TAG_W-1:0] head;
  reg [TAG_W-1:0] tail;
  reg [CNT_W-1:0] count;

  integer i;

  // --------------------------
  // Helpers
  // --------------------------
  function [TAG_W-1:0] inc_tag(input [TAG_W-1:0] t);
    inc_tag = t + {{(TAG_W-1){1'b0}},1'b1};
  endfunction

  // --------------------------
  // Status
  // --------------------------
  assign rob_empty = (count == 0);
  assign rob_full  = (count == ROB_DEPTH);

  assign ra_ready = valid[ra_tag] & ready[ra_tag];
  assign ra_value = value[ra_tag];

  assign rb_ready = valid[rb_tag] & ready[rb_tag];
  assign rb_value = value[rb_tag];

  wire head_can_commit = (!rob_empty) && valid[head] && ready[head];

  wire                 alloc_we_eff = alloc_we | alloc_jlx;
  wire [ADDR_SIZE-1:0] alloc_rd_eff = alloc_jlx ? 5'd31 : alloc_rd_arch;

  // commit/alloc enables (note: alloc also blocked when full)
  wire do_alloc  = alloc_valid && !rob_full && !flush_valid;
  wire do_commit = head_can_commit && !flush_valid;

  // 1-cycle pulse during flush
  reg recovering_r;
  assign recovering = recovering_r;

  // --------------------------
  // Sequential
  // --------------------------
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

      recovering_r <= 1'b0;

      for (i = 0; i < ROB_DEPTH; i = i + 1) begin
        valid[i] <= 1'b0;
        ready[i] <= 1'b0;
        we[i]    <= 1'b0;
        rd[i]    <= {ADDR_SIZE{1'b0}};
        value[i] <= {XLEN{1'b0}};
      end
    end else begin
      // defaults
      C_valid      <= 1'b0;
      recovering_r <= 1'b0;

      // --------------------------
      // WB (mark ready)
      // --------------------------
      if (wb_valid && valid[wb_tag]) begin
        value[wb_tag] <= wb_value;
        ready[wb_tag] <= 1'b1;
      end

      // --------------------------
      // Flush (invalidate younger than flush_tag)
      // --------------------------
      if (flush_valid) begin
        recovering_r <= 1'b1;

        // invalidate (flush_tag+1) .. (tail-1)
        begin : FLUSH_BLOCK
          reg [TAG_W-1:0] idx;
          reg [CNT_W-1:0] new_count;

          // invalidate younger
          idx = inc_tag(flush_tag);
          while (idx != tail) begin
            valid[idx] <= 1'b0;
            ready[idx] <= 1'b0;
            we[idx]    <= 1'b0;
            rd[idx]    <= {ADDR_SIZE{1'b0}};
            value[idx] <= {XLEN{1'b0}};
            idx = inc_tag(idx);
          end

          // move tail to just after branch
          tail <= inc_tag(flush_tag);

          // IMPORTANT:
          // Do NOT recount using stale valid[] in the same cycle.
          // Minimal safe approach: recompute count from current count by
          // clearing everything younger. We can't know how many were younger
          // without scanning, so simplest safe solution is:
          // - set count to 0 and rebuild as program runs (functional but pessimistic)
          //
          // Better: scan with a temporary shadow "new_count" using *blocking*
          // reads of current valid[] AND excluding the invalidated range.
          // We'll do that here.
          new_count = {CNT_W{1'b0}};
          for (i = 0; i < ROB_DEPTH; i = i + 1) begin
            // Keep entries that are NOT in the younger range.
            // Younger range is (flush_tag+1 .. tail-1) in circular sense.
            // We test membership by walking from inc(flush_tag) to tail.
            // Since Verilog can't easily do that membership test cheaply,
            // we just conservatively recount ONLY entries that are currently valid
            // AND are not going to be invalidated by our loop above.
            // To avoid stale/nonblocking issues, we simply treat any index in that
            // range as invalid.
            reg in_flush_range;
            reg [TAG_W-1:0] t;
            in_flush_range = 1'b0;
            t = inc_tag(flush_tag);
            while (t != tail) begin
              if (t == i[TAG_W-1:0]) in_flush_range = 1'b1;
              t = inc_tag(t);
            end
            if (valid[i] && !in_flush_range) new_count = new_count + {{(CNT_W-1){1'b0}},1'b1};
          end
          count <= new_count;
        end
      end
      else begin
        // --------------------------
        // Allocate (new entry)
        // --------------------------
        if (do_alloc) begin
          valid[alloc_tag] <= 1'b1;
          ready[alloc_tag] <= (alloc_we_eff == 1'b0); // no-write ops are ready immediately
          we[alloc_tag]    <= alloc_we_eff;
          rd[alloc_tag]    <= alloc_rd_eff;

          tail <= inc_tag(alloc_tag);
        end

        // --------------------------
        // Commit (head)
        // --------------------------
        if (do_commit) begin
          C_valid   <= 1'b1;
          C_we      <= we[head];
          C_rd_arch <= rd[head];
          C_value   <= value[head];
          C_tag     <= head;

          valid[head] <= 1'b0;
          ready[head] <= 1'b0;

          head <= inc_tag(head);
        end

        // --------------------------
        // Count update (single place!)
        // --------------------------
        case ({do_alloc, do_commit})
          2'b10: count <= count + {{(CNT_W-1){1'b0}},1'b1};
          2'b01: count <= count - {{(CNT_W-1){1'b0}},1'b1};
          default: count <= count;
        endcase
      end
    end
  end

endmodule
