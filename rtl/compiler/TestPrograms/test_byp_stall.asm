# ==============================
# Init constants / base address
# ==============================
addi r1  r1  r1  16     # r1 = 16  (base address)
addi r2  r2  r2  42     # r2 = 42  (data A)
addi r3  r3  r3  7      # r3 = 7   (data B)
addi r4  r4  r4  1      # r4 = 1
addi r0  r0  r0  0      # bubble / NOP

# ======================================================
# 1) EX->EX forward into STORE data (no stall expected)
#    r8 = r2 + r3; then store r8 to [r1+0] immediately
# ======================================================
add   r2  r3  r8  0     # r8 = 42 + 7 = 49 (producer in EX)
store r1  r8  r0  0     # MEM[16] = r8 (EX->EX forward for store data)

# ======================================================
# 2) LOAD-USE hazard (stall 1 cycle, then MEM->EX forward)
#    load [r1+0] -> r9; immediately use r9
# ======================================================
load  r1  r0  r9  0     # r9 = MEM[16] = 49
add   r9  r4  r10 0     # r10 = 49 + 1 = 50 (requires 1-cycle stall, then MEM->EX forward)

# ======================================================
# 3) WB->EX forward of a loaded value
#    load -> r11; two bubbles; then use r11
# ======================================================
load  r1  r0  r11 0     # r11 = 49
addi  r0  r0  r0  0     # bubble
addi  r0  r0  r0  0     # bubble
add   r11 r4  r12 0     # r12 = 49 + 1 = 50 (WB->EX forward)

# ======================================================
# 4) Store using a recently loaded value (forward store data)
#    re-load to r13, do an unrelated op, then store to [r1+4]
# ======================================================
load  r1  r0  r13 0     # r13 = 49
add   r2  r3  r14 0     # unrelated ALU op (keeps pipeline busy)
store r1  r13 r0  4     # MEM[20] = r13 (forward r13 to store data path)

# Final bubble
addi  r0  r0  r0  0
