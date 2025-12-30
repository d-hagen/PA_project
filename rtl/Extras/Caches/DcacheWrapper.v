// Stages/dcache_with_sb.v
`timescale 1ns/1ps

module dcache_with_sb #(
    parameter XLEN      = 32,
    parameter LINE_BITS = 16
)(
    input  wire                 clk,
    input  wire                 rst,

    // MEM stage interface
    input  wire                 MEM_ld,
    input  wire                 MEM_str,
    input  wire                 MEM_byt,
    input  wire [XLEN-1:0]      MEM_alu_out,      // PA when valid
    input  wire [XLEN-1:0]      MEM_b2,
    output reg  [XLEN-1:0]      MEM_data_mem,
    output reg                  dcache_stall,

    // From DTLB
    input  wire                 Dtlb_addr_valid,

    // Backing memory read interface (line read)
    output reg                  Dc_mem_req,
    output reg  [LINE_BITS-1:0] Dc_mem_addr,
    input  wire [127:0]         MEM_data_line,
    input  wire                 MEM_mem_valid,

    // Backing memory write-back interface (eviction)
    output reg                  Dc_wb_we,
    output reg  [LINE_BITS-1:0] Dc_wb_addr,
    output reg  [127:0]         Dc_wb_wline,

    // PTW (word read via line interface)
    input  wire                 Ptw_req,
    input  wire [19:0]          Ptw_addr,
    output reg  [31:0]          Ptw_rdata,
    output reg                  Ptw_valid,

    // ---------------- Store Buffer hooks ----------------
    // Cache -> SB on store miss (enqueue store)
    output reg                  SB_need_fill,
    output reg  [LINE_BITS-1:0] SB_fill_line,

    // SB -> cache line fill request
    input  wire                 SB_fill_pending,
    input  wire [LINE_BITS-1:0] SB_fill_line_req,

    // Cache -> SB: refill installed
    output reg                  DC_fill_valid,
    output reg  [LINE_BITS-1:0] DC_fill_line,

    // SB -> cache commit port (replay stores once line exists)
    input  wire                 SB_commit_valid,
    input  wire [LINE_BITS-1:0] SB_commit_line,
    input  wire [1:0]           SB_commit_word,
    input  wire [31:0]          SB_commit_wdata,
    input  wire [3:0]           SB_commit_wmask,
    output wire                 DC_commit_ready,

    // NEW: SB backpressure (stall store if SB is full on miss)
    input  wire                 SB_full,

    output wire                 Dc_busy
);

    // ------------------------------------------------------------
    // Tiny 4-line fully-associative cache
    // ------------------------------------------------------------
    reg                     valid [0:3];
    reg                     dirty [0:3];
    reg [LINE_BITS-1:0]     tag   [0:3];
    reg [31:0]              data  [0:3][0:3];
    reg [1:0]               fifo_ptr;

    integer i;

    // Address decode
    wire [LINE_BITS-1:0] addr_line = MEM_alu_out[19:4];
    wire [1:0]           addr_word = MEM_alu_out[3:2];
    wire [1:0]           addr_byte = MEM_alu_out[1:0];

    // PTW decode
    wire [LINE_BITS-1:0] ptw_line = Ptw_addr[19:4];
    wire [1:0]           ptw_word = Ptw_addr[3:2];

    // Commit ready whenever we are not in the middle of consuming a returning line
    assign DC_commit_ready = !MEM_mem_valid;

    // ------------------------------------------------------------
    // Lookup (combinational)
    // ------------------------------------------------------------
    reg hit;
    reg [1:0] hit_idx;

    always @(*) begin
        hit = 1'b0;
        hit_idx = 2'd0;
        if (Dtlb_addr_valid && (MEM_ld || MEM_str)) begin
            for (i = 0; i < 4; i = i + 1) begin
                if (valid[i] && (tag[i] == addr_line)) begin
                    hit     = 1'b1;
                    hit_idx = i[1:0];
                end
            end
        end
    end

    // ------------------------------------------------------------
    // Mask merge helper for SB commit
    // ------------------------------------------------------------
    function automatic [31:0] merge_masked(
        input [31:0] oldw,
        input [31:0] neww,
        input [3:0]  m
    );
        begin
            merge_masked = oldw;
            if (m[0]) merge_masked[7:0]   = neww[7:0];
            if (m[1]) merge_masked[15:8]  = neww[15:8];
            if (m[2]) merge_masked[23:16] = neww[23:16];
            if (m[3]) merge_masked[31:24] = neww[31:24];
        end
    endfunction

    // ------------------------------------------------------------
    // One-request-at-a-time memory port latch
    // ------------------------------------------------------------
    reg inflight;

    localparam REQ_NONE = 2'd0;
    localparam REQ_PTW  = 2'd1;
    localparam REQ_LD   = 2'd2;
    localparam REQ_SB   = 2'd3;

    reg [1:0]           req_kind;
    reg [LINE_BITS-1:0] req_line;
    reg [1:0]           req_word;

    // Busy indicator
    assign Dc_busy = inflight | dcache_stall;

    // ------------------------------------------------------------
    // Combinational outputs
    // ------------------------------------------------------------
    always @(*) begin
        // Defaults
        Dc_mem_req   = 1'b0;
        Dc_mem_addr  = {LINE_BITS{1'b0}};

        dcache_stall    = 1'b0;
        MEM_data_mem = 32'd0;

        // SB handshake defaults (pulsed in sequential)
        // SB_need_fill / DC_fill_valid are sequential pulses

        // LOAD hit => return data immediately (no stall)
        if (MEM_ld && Dtlb_addr_valid) begin
            if (hit && !inflight) begin
                reg [31:0] lw;
                lw = data[hit_idx][addr_word];
                if (MEM_byt) begin
                    case (addr_byte)
                        2'b00: MEM_data_mem = {24'b0, lw[7:0]};
                        2'b01: MEM_data_mem = {24'b0, lw[15:8]};
                        2'b10: MEM_data_mem = {24'b0, lw[23:16]};
                        2'b11: MEM_data_mem = {24'b0, lw[31:24]};
                    endcase
                end else begin
                    MEM_data_mem = lw;
                end
            end else begin
                // load miss: stall until refill returns
                dcache_stall = 1'b1;
            end
        end

        // STORE behavior with SB:
        // - store hit: update cache immediately (no stall)
        // - store miss: enqueue to SB (no stall), unless SB_full => stall
        if (MEM_str && Dtlb_addr_valid) begin
            if (!hit) begin
                if (SB_full) begin
                    // cannot accept this store yet
                    dcache_stall = 1'b1;
                end
            end
        end

        // Start a new memory transaction if none inflight and no line returning this cycle
        if (!inflight && !MEM_mem_valid) begin
            // Priority: PTW > load miss > SB fill
            if (Ptw_req) begin
                Dc_mem_req  = 1'b1;
                Dc_mem_addr = ptw_line;
            end else if (MEM_ld && Dtlb_addr_valid && !hit) begin
                Dc_mem_req  = 1'b1;
                Dc_mem_addr = addr_line;
            end else if (SB_fill_pending) begin
                Dc_mem_req  = 1'b1;
                Dc_mem_addr = SB_fill_line_req;
            end
        end
    end

    // ------------------------------------------------------------
    // Sequential behavior
    // ------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 4; i = i + 1) begin
                valid[i] <= 1'b0;
                dirty[i] <= 1'b0;
                tag[i]   <= {LINE_BITS{1'b0}};
            end
            fifo_ptr <= 2'd0;

            inflight <= 1'b0;
            req_kind <= REQ_NONE;
            req_line <= {LINE_BITS{1'b0}};
            req_word <= 2'd0;

            Dc_wb_we    <= 1'b0;
            Dc_wb_addr  <= {LINE_BITS{1'b0}};
            Dc_wb_wline <= 128'd0;

            Ptw_rdata <= 32'd0;
            Ptw_valid <= 1'b0;

            SB_need_fill <= 1'b0;
            SB_fill_line <= {LINE_BITS{1'b0}};

            DC_fill_valid <= 1'b0;
            DC_fill_line  <= {LINE_BITS{1'b0}};
        end else begin
            // one-cycle pulses low by default
            Dc_wb_we      <= 1'b0;
            Ptw_valid     <= 1'b0;
            SB_need_fill  <= 1'b0;
            DC_fill_valid <= 1'b0;

            // --------------------------------------------------------
            // Accept a new memory request (latch it) when we pulse Dc_mem_req
            // --------------------------------------------------------
            if (!inflight && Dc_mem_req) begin
                inflight <= 1'b1;
                req_line <= Dc_mem_addr;

                if (Ptw_req) begin
                    req_kind <= REQ_PTW;
                    req_word <= ptw_word;
                end else if (MEM_ld && Dtlb_addr_valid && !hit) begin
                    req_kind <= REQ_LD;
                    req_word <= 2'd0;
                end else begin
                    req_kind <= REQ_SB;
                    req_word <= 2'd0;
                end
            end

            // --------------------------------------------------------
            // Store hit: write into cache immediately
            // --------------------------------------------------------
            if (MEM_str && Dtlb_addr_valid && hit && !inflight) begin
                if (MEM_byt) begin
                    reg [31:0] w;
                    w = data[hit_idx][addr_word];
                    case (addr_byte)
                        2'b00: w[7:0]   = MEM_b2[7:0];
                        2'b01: w[15:8]  = MEM_b2[7:0];
                        2'b10: w[23:16] = MEM_b2[7:0];
                        2'b11: w[31:24] = MEM_b2[7:0];
                    endcase
                    data[hit_idx][addr_word] <= w;
                end else begin
                    data[hit_idx][addr_word] <= MEM_b2;
                end
                dirty[hit_idx] <= 1'b1;
            end

            // --------------------------------------------------------
            // Store miss: enqueue into SB (pulse), unless SB_full
            // --------------------------------------------------------
            if (MEM_str && Dtlb_addr_valid && !hit && !inflight) begin
                if (!SB_full) begin
                    SB_need_fill <= 1'b1;
                    SB_fill_line <= addr_line;
                end
            end

            // --------------------------------------------------------
            // SB commit: masked merge into cache if that line is present
            // --------------------------------------------------------
            if (SB_commit_valid && DC_commit_ready) begin
                for (i = 0; i < 4; i = i + 1) begin
                    if (valid[i] && (tag[i] == SB_commit_line)) begin
                        data[i][SB_commit_word] <= merge_masked(data[i][SB_commit_word],
                                                               SB_commit_wdata,
                                                               SB_commit_wmask);
                        dirty[i] <= 1'b1;
                    end
                end
            end

            // --------------------------------------------------------
            // Memory response handling
            // --------------------------------------------------------
            if (MEM_mem_valid && inflight) begin
                inflight <= 1'b0;

                if (req_kind == REQ_PTW) begin
                    case (req_word)
                        2'b00: Ptw_rdata <= MEM_data_line[31:0];
                        2'b01: Ptw_rdata <= MEM_data_line[63:32];
                        2'b10: Ptw_rdata <= MEM_data_line[95:64];
                        2'b11: Ptw_rdata <= MEM_data_line[127:96];
                    endcase
                    Ptw_valid <= 1'b1;
                end else begin
                    // refill install (for load miss or SB fill)
                    if (valid[fifo_ptr] && dirty[fifo_ptr]) begin
                        Dc_wb_we            <= 1'b1;
                        Dc_wb_addr          <= tag[fifo_ptr];
                        Dc_wb_wline[31:0]   <= data[fifo_ptr][0];
                        Dc_wb_wline[63:32]  <= data[fifo_ptr][1];
                        Dc_wb_wline[95:64]  <= data[fifo_ptr][2];
                        Dc_wb_wline[127:96] <= data[fifo_ptr][3];
                    end

                    valid[fifo_ptr] <= 1'b1;
                    dirty[fifo_ptr] <= 1'b0;
                    tag[fifo_ptr]   <= req_line;

                    data[fifo_ptr][0] <= MEM_data_line[31:0];
                    data[fifo_ptr][1] <= MEM_data_line[63:32];
                    data[fifo_ptr][2] <= MEM_data_line[95:64];
                    data[fifo_ptr][3] <= MEM_data_line[127:96];

                    // notify SB that this line is now in cache
                    DC_fill_valid <= 1'b1;
                    DC_fill_line  <= req_line;

                    fifo_ptr <= fifo_ptr + 1'b1;
                end

                req_kind <= REQ_NONE;
            end
        end
    end

endmodule
