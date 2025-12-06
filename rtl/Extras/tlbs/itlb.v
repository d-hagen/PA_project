module itlb #(
    parameter VA_WIDTH          = 32,
    parameter PC_BITS           = 20,
    parameter PAGE_OFFSET_WIDTH = 12,       // 4 KiB pages
    parameter VPN_WIDTH         = VA_WIDTH - PAGE_OFFSET_WIDTH, // 20-bit VPN
    parameter PPN_WIDTH         = PC_BITS - PAGE_OFFSET_WIDTH,       // size of PPN (your PA bits)
    parameter NUM_ENTRIES       = 16
)(
    input                       clk,
    input                       rst,

    input  [VA_WIDTH-1:0]       va_in,

    input                       F_admin,

    // Page table walker interface
    input                       F_ptw_valid,          // like F_mem_valid
    input  [PPN_WIDTH-1:0]      F_ptw_pa,             // translated PPN from PTW

    output [PC_BITS-1:0]        F_pc,                 // PPN (or PA-high) out
    output                      Itlb_stall,           // stall pipeline on miss

    output                       Itlb_pa_request,      // request to PTW (like Ic_mem_req)
    output [VPN_WIDTH-1:0]       Itlb_va               // VA sent to PTW (like Ic_mem_addr)
);

    // ----------------------------------------------------------------
    // Internal ITLB storage
    // ----------------------------------------------------------------

    reg [VPN_WIDTH-1:0]  vpn_buf   [0:NUM_ENTRIES-1];
    reg [PPN_WIDTH-1:0]  ppn_buf   [0:NUM_ENTRIES-1];
    reg [NUM_ENTRIES-1:0] valid;

    // simple FIFO replacement pointer (0..15)
    reg [3:0] fifo_ptr;

    // VPN for which the current PTW request is outstanding
    reg [VPN_WIDTH-1:0] miss_vpn;

    integer i;

    // Extract VPN from VA
    wire [VPN_WIDTH-1:0] va_vpn = va_in[VA_WIDTH-1:PAGE_OFFSET_WIDTH];


    // ----------------------------------------------------------------
    // Combinational lookup + PTW request logic
    // ----------------------------------------------------------------

    reg hit;
    reg [PPN_WIDTH-1:0] hit_ppn;

   always @(*) begin
        hit     = 1'b0;
        hit_ppn = {PPN_WIDTH{1'b0}};

        // Normal mode lookup (skip lookup while PTW is returning,
        // similar to icache skipping tag lookup when F_mem_valid is high)
        if (!F_admin && !F_ptw_valid) begin
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                if (!hit && valid[i] && (vpn_buf[i] == va_vpn)) begin
                    hit     = 1'b1;
                    hit_ppn = ppn_buf[i];
                end
            end
        end
    end

    // F_pc:
    // - admin mode: lower 20 bits of VA
    // - normal hit: PPN from TLB
    // - normal miss: value is irrelevant (stall is high), so drive 0
    assign F_pc =
        F_admin ? va_in[PPN_WIDTH-1:0] :     // admin mode bypass
        hit     ? {hit_ppn, va_in[PAGE_OFFSET_WIDTH-1:0]}  :     // normal hit
                  {PPN_WIDTH{1'b0}};         // normal miss (unused while stalled)

    // Stall whenever we are in normal mode and do not hit in the TLB
    assign Itlb_stall = (!F_admin) && (!hit);

    // Request to PTW only when:
    //  - in normal mode
    //  - we don't hit
    //  - PTW is not currently returning a result
    assign Itlb_pa_request = (!F_admin) && (!hit) && (!F_ptw_valid);

    // VA sent to PTW (analogous to Ic_mem_addr = pc_line; here we send full VA)
    assign Itlb_va = va_in[VA_WIDTH-1:PAGE_OFFSET_WIDTH]; // VA[31:12]

    // ----------------------------------------------------------------
    // Sequential logic: reset, record miss VPN, refill on PTW return
    // ----------------------------------------------------------------

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                vpn_buf[i] <= {VPN_WIDTH{1'b0}};
                ppn_buf[i] <= {PPN_WIDTH{1'b0}};
                valid[i]   <= 1'b0;
            end
            fifo_ptr <= 4'd0;
            miss_vpn <= {VPN_WIDTH{1'b0}};
        end else begin
            // latch VPN at time of miss request
            // (assumes va_in is held constant while Itlb_stall=1,
            // just like F_pc is held while F_stall=1 in the icache)
            if (Itlb_pa_request && !hit) begin
                miss_vpn <= va_vpn;
            end

            // refill one TLB entry when PTW returns a translation
            if (F_ptw_valid) begin
                // simple FIFO replacement policy
                vpn_buf[fifo_ptr] <= miss_vpn;
                ppn_buf[fifo_ptr] <= F_ptw_pa;
                valid[fifo_ptr]   <= 1'b1;

                fifo_ptr          <= fifo_ptr + 1'b1;
            end
        end
    end

endmodule
