module f_to_d_reg #(
    parameter integer XLEN    = 32,
    parameter integer PC_BITS = 5
)(
    input  wire                   clk,
    input  wire                   rst,
    input  wire [PC_BITS-1:0]     F_pc,
    input  wire [XLEN-1:0]        F_inst,
    input  wire                   F_BP_taken,          

    input                         stall_D,
    input                         EX_taken,

    output wire [PC_BITS-1:0]     D_pc,
    output wire [XLEN-1:0]        D_inst,
    output  wire                  D_BP_taken          

);
    reg [PC_BITS-1:0] d_pc;
    reg [XLEN-1:0]    d_inst;
    reg d_bp_taken;

    localparam [XLEN-1:0] NOP = 32'b00100000000000000000000000000000;  // or addi r0 r0 r0 0

    // Synchronous reset is fine here
    always @(posedge clk) begin
        if (rst || EX_taken) begin
            d_pc       <= {PC_BITS{1'b0}};
            d_inst     <= NOP;
            d_bp_taken <= 0;
        end else if (!stall_D) begin
            d_pc       <= F_pc;
            d_inst     <= F_inst;
            d_bp_taken <= F_BP_taken;

        end
    end

    assign D_pc        = d_pc;
    assign D_inst      = d_inst;
    assign D_BP_taken = d_bp_taken;

endmodule
