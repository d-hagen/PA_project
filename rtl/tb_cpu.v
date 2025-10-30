`timescale 1ns/1ps

module cpu_run_tb;

  // ---- Match your CPU defaults ----
  localparam integer XLEN      = 32;
  localparam integer REG_NUM   = 32;
  localparam integer ADDR_SIZE = 5;
  localparam integer PC_BITS   = 5;

  // End of program (first zero instruction is at/after 22)
  localparam integer END_PC = 22;

  // ---- Clock & Reset ----
  reg clk = 1'b0;
  reg rst = 1'b1;

  // ---- DUT: CPU ----
  cpu #(
    .XLEN(XLEN),
    .REG_NUM(REG_NUM),
    .ADDR_SIZE(ADDR_SIZE),
    .PC_BITS(PC_BITS)
  ) dut (
    .clk(clk),
    .rst(rst)
  );

  // ---- Clock generator: 10ns period ----
  always #5 clk = ~clk;

  // ---- (optional) waves ----
  initial begin
    $dumpfile("cpu_run_tb.vcd");
    $dumpvars(0, cpu_run_tb);
  end

  // ---- Vars for run loop ----
  integer i;
  integer cycles;
  reg [31:0] curr_inst;

  // ---- Drive reset, run until end-of-program, then dump regs ----
  initial begin
    $display("===========================================");
    $display("CPU RUN TB (Verilog-2005): start @ PC=0, stop at first NOP");
    $display("===========================================");

    // Hold reset a few cycles to let memories initialize ($readmemh etc.)
    repeat (3) @(posedge clk);
    rst <= 1'b0;

    cycles = 0;

    // Named block so we can 'disable run_loop;' instead of SystemVerilog 'break;'
    begin : run_loop
      forever begin
        @(posedge clk);
        cycles = cycles + 1;

        // peek fetch-stage PC and instruction (hierarchical)
        curr_inst = dut.F_inst;

        // Stop condition: first zero instruction at/after END_PC
        if ((dut.F_pc >= END_PC[PC_BITS-1:0]) && (curr_inst == 32'h00000000)) begin
          // drain a few cycles to retire pipeline
          repeat (5) @(posedge clk);
          $display("---- End of program reached at PC=%0d after %0d cycles ----",
                   dut.F_pc, cycles);
          disable run_loop;
        end

        // Safety timeout
        if (cycles > 2000) begin
          $display("** TIMEOUT: exceeded cycle limit, stopping.");
          disable run_loop;
        end
      end
    end

    // Dump regfile contents (regs[0..31])
    $display("\n==== REGISTER FILE DUMP ====");
    for (i = 0; i < REG_NUM; i = i + 1) begin
      $display("x%0d = 0x%08h (%0d)", i, dut.u_regfile.regs[i], dut.u_regfile.regs[i]);
    end
    $display("============================\n");

    $finish;
  end

endmodule
