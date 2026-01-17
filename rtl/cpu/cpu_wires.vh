  // =======================
  // Wire declarations
  // =======================

  // ----- Program Counter / Fetch -----
  wire [VPC_BITS-1:0] F_pc_va;
  wire [PC_BITS-1:0]  F_pc;
  wire [XLEN-1:0]     F_inst;

  // Branch Predictor / buffer
  wire                 F_BP_taken;
  wire [VPC_BITS-1:0]  F_BP_target_pc;
  wire                 F_stall;

  // ===== ITLB / PTW wires =====
  wire               Itlb_ptw_valid;
  wire [7:0]         Itlb_ptw_pa;
  wire               Itlb_ptw_fault;        // NEW: PTW says ITLB walk faulted

  wire               Itlb_stall;
  wire               Itlb_pa_request;
  wire [19:0]        Itlb_va;

  // ===== DTLB / PTW wires =====
  wire               Dtlb_ptw_valid;
  wire [7:0]         Dtlb_ptw_pa;
  wire               Dtlb_ptw_fault;        // NEW: PTW says DTLB walk faulted

  wire               Dtlb_pa_request;
  wire [19:0]        Dtlb_va;

  wire [31:0]        Dtlb_addr_out;
  wire               Dtlb_addr_valid;
  wire               Dtlb_stall;

  // PTW <-> dcache interface
  wire        Ptw_mem_req;
  wire [19:0] Ptw_mem_addr;
  wire [31:0] Ptw_mem_rdata;
  wire        Ptw_mem_valid;
  wire        Ptw_accepted;                 // NEW: handshake from dcache

  // Decode stage / F→D reg
  wire [XLEN-1:0]     D_inst;
  wire [VPC_BITS-1:0] D_pc;
  wire [VPC_BITS-1:0] EX_pc;
  wire [VPC_BITS-1:0] MEM_pc;
  wire [VPC_BITS-1:0] WB_pc;

  wire D_exc;
  wire D_jlx;
  wire EX_jlx;
  wire MEM_jlx;
  wire WB_jlx;

  // NEW: iret decoded signal (separate opcode)
  wire D_iret;

  wire               D_BP_taken;
  wire [VPC_BITS-1:0] D_BP_target_pc;

  // NEW: carry ITLB PTW fault into D stage
  wire               D_itlb_ptw_fault;

  // Decoder outputs
  wire [5:0]         D_opc;
  wire [4:0]         D_ra;
  wire [4:0]         D_rb;
  wire [4:0]         D_rd;
  wire [10:0]        D_imd;
  wire               D_we;
  wire [3:0]         D_alu_op;
  wire               D_ld;
  wire               D_str;
  wire               D_brn;
  wire               D_jmp;
  wire               D_addi;
  wire               D_mul;
  wire               D_byt;

  // Hazard unit
  wire               stall_D;
  wire [2:0]         EX_D_bp;
  wire [2:0]         MEM_D_bp;
  wire [2:0]         WB_D_bp;

  // Regfile outputs
  wire [XLEN-1:0]    D_a;
  wire [XLEN-1:0]    D_b;
  wire [XLEN-1:0]    D_a2;
  wire [XLEN-1:0]    D_b2;

  // Execute stage / D→EX reg
  wire [XLEN-1:0]    EX_a;
  wire [XLEN-1:0]    EX_a2;
  wire [XLEN-1:0]    EX_b;
  wire [XLEN-1:0]    EX_b2;
  wire [3:0]         EX_alu_op;
  wire [4:0]         EX_rd;
  wire               EX_ld;
  wire               EX_str;
  wire               EX_byt;
  wire               EX_we;
  wire               EX_brn;
  wire               EX_mul;
  wire               EX_BP_taken;
  wire [VPC_BITS-1:0] EX_BP_target_pc;

  // ALU outputs
  wire [XLEN-1:0]    EX_alu_out;
  wire               EX_taken;
  wire               EX_true_taken;

  // EX → MEM pipeline register wires
  wire [XLEN-1:0]    MEM_alu_out;
  wire               MEM_taken;
  wire [XLEN-1:0]    MEM_b2;
  wire [XLEN-1:0]    MEM_a2;
  wire [4:0]         MEM_rd;
  wire               MEM_we;
  wire               MEM_ld;
  wire               MEM_str;
  wire               MEM_byt;
  wire               MEM_mul;

  // Global stall from D-cache
  wire               dcache_stall;

  // I-Cache <-> Instruction Memory
  wire               Ic_mem_req;
  wire [PC_BITS-5:0] Ic_mem_addr;
  wire [127:0]       F_mem_inst;
  wire               F_mem_valid;

  // D-cache <-> Backing Data Memory
  wire               Dc_mem_req;
  wire [PC_BITS-5:0] Dc_mem_addr;
  wire [127:0]       MEM_data_line;
  wire               MEM_mem_valid;

  wire               Dc_wb_we;
  wire [PC_BITS-5:0] Dc_wb_addr;
  wire [127:0]       Dc_wb_wline;
  wire [XLEN-1:0]    MEM_data_mem;

  // MEM → WB pipeline register wires
  wire [XLEN-1:0]    WB_data_mem;
  wire [4:0]         WB_rd;
  wire               WB_we;
  wire               dcache_data_valid;

  // =======================
  // Store Buffer <-> D$ wires (UPDATED for masked stores + byte forwarding)
  // =======================

  // Drain request from SB -> D$
  wire                 store_request;
  wire [19:0]          store_request_address; // WORD-ALIGNED PA[19:0] (addr[1:0]==0)
  wire [31:0]          store_request_wdata;   // masked word data
  wire [3:0]           store_request_wmask;   // per-byte mask (lane0..lane3)
  wire                 store_valid;           // D$ accepted/applied head entry

  // SB -> D$ load forwarding (byte-granular)
  wire [3:0]           sb_fwd_mask;           // per load byte (bit0 used for byte load)
  wire [31:0]          sb_fwd_data;           // forwarded bytes in load-lane order
  wire                 sb_all_hit;            // SB fully satisfies the current load

  // Store buffer stall
  wire                 sb_stall;

  // =======================
  // MUL pipe wires
  // =======================
  wire                 mul_result_valid;
  wire [XLEN-1:0]      mul_result;
  wire                 mul_busy;
  wire [ADDR_SIZE-1:0] mul_busy_rd;

  wire                 mul_wb_conflict_stall;
  wire                 mul_issue_stall;

  // ============================================================
  // ROB + Rename wires
  // ============================================================
  wire                  RN_ra_is_rob, RN_rb_is_rob;
  wire [TAG_W-1:0]      RN_ra_tag, RN_rb_tag;
  wire [TAG_W-1:0]      RN_dst_tag;
  wire                  RN_alloc;
  wire [TAG_W-1:0]      RN_alloc_tag;

  wire                  ROB_ra_ready, ROB_rb_ready;
  wire [XLEN-1:0]       ROB_ra_value, ROB_rb_value;

  wire                  rob_full, rob_empty;

  wire                  C_valid;
  wire                  C_we;
  wire [ADDR_SIZE-1:0]  C_rd_arch;
  wire [XLEN-1:0]       C_value;
  wire [TAG_W-1:0]      C_tag;

  wire                  RF_stall;

  // Tag wires through pipeline regs
  wire [TAG_W-1:0]      D_tag = RN_dst_tag;
  wire [TAG_W-1:0]      EX_tag;
  wire [TAG_W-1:0]      MEM_tag;
  wire [TAG_W-1:0]      WB_tag;

  // MUL tag at completion
  wire [TAG_W-1:0]      mul_result_tag;
  wire [4:0]            mul_rd_done;

  // ============================================================
  // Tag-bypass wires from Hazard_unit -> regfile
  // ============================================================
  wire                  RA_tag_bp_valid;
  wire [XLEN-1:0]       RA_tag_bp_value;
  wire                  RB_tag_bp_valid;
  wire [XLEN-1:0]       RB_tag_bp_value;

  // ============================================================
  // Producer tag/value wires (EX/MEM/WB)
  // ============================================================
  wire EX_tag_we;
  wire [XLEN-1:0] EX_tag_value;

  wire MEM_tag_we;
  wire [XLEN-1:0] MEM_tag_value;

  wire WB_tag_we;
  wire [XLEN-1:0] WB_tag_value;

  // ============================================================
  // Exception handler / unified flush wires (branch + exceptions)
  // ============================================================
  wire                  eh_flush_valid;
  wire [TAG_W-1:0]      eh_flush_tag;

  wire                  exc_set_valid;
  wire [TAG_W-1:0]      exc_set_tag;
  wire [XLEN-1:0]       exc_set_pc;

  wire                  F_flush, D_flush, EX_flush, MEM_flush, WB_flush;

  // ============================================================
  // ROB exception outputs + stall + IRET commit
  // ============================================================
  wire                  rob_stall;

  wire                  EXC_we;
  wire [XLEN-1:0]       EXC_pc;
  wire [3:0]            EXC_type;
  wire [TAG_W-1:0]      EXC_tag;

  wire                  IRET_we;
  wire [TAG_W-1:0]      IRET_tag;

  // regfile exception registers (rm1/rm2)
  wire [XLEN-1:0]       rm1;
  wire [31:0]           rm2;

  // ============================================================
  // Global admin (CPU-owned): set on exception commit, clear on iret commit
  // ============================================================
  reg admin;

  // ============================================================
  // misc
  // ============================================================
  wire WB_ld_valid;
