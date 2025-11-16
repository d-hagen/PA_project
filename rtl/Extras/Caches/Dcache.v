module dcache #(
    parameter XLEN = 32
)(
    input  wire             clk,
    input  wire             rst,

    // MEM stage interface
    input  wire             MEM_ld,
    input  wire             MEM_str,
    input  wire             MEM_byt,
    input  wire [XLEN-1:0]  MEM_alu_out,
    input  wire [XLEN-1:0]  MEM_b2,
    output reg  [XLEN-1:0]  MEM_data_mem,
    output reg              MEM_stall,

    // Backing memory read interface
    output reg              Dc_rd_req,
    output reg  [3:0]       Dc_rd_addr,
    input  wire [127:0]     Dc_rline,
    input  wire             Dc_rd_valid,

    // Backing memory write-back interface
    output reg              Dc_wb_we,
    output reg  [3:0]       Dc_wb_addr,
    output reg  [127:0]     Dc_wb_wline
);

    // Cache storage
    reg        valid [0:3];
    reg        dirty [0:3];
    reg [3:0]  tag   [0:3];
    reg [31:0] data  [0:3][0:3];

    // Control state
    reg [1:0] fifo_ptr;
    reg       hit;
    reg [1:0] hit_idx;
    reg [3:0] miss_line;

    integer i;

    // Address decode
    wire [5:0] addr_word = MEM_alu_out[5:0];
    wire [3:0] addr_line = addr_word[5:2];
    wire [1:0] addr_off  = addr_word[1:0];

    wire op_active = MEM_ld | MEM_str;

    // Sequential logic
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 4; i = i + 1) begin
                valid[i] <= 1'b0;
                dirty[i] <= 1'b0;
                tag[i]   <= 4'd0;
            end
            fifo_ptr    <= 2'd0;
            miss_line   <= 4'd0;
            Dc_wb_we    <= 1'b0;
            Dc_wb_addr  <= 4'd0;
            Dc_wb_wline <= 128'd0;

        end else begin
            Dc_wb_we <= 1'b0;

            // Track miss line
            if (Dc_rd_req && !hit && op_active)
                miss_line <= addr_line;

            // Refill
            if (Dc_rd_valid) begin
                // Optional write-back
                if (valid[fifo_ptr] && dirty[fifo_ptr]) begin
                    Dc_wb_we            <= 1'b1;
                    Dc_wb_addr          <= tag[fifo_ptr];
                    Dc_wb_wline[31:0]   <= data[fifo_ptr][0];
                    Dc_wb_wline[63:32]  <= data[fifo_ptr][1];
                    Dc_wb_wline[95:64]  <= data[fifo_ptr][2];
                    Dc_wb_wline[127:96] <= data[fifo_ptr][3];
                end

                // Install new line
                valid[fifo_ptr] <= 1'b1;
                dirty[fifo_ptr] <= 1'b0;
                tag[fifo_ptr]   <= miss_line;

                data[fifo_ptr][0] <= Dc_rline[31:0];
                data[fifo_ptr][1] <= Dc_rline[63:32];
                data[fifo_ptr][2] <= Dc_rline[95:64];
                data[fifo_ptr][3] <= Dc_rline[127:96];

                fifo_ptr <= fifo_ptr + 1'b1;
            end

            // Store-hit update
            if (MEM_str && hit) begin
                if (MEM_byt)
                    data[hit_idx][addr_off] <= {24'b0, MEM_b2[7:0]};
                else
                    data[hit_idx][addr_off] <= MEM_b2;

                dirty[hit_idx] <= 1'b1;
            end
        end
    end

    // Combinational logic
    always @(*) begin
        hit          = 1'b0;
        hit_idx      = 2'd0;
        MEM_stall    = 1'b0;
        MEM_data_mem = MEM_alu_out;

        Dc_rd_req    = 1'b0;
        Dc_rd_addr   = addr_line;

        // Tag lookup
        if (op_active && !Dc_rd_valid) begin
            for (i = 0; i < 4; i = i + 1) begin
                if (valid[i] && (tag[i] == addr_line)) begin
                    hit     = 1'b1;
                    hit_idx = i[1:0];
                end
            end
        end

        // Load
        if (MEM_ld) begin
            if (hit) begin
                MEM_data_mem = MEM_byt ?
                               {24'b0, data[hit_idx][addr_off][7:0]} :
                               data[hit_idx][addr_off];
            end else begin
                MEM_stall  = 1'b1;
                Dc_rd_req  = Dc_rd_valid ? 1'b0 : 1'b1;
                Dc_rd_addr = addr_line;
            end
        end

        // Store
        if (MEM_str) begin
            if (!hit) begin
                MEM_stall  = 1'b1;
                Dc_rd_req  = Dc_rd_valid ? 1'b0 : 1'b1;
                Dc_rd_addr = addr_line;
            end
        end
    end

endmodule
