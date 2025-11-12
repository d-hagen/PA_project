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
        $display("C%0d | F_pc=%0d F_inst=0x%08h | D_pc=%0d | EX_taken=%0b -> target=%0d | stall_D=%0b | EX_we=%0b",
                 cycles,
                 dut.F_pc,
                 curr_inst,
                 dut.D_pc,
                 dut.EX_taken,
                 dut.EX_alu_out[PC_BITS-1:0],
                 dut.stall_D,
                 dut.EX_we);

        if ((dut.F_pc >= END_PC[PC_BITS-1:0]) && (curr_inst == 32'h00000000)) begin
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

    $finish;
  end

endmodule
