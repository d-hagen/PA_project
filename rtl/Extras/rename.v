`timescale 1ns/1ps

module rename #(
  parameter integer REG_NUM   = 32,
  parameter integer ADDR_SIZE = 5,
  parameter integer ROB_DEPTH = 16,
  parameter integer TAG_W     = $clog2(ROB_DEPTH)
)(
  input  wire                   clk,
  input  wire                   rst,

  // undo RAT updates from younger instructions.
  input  wire                   flush_valid,
  input  wire [TAG_W-1:0]       flush_tag,

  // Decode regs
  input  wire [ADDR_SIZE-1:0]   D_ra,
  input  wire [ADDR_SIZE-1:0]   D_rb,
  input  wire [ADDR_SIZE-1:0]   D_rd,
  input  wire                   D_we,
  input  wire                   D_jlx,

  // Instruction advances 
  input  wire                   D_fire,

  // Rename outputs 
  output wire                   ra_is_rob,
  output wire                   rb_is_rob,
  output wire [TAG_W-1:0]       ra_tag,
  output wire [TAG_W-1:0]       rb_tag,

  //tag for  instruction
  output wire [TAG_W-1:0]       dst_tag,
  output wire                   rob_alloc,
  output wire [TAG_W-1:0]       rob_alloc_tag,

  // Stall when ROB full
  input  wire                   rob_full_in,

  // ROB commit -> clear RAT mapping
  input  wire                   C_valid,
  input  wire                   C_we,
  input  wire [ADDR_SIZE-1:0]   C_rd_arch,
  input  wire [TAG_W-1:0]       C_tag
);

  // JLX -> r31 and  write
  wire [ADDR_SIZE-1:0] dest_arch = D_jlx ? 5'd31 : D_rd;
  wire                 dest_we   = D_we | D_jlx;

  // RAT
  reg                  rat_valid [0:REG_NUM-1];
  reg [TAG_W-1:0]       rat_tag   [0:REG_NUM-1];

  // Tail pointer 
  reg [TAG_W-1:0] tail_tag;

  // ------------------------------------------------------------------
  // RAT undo-log 
  // ------------------------------------------------------------------
  // Store:
  //   * destination renamed 
  //   * write enable (dest_we)
  //   * previous RAT mapping for dst
  //
  // flush: (tail_tag-1) ->(flush_tag+1) // walking backwards
  reg [ADDR_SIZE-1:0] undo_arch      [0:ROB_DEPTH-1];
  reg                 undo_we        [0:ROB_DEPTH-1];
  reg                 undo_prev_v    [0:ROB_DEPTH-1];
  reg [TAG_W-1:0]      undo_prev_tag [0:ROB_DEPTH-1];

  // helper: increment/decrement tag modulo ROB_DEPTH (TAG_W bits)
  function [TAG_W-1:0] inc_tag(input [TAG_W-1:0] t);
    inc_tag = t + {{(TAG_W-1){1'b0}},1'b1};
  endfunction

  function [TAG_W-1:0] dec_tag(input [TAG_W-1:0] t);
    dec_tag = t - {{(TAG_W-1){1'b0}},1'b1};
  endfunction

  integer i;

  // --------------------------
  // COMBINATIONAL LOOKUP
  // --------------------------
  assign ra_is_rob = rat_valid[D_ra];
  assign rb_is_rob = rat_valid[D_rb];

  assign ra_tag    = rat_tag[D_ra];
  assign rb_tag    = rat_tag[D_rb];

  //  next tag 
  assign dst_tag       = tail_tag;
  assign rob_alloc_tag = tail_tag;

  // only tag if fire 
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

      for (i = 0; i < ROB_DEPTH; i = i + 1) begin
        undo_arch[i]      <= {ADDR_SIZE{1'b0}};
        undo_we[i]        <= 1'b0;
        undo_prev_v[i]    <= 1'b0;
        undo_prev_tag[i]  <= {TAG_W{1'b0}};
      end
    end else begin
      // ------------------------------------------------------------
      // Flush recovery 
      // ------------------------------------------------------------
      if (flush_valid) begin
     
        reg [TAG_W-1:0] idx;
        idx = dec_tag(tail_tag);

        while (idx != flush_tag) begin
          if (undo_we[idx] && (undo_arch[idx] != {ADDR_SIZE{1'b0}})) begin
            rat_valid[undo_arch[idx]] <= undo_prev_v[idx];
            rat_tag[undo_arch[idx]]   <= undo_prev_tag[idx];
          end
          idx = dec_tag(idx);
        end

        tail_tag <= inc_tag(flush_tag);

        // commit after flush
        if (C_valid && C_we && (C_rd_arch != {ADDR_SIZE{1'b0}})) begin
          if (rat_valid[C_rd_arch] && (rat_tag[C_rd_arch] == C_tag)) begin
            rat_valid[C_rd_arch] <= 1'b0;
            rat_tag[C_rd_arch]   <= {TAG_W{1'b0}};
          end
        end
      end
      else begin
        // ------------------------------------------------------------
        //Normal commit, clear mapping  pointing to tag
        // ------------------------------------------------------------
        if (C_valid && C_we && (C_rd_arch != {ADDR_SIZE{1'b0}})) begin
          if (rat_valid[C_rd_arch] && (rat_tag[C_rd_arch] == C_tag)) begin
            rat_valid[C_rd_arch] <= 1'b0;
            rat_tag[C_rd_arch]   <= {TAG_W{1'b0}};
          end
        end

        // ------------------------------------------------------------
        // 3) Normal rename update on issue (log -> update -> advance)
        // ------------------------------------------------------------
        if (D_fire && !rob_full_in) begin
          // Log previous mapping for this tag (even if dest_we=0)
          undo_arch[tail_tag]      <= dest_arch;
          undo_we[tail_tag]        <= (dest_we && (dest_arch != {ADDR_SIZE{1'b0}}));
          undo_prev_v[tail_tag]    <= rat_valid[dest_arch];
          undo_prev_tag[tail_tag]  <= rat_tag[dest_arch];

          // Update RAT for dest
          if (dest_we && (dest_arch != {ADDR_SIZE{1'b0}})) begin
            rat_valid[dest_arch] <= 1'b1;
            rat_tag[dest_arch]   <= tail_tag;
          end

          tail_tag <= inc_tag(tail_tag);
        end
      end
    end
  end

endmodule
