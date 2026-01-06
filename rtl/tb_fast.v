`timescale 1ns/1ps

module cpu_run_tb;

  localparam integer XLEN      = 32;
  localparam integer REG_NUM   = 32;
  localparam integer ADDR_SIZE = 5;
  localparam integer PC_BITS   = 20;

  // progress marker interval (prints ONLY a marker line)
  localparam integer PROGRESS_EVERY   = 500000;

  // stop VCD dumping after this many "finished instructions"
  localparam integer DUMP_STOP_INSTS  = 1000000;

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

  // VCD control
  reg dump_on;

  initial begin
    $dumpfile("cpu_run_tb.vcd");
    $dumpvars(0, cpu_run_tb); // dumping stops later via $dumpoff
    dump_on = 1'b1;
  end

  integer cycles;
  reg [31:0] curr_inst;

  // "instructions finished" counter: increments when WB_pc changes (excluding 0)
  reg [31:0] prev_WB_pc;
  integer finished_count;

  // Marker capture:
  //  - First time we FETCH 0x00000000: start measurement window
  //  - Second time we FETCH 0x00000000: capture endpc; stop when WB_pc == endpc
  reg        start_valid;
  integer    start_cycle;
  integer    start_finished_snap;

  reg        endpc_valid;
  reg [31:0] endpc;

  // Final results latched (so we print once, after the loop)
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
      $display("CPU RUN TB: progress marker every %0d cycles", PROGRESS_EVERY);
      $display("VCD: dumping ON initially; dumping OFF after %0d finished instructions", DUMP_STOP_INSTS);
      $display("Markers: 1st fetched 0 => start window, 2nd fetched 0 => endpc; stop at WB_pc==endpc");
      $display("END: prints CPI + regfile + memory/cache/storebuffer/etc dumps");
      $display("===========================================");
    end
  endtask

  task print_progress_marker;
    input integer cyc;
    input integer insts;
    begin
      $display("[progress] cycle=%0d reached, finished_insts=%0d", cyc, insts);
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
      $display("  Total : cycles=%0d insts=%0d CPI=%0f", total_cycles, total_insts, total_cpi);
      $display("  Marker: cycles=%0d insts=%0d CPI=%0f", marker_cycles, marker_insts, marker_cpi);
      $display("");
    end
  endtask

  task dump_regfile;
    integer k;
    begin
      $display("\n==== REGISTER FILE DUMP ====");
      for (k = 0; k < REG_NUM; k = k + 1) begin
        $display("x%0d = 0x%08h (%0d)", k, dut.u_regfile.regs[k], dut.u_regfile.regs[k]);
      end
      $display("============================\n");
    end
  endtask

  task dump_mem_lines_0_7;
    integer k;
    begin
      $display("\n==== MEMORY LINES (0..7) ====");
      for (k = 0; k < 8; k = k + 1) begin
        $display("Line %0d: %08h  %08h  %08h  %08h",
                  k,
                  dut.u_unified_mem.line[k][0],
                  dut.u_unified_mem.line[k][1],
                  dut.u_unified_mem.line[k][2],
                  dut.u_unified_mem.line[k][3]);
      end
    end
  endtask

  task dump_backing_data_mem;
    integer k;
    begin
      $display("\n==== BACKING DATA MEMORY (u_data_mem) ====");
      for (k = 8; k < 24; k = k + 1) begin
        $display("Line %0d: %08d %08d %08d %08d",
                  k,
                  dut.u_unified_mem.line[k][0],
                  dut.u_unified_mem.line[k][1],
                  dut.u_unified_mem.line[k][2],
                  dut.u_unified_mem.line[k][3]);
      end
    end
  endtask

  task dump_dcache;
    integer k;
    begin
      $display("\n==== D-CACHE CONTENT ====");
      for (k = 0; k < 4; k = k + 1) begin
        $display("Entry %0d | valid=%0b dirty=%0b tag=%0d",
                  k,
                  dut.u_dcache.valid[k],
                  dut.u_dcache.dirty[k],
                  dut.u_dcache.tag[k]);

        $display("    DATA: %0d %0d %0d %0d",
                  dut.u_dcache.data[k][0],
                  dut.u_dcache.data[k][1],
                  dut.u_dcache.data[k][2],
                  dut.u_dcache.data[k][3]);
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

      for (k = 0; k < dut.u_store_buffer.DEPTH; k = k + 1) begin
        $display("SB[%0d] | addr20=0x%0d (line=%0d word=%0d byte=%0d) data=0x%0d byt=%0d",
                k,
                dut.u_store_buffer.addr_q[k],
                dut.u_store_buffer.addr_q[k][19:4],
                dut.u_store_buffer.addr_q[k][3:2],
                dut.u_store_buffer.addr_q[k][1:0],
                dut.u_store_buffer.data_q[k],
                dut.u_store_buffer.byt_q[k]);
      end
    end
  endtask

  task print_rob;
    integer j;
    begin
      $display("\n---- ROB ---- full=%0b empty=%0b head=%0d count=%0d",
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

  task print_end_of_test;
    begin
      $display("==========================================");
      $display("               END OF TEST");
      $display("==========================================");
    end
  endtask

  // Example helper (kept from your original)
  task print_mem_line_by_dec_addr;
    input integer addr_dec;
    input         fmt;
    integer line_idx;
    begin
      line_idx = addr_dec / 16;
      if (fmt) begin
        $display("MEM[addr=%0d] -> line %0d : %08h %08h %08h %08h",
                  addr_dec, line_idx,
                  dut.u_unified_mem.line[line_idx][0],
                  dut.u_unified_mem.line[line_idx][1],
                  dut.u_unified_mem.line[line_idx][2],
                  dut.u_unified_mem.line[line_idx][3]);
      end else begin
        $display("MEM[addr=%0d] -> line %0d : %0d %0d %0d %0d",
                  addr_dec, line_idx,
                  dut.u_unified_mem.line[line_idx][0],
                  dut.u_unified_mem.line[line_idx][1],
                  dut.u_unified_mem.line[line_idx][2],
                  dut.u_unified_mem.line[line_idx][3]);
      end
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

    endpc_valid    = 1'b0;
    endpc          = 32'h0;

    have_results       = 1'b0;
    final_total_cycles = 0;
    final_total_insts  = 0;
    final_total_cpi    = 0.0;
    final_win_cycles   = 0;
    final_win_insts    = 0;
    final_win_cpi      = 0.0;

    begin : run_loop
      forever begin
        @(posedge clk);
        cycles = cycles + 1;

        curr_inst = dut.F_inst;

        // ------------------------------------------------------------
        // Capture START/END markers based on FETCH of 0x00000000
        // ------------------------------------------------------------
        if (!rst) begin
          if (dut.F_inst == 32'h00000000) begin
            if (!start_valid) begin
              start_valid         <= 1'b1;
              start_cycle         <= cycles;
              start_finished_snap <= finished_count;
            end
            else if (!endpc_valid) begin
              endpc       <= dut.F_pc_va;
              endpc_valid <= 1'b1;
            end
          end
        end

        // ------------------------------------------------------------
        // Count "finished instructions" (WB_pc changes, WB_pc != 0)
        // ------------------------------------------------------------
        if (!rst) begin
          if ((dut.WB_pc !== prev_WB_pc) && (dut.WB_pc !== 0)) begin
            finished_count = finished_count + 1;
            prev_WB_pc     = dut.WB_pc;

            // Stop VCD dumping after N finished instructions
            if (dump_on && (finished_count >= DUMP_STOP_INSTS)) begin
              $dumpoff;
              dump_on = 1'b0;
              $display("[vcd] dumping OFF at finished_insts=%0d (cycle=%0d)", finished_count, cycles);
            end
          end
        end

        // ------------------------------------------------------------
        // Progress marker every 500k cycles: ONLY marker line
        // (avoid cycle 0 by requiring cycles != 0)
        // ------------------------------------------------------------
        if (!rst && (cycles != 0) && (cycles % PROGRESS_EVERY == 0)) begin
          print_progress_marker(cycles, finished_count);
        end

        // ------------------------------------------------------------
        // Normal stop: END marker reaches WB
        // ------------------------------------------------------------
        if (!rst && endpc_valid && (dut.WB_pc == endpc)) begin
          integer win_cycles;
          integer win_insts;
          integer total_cycles;
          integer total_insts;
          real    total_cpi;
          real    win_cpi;

          repeat (5) @(posedge clk);

          total_cycles = cycles;
          total_insts  = finished_count;

          if (total_insts > 0) total_cpi = (total_cycles * 1.0) / total_insts;
          else                 total_cpi = 0.0;

          if (start_valid) begin
            win_cycles = cycles - start_cycle;
            win_insts  = finished_count - start_finished_snap;
          end else begin
            win_cycles = 0;
            win_insts  = 0;
          end

          if (win_insts > 0) win_cpi = (win_cycles * 1.0) / win_insts;
          else               win_cpi = 0.0;

          // latch results for end-of-test printing
          have_results       = 1'b1;
          final_total_cycles = total_cycles;
          final_total_insts  = total_insts;
          final_total_cpi    = total_cpi;
          final_win_cycles   = win_cycles;
          final_win_insts    = win_insts;
          final_win_cpi      = win_cpi;

          disable run_loop;
        end

        // ------------------------------------------------------------
        // Safety timeout
        // ------------------------------------------------------------
        if (cycles > 2000000000) begin
          real total_cpi_to;

          print_timeout();

          if (finished_count > 0) total_cpi_to = (cycles * 1.0) / finished_count;
          else                    total_cpi_to = 0.0;

          have_results       = 1'b1;
          final_total_cycles = cycles;
          final_total_insts  = finished_count;
          final_total_cpi    = total_cpi_to;

          // marker-window unknown on timeout if start never seen
          if (start_valid) begin
            final_win_cycles = cycles - start_cycle;
            final_win_insts  = finished_count - start_finished_snap;
            if (final_win_insts > 0) final_win_cpi = (final_win_cycles * 1.0) / final_win_insts;
            else                     final_win_cpi = 0.0;
          end else begin
            final_win_cycles = 0;
            final_win_insts  = 0;
            final_win_cpi    = 0.0;
          end

          disable run_loop;
        end
      end
    end

    // ------------------------------------------------------------
    // END-OF-TEST OUTPUTS (ONCE)
    // ------------------------------------------------------------

    if (have_results) begin
      print_cpi_summary(
        final_total_cycles, final_total_insts, final_total_cpi,
        final_win_cycles,   final_win_insts,   final_win_cpi
      );
    end else begin
      $display("");
      $display("NOTE: No results latched (unexpected). cycles=%0d finished_insts=%0d", cycles, finished_count);
      $display("");
    end

    dump_regfile();

    // Your other dumps (re-added)
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
