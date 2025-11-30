# ---------- Initialization ----------
addi r1  r1  r1  1       # r1 = 1
addi r2  r2  r2  2       # r2 = 21
addi r3  r3  r3  3       # r3 = 3


# ---------- Jump 1: Skip 2 instructions ----------
jalx  r1 r2 r3  8    # jump to pc 8 skip next 2 PC=3
addi r10 r10 r10 99      # should be skipped
addi r11 r11 r11 88      # should be skipped
addi r12 r12 r12 77      # first executes after jump
addi r0  r0  r0  0       # NOP for spacing

jalx r3 r2 r1  1     # jump to pc 3 PC=8
addi r13 r13 r13 66      # skipped
addi r14 r14 r14 55      # skipped
addi r15 r15 r15 44      # skipped
addi r16 r16 r16 33      # executes after jump