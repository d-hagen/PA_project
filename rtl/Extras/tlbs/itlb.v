module itlb #(
    parameter VA_WIDTH    = 32,
    parameter PA_WIDTH    = 20,
    parameter NUM_ENTRIES = 16
)(
    input                      clk,
    input                      reset,

    // Fetch stage virtual address
    input  [VA_WIDTH-1:0]      pc,

    // Control input to change admin mode from D stage
    input                      D_admin_change,   // when 1 -> force admin_mode = 0

    // Write interface for TLB entries (FIFO policy)
    input                      Wb_tlb_we,
    input  [VA_WIDTH-1:0]      WB_tlb_value_va,
    input  [PA_WIDTH-1:0]      WB_tlb_value_pa,

    // Outputs
    output                     hit,      // TLB hit (only when admin_mode = 0)
    output [PA_WIDTH-1:0]      F_pc,     // physical PC to fetch
    output                     F_admin   // current/next admin mode bit for pipeline
);

    // ------------------------------------------------------------
    // Internal TLB storage
    // ------------------------------------------------------------
    reg [VA_WIDTH-1:0] va_array [0:NUM_ENTRIES-1];
    reg [PA_WIDTH-1:0] pa_array [0:NUM_ENTRIES-1];
    reg                valid_array [0:NUM_ENTRIES-1];

    // FIFO write pointer
    reg [3:0] write_ptr;

    // Admin mode state (stored in ITLB)
    reg admin_mode;         // 0 = user mode, 1 = admin mode
    reg next_admin_mode;    // combinational "next" value

    integer i;

    // For lookup
    reg                found;
    reg [PA_WIDTH-1:0] found_pa;

    // ============================================================
    // RESET + FIFO WRITE LOGIC + ADMIN REGISTER UPDATE
    // ============================================================
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                va_array[i]    <= {VA_WIDTH{1'b0}};
                pa_array[i]    <= {PA_WIDTH{1'b0}};
                valid_array[i] <= 1'b0;
            end
            write_ptr     <= 4'd0;
            admin_mode    <= 1'b0;   // start in user mode
        end else begin
            // FIFO-style TLB write
            if (Wb_tlb_we) begin
                va_array[write_ptr]    <= WB_tlb_value_va;
                pa_array[write_ptr]    <= WB_tlb_value_pa;
                valid_array[write_ptr] <= 1'b1;

                if (write_ptr == (NUM_ENTRIES-1))
                    write_ptr <= 4'd0;
                else
                    write_ptr <= write_ptr + 4'd1;
            end

            // Update admin_mode with precomputed next_admin_mode
            admin_mode <= next_admin_mode;
        end
    end

    // ============================================================
    // COMBINATIONAL: LOOKUP, MISS DETECT, ADMIN MODE NEXT STATE
    // ============================================================
    reg [PA_WIDTH-1:0] out_pa;
    reg                out_hit;
    reg                miss_event;

    always @(*) begin
        // ---------------------------------------------------------
        // Defaults
        // ---------------------------------------------------------
        out_hit         = 1'b0;
        out_pa          = {PA_WIDTH{1'b0}};
        miss_event      = 1'b0;
        next_admin_mode = admin_mode;   // start from current state

        found    = 1'b0;
        found_pa = {PA_WIDTH{1'b0}};

        // ---------------------------------------------------------
        // Translation behavior depends on current admin_mode
        // ---------------------------------------------------------
        if (admin_mode && !D_admin_change   ) begin
            // ADMIN MODE: bypass TLB, just pass through VA low bits
            out_hit    = 1'b0;                  // no real TLB hit
            out_pa     = pc[PA_WIDTH-1:0];
            miss_event = 1'b0;                  // no new miss event in admin mode
        end else begin
            // USER MODE: normal TLB lookup
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                if (valid_array[i] && (va_array[i] == pc)) begin
                    found    = 1'b1;
                    found_pa = pa_array[i];
                end
            end

            if (found) begin
                out_hit    = 1'b1;
                out_pa     = found_pa;
                miss_event = 1'b0;
            end else begin
                // MISS IN USER MODE:
                // - F_pc = 666
                // - enter admin mode
                out_hit    = 1'b0;
                out_pa     = 20'd666;
                miss_event = 1'b1;
            end
        end

        // ---------------------------------------------------------
        // ADMIN MODE STATE UPDATE RULES
        //
        // 1. D_admin_change == 1 → force admin_mode = 0
        // 2. miss_event == 1    → set admin_mode = 1
        //
        // Priority:
        //   - clear (D_admin_change) has priority over set.
        // ---------------------------------------------------------
        if (D_admin_change) begin
            next_admin_mode = 1'b0;
        end else if (miss_event) begin
            next_admin_mode = 1'b1;
        end

  
    end

    // ------------------------------------------------------------
    // Final outputs
    // ------------------------------------------------------------
    assign hit     = out_hit;          // TLB hit in user mode only
    assign F_pc    = out_pa;           // physical PC (or 666, or passthrough in admin)
    assign F_admin = next_admin_mode;  // mode bit to send down pipeline

endmodule
