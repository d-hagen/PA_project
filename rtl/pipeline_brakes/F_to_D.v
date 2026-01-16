module f_to_d_reg #(
    parameter integer XLEN    = 32,
    parameter integer PC_BITS = 12,
    parameter integer VPC_BITS = 32
)(
    input  wire                   clk,
    input  wire                   rst,
    input  wire [VPC_BITS-1:0]    F_pc,
    input  wire [XLEN-1:0]        F_inst,
    input  wire                   F_BP_taken,

    // NEW: fault pulse/flag coming from fetch/itlb side (however you generate it)
    input  wire                   Itlb_ptw_fault,

    input  wire                   stall_D,
    input  wire                   dcache_stall,
    input  wire                   sb_stall,
    input  wire                   Itlb_stall,
    input  wire                   Dtlb_stall,

    input  wire                   EX_taken,
    input  wire [VPC_BITS-1:0]    F_BP_target_pc,

    input  wire                   mul_wb_conflict_stall,
    input  wire                   mul_issue_stall,          // NEW

    output wire [VPC_BITS-1:0]    D_pc,
    output wire [XLEN-1:0]        D_inst,
    output wire                   D_BP_taken,
    output wire [VPC_BITS-1:0]    D_BP_target_pc,

    // NEW: registered fault into D stage
    output wire                   D_itlb_ptw_fault
);

    reg [VPC_BITS-1:0]  d_pc;
    reg [XLEN-1:0]      d_inst;
    reg                 d_bp_taken;
    reg [VPC_BITS-1:0]  d_bp_target_pc;

    // NEW flop
    reg                 d_itlb_ptw_fault;

    localparam [XLEN-1:0] NOP = 32'b00100000000000000000000000000000;

    always @(posedge clk) begin
        if (rst || Itlb_stall || EX_taken) begin
            d_pc             <= {VPC_BITS{1'b0}};
            d_inst           <= NOP;
            d_bp_taken       <= 1'b0;
            d_bp_target_pc   <= {VPC_BITS{1'b0}};
            d_itlb_ptw_fault <= 1'b0;   // clear on flush/nop inject
        end
        else if (!stall_D) begin
            d_pc             <= F_pc;
            d_inst           <= F_inst;
            d_bp_taken       <= F_BP_taken;
            d_bp_target_pc   <= F_BP_target_pc;
            d_itlb_ptw_fault <= Itlb_ptw_fault; // latch
        end
        // else: hold current D regs (stall)
    end

    assign D_pc             = d_pc;
    assign D_inst           = d_inst;
    assign D_BP_taken       = d_bp_taken;
    assign D_BP_target_pc   = d_bp_target_pc;
    assign D_itlb_ptw_fault = d_itlb_ptw_fault;

endmodule