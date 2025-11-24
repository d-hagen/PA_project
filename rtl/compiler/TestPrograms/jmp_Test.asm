# ---------- Initialization ----------
addi r1  r1  r1  1       # r1 = 1
addi r2  r2  r2  2       # r2 = 2
addi r3  r3  r3  3       # r3 = 3

# ---------- Jump 1: Skip 2 instructions ----------
jmp  r1  r0  r0  3    # jump ahead 4 = ra + immediate (skip next 2)
addi r10 r10 r10 99      # should be skipped
addi r11 r11 r11 88      # should be skipped
addi r12 r12 r12 77      # first executes after jump
addi r0  r0  r0  0       # NOP for spacing

# ---------- Jump 2: Skip 3 instructions ----------
jmp  r1  r0  r0  4       # jump ahead 5 (skip next 3)
addi r13 r13 r13 66      # skipped
addi r14 r14 r14 55      # skipped
addi r15 r15 r15 44      # skipped
addi r16 r16 r16 33      # executes after jump

# ---------- Jump 3: Small skip ----------
jmp  r1  r0  r0  2       # jump ahead 3 (skip next 1)
addi r17 r17 r17 22      # skipped
addi r18 r18 r18 11      # executes after jump

# ---------- Program end ----------
addi r20 r20 r20 9       # mark program end
