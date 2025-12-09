# ---------- Init (set some small constants) ----------
addi r1  r1  r1  5      # r1 = 5
addi r2  r2  r2  7      # r2 = 7
addi r4  r4  r4  3      # r4 = 3
addi r0  r0  r0  0      # nop / bubble style you use

# ---------- 1 EX->EX forward (single operand) ----------
# r3 = r1 + r2; then use r3 immediately as a source
add  r1  r2  r3  0      # r3 = 5 + 7 = 12  (producer in EX)
add  r3  r3  r5  0      # needs EX->EX forward of r3; r5 = 12 + 3 = 15

# ---------- 2 EX->EX forward (both operands from prior dest) ----------
# r6 = r1 + r2; then r7 = r6 + r6 immediately
add  r1  r2  r6  0      # r6 = 12          (producer in EX)
add  r6  r6  r7  0      # both operands need EX->EX forward; r7 = 24

# ---------- 3 MEM->EX forward (one bubble between producer and consumer) ----------
# Producer moves to MEM while consumer is in EX
add  r1  r2  r8  0      # r8 = 12          (producer)
addi r0  r0  r0  0      # bubble
add  r8  r4  r9  0      # needs MEM->EX forward of r8; r9 = 12 + 3 = 15

# ---------- 4 WB->EX forward (two bubbles between producer and consumer) ----------
add  r1  r2  r10 0      # r10 = 12         (producer)
addi r0  r0  r0  0      # bubble
addi r0  r0  r0  0      # bubble
add  r10 r4  r11 0      # needs WB->EX forward of r10; r11 = 12 + 3 = 15

# ---------- 5 Mixed chain check (keeps the bypass network busy) ----------
# r12 = r7 + r9  (both may come from recent pipeline stages)
add  r7  r9  r12 0      # depends on earlier results, should forward as needed

# End
addi r0  r0  r0  0      # final bubble / NOP


