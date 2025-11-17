`timescale 1ns/1ps

module cpu_run_tb;

  localparam integer XLEN      = 32;
  localparam integer REG_NUM   = 32;
  localparam integer ADDR_SIZE = 5;
  localparam integer PC_BITS   = 12;
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
          $display("C%0d | F_pc=%0d F_inst=0x%08h | EX_alu_out=%0d | EX_taken=%0b -> EX_ra=%0b | EX_rb=%0b | stall_d=%0b EX_true_taken=%0b",
                  cycles,
                  dut.F_pc,
                  curr_inst,
                  dut.EX_alu_out,
                  dut.EX_taken,
                  dut.EX_a,
                  dut.EX_b,
                  dut.stall_D,
                  dut.EX_true_taken);
        end


        if ( (curr_inst == 32'h00000000)) begin
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

    $display("\n==== MEMORY LINES (0..3) ====");
    for (i = 0; i < 8; i = i + 1) begin
      $display("Line %0d: %08h  %08h  %08h  %08h",
                i,
                dut.u_unified_mem.line[i][0],
                dut.u_unified_mem.line[i][1],
                dut.u_unified_mem.line[i][2],
                dut.u_unified_mem.line[i][3]);
    end

     // =====================================================
    // BACKING DATA MEMORY PRINT (16 lines)
    // =====================================================
    $display("\n==== BACKING DATA MEMORY (u_data_mem) ====");
    for (i = 8; i < 24; i = i + 1)
      $display("Line %0d: %08d %08d %08d %08d",
                i,
                dut.u_unified_mem.line[i][0],
                dut.u_unified_mem.line[i][1],
                dut.u_unified_mem.line[i][2],
                dut.u_unified_mem.line[i][3]);

 

    // =====================================================
    // D-CACHE CONTENTS
    // =====================================================
    $display("\n==== D-CACHE CONTENT ====");
    for (i = 0; i < 4; i = i + 1) begin
      $display("Entry %0d | valid=%0b dirty=%0b tag=%0d",
                i,
                dut.u_dcache.valid[i],
                dut.u_dcache.dirty[i],
                dut.u_dcache.tag[i]);

      $display("    DATA: %08h %08h %08h %08h",
                dut.u_dcache.data[i][0],
                dut.u_dcache.data[i][1],
                dut.u_dcache.data[i][2],
                dut.u_dcache.data[i][3]);
    end

    $display("==========================================");
    $display("               END OF TEST");
    $display("==========================================");
   
    $finish;
  end

endmodule
