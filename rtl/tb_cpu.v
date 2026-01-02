`timescale 1ns/1ps

module cpu_run_tb;

  localparam integer XLEN      = 32;
  localparam integer REG_NUM   = 32;
  localparam integer ADDR_SIZE = 5;
  localparam integer PC_BITS   = 20;
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

  task print_rob;
    integer j;
    begin
      $display("---- ROB ---- full=%0b empty=%0b head=%0d count=%0d",
               dut.rob_full, dut.rob_empty, dut.u_rob.head, dut.u_rob.count);

      for (j = 0; j < dut.u_rob.ROB_DEPTH; j = j + 1) begin
        $display("ROB[%0d] v=%0b rdy=%0b we=%0b rd=%0d val=0x%0d",
                 j,
                 dut.u_rob.valid[j],
                 dut.u_rob.ready[j],
                 dut.u_rob.we[j],
                 dut.u_rob.rd[j],
                 dut.u_rob.value[j]);
      end
      $display("------------");
    end
  endtask


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
       if (cycles <= 100) begin
          $display(
            "C%0d | F_pc_va=%0d F_inst=0x%08h | F_pc=%0d | D_mul=%0d -> mul_issue_stall=%0d | EX_mul=%0d | RF_stall=%0d mul_busy=%0d mul_v5=%0d mul_wb_conflict=%0d",
            cycles,
            dut.F_pc_va,
            curr_inst,
            dut.F_pc,
            dut.D_mul,
            dut.mul_issue_stall,
            dut.EX_mul,

            // replace MEM_ld + duplicate sb_data
            dut.RF_stall,
            dut.mul_busy,
            dut.mul_result_valid,
            dut.mul_wb_conflict_stall
          );
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
    print_rob();

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


      // =====================================================
    // STORE BUFFER CONTENTS
    // (updated for new SB: addr_q is full PA[19:0])
    // =====================================================
    $display("\n==== STORE BUFFER CONTENT ====");
    $display("count=%0d head=%0d tail=%0d",
            dut.u_store_buffer.count,
            dut.u_store_buffer.head,
            dut.u_store_buffer.tail);

    for (i = 0; i < dut.u_store_buffer.DEPTH; i = i + 1) begin
      $display("SB[%0d] | addr20=0x%05h (line=%0d word=%0d byte=%0d) data=0x%0d byt=%0d",
              i,
              dut.u_store_buffer.addr_q[i],
              dut.u_store_buffer.addr_q[i][19:4],
              dut.u_store_buffer.addr_q[i][3:2],
              dut.u_store_buffer.addr_q[i][1:0],
              dut.u_store_buffer.data_q[i],
              dut.u_store_buffer.byt_q[i]);
    end
    $display("==========================================");



    $display("==========================================");
    $display("               END OF TEST");
    $display("==========================================");
   
    $finish;
  end

endmodule
