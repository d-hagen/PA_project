module icache #(
    parameter integer PC_BITS   = 20,   // [19:4]=line, [3:2]=word, [1:0]=byte
    parameter integer LINE_BITS = 16
)(
    input  wire                  clk,
    input  wire                  rst,

    input  wire [PC_BITS-1:0]    F_pc,
    input  wire [127:0]          F_mem_inst,
    input  wire                  F_mem_valid,

    output reg                   Ic_mem_req,
    output reg  [LINE_BITS-1:0]  Ic_mem_addr,

    output reg  [31:0]           F_inst,
    output reg                   F_stall
);

    // 4-entry FIFO, fully-associative I-cache
    reg                     valid [0:3];
    reg [LINE_BITS-1:0]     tag   [0:3];
    reg [31:0]              data  [0:3][0:3];
    reg [1:0]               fifo_ptr;

    integer i;

    // Address decode
    wire [LINE_BITS-1:0] pc_line = F_pc[19:4];
    wire [1:0]           pc_word = F_pc[3:2];

    // -----------------------------
    // FSM for single outstanding req
    // -----------------------------
    localparam [1:0] S_IDLE     = 2'd0;
    localparam [1:0] S_MISSWAIT = 2'd1;
    localparam [1:0] S_PFWAIT   = 2'd2;

    reg [1:0]           state;

    reg [LINE_BITS-1:0] inflight_line;
    reg                 inflight_is_pf;

    reg [LINE_BITS-1:0] last_loaded_line;
    reg                 have_last_loaded;

    // If a miss happens during PF, we "remember" that we owe a miss check
    reg                 pending_miss;

    // -----------------------------
    // Lookup helpers
    // -----------------------------
    reg        hit;
    reg [1:0]  hit_idx;

    reg        pf_hit;
    wire [LINE_BITS-1:0] pf_line = last_loaded_line + {{(LINE_BITS-1){1'b0}},1'b1};

    // -----------------------------
    // Combinational lookup
    // -----------------------------
    always @(*) begin
        hit     = 1'b0;
        hit_idx = 2'd0;

        for (i = 0; i < 4; i = i + 1) begin
            if (valid[i] && (tag[i] == pc_line)) begin
                hit     = 1'b1;
                hit_idx = i[1:0];
            end
        end

        pf_hit = 1'b0;
        if (have_last_loaded) begin
            for (i = 0; i < 4; i = i + 1) begin
                if (valid[i] && (tag[i] == pf_line)) begin
                    pf_hit = 1'b1;
                end
            end
        end
    end

    // -----------------------------
    // Outputs / request generation
    // -----------------------------
    always @(*) begin
        // defaults
        F_inst      = 32'h2000_0000; // NOP
        F_stall     = 1'b0;
        Ic_mem_req  = 1'b0;
        Ic_mem_addr = pc_line;

        // Provide instruction on hit (even while PF in-flight)
        if (hit) begin
            F_inst = data[hit_idx][pc_word];
        end

        case (state)
            S_IDLE: begin
                if (!hit) begin
                    // Demand miss: request and stall
                    F_stall     = 1'b1;
                    Ic_mem_req  = (!F_mem_valid) ? 1'b1 : 1'b0;
                    Ic_mem_addr = pc_line;
                end else begin
                    // Hit: no stall. If idle and we have a last_loaded_line, prefetch next line.
                    if (have_last_loaded && !pf_hit) begin
                        // Background prefetch (does NOT stall)
                        Ic_mem_req  = (!F_mem_valid) ? 1'b1 : 1'b0;
                        Ic_mem_addr = pf_line;
                    end
                end
            end

            S_PFWAIT: begin
                // Prefetch in flight. Only stall if the current fetch is missing.
                if (!hit) begin
                    F_stall = 1'b1;
                end
                // no new request while busy
            end

            S_MISSWAIT: begin
                // Demand miss in flight: always stall
                F_stall = 1'b1;
                // no new request while busy
            end

            default: begin
                // safe fallback
                F_stall = 1'b1;
            end
        endcase
    end

    // -----------------------------
    // Sequential state / refill
    // -----------------------------
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 4; i = i + 1) begin
                valid[i] <= 1'b0;
                tag[i]   <= {LINE_BITS{1'b0}};
            end
            fifo_ptr         <= 2'd0;
            state            <= S_IDLE;
            inflight_line    <= {LINE_BITS{1'b0}};
            inflight_is_pf   <= 1'b0;
            last_loaded_line <= {LINE_BITS{1'b0}};
            have_last_loaded <= 1'b0;
            pending_miss     <= 1'b0;
        end else begin
            // If we are prefetching and we observe a miss, remember that we owe a miss check.
            // (F_pc is assumed held stable while F_stall=1; in PFWAIT we assert F_stall on miss)
            if (state == S_PFWAIT) begin
                if (!hit) begin
                    pending_miss <= 1'b1;
                end
            end

            // Launch request bookkeeping (only when idle and actually requesting)
            // Note: Ic_mem_req is combinational, so we latch the chosen line here.
            if (state == S_IDLE && Ic_mem_req && !F_mem_valid) begin
                inflight_line  <= Ic_mem_addr;
                inflight_is_pf <= hit; // In S_IDLE we only issue PF on hit-path; miss otherwise
                // But be explicit: if hit==0 then it's a miss request; if hit==1 then it's prefetch
                if (!hit) state <= S_MISSWAIT;
                else      state <= S_PFWAIT;
            end

            // Handle memory return: install the line we actually requested (inflight_line)
            if (F_mem_valid) begin
                valid[fifo_ptr] <= 1'b1;
                tag[fifo_ptr]   <= inflight_line;

                data[fifo_ptr][0] <= F_mem_inst[31:0];
                data[fifo_ptr][1] <= F_mem_inst[63:32];
                data[fifo_ptr][2] <= F_mem_inst[95:64];
                data[fifo_ptr][3] <= F_mem_inst[127:96];

                fifo_ptr <= fifo_ptr + 1'b1;

                last_loaded_line <= inflight_line;
                have_last_loaded <= 1'b1;

                // After completing any in-flight transaction, go idle.
                // If a miss was pending during prefetch, the next cycle S_IDLE logic will
                // either see a hit (resolved) or issue the real miss request.
                state <= S_IDLE;

                // If the prefetched line happened to fix the miss, pending_miss can drop next cycle.
                // We can optimistically clear it here ONLY if the inflight line equals current pc_line
                // OR if we weren't tracking any pending miss.
                if (pending_miss) begin
                    // If the demanded line was exactly what we just filled, it is now resolved.
                    if (inflight_line == pc_line) begin
                        pending_miss <= 1'b0;
                    end
                    // else: leave it set; S_IDLE + lookup will cause a real miss request if still missing
                end
            end

            // Clear pending_miss once fetch is hitting again in idle
            if (state == S_IDLE && pending_miss && hit) begin
                pending_miss <= 1'b0;
            end
        end
    end

endmodule
