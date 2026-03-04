`timescale 1ns/1ps

module cpu_run_tb;

  localparam integer XLEN            = 32;
  localparam integer REG_NUM         = 32;
  localparam integer ADDR_SIZE        = 5;
  localparam integer PC_BITS          = 20;

  // ------------------------------------------------------------
  // WAVEFORM CONTROL CONSTANTS
  // ------------------------------------------------------------
  localparam integer WAVE_START_CYCLE = 1000;                 // cycle to start dumping
  localparam integer WAVE_NUM_CYCLES  = 2000;            // number of cycles to dump
  localparam string  WAVE_FILE        = "Test.vcd";  // VCD filename

  // progress marker interval (prints ONLY a marker line)
  localparam integer PROGRESS_EVERY   = 500000;

  reg clk = 1'b0;
  reg rst = 1'b1;

  cpu #(
    .XLEN     (XLEN),
    .REG_NUM  (REG_NUM),
    .ADDR_SIZE(ADDR_SIZE),
    .PC_BITS  (PC_BITS)
  ) dut (
    .clk(clk),
    .rst(rst)
  );

  always #5 clk = ~clk;

  // ------------------------------------------------------------
  // VCD control
  // ------------------------------------------------------------
  reg dump_on;
  initial begin
    $dumpfile(WAVE_FILE);
    $dumpvars(0, cpu_run_tb);
    $dumpoff;              // start with dumping OFF
    dump_on = 1'b0;
  end

  integer cycles;
  reg [31:0] curr_inst;

  // "instructions finished" counter: increments when WB_pc changes (excluding 0)
  reg [31:0] prev_WB_pc;
  integer    finished_count;

  // Marker capture
  reg        start_valid;
  integer    start_cycle;
  integer    start_finished_snap;
  reg        endpc_valid;
  reg [31:0] endpc;

  // Final results latched
  reg     have_results;
  integer final_total_cycles;
  integer final_total_insts;
  real    final_total_cpi;
  integer final_win_cycles;
  integer final_win_insts;
  real    final_win_cpi;

  // ------------------------------------------------------------
  // PRINT / DUMP TASKS
  // ------------------------------------------------------------
  task print_banner;
    begin
      $display("===========================================");
      $display("CPU RUN TB");
      $display("Progress marker every %0d cycles", PROGRESS_EVERY);
      $display("VCD window: start=%0d cycles, length=%0d cycles",
               WAVE_START_CYCLE, WAVE_NUM_CYCLES);
      $display("VCD file: %s", WAVE_FILE);
      $display("Markers: 1st fetched 0 => start window, 2nd fetched 0 => endpc");
      $display("===========================================");
    end
  endtask

  task print_progress_marker;
    input integer cyc;
    input integer insts;
    begin
      $display("[progress] cycle=%0d finished_insts=%0d", cyc, insts);
    end
  endtask

  task print_timeout;
    begin
      $display("** TIMEOUT: exceeded cycle limit, stopping.");
    end
  endtask

  task print_cpi_summary;
    input integer total_cycles;
    input integer total_insts;
    input real    total_cpi;
    input integer marker_cycles;
    input integer marker_insts;
    input real    marker_cpi;
    begin
      $display("");
      $display("CPI SUMMARY");
      $display(" Total : cycles=%0d insts=%0d CPI=%0f",
               total_cycles, total_insts, total_cpi);
      $display(" Marker: cycles=%0d insts=%0d CPI=%0f",
               marker_cycles, marker_insts, marker_cpi);
      $display("");
    end
  endtask

  task dump_regfile;
    integer k;
    begin
      $display("\n==== REGISTER FILE DUMP ====");
      for (k = 0; k < REG_NUM; k = k + 1)
        $display("x%0d = 0x%08h (%0d)",
                 k, dut.u_regfile.regs[k], dut.u_regfile.regs[k]);
      $display("============================\n");
    end
  endtask

  task dump_mem_lines_0_7;
    integer k;
    begin
      $display("\n==== MEMORY LINES (0..7) ====");
      for (k = 0; k < 8; k = k + 1)
        $display("Line %0d: %08h %08h %08h %08h",
                 k,
                 dut.u_unified_mem.line[k][0],
                 dut.u_unified_mem.line[k][1],
                 dut.u_unified_mem.line[k][2],
                 dut.u_unified_mem.line[k][3]);
    end
  endtask

  task dump_backing_data_mem;
    integer k;
    begin
      $display("\n==== BACKING DATA MEMORY ====");
      for (k = 8; k < 24; k = k + 1)
        $display("Line %0d: %08d %08d %08d %08d",
                 k,
                 dut.u_unified_mem.line[k][0],
                 dut.u_unified_mem.line[k][1],
                 dut.u_unified_mem.line[k][2],
                 dut.u_unified_mem.line[k][3]);
    end
  endtask

  task dump_dcache;
    integer k, b;
    reg [127:0] line;
    reg [31:0]  w0, w1, w2, w3;
    begin
      $display("\n==== D-CACHE CONTENT ====");
      for (k = 0; k < 4; k = k + 1) begin
        line = 128'd0;
        for (b = 0; b < 16; b = b + 1)
          line[8*b +: 8] = dut.u_dcache.data_b[k][b];

        w0 = line[31:0];
        w1 = line[63:32];
        w2 = line[95:64];
        w3 = line[127:96];

        $display("Entry %0d | valid=%0b dirty=%0b tag=0x%0h",
                 k, dut.u_dcache.valid[k], dut.u_dcache.dirty[k], dut.u_dcache.tag[k]);
        $display("W0=%08h W1=%08h W2=%08h W3=%08h", w0, w1, w2, w3);
      end
    end
  endtask

  task dump_store_buffer;
    integer k;
    begin
      $display("\n==== STORE BUFFER CONTENT ====");
      $display("count=%0d head=%0d tail=%0d",
               dut.u_store_buffer.count,
               dut.u_store_buffer.head,
               dut.u_store_buffer.tail);

      for (k = 0; k < dut.u_store_buffer.DEPTH; k = k + 1)
        $display("SB[%0d] addr=0x%05h data=0x%08h mask=%b",
                 k,
                 dut.u_store_buffer.addrw_q[k],
                 dut.u_store_buffer.wdata_q[k],
                 dut.u_store_buffer.wmask_q[k]);
    end
  endtask

  task print_rob;
    integer j;
    begin
      $display("\n---- ROB ---- head=%0d count=%0d",
               dut.u_rob.head, dut.u_rob.count);
      for (j = 0; j < dut.u_rob.ROB_DEPTH; j = j + 1)
        $display("ROB[%0d] v=%0b rdy=%0b rd=%0d val=%0d",
                 j,
                 dut.u_rob.valid[j],
                 dut.u_rob.ready[j],
                 dut.u_rob.rd[j],
                 dut.u_rob.value[j]);
    end
  endtask

  task print_mem_line_by_dec_addr;
    input integer addr_dec;
    input         fmt;
    integer       line_idx;
    begin
      line_idx = addr_dec / 16;
      if (fmt)
        $display("MEM[%0d] : %08h %08h %08h %08h",
                 addr_dec,
                 dut.u_unified_mem.line[line_idx][0],
                 dut.u_unified_mem.line[line_idx][1],
                 dut.u_unified_mem.line[line_idx][2],
                 dut.u_unified_mem.line[line_idx][3]);
      else
        $display("MEM[%0d] : %0d %0d %0d %0d",
                 addr_dec,
                 dut.u_unified_mem.line[line_idx][0],
                 dut.u_unified_mem.line[line_idx][1],
                 dut.u_unified_mem.line[line_idx][2],
                 dut.u_unified_mem.line[line_idx][3]);
    end
  endtask

  task print_end_of_test;
    begin
      $display("==========================================");
      $display(" END OF TEST");
      $display("==========================================");
    end
  endtask

  // ------------------------------------------------------------
  // MAIN
  // ------------------------------------------------------------
  initial begin
    print_banner();

    repeat (3) @(posedge clk);
    rst <= 1'b0;

    cycles         = 0;
    prev_WB_pc     = 32'hFFFF_FFFF;
    finished_count = 0;

    start_valid         = 1'b0;
    start_cycle         = 0;
    start_finished_snap = 0;
    endpc_valid         = 1'b0;
    endpc               = 32'h0;

    have_results = 1'b0;

    begin : run_loop
      forever begin
        @(posedge clk);

        cycles    = cycles + 1;
        curr_inst = dut.F_inst;

        // ------------------------------------------------------------
        // Waveform window control
        // ------------------------------------------------------------
        if (!rst) begin
          if (!dump_on &&
              cycles >= WAVE_START_CYCLE &&
              cycles <  (WAVE_START_CYCLE + WAVE_NUM_CYCLES)) begin
            $dumpon;
            dump_on = 1'b1;
            $display("[vcd] dumping ON at cycle=%0d", cycles);
          end

          if (dump_on &&
              cycles >= (WAVE_START_CYCLE + WAVE_NUM_CYCLES)) begin
            $dumpoff;
            dump_on = 1'b0;
            $display("[vcd] dumping OFF at cycle=%0d", cycles);
          end
        end

        // ------------------------------------------------------------
        // Marker detection
        // ------------------------------------------------------------
        if (!rst && dut.F_inst == 32'h00000000) begin
          if (!start_valid) begin
            start_valid         <= 1'b1;
            start_cycle         <= cycles;
            start_finished_snap <= finished_count;
          end else if (!endpc_valid) begin
            endpc       <= dut.F_pc_va;
            endpc_valid <= 1'b1;
          end
        end

        // ------------------------------------------------------------
        // Finished instruction count
        // ------------------------------------------------------------
        if (!rst && (dut.WB_pc !== prev_WB_pc) && (dut.WB_pc !== 0)) begin
          finished_count = finished_count + 1;
          prev_WB_pc     = dut.WB_pc;
        end

        // ------------------------------------------------------------
        // Progress marker
        // ------------------------------------------------------------
        if (!rst && cycles != 0 && cycles % PROGRESS_EVERY == 0)
          print_progress_marker(cycles, finished_count);

        // ------------------------------------------------------------
        // Normal termination
        // ------------------------------------------------------------
        if (!rst && endpc_valid && dut.WB_pc == endpc) begin
          integer win_cycles, win_insts;

          repeat (5) @(posedge clk);

          final_total_cycles = cycles;
          final_total_insts  = finished_count;
          final_total_cpi    = (finished_count > 0)
                               ? (cycles * 1.0) / finished_count : 0.0;

          if (start_valid) begin
            win_cycles = cycles - start_cycle;
            win_insts  = finished_count - start_finished_snap;
          end else begin
            win_cycles = 0;
            win_insts  = 0;
          end

          final_win_cycles = win_cycles;
          final_win_insts  = win_insts;
          final_win_cpi    = (win_insts > 0)
                             ? (win_cycles * 1.0) / win_insts : 0.0;

          have_results = 1'b1;
          disable run_loop;
        end

        // ------------------------------------------------------------
        // Safety timeout
        // ------------------------------------------------------------
        if (cycles > 2000000000) begin
          print_timeout();
          final_total_cycles = cycles;
          final_total_insts  = finished_count;
          final_total_cpi    = (finished_count > 0)
                               ? (cycles * 1.0) / finished_count : 0.0;
          have_results = 1'b1;
          disable run_loop;
        end

      end
    end

    // ------------------------------------------------------------
    // END-OF-TEST OUTPUTS
    // ------------------------------------------------------------
    if (have_results)
      print_cpi_summary(final_total_cycles, final_total_insts, final_total_cpi,
                        final_win_cycles, final_win_insts, final_win_cpi);

    dump_regfile();
    print_mem_line_by_dec_addr(1516, 1'b0);
    dump_mem_lines_0_7();
    dump_backing_data_mem();
    print_rob();
    dump_dcache();
    dump_store_buffer();

    print_end_of_test();
    $finish;
  end

endmodule
