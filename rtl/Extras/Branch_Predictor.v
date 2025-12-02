module branch_buffer #(
    parameter integer PC_BITS = 20,   // PC is 20 bits: [19:0] byte address, word-aligned
    parameter integer DEPTH   = 8,
    parameter integer INDX    = 3     // log2(DEPTH)
)(
    input  wire                  clk,
    input  wire                  rst,

    // Fetch-time lookup
    input  wire [PC_BITS-1:0]    F_pc,           

    // Execute-time update
    input  wire                  EX_brn,         // instruction in EX is a branch
    input  wire [PC_BITS-1:0]    EX_pc,          // its PC
    input  wire [PC_BITS-1:0]    EX_alu_out,     // resolved target PC (byte address, aligned)
    input  wire                  EX_true_taken,  // resolved direction
    input  wire                  F_stall,
    input  wire                  MEM_stall,

    // Predicted outputs to IF
    output wire [PC_BITS-1:0]    F_BP_target_pc, // predicted next PC
    output wire                  F_BP_taken      // predicted taken (on hit), else 0
);

    // Buffer arrays
    reg [PC_BITS-1:0] pc_buf     [0:DEPTH-1];
    reg [PC_BITS-1:0] target_buf [0:DEPTH-1];
    reg               taken_buf  [0:DEPTH-1];

    integer i;

    // ---------------- Fetch-time lookup ----------------
    reg              f_hit;
    reg [INDX-1:0]   f_hit_idx;

    always @(*) begin
        f_hit     = 1'b0;
        f_hit_idx = {INDX{1'b0}};
        // Simple priority-encode the first match
        for (i = 0; i < DEPTH; i = i + 1) begin
            if (!f_hit && (pc_buf[i] == F_pc)) begin
                f_hit     = 1'b1;
                f_hit_idx = i[INDX-1:0];  // location of hit 
            end
        end
    end

    wire taken_on_hit = f_hit ? taken_buf[f_hit_idx] : 1'b0;

    // PC + 4 for sequential fall-through (PC is byte address, word-aligned)
    wire [PC_BITS-1:0] seq_pc =
        F_pc + ( (!F_stall && !MEM_stall) ? {{(PC_BITS-3){1'b0}}, 3'd4} : {PC_BITS{1'b0}} );
        // For PC_BITS = 20 this is effectively: F_pc + 20'd4 when not stalled

    assign F_BP_taken     = taken_on_hit;
    assign F_BP_target_pc = (f_hit && taken_on_hit) ? target_buf[f_hit_idx]
                                                    : seq_pc;

    // ---------------- Execute-time lookup ----------------
    reg            ex_hit;
    reg [INDX-1:0] ex_hit_idx;

    always @(*) begin
        ex_hit     = 1'b0;
        ex_hit_idx = {INDX{1'b0}};
        for (i = 0; i < DEPTH; i = i + 1) begin
            if (!ex_hit && (pc_buf[i] == EX_pc)) begin
                ex_hit     = 1'b1;
                ex_hit_idx = i[INDX-1:0];
            end
        end
    end

    // FIFO insert: shift down, put new at index 0
    task automatic fifo_insert_new;
        integer k;
        begin
            for (k = DEPTH-1; k > 0; k = k - 1) begin
                pc_buf[k]     <= pc_buf[k-1];
                target_buf[k] <= target_buf[k-1];
                taken_buf[k]  <= taken_buf[k-1];
            end
            pc_buf[0]     <= EX_pc;
            target_buf[0] <= EX_alu_out;
            taken_buf[0]  <= EX_true_taken;
        end
    endtask

    // ---------------- Sequential state updates ----------------
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < DEPTH; i = i + 1) begin
                pc_buf[i]     <= {PC_BITS{1'b0}};
                target_buf[i] <= {PC_BITS{1'b0}};
                taken_buf[i]  <= 1'b0;
            end
        end else if (EX_brn) begin
            if (ex_hit) begin
                // Update existing entry
                taken_buf[ex_hit_idx]  <= EX_true_taken;
                target_buf[ex_hit_idx] <= EX_alu_out;
            end else begin
                // Insert new entry
                fifo_insert_new();
            end
        end
    end

endmodule
