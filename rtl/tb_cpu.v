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
  real cpi;

  // Dynamic end-PC capture: first time we FETCH 0x00000000, remember its PC
  reg        endpc_valid;
  reg [31:0] endpc;

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
    $display("CPU RUN TB (Verilog-2005): start @ PC=0, stop when WB_pc == PC(of fetched 0x00000000)");
    $display("===========================================");

    repeat (3) @(posedge clk);
    rst <= 1'b0;

    cycles         = 0;
    prev_WB_pc     = 32'hFFFF_FFFF;
    finished_count = 0;

    endpc_valid    = 1'b0;
    endpc          = 32'h0;

    begin : run_loop
      forever begin
        @(posedge clk);
        cycles = cycles + 1;

        curr_inst = dut.F_inst;

        // ------------------------------------------------------------
        // 1) Capture END PC dynamically:
        //    first time we FETCH 0x00000000 in F stage, remember its F_pc.
        // ------------------------------------------------------------
        if (!rst && !endpc_valid) begin
          if (dut.F_inst == 32'h00000000) begin
            endpc       <= dut.F_pc;
            endpc_valid <= 1'b1;
            $display("** Detected end-instruction fetch: F_inst=0 at F_pc=%0d (cycle %0d) **",
                     dut.F_pc, cycles);
          end
        end

        // ------------------------------------------------------------
        // 2) Count "finished instructions":
        //    increments when WB_pc changes AND new WB_pc != 0.
        //    IMPORTANT: do NOT update prev_WB_pc when WB_pc==0 (bubble),
        //    otherwise you may double count when WB_pc returns to a real value.
        // ------------------------------------------------------------
        if (!rst) begin
          if ((dut.WB_pc !== prev_WB_pc) && (dut.WB_pc !== 0)) begin
            finished_count = finished_count + 1;
            prev_WB_pc     = dut.WB_pc;
          end
        end

        // ------------------------------------------------------------
        // Trace (first N cycles)
        // ------------------------------------------------------------
        if (cycles <= 450) begin
          $display(
            "C%0d | F_pc_va=%0d F_inst=0x%08h | F_pc=%0d | sb_hit=%0d -> Dtlb_addr_out=%0d | sb_data=%0d | MEM_ld=%0b store_valid=%0b sb_load_miss=%0b mul_wb_conflict=%0b",
            cycles,
            dut.F_pc_va,
            curr_inst,
            dut.F_pc,
            dut.sb_hit,
            dut.Dtlb_addr_out,
            dut.sb_data,
            dut.MEM_ld,
            dut.store_valid,
            dut.sb_load_miss,
            dut.mul_wb_conflict_stall,
          );
        end

        // ------------------------------------------------------------
        // 3) Stop when the end-instruction reaches WB:
        //    WB_pc == saved endpc (only if we have captured it).
        // ------------------------------------------------------------
        if (!rst && endpc_valid && (dut.WB_pc == endpc)) begin
          // Let a few cycles drain for nicer end-state dumps
          repeat (5) @(posedge clk);

          if (finished_count > 0)
            cpi = (cycles * 1.0) / finished_count;
          else
            cpi = 0.0;

          $display("---- End of program reached when WB_pc == endpc (%0d) after %0d cycles ----",
                   endpc, cycles);
          $display("---- Instructions finished (WB_pc changes, excluding 0) = %0d ----", finished_count);
          $display("---- CPI = %0f ----", cpi);

          disable run_loop;
        end

        if (cycles > 2000) begin
          $display("** TIMEOUT: exceeded cycle limit, stopping.");
          disable run_loop;
        end
      end
    end

    // -----------------------------
    // End-of-test dumps
    // -----------------------------
    print_rob();

    $display("\n==== REGISTER FILE DUMP ====");
    for (i = 0; i < REG_NUM; i = i + 1) begin
      $display("x%0d = 0x%08h (%0d)", i, dut.u_regfile.regs[i], dut.u_regfile.regs[i]);
    end
    $display("============================\n");

    $display("\n==== MEMORY LINES (0..7) ====");
    for (i = 0; i < 8; i = i + 1) begin
      $display("Line %0d: %08h  %08h  %08h  %08h",
                i,
                dut.u_unified_mem.line[i][0],
                dut.u_unified_mem.line[i][1],
                dut.u_unified_mem.line[i][2],
                dut.u_unified_mem.line[i][3]);
    end

    $display("\n==== BACKING DATA MEMORY (u_data_mem) ====");
    for (i = 8; i < 24; i = i + 1) begin
      $display("Line %0d: %08d %08d %08d %08d",
                i,
                dut.u_unified_mem.line[i][0],
                dut.u_unified_mem.line[i][1],
                dut.u_unified_mem.line[i][2],
                dut.u_unified_mem.line[i][3]);
    end

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

    $display("\n==== STORE BUFFER CONTENT ====");
    $display("count=%0d head=%0d tail=%0d",
            dut.u_store_buffer.count,
            dut.u_store_buffer.head,
            dut.u_store_buffer.tail);

    for (i = 0; i < dut.u_store_buffer.DEPTH; i = i + 1) begin
      $display("SB[%0d] | addr20=0x%0d (line=%0d word=%0d byte=%0d) data=0x%0d byt=%0d",
              i,
              dut.u_store_buffer.addr_q[i],
              dut.u_store_buffer.addr_q[i][19:4],
              dut.u_store_buffer.addr_q[i][3:2],
              dut.u_store_buffer.addr_q[i][1:0],
              dut.u_store_buffer.data_q[i],
              dut.u_store_buffer.byt_q[i]);
    end

    $display("==========================================");
    $display("               END OF TEST");
    $display("==========================================");

    $finish;
  end

endmodule
