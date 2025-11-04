module d_to_ex_reg #(
    parameter XLEN = 32
)(
    input  wire             clk,
    input  wire             rst,

    // D stage inputs
    input  wire [XLEN-1:0]  D_a,
    input  wire [XLEN-1:0]  D_a2,
    input  wire [XLEN-1:0]  D_b,
    input  wire [XLEN-1:0]  D_b2,
    input  wire [3:0]       D_alu_op,   // 4-bit opcode
    input  wire             D_brn,      // branch mode
    input  wire [4:0]       D_rd,       
    input  wire             D_ld,       // <— missing input for EX_ld (load)
    input  wire             D_str,      // <— missing input for EX_str (store)
    input  wire             D_we,      // <— missing input for EX_str (write enable)

    input wire             stall_D,
    input                  EX_taken,

    


    // EX stage outputs
    output wire [XLEN-1:0]  EX_a,
    output wire [XLEN-1:0]  EX_a2,
    output wire [XLEN-1:0]  EX_b,
    output wire [XLEN-1:0]  EX_b2,
    output wire [3:0]       EX_alu_op,  // 4-bit opcode
   
    output wire [4:0]       EX_rd,
    output wire             EX_ld,
    output wire             EX_str,
    output wire             EX_we,
    output wire             EX_brn    // branch mode


);

    // Pipeline flops
    reg [XLEN-1:0]  ex_a_r, ex_a2_r, ex_b_r, ex_b2_r;
    reg [3:0]       ex_alu_op_r;
    reg             ex_brn_r;
    reg [4:0]       ex_rd_r;
    reg             ex_ld_r, ex_str_r, ex_we_r;

    always @(posedge clk) begin
        if (rst || stall_D || EX_taken) begin
            ex_a_r       <= {XLEN{1'b0}};
            ex_a2_r      <= {XLEN{1'b0}};
            ex_b_r       <= {XLEN{1'b0}};
            ex_b2_r      <= {XLEN{1'b0}};
            ex_alu_op_r  <= 4'd0;
            ex_brn_r     <= 1'b0;
            ex_rd_r      <= 5'd0;
            ex_ld_r      <= 1'b0;
            ex_str_r     <= 1'b0;
            ex_we_r      <= 1'b0;

        end else begin
            ex_a_r       <= D_a;
            ex_a2_r      <= D_a2;
            ex_b_r       <= D_b;
            ex_b2_r      <= D_b2;
            ex_alu_op_r  <= D_alu_op;
            ex_brn_r     <= D_brn;
            ex_rd_r      <= D_rd;
            ex_ld_r      <= D_ld;
            ex_str_r     <= D_str;
            ex_we_r      <= D_we;

        end
    end

    // Drive outputs
    assign EX_a      = ex_a_r;
    assign EX_a2     = ex_a2_r;
    assign EX_b      = ex_b_r;
    assign EX_b2     = ex_b2_r;
    assign EX_alu_op = ex_alu_op_r;
    assign EX_brn    = ex_brn_r;
    assign EX_rd     = ex_rd_r;
    assign EX_ld     = ex_ld_r;
    assign EX_str    = ex_str_r;
    assign EX_we     = ex_we_r;


endmodule
