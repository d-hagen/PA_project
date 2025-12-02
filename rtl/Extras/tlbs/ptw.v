// Very simple Page Table Walker (PTW) for testing the ITLB
// - On Itlb_pa_request, it latches the VA and,
//   after a fixed latency, returns F_ptw_valid + F_ptw_pa.
// - Translation rule for testing:
//       F_ptw_pa = lower 20 bits of VA + 4
//   so logically: VA = PA - 4 (on low 20 bits)
//
// This is *not* a real page-table walker, just a test stub.

module ptw #(
    parameter VA_WIDTH     = 32,
    parameter PPN_WIDTH    = 20,
    parameter PTW_LATENCY  = 8   // cycles between request and response
)(
    input  wire                    clk,
    input  wire                    rst,

    // From ITLB
    input  wire                    Itlb_pa_request, // request for translation
    input  wire [VA_WIDTH-1:0]     Itlb_va,         // VA for which we need PA

    // To ITLB
    output reg                     F_ptw_valid,     // 1-cycle pulse when PA is ready
    output reg  [PPN_WIDTH-1:0]    F_ptw_pa         // translated "PPN"/PA-high
);

    // Internal state
    reg                    busy;         // PTW is processing a request
    reg [VA_WIDTH-1:0]     va_latched;   // VA latched at request time

    // Counter for fixed latency
    // Enough bits to count up to PTW_LATENCY
    localparam CNT_BITS = $clog2(PTW_LATENCY + 1);
    reg [CNT_BITS-1:0]     cnt;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            busy        <= 1'b0;
            va_latched  <= {VA_WIDTH{1'b0}};
            cnt         <= {CNT_BITS{1'b0}};
            F_ptw_valid <= 1'b0;
            F_ptw_pa    <= {PPN_WIDTH{1'b0}};
        end else begin
            // Default: no valid result this cycle
            F_ptw_valid <= 1'b0;

            if (!busy) begin
                // Idle: wait for a request from ITLB
                if (Itlb_pa_request) begin
                    busy       <= 1'b1;
                    va_latched <= Itlb_va;
                    cnt        <= PTW_LATENCY[CNT_BITS-1:0];  // start countdown
                end
            end else begin
                // Busy: count down until result is ready
                if (cnt != 0) begin
                    cnt <= cnt - 1'b1;
                end else begin
                    // Time to return a translation
                    busy        <= 1'b0;

                    // Compute "PA": lower 20 bits of VA + 4
                    // (test mapping: VA = PA - 4 on low 20 bits)
                    F_ptw_pa    <= va_latched[PPN_WIDTH-1:0] + 20'd4;

                    // Signal to ITLB that a translation is ready (for 1 cycle)
                    F_ptw_valid <= 1'b1;
                end
            end
        end
    end

endmodule
