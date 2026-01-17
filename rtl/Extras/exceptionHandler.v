`timescale 1ns/1ps

module exc_handler #(
  parameter integer XLEN  = 32,
  parameter integer TAG_W = 5
)(
  // -------------------------
  // Exceptions per stage (NO F/D ANYMORE)
  // -------------------------
  input  wire                 EX_exc,
  input  wire [TAG_W-1:0]     EX_tag,
  input  wire [XLEN-1:0]      EX_pc,

  input  wire                 MEM_exc,
  input  wire [TAG_W-1:0]     MEM_tag,
  input  wire [XLEN-1:0]      MEM_pc,

  input  wire                 WB_exc,
  input  wire [TAG_W-1:0]     WB_tag,
  input  wire [XLEN-1:0]      WB_pc,

  // -------------------------
  // Branch mispredict flush (EX stage)
  // -------------------------
  input  wire                 EX_taken,   // flush request
  input  wire [TAG_W-1:0]     EX_br_tag,  //  EX_tag

  // -------------------------
  // To ROB: mark exception entry (ONLY if exception "wins")
  // -------------------------
  output reg                  exc_set_valid,
  output reg  [TAG_W-1:0]     exc_set_tag,
  output reg  [XLEN-1:0]      exc_set_pc,

  // -------------------------
  // Unified flush out to ROB + rest of core
  // -------------------------
  output reg                  flush_valid,
  output reg  [TAG_W-1:0]     flush_tag,

  // per-stage kill/flush (immediate)
  output reg                  F_flush,
  output reg                  D_flush,
  output reg                  EX_flush,
  output reg                  MEM_flush,
  output reg                  WB_flush
);

  // "event source" encoding
  localparam [2:0] SRC_NONE  = 3'd0,
                   SRC_EX    = 3'd3,
                   SRC_MEM   = 3'd4,
                   SRC_WB    = 3'd5,
                   SRC_BR_EX = 3'd6;

  // pick oldest exception 
  reg              exc_any;
  reg [2:0]        exc_src;
  reg [TAG_W-1:0]  exc_pick_tag;
  reg [XLEN-1:0]   exc_pick_pc;

  always @* begin
    exc_any      = 1'b0;
    exc_src      = SRC_NONE;
    exc_pick_tag = {TAG_W{1'b0}};
    exc_pick_pc  = {XLEN{1'b0}};

    if (WB_exc) begin
      exc_any      = 1'b1;
      exc_src      = SRC_WB;
      exc_pick_tag = WB_tag;
      exc_pick_pc  = WB_pc;
    end else if (MEM_exc) begin
      exc_any      = 1'b1;
      exc_src      = SRC_MEM;
      exc_pick_tag = MEM_tag;
      exc_pick_pc  = MEM_pc;
    end else if (EX_exc) begin
      exc_any      = 1'b1;
      exc_src      = SRC_EX;
      exc_pick_tag = EX_tag;
      exc_pick_pc  = EX_pc;
    end
  end

  // Exception or Branch Flush:
  // - WB/MEM exceptions are older than EX_taken -> exception wins
  // - EX exception  >  EX_taken | branch instruction faulty 
  reg [2:0] chosen_src;

  always @* begin
    chosen_src = SRC_NONE;

    if (exc_any) begin
      if (exc_src == SRC_WB || exc_src == SRC_MEM) begin
        chosen_src = exc_src;
      end else begin
        // exc_src == SRC_EX
        chosen_src = SRC_EX; 
      end
    end else begin
      chosen_src = (EX_taken) ? SRC_BR_EX : SRC_NONE;
    end

    // -------------------------
    // Defaults
    // -------------------------
    flush_valid   = 1'b0;
    flush_tag     = {TAG_W{1'b0}};

    exc_set_valid = 1'b0;
    exc_set_tag   = {TAG_W{1'b0}};
    exc_set_pc    = {XLEN{1'b0}};

    F_flush   = 1'b0;
    D_flush   = 1'b0;
    EX_flush  = 1'b0;
    MEM_flush = 1'b0;
    WB_flush  = 1'b0;

    // -------------------------
    // Drive outputs
    // -------------------------
    case (chosen_src)
      SRC_WB: begin
        // exception at WB: flush younger MEM/EX/D/F
        flush_valid   = 1'b1;
        flush_tag     = exc_pick_tag;

        exc_set_valid = 1'b1;
        exc_set_tag   = exc_pick_tag;
        exc_set_pc    = exc_pick_pc;

        MEM_flush = 1'b1;
        EX_flush  = 1'b1;
        D_flush   = 1'b1;
        F_flush   = 1'b1;
      end

      SRC_MEM: begin
        // exception at MEM: flush younger EX/D/F
        flush_valid   = 1'b1;
        flush_tag     = exc_pick_tag;

        exc_set_valid = 1'b1;
        exc_set_tag   = exc_pick_tag;
        exc_set_pc    = exc_pick_pc;

        EX_flush = 1'b1;
        D_flush  = 1'b1;
        F_flush  = 1'b1;
      end

      SRC_EX: begin
        // exception at EX: flush younger D/F
        flush_valid   = 1'b1;
        flush_tag     = exc_pick_tag;

        exc_set_valid = 1'b1;
        exc_set_tag   = exc_pick_tag;
        exc_set_pc    = exc_pick_pc;

        D_flush = 1'b1;
        F_flush = 1'b1;
      end

      SRC_BR_EX: begin
        // branch mispredict flush at EX: flush younger D/F
        flush_valid = 1'b1;
        flush_tag   = EX_br_tag;

        // branch wins -> do NOT mark exception
        D_flush = 1'b1;
        F_flush = 1'b1;
      end

      default: begin
        // no event
      end
    endcase
  end

endmodule
