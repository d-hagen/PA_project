module store_buffer #(
    parameter XLEN      = 32,
    parameter LINE_BITS = 16,   // addr[19:4]
    parameter DEPTH     = 4
)(
    input  wire                 clk,
    input  wire                 rst,

    // From MEM stage
    input  wire [XLEN-1:0]      Dtlb_addr,        // translated addr (use low 20 bits)
    input  wire                 Dtlb_addr_valid,  // 1 when Dtlb_addr is a valid translated PA

    input  wire [XLEN-1:0]      MEM_b2,        // store value
    input  wire                 MEM_ld,
    input  wire                 MEM_str,
    input  wire                 MEM_byt,       // 1=byte, 0=word (for the current op)

    // Cache handshake for draining buffered stores
    input  wire                 store_valid,   

    // To cache (drain head entry)
    output wire                 sb_load_miss,          // 1 if load line NOT in SB (line-based presence)
    output wire                 store_request,
    output wire [19:0]          store_request_address, 
    output wire [XLEN-1:0]      store_request_value,
    output wire                 store_byte,            // 1=byte, 0=word

    // Load forwarding
    output reg                  sb_hit,                // SB can satisfy this load
    output reg  [XLEN-1:0]      sb_data,               // forwarded load data (valid when sb_hit=1)

    // Global stall inputs (so SB only enqueues when pipeline is advancing)
    input  wire                 Dtlb_stall,
    input  wire                 dcache_stall,

    // Stall output (only when a store wants to enter and SB is full)
    output wire                 sb_stall
);

    // -----------------------------
    // Decode current (load) address (20-bit PA)
    // -----------------------------
    wire [19:0]          ld_addr20 = Dtlb_addr[19:0];
    wire [LINE_BITS-1:0] ld_line   = ld_addr20[19:4];
    wire [1:0]           ld_word   = ld_addr20[3:2];
    wire [1:0]           ld_byte   = ld_addr20[1:0];

    // -----------------------------
    // FIFO storage: store FULL PA[19:0] + data + size
    // -----------------------------
    reg [19:0]      addr_q [0:DEPTH-1];   // full PA[19:0]
    reg [XLEN-1:0]  data_q [0:DEPTH-1];
    reg             byt_q  [0:DEPTH-1];   // 1=byte store, 0=word store

    localparam PTR_W = (DEPTH <= 2) ? 1 :
                       (DEPTH <= 4) ? 2 :
                       (DEPTH <= 8) ? 3 :
                       (DEPTH <= 16)? 4 :
                       (DEPTH <= 32)? 5 : 6;

    reg [PTR_W-1:0] head, tail;
    reg [PTR_W:0]   count; // 0..DEPTH

    wire sb_full  = (count == DEPTH);
    wire sb_empty = (count == 0);

    // Pipeline advancing qualifier
    wire no_stall = (!dcache_stall) && (!Dtlb_stall);

    assign sb_stall = no_stall && Dtlb_addr_valid && MEM_str && sb_full;

    // -----------------------------
    // Pointer helpers
    // -----------------------------
    function [PTR_W-1:0] ptr_inc(input [PTR_W-1:0] p);
        begin
            if (p == (DEPTH-1)) ptr_inc = {PTR_W{1'b0}};
            else                ptr_inc = p + 1'b1;
        end
    endfunction

    function [PTR_W-1:0] ptr_wrap_add(input [PTR_W-1:0] p, input integer add);
        reg [PTR_W:0] tmp;
        begin
            tmp = p + add[PTR_W-1:0];
            if (tmp >= DEPTH) tmp = tmp - DEPTH;
            ptr_wrap_add = tmp[PTR_W-1:0];
        end
    endfunction

    // -----------------------------
    // Line presence check (for sb_load_miss)
    // -----------------------------
    integer k;
    reg line_present;
    reg [PTR_W-1:0] idx;

    always @(*) begin
        line_present = 1'b0;
        for (k = 0; k < DEPTH; k = k + 1) begin
            if (k < count) begin
                idx = ptr_wrap_add(head, k);
                if (addr_q[idx][19:4] == ld_line)
                    line_present = 1'b1;
            end
        end
    end

    assign sb_load_miss = MEM_ld && (!Dtlb_addr_valid || !line_present);

    // -----------------------------
    // Load forwarding (youngest match wins)
    // -----------------------------
    integer r;
    reg [PTR_W-1:0] ridx;
    reg found;

    always @(*) begin
        sb_hit  = 1'b0;
        sb_data = {XLEN{1'b0}};
        found   = 1'b0;

        if (MEM_ld && Dtlb_addr_valid) begin
            for (r = 0; r < DEPTH; r = r + 1) begin
                if (!found && (r < count)) begin
                    if (tail == 0)
                        ridx = DEPTH-1;
                    else
                        ridx = tail - 1;

                    if (ridx >= r[PTR_W-1:0])
                        ridx = ridx - r[PTR_W-1:0];
                    else
                        ridx = ridx + DEPTH - r[PTR_W-1:0];

                    if (MEM_byt) begin
                        // byte load: must match byte-store to same exact byte address
                        if ( byt_q[ridx] &&
                             addr_q[ridx][19:4] == ld_line &&
                             addr_q[ridx][3:2]  == ld_word &&
                             addr_q[ridx][1:0]  == ld_byte ) begin
                            found  = 1'b1;
                            sb_hit = 1'b1;
                            case (ld_byte)
                                2'b00: sb_data = {{(XLEN-8){1'b0}}, data_q[ridx][7:0]};
                                2'b01: sb_data = {{(XLEN-8){1'b0}}, data_q[ridx][15:8]};
                                2'b10: sb_data = {{(XLEN-8){1'b0}}, data_q[ridx][23:16]};
                                2'b11: sb_data = {{(XLEN-8){1'b0}}, data_q[ridx][31:24]};
                            endcase
                        end
                    end else begin
                        // word load: must match word-store to same word address
                        if ( !byt_q[ridx] &&
                             addr_q[ridx][19:4] == ld_line &&
                             addr_q[ridx][3:2]  == ld_word ) begin
                            found   = 1'b1;
                            sb_hit  = 1'b1;
                            sb_data = data_q[ridx];
                        end
                    end
                end
            end
        end
    end


    assign store_request         = !sb_empty;
    assign store_request_address = addr_q[head];   
    assign store_request_value   = data_q[head];
    assign store_byte            = byt_q[head];

    // -----------------------------
    // Enqueue / Dequeue
    // -----------------------------
    wire do_enq = no_stall && Dtlb_addr_valid && MEM_str && !sb_full;
    wire do_deq = store_request && store_valid;

    always @(posedge clk) begin
        if (rst) begin
            head  <= {PTR_W{1'b0}};
            tail  <= {PTR_W{1'b0}};
            count <= {(PTR_W+1){1'b0}};
        end else begin
            // Write payload on enqueue (uses old tail)
            if (do_enq) begin
                addr_q[tail] <= Dtlb_addr[19:0];
                data_q[tail] <= MEM_b2;
                byt_q[tail]  <= MEM_byt;
            end

            // pointers
            if (do_deq) head <= ptr_inc(head);
            if (do_enq) tail <= ptr_inc(tail);

            // count
            case ({do_enq, do_deq})
                2'b10: count <= count + 1'b1; // enq only
                2'b01: count <= count - 1'b1; // deq only
                default: count <= count;      // both/neither
            endcase
        end
    end

endmodule
