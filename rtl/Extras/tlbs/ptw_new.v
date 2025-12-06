module ptw_2level #(
    parameter VA_WIDTH          = 32,
    parameter PC_BITS           = 20,
    parameter PAGE_OFFSET_WIDTH = 12,                         // 4 KiB
    parameter VPN_WIDTH         = VA_WIDTH - PAGE_OFFSET_WIDTH, // 20
    parameter PPN_WIDTH         = PC_BITS - PAGE_OFFSET_WIDTH   // 8
)(
    input                       clk,
    input                       rst,

    // ---------- From ITLB ----------
    input                       Itlb_pa_request,              // TLB miss request
    input  [VPN_WIDTH-1:0]      Itlb_va,                      // VPN = VA[31:12] (see note below)

    // ---------- Back to ITLB ----------
    output reg                  F_ptw_valid,                  // 1-cycle pulse
    output reg [PPN_WIDTH-1:0]  F_ptw_pa,                     // translated PPN

    // ---------- Word-level memory interface ----------
    output reg                  Ptw_mem_req,                  // PTW wants a PTE
    output reg  [PC_BITS-1:0]   Ptw_mem_addr,                 // physical byte addr
    input       [31:0]          Ptw_mem_rdata,                // PTE data
    input                       Ptw_mem_valid,                // PTE data valid

    // ---------- Busy from dcache ----------
    input                       MEM_stall                       // 1 = cache using memory
);

    // ============================================================
    // Hard-coded root page table PPN
    // L1 table will live at physical address: {ROOT_PPN, 12'b0}
    // TODO: later replace this with a CSR input (satp.PPN-style)
    // ============================================================
    localparam [PPN_WIDTH-1:0] ROOT_PPN = 8'h09;  // L1 at phys 0x01000

    // ============================================================
    // Split VPN into L1 and L2 indices
    // ============================================================
    reg  [VPN_WIDTH-1:0] vpn_q;
    wire [9:0] vpn1 = vpn_q[VPN_WIDTH-1 -: 10];  // upper 10 bits [19:10]
    wire [9:0] vpn0 = vpn_q[9:0];                // lower 10 bits [9:0]

    // Latched PPNs
    reg [PPN_WIDTH-1:0] l1_ppn_q;
    reg [PPN_WIDTH-1:0] l2_ppn_q;

    // Extract PPN from 32-bit PTE: bits [PPN_WIDTH+PAGE_OFFSET_WIDTH-1 : PAGE_OFFSET_WIDTH]
    // For PC_BITS=20, PAGE_OFFSET_WIDTH=12 => bits [19:12]
    wire [PPN_WIDTH-1:0] pte_ppn =
        Ptw_mem_rdata[PPN_WIDTH + PAGE_OFFSET_WIDTH - 1 : PAGE_OFFSET_WIDTH];

    // ============================================================
    // FSM encoding
    // ============================================================
    localparam S_IDLE    = 3'd0;
    localparam S_L1_REQ  = 3'd1;
    localparam S_L1_WAIT = 3'd2;
    localparam S_L2_REQ  = 3'd3;
    localparam S_L2_WAIT = 3'd4;
    localparam S_RESP    = 3'd5;

    reg [2:0] state, next_state;

    // ============================================================
    // Sequential logic
    // ============================================================
    always @(posedge clk) begin
        if (rst) begin
            state        <= S_IDLE;
            vpn_q        <= {VPN_WIDTH{1'b0}};
            l1_ppn_q     <= {PPN_WIDTH{1'b0}};
            l2_ppn_q     <= {PPN_WIDTH{1'b0}};
            F_ptw_valid  <= 1'b0;
            F_ptw_pa     <= {PPN_WIDTH{1'b0}};
            Ptw_mem_req  <= 1'b0;
            Ptw_mem_addr <= {PC_BITS{1'b0}};
        end else begin
            state <= next_state;

            case (state)
                // ---------------- IDLE ----------------
                S_IDLE: begin
                    F_ptw_valid <= 1'b0;
                    Ptw_mem_req <= 1'b0;

                    if (Itlb_pa_request) begin
                        vpn_q <= Itlb_va;      // latch VPN of the miss
                    end
                end

                // ---------------- L1_REQ ----------------
                S_L1_REQ: begin
                    F_ptw_valid <= 1'b0;

                    // Only issue memory req when cache isn't using the port
                    if (!MEM_stall) begin
                        Ptw_mem_req  <= 1'b1;
                        // L1 PTE addr = {ROOT_PPN, vpn1, 2'b00}
                        Ptw_mem_addr <= {ROOT_PPN, vpn1, 2'b00};
                    end else begin
                        Ptw_mem_req  <= 1'b0;   // wait
                    end
                end

                // ---------------- L1_WAIT ----------------
                S_L1_WAIT: begin
                    Ptw_mem_req <= 1'b0;
                    F_ptw_valid <= 1'b0;

                    if (Ptw_mem_valid) begin
                        // Capture L1 PPN (base of L2-table page)
                        l1_ppn_q <= pte_ppn;
                    end
                end

                // ---------------- L2_REQ ----------------
                S_L2_REQ: begin
                    F_ptw_valid <= 1'b0;

                    if (!MEM_stall) begin
                        Ptw_mem_req  <= 1'b1;
                        // L2 PTE addr = {l1_ppn_q, vpn0, 2'b00}
                        Ptw_mem_addr <= {l1_ppn_q, vpn0, 2'b00};
                    end else begin
                        Ptw_mem_req  <= 1'b0;
                    end
                end

                // ---------------- L2_WAIT ----------------
                S_L2_WAIT: begin
                    Ptw_mem_req <= 1'b0;

                    if (Ptw_mem_valid) begin
                        l2_ppn_q    <= pte_ppn;
                        F_ptw_pa    <= pte_ppn;
                        F_ptw_valid <= 1'b1;    // 1-cycle pulse
                    end else begin
                        F_ptw_valid <= 1'b0;
                    end
                end

                // ---------------- RESP ----------------
                S_RESP: begin
                    // Drop valid after one cycle
                    F_ptw_valid <= 1'b0;
                end

                default: begin
                    F_ptw_valid <= 1'b0;
                    Ptw_mem_req <= 1'b0;
                end
            endcase
        end
    end

    // ============================================================
    // Next-state logic
    // ============================================================
    always @(*) begin
        next_state = state;

        case (state)
            S_IDLE: begin
                if (Itlb_pa_request)
                    next_state = S_L1_REQ;
            end

            S_L1_REQ: begin
                if (!MEM_stall)
                    next_state = S_L1_WAIT;
            end

            S_L1_WAIT: begin
                if (Ptw_mem_valid)
                    next_state = S_L2_REQ;
            end

            S_L2_REQ: begin
                if (!MEM_stall)
                    next_state = S_L2_WAIT;
            end

            S_L2_WAIT: begin
                if (Ptw_mem_valid)
                    next_state = S_RESP;
            end

            S_RESP: begin
                next_state = S_IDLE;
            end

            default: next_state = S_IDLE;
        endcase
    end

endmodule
