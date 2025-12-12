module ex_to_mem_reg #(
    parameter XLEN    = 32,
    parameter PC_BITS = 32
)(
    input  wire                 clk,
    input  wire                 rst,

    // EX stage inputs
    input  wire [XLEN-1:0]      EX_alu_out,
    input  wire                 EX_taken,
    input  wire [XLEN-1:0]      EX_b2,
    input  wire [XLEN-1:0]      EX_a2,
    input  wire [4:0]           EX_rd,
    input  wire                 EX_we,
    input  wire                 EX_ld,
    input  wire                 EX_str,
    input  wire                 EX_byt,
    input  wire                 MEM_stall,
    input  wire [XLEN-1:0]      EX_pc,
    input  wire                 EX_jlx,

    // MEM stage outputs
    output wire [XLEN-1:0]      MEM_alu_out,
    output wire                 MEM_taken,
    output wire [XLEN-1:0]      MEM_b2,
    output wire [XLEN-1:0]      MEM_a2,
    output wire [4:0]           MEM_rd,
    output wire                 MEM_we,
    output wire                 MEM_ld,
    output wire                 MEM_str,
    output wire                 MEM_byt,
    output wire [XLEN-1:0]   MEM_pc,
    output wire                 MEM_jlx
);

    reg [XLEN-1:0]        mem_alu_out_r, mem_b2_r, mem_a2_r;
    reg                   mem_taken_r, mem_we_r, mem_ld_r, mem_str_r, mem_byt_r;
    reg [4:0]             mem_rd_r;
    reg [XLEN-1:0]     mem_pc_r;
    reg                   mem_jlx_r;

    always @(posedge clk) begin
        if (rst) begin
            mem_alu_out_r <= {XLEN{1'b0}};
            mem_taken_r   <= 1'b0;
            mem_b2_r      <= {XLEN{1'b0}};
            mem_a2_r      <= {XLEN{1'b0}};
            mem_rd_r      <= 5'd0;
            mem_we_r      <= 1'b0;
            mem_ld_r      <= 1'b0;
            mem_str_r     <= 1'b0;
            mem_byt_r     <= 1'b0;
            mem_pc_r      <= {PC_BITS{1'b0}};
            mem_jlx_r     <= 1'b0;
        end
        else if (!MEM_stall) begin
            mem_alu_out_r <= EX_alu_out;
            mem_taken_r   <= EX_taken;
            mem_b2_r      <= EX_b2;
            mem_a2_r      <= EX_a2;
            mem_rd_r      <= EX_rd;
            mem_we_r      <= EX_we;
            mem_ld_r      <= EX_ld;
            mem_str_r     <= EX_str;
            mem_byt_r     <= EX_byt;
            mem_pc_r      <= EX_pc;
            mem_jlx_r     <= EX_jlx;
        end
    end

    assign MEM_alu_out = mem_alu_out_r;
    assign MEM_taken   = mem_taken_r;
    assign MEM_b2      = mem_b2_r;
    assign MEM_a2      = mem_a2_r;
    assign MEM_rd      = mem_rd_r;
    assign MEM_we      = mem_we_r;
    assign MEM_ld      = mem_ld_r;
    assign MEM_str     = mem_str_r;
    assign MEM_byt     = mem_byt_r;
    assign MEM_pc      = mem_pc_r;
    assign MEM_jlx     = mem_jlx_r;

endmodule
