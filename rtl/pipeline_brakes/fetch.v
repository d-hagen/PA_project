module f_to_d_reg #(
    parameter integer XLEN    = 32,
    parameter integer PC_BITS = 5
)(
    input  wire                   clk,
    input  wire                   rst,
    input  wire [PC_BITS-1:0]     F_pc,
    input  wire [XLEN-1:0]        F_inst,
    output wire [PC_BITS-1:0]     D_pc,
    output wire [XLEN-1:0]        D_inst
);
    reg [PC_BITS-1:0] d_pc;
    reg [XLEN-1:0]    d_inst;

    // Synchronous reset is fine here
    always @(posedge clk) begin
        if (rst) begin
            d_pc   <= {PC_BITS{1'b0}};
            d_inst <= {XLEN{1'b0}};
        end else begin
            d_pc   <= F_pc;
            d_inst <= F_inst;
        end
    end

    assign D_pc   = d_pc;
    assign D_inst = d_inst;
endmodule
