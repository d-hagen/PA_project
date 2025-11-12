# ========== Init ==========
addi r1  r1  r1  1       # r1 = 1
addi r2  r2  r2  2       # r2 = 2
addi r3  r3  r3  3       # r3 = 3
addi r0  r0  r0  0       # bubble / NOP

# ---------- BEQ taken (flush next instr) ----------
# r1 == r1 -> taken; next addi must be flushed
beq  r1  r1  r0  2
addi r10 r10 r10 99      # should be SKIPPED if flush works
addi r0  r0  r0  0       # landing bubble

# ---------- BEQ not taken (no flush) ----------
# r1 != r2 -> not taken; next addi executes
beq  r1  r2  r0  2
addi r11 r11 r11 77      # should EXECUTE
addi r0  r0  r0  0       # bubble

# ---------- BLT taken (flush) ----------
# 1 < 2 -> taken; next addi must be flushed
blt  r1  r2  r0  2
addi r12 r12 r12 55      # should be SKIPPED
addi r0  r0  r0  0       # bubble

# ---------- BGT taken (flush) ----------
# 3 > 2 -> taken; next addi must be flushed
bgt  r3  r2  r0  2
addi r13 r13 r13 44      # should be SKIPPED
addi r0  r0  r0  0       # bubble

# ---------- Unconditional jump using beq r0,r0 (always true) ----------
# Acts like a JUMP; next addi must be flushed
beq  r0  r0  r0  2
addi r14 r14 r14 123     # should be SKIPPED
addi r0  r0  r0  0       # bubble (landing)

# ---------- Not-taken branch (fall-through executes) ----------
# 3 < 1 ? false -> not taken; next addi executes
blt  r3  r1  r0  2
addi r16 r16 r16 8       # should EXECUTE
addi r0  r0  r0  0       # bubble

# End bubble
addi r0  r0  r0  0
