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
  input  wire                   alloc_iret,

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

  // --------------------------
  // EXC: mark + commit outputs
  // --------------------------
  input  wire                   exc_set_valid,
  input  wire [TAG_W-1:0]       exc_set_tag,
  input  wire [XLEN-1:0]        exc_set_pc,

  output reg                    EXC_we,
  output reg  [XLEN-1:0]        EXC_pc,
  output reg  [3:0]             EXC_type,
  output reg  [TAG_W-1:0]       EXC_tag,

  // --------------------------
  // iret commit pulse
  // --------------------------
  output reg                    IRET_we,
  output reg  [TAG_W-1:0]       IRET_tag,

  // stall while exception pending
  output wire                   rob_stall,

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

  // EXC: per-entry exception state (PC is stored in value[] when exc_flag=1)
  reg                   exc_flag [0:ROB_DEPTH-1];

  // per-entry iret marker
  reg                   iret_flag [0:ROB_DEPTH-1];

  // sticky "exception pending" state -> stall
  reg                   exc_pending;
  reg [TAG_W-1:0]       exc_pending_tag;
  assign rob_stall = exc_pending;

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

  // Block forwarding from exception entries:
  // if exc_flag[tag]==1, this tag must not be considered a ready producer
  assign ra_ready = valid[ra_tag] & ready[ra_tag] & !exc_flag[ra_tag];
  assign ra_value = value[ra_tag];

  assign rb_ready = valid[rb_tag] & ready[rb_tag] & !exc_flag[rb_tag];
  assign rb_value = value[rb_tag];

  wire head_can_commit = (!rob_empty) && valid[head] && ready[head];

  wire                 alloc_we_eff = alloc_we | alloc_jlx;
  wire [ADDR_SIZE-1:0] alloc_rd_eff  = alloc_jlx ? 5'd31 : alloc_rd_arch;

  // block alloc while exception pending -> no new inst into ROB when exception in pipe
  wire do_alloc  = alloc_valid && !rob_full && !flush_valid && !rob_stall;

  // Commit when head ready and not flushing
  wire do_commit = head_can_commit && !flush_valid;

  // 1-cycle pulse flush indicator
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

      // EXC: defaults
      EXC_we   <= 1'b0;
      EXC_pc   <= {XLEN{1'b0}};
      EXC_type <= 4'd0;
      EXC_tag  <= {TAG_W{1'b0}};

      // IRET: defaults
      IRET_we  <= 1'b0;
      IRET_tag <= {TAG_W{1'b0}};

      // stall state reset
      exc_pending     <= 1'b0;
      exc_pending_tag <= {TAG_W{1'b0}};

      recovering_r <= 1'b0;

      for (i = 0; i < ROB_DEPTH; i = i + 1) begin
        valid[i]     <= 1'b0;
        ready[i]     <= 1'b0;
        we[i]        <= 1'b0;
        rd[i]        <= {ADDR_SIZE{1'b0}};
        value[i]     <= {XLEN{1'b0}};
        exc_flag[i]  <= 1'b0;
        iret_flag[i] <= 1'b0;
      end

    end else begin
      // defaults
      C_valid      <= 1'b0;
      recovering_r <= 1'b0;

      // EXC: pulse outputs default low
      EXC_we   <= 1'b0;
      EXC_pc   <= {XLEN{1'b0}};
      EXC_type <= 4'd0;
      EXC_tag  <= {TAG_W{1'b0}};

      // IRET: pulse outputs default low
      IRET_we  <= 1'b0;
      IRET_tag <= {TAG_W{1'b0}};

      // --------------------------
      // WB (mark ready)
      // --------------------------
      // entry already marked as exception, value[] holds exc PC.
      if (wb_valid && valid[wb_tag] && !exc_flag[wb_tag]) begin
        value[wb_tag] <= wb_value;
        ready[wb_tag] <= 1'b1;
      end

      // --------------------------
      // EXC: mark exception on the entry + raise stall sticky
      // Store exception PC in value[] and force ready=1 so it can commit.
      // --------------------------
      if (exc_set_valid && valid[exc_set_tag]) begin
        exc_flag[exc_set_tag] <= 1'b1;
        value[exc_set_tag]    <= exc_set_pc; // reuse value as exc_pc
        ready[exc_set_tag]    <= 1'b1;       // ensure it can reach commit

        if (!exc_pending) begin
          exc_pending     <= 1'b1;
          exc_pending_tag <= exc_set_tag;
        end
      end

      // --------------------------
      // Flush
      // --------------------------
      if (flush_valid) begin
        recovering_r <= 1'b1;

        begin : FLUSH_BLOCK
          reg [TAG_W-1:0] idx;
          reg [CNT_W-1:0] new_count;

          idx = inc_tag(flush_tag);
          while (idx != tail) begin
            valid[idx]     <= 1'b0;
            ready[idx]     <= 1'b0;
            we[idx]        <= 1'b0;
            rd[idx]        <= {ADDR_SIZE{1'b0}};
            value[idx]     <= {XLEN{1'b0}};
            exc_flag[idx]  <= 1'b0;
            iret_flag[idx] <= 1'b0;

            // flushed exception -> clear stall
            if (exc_pending && (idx == exc_pending_tag))
              exc_pending <= 1'b0;

            idx = inc_tag(idx);
          end

          tail <= inc_tag(flush_tag);

          new_count = {CNT_W{1'b0}};
          for (i = 0; i < ROB_DEPTH; i = i + 1) begin
            reg in_flush_range;
            reg [TAG_W-1:0] t;
            in_flush_range = 1'b0;
            t = inc_tag(flush_tag);
            while (t != tail) begin
              if (t == i[TAG_W-1:0]) in_flush_range = 1'b1;
              t = inc_tag(t);
            end
            if (valid[i] && !in_flush_range)
              new_count = new_count + {{(CNT_W-1){1'b0}},1'b1};
          end
          count <= new_count;
        end

      end else begin
        // --------------------------
        // NEW entry
        // --------------------------
        if (do_alloc) begin
          valid[alloc_tag] <= 1'b1;
          // no-write ops -> ready immediately
          ready[alloc_tag] <= ((alloc_we_eff == 1'b0) || alloc_iret);
          we[alloc_tag]    <= alloc_we_eff;
          rd[alloc_tag]    <= alloc_rd_eff;

          // clear exception state
          exc_flag[alloc_tag] <= 1'b0;

          // tag iret
          iret_flag[alloc_tag] <= alloc_iret;

          tail <= inc_tag(alloc_tag);
        end

        // --------------------------
        // Commit
        // Priority: EXC > IRET > normal
        // --------------------------
        if (do_commit) begin
          if (exc_flag[head]) begin
            // exception commit
            EXC_we   <= 1'b1;
            EXC_pc   <= value[head]; // exception PC stored in value[]
            EXC_type <= 4'd0;
            EXC_tag  <= head;

            // head exception -> clear stall
            if (exc_pending && (exc_pending_tag == head))
              exc_pending <= 1'b0;

            C_valid <= 1'b0;

          end else if (iret_flag[head]) begin
            // iret commit pulse
            IRET_we  <= 1'b1;
            IRET_tag <= head;

            C_valid <= 1'b0;

          end else begin
            // normal commit
            C_valid   <= 1'b1;
            C_we      <= we[head];
            C_rd_arch <= rd[head];
            C_value   <= value[head];
            C_tag     <= head;
          end

          // retire entry
          valid[head]     <= 1'b0;
          ready[head]     <= 1'b0;
          exc_flag[head]  <= 1'b0;
          iret_flag[head] <= 1'b0;

          head <= inc_tag(head);
        end

        // --------------------------
        // Count update
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
