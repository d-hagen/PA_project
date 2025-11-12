
module branch_buffer (
  input  wire       clk,
  input  wire       rst,

  // Fetch-time lookup
  input  wire [4:0] F_pc,           

  // Execute-time update
  input  wire       EX_brn,         // instruction in EX is a branch
  input  wire [4:0] EX_pc,          // its PC
  input  wire [4:0] EX_alu_out,     // resolved target PC
  input  wire       EX_true_taken,       // resolved direction

  // Predicted outputs to IF
  output wire [4:0] F_BP_target_pc,   // predicted next PC
  output wire       F_BP_taken          // predicted taken (on hit), else 0
);

  localparam DEPTH = 8;
  localparam INDX  = 3; 

  // Buffer arrays
  reg [4:0] pc_buf     [0:DEPTH-1];
  reg [4:0] target_buf [0:DEPTH-1];
  reg       taken_buf  [0:DEPTH-1];

  integer i;

  //Fetch lookup
  reg              f_hit;
  reg [INDX-1:0]   f_hit_idx;

  always @(*) begin
    f_hit     = 1'b0;
    f_hit_idx = {INDX{1'b0}};
    // Simple priority-encode the first match
    for (i = 0; i < DEPTH; i = i + 1) begin
      if (!f_hit && (pc_buf[i] == F_pc)) begin
        f_hit     = 1'b1;
        f_hit_idx = i[INDX-1:0];  //location of hit 
      end
    end
  end

  wire taken_on_hit = f_hit ? taken_buf[f_hit_idx] : 1'b0;

  assign F_BP_taken       = taken_on_hit;
  assign F_BP_target_pc = (f_hit && taken_on_hit) ? target_buf[f_hit_idx]
                                                : (F_pc + 5'd1);

  /// EX lookup
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

  // Sequential state updates
  always @(posedge clk) begin
    if (rst) begin
      for (i = 0; i < DEPTH; i = i + 1) begin
        pc_buf[i]     <= 5'd0;
        target_buf[i] <= 5'd0;
        taken_buf[i]  <= 1'b0;
      end
    end else if (EX_brn) begin
      if (ex_hit) begin // 
        taken_buf[ex_hit_idx]  <= EX_true_taken; //update taken
      end else begin
        fifo_insert_new();
      end
    end
  end

endmodule
