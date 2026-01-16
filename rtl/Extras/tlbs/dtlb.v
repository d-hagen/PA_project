module dtlb #(
    parameter VA_WIDTH          = 32,
    parameter PA_BITS           = 20,
    parameter PAGE_OFFSET_WIDTH = 12,                         // 4 KiB pages
    parameter VPN_WIDTH         = VA_WIDTH - PAGE_OFFSET_WIDTH, // 20-bit VPN
    parameter PPN_WIDTH         = PA_BITS - PAGE_OFFSET_WIDTH,  // 8-bit PPN if PA_BITS=20
    parameter NUM_ENTRIES       = 16
)(
    input                       clk,
    input                       rst,

    input  [VA_WIDTH-1:0]       va_in,

    input                       MEM_ld,
    input                       MEM_str,

    input                       admin,

    // Page table walker interface
    input                       MEM_ptw_valid,   // PTW returning translation
    input  [PPN_WIDTH-1:0]      MEM_ptw_pa,      // translated PPN from PTW

    // Outputs
    output [31:0]               Dtlb_addr_out,      // [19:0] = PA, [31:20]=0
    output                      Dtlb_addr_valid,    // 1 when Dtlb_addr_out is a valid PA
    output                      Dtlb_stall,      // stall on miss during ld/str

    output                      Dtlb_pa_request, // request PTW on miss
    output [VPN_WIDTH-1:0]      Dtlb_va          // VPN sent to PTW
);

    // ----------------------------------------------------------------
    // Internal DTLB storage
    // ----------------------------------------------------------------
    reg [VPN_WIDTH-1:0]   vpn_buf [0:NUM_ENTRIES-1];
    reg [PPN_WIDTH-1:0]   ppn_buf [0:NUM_ENTRIES-1];
    reg [NUM_ENTRIES-1:0] valid;

    reg [3:0]             fifo_ptr;
    reg [VPN_WIDTH-1:0]   miss_vpn;

    integer i;

    wire do_mem_access = MEM_ld || MEM_str;

    // Extract VPN and page offset from VA
    wire [VPN_WIDTH-1:0]        va_vpn    = va_in[VA_WIDTH-1:PAGE_OFFSET_WIDTH];
    wire [PAGE_OFFSET_WIDTH-1:0] va_off   = va_in[PAGE_OFFSET_WIDTH-1:0];

    // ----------------------------------------------------------------
    // Combinational lookup
    // ----------------------------------------------------------------
    reg hit;
    reg [PPN_WIDTH-1:0] hit_ppn;

    always @(*) begin
        hit     = 1'b0;
        hit_ppn = {PPN_WIDTH{1'b0}};

        // Only lookup when this is a real memory op and PTW isn't returning
        if (do_mem_access && !MEM_ptw_valid) begin
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                if (!hit && valid[i] && (vpn_buf[i] == va_vpn)) begin
                    hit     = 1'b1;
                    hit_ppn = ppn_buf[i];
                end
            end
        end
    end

    // Build 20-bit PA = {PPN, offset}
    wire [PA_BITS-1:0] pa20 = {hit_ppn, va_off};

    // Output address:
    // - admin/bypass (no ld/str): passthrough va_in (32-bit)
    // - hit: zero-extend PA20 into 32-bit, with PA in low 20 bits
    // - miss: drive 0 (invalid anyway)
    assign Dtlb_addr_out =
        (!do_mem_access || admin) ? va_in :
        (hit)            ? {12'b0, pa20} :
                           32'b0;

    // Valid when:
    // - bypass/admin: always "valid" output (since we’re just passing through)
    // - memory op: valid only on hit
    assign Dtlb_addr_valid = (!do_mem_access || admin) ? 1'b1 : hit;

    // Stall only on real memory ops that miss
    assign Dtlb_stall = (do_mem_access) && (!hit) && !admin;

    // PTW request only when:
    //  - real memory op
    //  - miss
    //  - PTW not currently returning
    assign Dtlb_pa_request = (do_mem_access) && (!hit) && (!MEM_ptw_valid) && !admin;

    // Send VPN to PTW
    assign Dtlb_va = va_vpn;

    // ----------------------------------------------------------------
    // Sequential: miss VPN capture + refill on PTW return
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
            if (Dtlb_pa_request && !hit) begin
                miss_vpn <= va_vpn;
            end

            // refill when PTW returns
            if (MEM_ptw_valid) begin
                vpn_buf[fifo_ptr] <= miss_vpn;
                ppn_buf[fifo_ptr] <= MEM_ptw_pa;
                valid[fifo_ptr]   <= 1'b1;
                fifo_ptr          <= fifo_ptr + 1'b1;
            end
        end
    end

endmodule