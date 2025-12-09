module f_to_d_reg #(
    parameter integer XLEN    = 32,
    parameter integer PC_BITS = 12
)(
    input  wire                   clk,
    input  wire                   rst,
    input  wire [PC_BITS-1:0]     F_pc,
    input  wire [XLEN-1:0]        F_inst,
    input  wire                   F_BP_taken,          

    input                         stall_D,
    input                         MEM_stall,
    input                         EX_taken,
    input wire [PC_BITS-1:0]      F_BP_target_pc, 
    input  wire [XLEN-1:0]        F_link_addr, 

    output wire [PC_BITS-1:0]     D_pc,
    output wire [XLEN-1:0]        D_inst,
    output wire                   D_BP_taken,
    output wire [PC_BITS-1:0]     D_BP_target_pc,  // Corrected comma to semicolon
    output wire  [XLEN-1:0]       D_link_addr
          

);
    reg [PC_BITS-1:0] d_pc;
    reg [XLEN-1:0]    d_inst;
    reg               d_bp_taken;
    reg [PC_BITS-1:0] d_bp_target_pc; 
    reg [XLEN-1:0] d_link_addr; 

    localparam [XLEN-1:0] NOP = 32'b00100000000000000000000000000000;  // or addi r0 r0 r0 0

    always @(posedge clk) begin
        if (rst) begin
            d_pc           <= {PC_BITS{1'b0}};
            d_inst         <= NOP;
            d_bp_taken     <= 0;
            d_bp_target_pc <= {PC_BITS{1'b0}};
            d_link_addr   <= {XLEN{1'b0}}; 
        end else if (!stall_D & !MEM_stall) begin
            d_pc           <= F_pc;
            d_inst         <= F_inst;
            d_bp_taken     <= F_BP_taken;
            d_bp_target_pc <= F_BP_target_pc;
            d_link_addr   <= F_link_addr;
        end
    end

    assign D_pc           = d_pc;
    assign D_inst         = d_inst;
    assign D_BP_taken     = d_bp_taken;
    assign D_BP_target_pc = d_bp_target_pc;
    assign  D_link_addr   = d_link_addr; // Propagate PC (Link Address)


endmodule