`timescale 1ns/1ps

module cpu_run_tb;

  localparam integer XLEN      = 32;
  localparam integer REG_NUM   = 32;
  localparam integer ADDR_SIZE = 5;
  localparam integer PC_BITS   = 5;
  localparam integer END_PC    = 22;

  reg clk = 1'b0;
  reg rst = 1'b1;

  cpu #(
    .XLEN(XLEN),
    .REG_NUM(REG_NUM),
    .ADDR_SIZE(ADDR_SIZE),
    .PC_BITS(PC_BITS)
  ) dut (
    .clk(clk),
    .rst(rst)
  );

  always #5 clk = ~clk;

  initial begin
    $dumpfile("cpu_run_tb.vcd");
    $dumpvars(0, cpu_run_tb);
  end

  integer i;
  integer cycles;
  reg [31:0] curr_inst;

  initial begin
    $display("===========================================");
    $display("CPU RUN TB (Verilog-2005): start @ PC=0, stop at first NOP");
    $display("===========================================");

    repeat (3) @(posedge clk);
    rst <= 1'b0;

    cycles = 0;

    begin : run_loop
      forever begin
        @(posedge clk);
        cycles = cycles + 1;

        curr_inst = dut.F_inst;

        // Added EX_mul display here
       if (cycles <= 70) begin
          $display("C%0d | F_pc=%0d F_inst=0x%08h | F_pc=%0d | EX_taken=%0b -> target=%0d | F_mem_req=%0b | F_stall=%0b F_mem_valid=%0b",
                  cycles,
                  dut.F_pc,
                  curr_inst,
                  dut.F_pc,
                  dut.EX_taken,
                  dut.EX_alu_out[PC_BITS-1:0],
                  dut.F_mem_req,
                  dut.F_stall,
                  dut.F_mem_valid);
        end


        if ( (curr_inst == 32'h200000ee)) begin
          repeat (5) @(posedge clk);
          $display("---- End of program reached at PC=%0d after %0d cycles ----",
                   dut.F_pc, cycles);
          disable run_loop;
        end

        if (cycles > 2000) begin
          $display("** TIMEOUT: exceeded cycle limit, stopping.");
          disable run_loop;
        end
      end
    end

    $display("\n==== REGISTER FILE DUMP ====");
    for (i = 0; i < REG_NUM; i = i + 1) begin
      $display("x%0d = 0x%08h (%0d)", i, dut.u_regfile.regs[i], dut.u_regfile.regs[i]);
    end
    $display("============================\n");

    $display("\n==== INSTRUCTION MEMORY LINES (0..3) ====");
    for (i = 0; i < 8; i = i + 1) begin
      $display("Line %0d: %08h  %08h  %08h  %08h",
                i,
                dut.u_instruct_mem.line[i][0],
                dut.u_instruct_mem.line[i][1],
                dut.u_instruct_mem.line[i][2],
                dut.u_instruct_mem.line[i][3]);
    end

    $finish;
  end

endmodule
