module icache #(
    parameter integer PC_BITS   = 20,   // [19:4]=line, [3:2]=word, [1:0]=byte
    parameter integer LINE_BITS = 16
)(
    input  wire                  clk,
    input  wire                  rst,

    // Fetch inputs
    input  wire [PC_BITS-1:0]    F_pc,
    input  wire [127:0]          F_mem_inst,
    input  wire                  F_mem_valid,

    // Memory request
    output reg                   Ic_mem_req,
    output reg  [LINE_BITS-1:0]  Ic_mem_addr,

    // Fetch outputs
    output reg  [31:0]           F_inst,
    output reg                   F_stall
);

    // ============================================================
    // Cache arrays (4-line, fully associative, FIFO replace)
    // ============================================================
    reg                     valid [0:3];
    reg [LINE_BITS-1:0]     tag   [0:3];
    reg [31:0]              data  [0:3][0:3]; // 4 words per line
    reg [1:0]               fifo_ptr;

    integer i;

    // ============================================================
    // PC decode
    // ============================================================
    wire [LINE_BITS-1:0] pc_line = F_pc[19:4]; // cache line
    wire [1:0]           pc_word = F_pc[3:2];  // word index

    // ============================================================
    // State machine
    // ============================================================
    localparam [1:0] S_IDLE     = 2'd0; // no request
    localparam [1:0] S_MISSWAIT = 2'd1; // demand miss
    localparam [1:0] S_PFWAIT   = 2'd2; // prefetch

    reg [1:0] state;

    // ============================================================
    // In-flight tracking
    // ============================================================
    reg [LINE_BITS-1:0] inflight_line;   // requested line
    reg                 inflight_is_pf;  // prefetch or demand

    // ============================================================
    // Prefetch tracking
    // ============================================================
    reg [LINE_BITS-1:0] last_loaded_line; // last filled line
    reg                 have_last_loaded;

    reg                 pending_miss;     // miss seen during PF

    // ============================================================
    // Lookup results
    // ============================================================
    reg        hit;
    reg [1:0]  hit_idx;

    reg        pf_hit;
    wire [LINE_BITS-1:0] pf_line = last_loaded_line + 1'b1; // next line

    // ============================================================
    // Cache lookup
    // ============================================================
    always @(*) begin
        hit     = 1'b0;
        hit_idx = 2'd0;

        // check current PC line
        for (i = 0; i < 4; i = i + 1) begin
            if (valid[i] && (tag[i] == pc_line)) begin
                hit     = 1'b1;
                hit_idx = i[1:0];
            end
        end

        // check prefetch line
        pf_hit = 1'b0;
        if (have_last_loaded) begin
            for (i = 0; i < 4; i = i + 1) begin
                if (valid[i] && (tag[i] == pf_line)) begin
                    pf_hit = 1'b1;
                end
            end
        end
    end

    // ============================================================
    // Outputs and request logic
    // ============================================================
    always @(*) begin
        // defaults
        F_inst      = 32'h2000_0000; // NOP
        F_stall     = 1'b0;
        Ic_mem_req  = 1'b0;
        Ic_mem_addr = pc_line;

        // instruction from cache
        if (hit) begin
            F_inst = data[hit_idx][pc_word];
        end

        case (state)
            S_IDLE: begin // idle
                if (!hit) begin // miss
                    F_stall     = 1'b1;
                    Ic_mem_req  = (!F_mem_valid) ? 1'b1 : 1'b0;
                    Ic_mem_addr = pc_line;
                end else begin // hit
                    // try prefetch
                    if (have_last_loaded && !pf_hit) begin
                        Ic_mem_req  = (!F_mem_valid) ? 1'b1 : 1'b0;
                        Ic_mem_addr = pf_line;
                    end
                end
            end

            S_PFWAIT: begin // prefetch in flight
                if (!hit) begin // miss while PF
                    F_stall = 1'b1;
                end
                // no new request
            end

            S_MISSWAIT: begin // demand miss in flight
                F_stall = 1'b1;
                // no new request
            end

            default: begin // safe
                F_stall = 1'b1;
            end
        endcase
    end

    // ============================================================
    // State and refill
    // ============================================================
    always @(posedge clk) begin
        if (rst) begin
            // clear cache
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
            // miss seen during PF
            if (state == S_PFWAIT && !hit) begin
                pending_miss <= 1'b1;
            end

            // latch request
            if (state == S_IDLE && Ic_mem_req && !F_mem_valid) begin
                inflight_line  <= Ic_mem_addr;
                inflight_is_pf <= hit; // hit=PF, miss=demand

                if (!hit)
                    state <= S_MISSWAIT;
                else
                    state <= S_PFWAIT;
            end

            // memory return
            if (F_mem_valid) begin
                valid[fifo_ptr] <= 1'b1;
                tag[fifo_ptr]   <= inflight_line;

                data[fifo_ptr][0] <= F_mem_inst[31:0];    // word 0
                data[fifo_ptr][1] <= F_mem_inst[63:32];   // word 1
                data[fifo_ptr][2] <= F_mem_inst[95:64];   // word 2
                data[fifo_ptr][3] <= F_mem_inst[127:96];  // word 3

                fifo_ptr <= fifo_ptr + 1'b1;

                last_loaded_line <= inflight_line;
                have_last_loaded <= 1'b1;

                state <= S_IDLE;

                // clear pending miss if filled
                if (pending_miss && inflight_line == pc_line) begin
                    pending_miss <= 1'b0;
                end
            end

            // clear pending miss on hit
            if (state == S_IDLE && pending_miss && hit) begin
                pending_miss <= 1'b0;
            end
        end
    end

endmodule
