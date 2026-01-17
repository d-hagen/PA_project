module store_buffer #(
    parameter XLEN      = 32,
    parameter LINE_BITS = 16,   // addr[19:4]
    parameter DEPTH     = 4
)(
    input  wire                 clk,
    input  wire                 rst,

    // From MEM stage
    input  wire [XLEN-1:0]      Dtlb_addr,
    input  wire                 Dtlb_addr_valid,

    input  wire [XLEN-1:0]      MEM_b2,
    input  wire                 MEM_ld,
    input  wire                 MEM_str,
    input  wire                 MEM_byt,       // 1=byte op, 0=word op

    // Cache handshake for draining buffered stores
    input  wire                 store_valid,

    // To cache (drain head entry)
    output wire                 store_request,
    output wire [19:0]          store_request_addr_w, // word-aligned (addr[1:0]==0)
    output wire [31:0]          store_request_wdata,
    output wire [3:0]           store_request_wmask,

    // Load forwarding (byte-granular)
    output reg  [3:0]           sb_fwd_mask,
    output reg  [31:0]          sb_fwd_data,
    output reg                  sb_all_hit,

    // Global stall inputs
    input  wire                 Dtlb_stall,
    input  wire                 dcache_stall,

    // Stall output
    output wire                 sb_stall
);

    // ============================================================
    // FIFO storage: word-aligned addr + data + byte-mask
    // ============================================================
    reg [19:0] addrw_q [0:DEPTH-1];
    reg [31:0] wdata_q [0:DEPTH-1];
    reg [3:0]  wmask_q [0:DEPTH-1];

    localparam PTR_W = (DEPTH <= 2) ? 1 :
                       (DEPTH <= 4) ? 2 :
                       (DEPTH <= 8) ? 3 :
                       (DEPTH <= 16)? 4 :
                       (DEPTH <= 32)? 5 : 6;

    reg [PTR_W-1:0] head, tail;
    reg [PTR_W:0]   count;

    wire sb_empty = (count == 0);

    // pipeline advancing qualifier
    wire no_stall = (!dcache_stall) && (!Dtlb_stall);

    // pointer increment
    function [PTR_W-1:0] ptr_inc;
        input [PTR_W-1:0] p;
        begin
            if (p == (DEPTH-1)) ptr_inc = {PTR_W{1'b0}};
            else                ptr_inc = p + 1'b1;
        end
    endfunction

    // ============================================================
    // Store decode
    // ============================================================
    wire [19:0] st_addr20  = Dtlb_addr[19:0];
    wire [1:0]  st_off     = st_addr20[1:0];
    wire [19:0] st_addr_w0 = {st_addr20[19:2], 2'b00};

    wire is_byte_st = MEM_str &&  MEM_byt;
    wire is_word_st = MEM_str && !MEM_byt;

    // free slots
    wire [PTR_W:0] free_slots = DEPTH - count;
    wire can_enq_1 = (free_slots >= 1);
    wire can_enq_2 = (free_slots >= 2);

    wire need_two_entries = (MEM_str && !MEM_byt && (st_off != 2'b00));

    // store doesnt fit
    assign sb_stall =
        (no_stall && Dtlb_addr_valid && MEM_str) &&
        ( MEM_byt ? !can_enq_1 :
          (need_two_entries ? !can_enq_2 : !can_enq_1) );

    // ============================================================
    // Helpers: set lane / mask, get byte from MEM_b2
    // ============================================================
    function [31:0] set_lane;
        input [31:0] wd_in;
        input [1:0]  lane;
        input [7:0]  val;
        reg   [31:0] wd;
        begin
            wd = wd_in;
            case (lane)
                2'd0: wd[7:0]   = val;
                2'd1: wd[15:8]  = val;
                2'd2: wd[23:16] = val;
                2'd3: wd[31:24] = val;
            endcase
            set_lane = wd;
        end
    endfunction

    function [3:0] set_mbit;
        input [3:0] m_in;
        input [1:0] lane;
        reg   [3:0] m;
        begin
            m = m_in;
            case (lane)
                2'd0: m[0] = 1'b1;
                2'd1: m[1] = 1'b1;
                2'd2: m[2] = 1'b1;
                2'd3: m[3] = 1'b1;
            endcase
            set_mbit = m;
        end
    endfunction

    function [7:0] get_b2_byte;
        input [1:0] idx2;
        begin
            case (idx2)
                2'd0: get_b2_byte = MEM_b2[7:0];
                2'd1: get_b2_byte = MEM_b2[15:8];
                2'd2: get_b2_byte = MEM_b2[23:16];
                default: get_b2_byte = MEM_b2[31:24];
            endcase
        end
    endfunction

    // ============================================================
    // Build enqueue entries (1 or 2)
    // ============================================================
    reg  [19:0] enq1_addrw, enq2_addrw;
    reg  [31:0] enq1_wdata, enq2_wdata;
    reg  [3:0]  enq1_wmask, enq2_wmask;
    reg         do_enq1, do_enq2;

    integer bi;
    integer pos;
    reg [1:0] lane_tmp;     // 2-bit lane computed via truncation
    reg [1:0] bi2;          // 2-bit version of bi

    always @(*) begin
        do_enq1    = 1'b0;
        do_enq2    = 1'b0;
        enq1_addrw = 20'd0; enq2_addrw = 20'd0;
        enq1_wdata = 32'd0; enq2_wdata = 32'd0;
        enq1_wmask = 4'd0;  enq2_wmask = 4'd0;

        if (no_stall && Dtlb_addr_valid && MEM_str) begin

            // BYTE store -> 1 entry
            if (is_byte_st) begin
                if (can_enq_1) begin
                    do_enq1    = 1'b1;
                    enq1_addrw = st_addr_w0;

                    enq1_wdata = 32'd0;
                    enq1_wmask = 4'd0;

                    enq1_wdata = set_lane(enq1_wdata, st_off, MEM_b2[7:0]);
                    enq1_wmask = set_mbit(enq1_wmask, st_off);
                end
            end

            // WORD store
            if (is_word_st) begin
                // aligned -> 1 entry
                if (st_off == 2'b00) begin
                    if (can_enq_1) begin
                        do_enq1    = 1'b1;
                        enq1_addrw = st_addr_w0;
                        enq1_wdata = MEM_b2;
                        enq1_wmask = 4'b1111;
                    end
                end else begin
                    // unaligned -> 2 entries
                    if (can_enq_2) begin
                        do_enq1    = 1'b1;
                        enq1_addrw = st_addr_w0;
                        enq2_addrw = st_addr_w0 + 20'd4;

                        enq1_wdata = 32'd0; enq2_wdata = 32'd0;
                        enq1_wmask = 4'd0;  enq2_wmask = 4'd0;

                        for (bi = 0; bi < 4; bi = bi + 1) begin
                            bi2 = bi[1:0]; 
                            pos = st_off + bi;

                            if (pos < 4) begin
                                lane_tmp = pos; // truncation -> 2-bit
                                enq1_wdata = set_lane(enq1_wdata, lane_tmp, get_b2_byte(bi2));
                                enq1_wmask = set_mbit(enq1_wmask, lane_tmp);
                            end else begin
                                do_enq2 = 1'b1;
                                lane_tmp = (pos - 4); // truncation -> 2-bit
                                enq2_wdata = set_lane(enq2_wdata, lane_tmp, get_b2_byte(bi2));
                                enq2_wmask = set_mbit(enq2_wmask, lane_tmp);
                            end
                        end
                    end
                end
            end
        end
    end



    // ============================================================
    // Dequeue when cache accepts head
    // ============================================================
    wire do_deq = (!sb_empty) && store_valid;

    // tail+1, tail+2
    reg [PTR_W-1:0] tail_next1;
    reg [PTR_W-1:0] tail_next2;

    always @(*) begin
        tail_next1 = ptr_inc(tail);
        tail_next2 = ptr_inc(tail_next1);
    end

    // next count
    reg [PTR_W:0] next_count;
    always @(*) begin
        next_count = count;
        if (do_enq1) next_count = next_count + 1'b1;
        if (do_enq2) next_count = next_count + 1'b1;
        if (do_deq)  next_count = next_count - 1'b1;
    end

    always @(posedge clk) begin
        if (rst) begin
            head  <= {PTR_W{1'b0}};
            tail  <= {PTR_W{1'b0}};
            count <= {(PTR_W+1){1'b0}};
        end else begin
            if (do_enq1) begin
                addrw_q[tail] <= enq1_addrw;
                wdata_q[tail] <= enq1_wdata;
                wmask_q[tail] <= enq1_wmask;
            end
            if (do_enq2) begin
                addrw_q[tail_next1] <= enq2_addrw;
                wdata_q[tail_next1] <= enq2_wdata;
                wmask_q[tail_next1] <= enq2_wmask;
            end

            if (do_deq) head <= ptr_inc(head);

            if (do_enq1 && do_enq2)      tail <= tail_next2;
            else if (do_enq1)            tail <= tail_next1;

            count <= next_count;
        end
    end

    // ============================================================
    // Drain head  to cache
    // ============================================================
    assign store_request        = !sb_empty;
    assign store_request_addr_w = addrw_q[head];
    assign store_request_wdata  = wdata_q[head];
    assign store_request_wmask  = wmask_q[head];

    // ============================================================
    // Forwarding: youngest-wins per load byte
    // ============================================================
    wire [19:0] ld_addr20 = Dtlb_addr[19:0];

    function [7:0] lane_byte;
        input [31:0] wd;
        input [1:0] lane;
        begin
            case (lane)
                2'd0: lane_byte = wd[7:0];
                2'd1: lane_byte = wd[15:8];
                2'd2: lane_byte = wd[23:16];
                default: lane_byte = wd[31:24];
            endcase
        end
    endfunction

    integer i, r;
    reg [PTR_W-1:0] ridx;
    reg [PTR_W-1:0] tail_m1;
    reg [PTR_W-1:0] r_trunc;

    reg [19:0] tmp_addr;
    reg [19:0] want_addr_w;
    reg [1:0]  want_lane;

    reg found0, found1, found2, found3;
    reg [7:0] val0, val1, val2, val3;

    always @(*) begin
        sb_fwd_mask = 4'b0000;
        sb_fwd_data = 32'd0;
        sb_all_hit  = 1'b0;

        found0 = 1'b0; found1 = 1'b0; found2 = 1'b0; found3 = 1'b0;
        val0   = 8'd0; val1   = 8'd0; val2   = 8'd0; val3   = 8'd0;

        if (tail == 0) tail_m1 = DEPTH-1;
        else           tail_m1 = tail - 1;

        if (MEM_ld && Dtlb_addr_valid) begin
            for (i = 0; i < (MEM_byt ? 1 : 4); i = i + 1) begin
                tmp_addr    = ld_addr20 + i;              
                want_addr_w = {tmp_addr[19:2], 2'b00};
                want_lane   = tmp_addr[1:0];

                for (r = 0; r < DEPTH; r = r + 1) begin
                    if (r < count) begin
                        r_trunc = r; // truncation into PTR_W bits

                        if (tail_m1 >= r_trunc) ridx = tail_m1 - r_trunc;
                        else                    ridx = tail_m1 + DEPTH - r_trunc;

                        if (addrw_q[ridx] == want_addr_w && wmask_q[ridx][want_lane]) begin
                            if (i == 0 && !found0) begin found0 = 1'b1; val0 = lane_byte(wdata_q[ridx], want_lane); end
                            else if (i == 1 && !found1) begin found1 = 1'b1; val1 = lane_byte(wdata_q[ridx], want_lane); end
                            else if (i == 2 && !found2) begin found2 = 1'b1; val2 = lane_byte(wdata_q[ridx], want_lane); end
                            else if (i == 3 && !found3) begin found3 = 1'b1; val3 = lane_byte(wdata_q[ridx], want_lane); end
                        end
                    end
                end
            end

            if (found0) begin sb_fwd_mask[0] = 1'b1; sb_fwd_data[7:0]   = val0; end
            if (found1) begin sb_fwd_mask[1] = 1'b1; sb_fwd_data[15:8]  = val1; end
            if (found2) begin sb_fwd_mask[2] = 1'b1; sb_fwd_data[23:16] = val2; end
            if (found3) begin sb_fwd_mask[3] = 1'b1; sb_fwd_data[31:24] = val3; end

            if (MEM_byt) sb_all_hit = sb_fwd_mask[0];
            else         sb_all_hit = &sb_fwd_mask;
        end
    end

endmodule
