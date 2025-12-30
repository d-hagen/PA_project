`timescale 1ns/1ps

module mem_stage_bundle_blackbox #(
    parameter XLEN      = 32,
    parameter VA_WIDTH  = 32,
    parameter PA_BITS   = 20,
    parameter LINE_BITS = 16,

    parameter PAGE_OFFSET_WIDTH = 12,
    parameter VPN_WIDTH         = VA_WIDTH - PAGE_OFFSET_WIDTH,
    parameter PPN_WIDTH         = PA_BITS - PAGE_OFFSET_WIDTH,
    parameter DTLB_ENTRIES      = 16,

    parameter SB_DEPTH          = 8
)(
    input  wire                 clk,
    input  wire                 rst,

    input  wire                 MEM_ld,
    input  wire                 MEM_str,
    input  wire                 MEM_byt,
    input  wire [VA_WIDTH-1:0]  MEM_alu_out,      // VA in (to DTLB)
    input  wire [XLEN-1:0]      MEM_b2,           // store value

    input  wire                 MEM_ptw_valid,
    input  wire [PPN_WIDTH-1:0] MEM_ptw_pa,

    output wire [31:0]          Dtlb_addr_out,
    output wire                 Dtlb_addr_valid,
    output wire                 Dtlb_stall,
    output wire                 Dtlb_pa_request,
    output wire [VPN_WIDTH-1:0] Dtlb_va,

    output wire                 Dc_mem_req,
    output wire [LINE_BITS-1:0] Dc_mem_addr,
    input  wire [127:0]         MEM_data_line,
    input  wire                 MEM_mem_valid,

    output wire                 Dc_wb_we,
    output wire [LINE_BITS-1:0] Dc_wb_addr,
    output wire [127:0]         Dc_wb_wline,

    input  wire                 Ptw_req,
    input  wire [19:0]          Ptw_addr,
    output wire [31:0]          Ptw_rdata,
    output wire                 Ptw_valid,

    output wire                 Dc_busy,

    output wire [XLEN-1:0]      MEM_data_mem,
    output wire                 dcache_stall,

    output wire                 SB_full,
    output wire                 SB_fwd_valid,
    output wire [31:0]          SB_fwd_data,
    output wire                 SB_fwd_block,

    output wire                 SB_fill_pending,
    output wire [LINE_BITS-1:0] SB_fill_line_req,

    output wire                 SB_need_fill,
    output wire [LINE_BITS-1:0] SB_fill_line,

    output wire                 DC_fill_valid,
    output wire [LINE_BITS-1:0] DC_fill_line,

    output wire                 SB_commit_valid,
    output wire [LINE_BITS-1:0] SB_commit_line,
    output wire [1:0]           SB_commit_word,
    output wire [31:0]          SB_commit_wdata,
    output wire [3:0]           SB_commit_wmask,
    output wire                 DC_commit_ready
);

    // ------------------------------------------------------------
    // DTLB
    // ------------------------------------------------------------
    dtlb #(
        .VA_WIDTH(VA_WIDTH),
        .PA_BITS(PA_BITS),
        .PAGE_OFFSET_WIDTH(PAGE_OFFSET_WIDTH),
        .VPN_WIDTH(VPN_WIDTH),
        .PPN_WIDTH(PPN_WIDTH),
        .NUM_ENTRIES(DTLB_ENTRIES)
    ) u_dtlb (
        .clk(clk),
        .rst(rst),

        .va_in(MEM_alu_out),
        .MEM_ld(MEM_ld),
        .MEM_str(MEM_str),

        .MEM_ptw_valid(MEM_ptw_valid),
        .MEM_ptw_pa(MEM_ptw_pa),

        .Dtlb_addr_out(Dtlb_addr_out),
        .Dtlb_addr_valid(Dtlb_addr_valid),
        .Dtlb_stall(Dtlb_stall),

        .Dtlb_pa_request(Dtlb_pa_request),
        .Dtlb_va(Dtlb_va)
    );

    // Physical address (PA) used by SB and D$
    wire [XLEN-1:0] MEM_pa = Dtlb_addr_out;

    // ------------------------------------------------------------
    // Local wires between cache and store buffer
    // ------------------------------------------------------------
    wire                 sb_need_fill_from_cache;
    wire [LINE_BITS-1:0] sb_fill_line_from_cache;

    assign SB_need_fill = sb_need_fill_from_cache;
    assign SB_fill_line = sb_fill_line_from_cache;

    // ------------------------------------------------------------
    // Store Buffer
    // ------------------------------------------------------------
    store_buffer #(
        .XLEN(XLEN),
        .LINE_BITS(LINE_BITS),
        .SB_DEPTH(SB_DEPTH)
    ) u_store_buffer (
        .clk(clk),
        .rst(rst),

        .MEM_str(MEM_str),
        .MEM_byt(MEM_byt),
        .MEM_alu_out(MEM_pa),
        .MEM_b2(MEM_b2),
        .Dtlb_addr_valid(Dtlb_addr_valid),

        .SB_need_fill(sb_need_fill_from_cache),
        .SB_fill_line_in(sb_fill_line_from_cache),

        .SB_fill_pending(SB_fill_pending),
        .SB_fill_line_req(SB_fill_line_req),

        .DC_fill_valid(DC_fill_valid),
        .DC_fill_line(DC_fill_line),

        .SB_commit_valid(SB_commit_valid),
        .SB_commit_line(SB_commit_line),
        .SB_commit_word(SB_commit_word),
        .SB_commit_wdata(SB_commit_wdata),
        .SB_commit_wmask(SB_commit_wmask),
        .DC_commit_ready(DC_commit_ready),

        .MEM_ld(MEM_ld),
        .MEM_ld_byt(MEM_byt),
        .MEM_ld_addr(MEM_pa),
        .MEM_ld_addr_valid(Dtlb_addr_valid),

        .SB_fwd_valid(SB_fwd_valid),
        .SB_fwd_data(SB_fwd_data),
        .SB_fwd_block(SB_fwd_block),

        .SB_full(SB_full)
    );

    // ------------------------------------------------------------
    // D-cache with SB integration
    // ------------------------------------------------------------
    wire [XLEN-1:0] MEM_data_mem_cache;
    wire            dcache_stall_cache;

    dcache_with_sb #(
        .XLEN(XLEN),
        .LINE_BITS(LINE_BITS)
    ) u_dcache (
        .clk(clk),
        .rst(rst),

        .MEM_ld(MEM_ld),
        .MEM_str(MEM_str),
        .MEM_byt(MEM_byt),
        .MEM_alu_out(MEM_pa),
        .MEM_b2(MEM_b2),
        .MEM_data_mem(MEM_data_mem_cache),
        .dcache_stall(dcache_stall_cache),

        .Dtlb_addr_valid(Dtlb_addr_valid),

        .Dc_mem_req(Dc_mem_req),
        .Dc_mem_addr(Dc_mem_addr),
        .MEM_data_line(MEM_data_line),
        .MEM_mem_valid(MEM_mem_valid),

        .Dc_wb_we(Dc_wb_we),
        .Dc_wb_addr(Dc_wb_addr),
        .Dc_wb_wline(Dc_wb_wline),

        .Ptw_req(Ptw_req),
        .Ptw_addr(Ptw_addr),
        .Ptw_rdata(Ptw_rdata),
        .Ptw_valid(Ptw_valid),

        .SB_need_fill(sb_need_fill_from_cache),
        .SB_fill_line(sb_fill_line_from_cache),

        .SB_fill_pending(SB_fill_pending),
        .SB_fill_line_req(SB_fill_line_req),

        .DC_fill_valid(DC_fill_valid),
        .DC_fill_line(DC_fill_line),

        .SB_commit_valid(SB_commit_valid),
        .SB_commit_line(SB_commit_line),
        .SB_commit_word(SB_commit_word),
        .SB_commit_wdata(SB_commit_wdata),
        .SB_commit_wmask(SB_commit_wmask),
        .DC_commit_ready(DC_commit_ready),

        .SB_full(SB_full),

        .Dc_busy(Dc_busy)
    );

    // ------------------------------------------------------------
    // Make D$ "use" SB for loads (forwarding mux)
    // ------------------------------------------------------------
    assign MEM_data_mem = (SB_fwd_valid)
                            ? {{(XLEN-32){1'b0}}, SB_fwd_data}
                            : MEM_data_mem_cache;

    // ------------------------------------------------------------
    // IMPORTANT:
    // pipeline must stall if:
    //  - cache stalls (load miss refill)
    //  - SB says block (partial overlap load, needs merge)
    // ------------------------------------------------------------
    assign dcache_stall = dcache_stall_cache | SB_fwd_block;

endmodule
