`timescale 1ns/1ps

module cpu_run_tb;

  localparam integer XLEN      = 32;
  localparam integer REG_NUM   = 32;
  localparam integer ADDR_SIZE = 5;
  localparam integer PC_BITS   = 20;

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

  // ------------------------------------------------------------
  // PRINT TASKS
  // ------------------------------------------------------------

  task print_banner;
    begin
      $display("===========================================");
      $display("CPU RUN TB (Verilog-2005): start @ PC=0, treat 1st fetched 0x00000000 as START marker, 2nd as END marker (stop at WB_pc==endpc)");
      $display("===========================================");
    end
  endtask

  task print_startinst_detected;
    input [31:0] f_pc_va;
    input integer cyc;
    begin
      $display("** Detected START marker fetch: F_inst=0 at F_pc=%0d (cycle %0d) -> begin CPI window **",
               f_pc_va, cyc);
    end
  endtask

  task print_endinst_detected;
    input [31:0] f_pc_va;
    input integer cyc;
    begin
      $display("** Detected END marker fetch (2nd zero): F_inst=0 at F_pc=%0d (cycle %0d) **",
               f_pc_va, cyc);
    end
  endtask

  task print_trace_line;
    input integer cyc;
    input [31:0] f_pc_va;
    input [31:0] inst;
    input [31:0] F_pc;
    input [31:0] store_req_addr;
    input [31:0] Ptw_mem_req;
    input [31:0] Dtlb_stall;
    input [31:0] Ptw_accepted;
    input [31:0] Ptw_mem_valid;
    input [31:0] EX_tag;
    input [31:0] wb_pc;
    begin
      $display(
        "C%0d | F_pc_va=%0d F_inst=0x%08h | F_pc=%0d | store_request_address=%0d -> Ptw_mem_req=%0d | Dtlb_stall=%0d | Ptw_accepted=%0b Ptw_mem_valid=%0d EX_tag=%0d WB_pc=%0d",
        cyc,
        f_pc_va,
        inst,
        F_pc,
        store_req_addr,
        Ptw_mem_req,
        Dtlb_stall,
        Ptw_accepted,
        Ptw_mem_valid,
        EX_tag,
        wb_pc
      );
    end
  endtask

  task print_timeout;
    begin
      $display("** TIMEOUT: exceeded cycle limit, stopping.");
    end
  endtask

  // NEW PRINT FORMAT YOU REQUESTED
  task print_summary_totals_and_marker;
    input integer total_cycles;
    input integer total_insts;
    input real    total_cpi;

    input integer marker_cycles;
    input integer marker_insts;
    input real    marker_cpi;
    begin
      $display("");
      $display("Total :");
      $display("%0d cycles", total_cycles);
      $display("%0d instructions", total_insts);
      $display("%0f CPI", total_cpi);
      $display("");
      $display("Marker :");
      $display("%0d cycles", marker_cycles);
      $display("%0d instructions", marker_insts);
      $display("%0f CPI", marker_cpi);
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

  task print_end_of_test;
    begin
      $display("==========================================");
      $display("               END OF TEST");
      $display("==========================================");
    end
  endtask

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

  // ------------------------------------------------------------
  // Print ONE unified memory line given a DECIMAL byte address
  // addr_dec : byte address in DECIMAL (e.g. 1540)
  // fmt      : 1 = HEX output, 0 = DECIMAL output
  // ------------------------------------------------------------
  task print_mem_line_by_dec_addr;
    input integer addr_dec;
    input         fmt;

    integer line_idx;
    begin
      // Each line = 16 bytes = 4 words
      line_idx = addr_dec / 16;

      if (fmt) begin
        $display("MEM[addr=%0d] -> line %0d : %08h %08h %08h %08h",
                  addr_dec,
                  line_idx,
                  dut.u_unified_mem.line[line_idx][0],
                  dut.u_unified_mem.line[line_idx][1],
                  dut.u_unified_mem.line[line_idx][2],
                  dut.u_unified_mem.line[line_idx][3]);
      end
      else begin
        $display("MEM[addr=%0d] -> line %0d : %0d %0d %0d %0d",
                  addr_dec,
                  line_idx,
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

    begin : run_loop
      forever begin
        @(posedge clk);
        cycles = cycles + 1;

        curr_inst = dut.F_inst;

        // ------------------------------------------------------------
        // Capture START/END markers based on FETCH of 0x00000000
        //   - 1st time F_inst==0 : START measurement window
        //   - 2nd time F_inst==0 : END marker PC (stop when reaches WB)
        // ------------------------------------------------------------
        if (!rst) begin
          if (dut.F_inst == 32'h00000000) begin
            if (!start_valid) begin
              start_valid         <= 1'b1;
              start_cycle         <= cycles;
              start_finished_snap <= finished_count;
              print_startinst_detected(dut.F_pc_va, cycles);
            end
            else if (!endpc_valid) begin
              endpc       <= dut.F_pc_va;
              endpc_valid <= 1'b1;
              print_endinst_detected(dut.F_pc_va, cycles);
            end
          end
        end

        // ------------------------------------------------------------
        // Count "finished instructions":
        // increments when WB_pc changes AND new WB_pc != 0.
        // Do NOT update prev_WB_pc when WB_pc==0 (bubble).
        // ------------------------------------------------------------
        if (!rst) begin
          if ((dut.WB_pc !== prev_WB_pc) && (dut.WB_pc !== 0)) begin
            finished_count = finished_count + 1;
            prev_WB_pc     = dut.WB_pc;
          end
        end

        // Trace (first N cycles)
        if (cycles<450 ) begin
          print_trace_line(
            cycles,
            dut.F_pc_va,
            curr_inst,
            dut.F_pc,
            dut.store_request_address,
            dut.Ptw_mem_req,
            dut.Dtlb_stall,
            dut.Ptw_accepted,
            dut.Ptw_mem_valid,
            dut.EX_tag,
            dut.WB_pc
          );
        end

        // ------------------------------------------------------------
        // Stop when END marker reaches WB (2nd zero's PC)
        // ------------------------------------------------------------
        if ((!rst && endpc_valid && (dut.WB_pc == endpc) )|| (cycles > 2000000)) begin
          integer win_cycles;
          integer win_insts;
          integer total_cycles;
          integer total_insts;
          real    total_cpi;
          real    win_cpi;

          repeat (5) @(posedge clk);

          // TOTAL stats (from cycle 0)
          total_cycles = cycles;
          total_insts  = finished_count;
          if (total_insts > 0)
            total_cpi = (total_cycles * 1.0) / total_insts;
          else
            total_cpi = 0.0;

          // MARKER-window stats
          win_cycles = cycles - start_cycle;
          win_insts  = finished_count - start_finished_snap;
          if (win_insts > 0)
            win_cpi = (win_cycles * 1.0) / win_insts;
          else
            win_cpi = 0.0;

          // Keep your original "where we ended" line (optional)
          $display("---- End of program reached when WB_pc == endpc (%0d) after %0d cycles ----",
                   endpc, cycles);

          // Print in the exact format you requested
          print_summary_totals_and_marker(
            total_cycles, total_insts, total_cpi,
            win_cycles,   win_insts,   win_cpi
          );

          disable run_loop;
        end

        if (cycles > 2000000000) begin
          print_timeout();
          disable run_loop;
        end
      end
    end

    // End-of-test dumps
    dump_regfile();

    // Example: print a specific line by DECIMAL byte address (decimal output)
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