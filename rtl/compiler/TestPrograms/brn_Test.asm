# Initialize comparands
addi r1  r1  r1  1       # r1 = 1
addi r2  r2  r2  2       # r2 = 2
addi r3  r3  r3  3       # r3 = 3

# BEQ taken: r1 == r1 -> skip next (imm=2 skips two slots)
beq  r1  r1  r0  5
addi r10 r10 r10 99      # (skipped if beq taken)
addi r0  r0  r0  0       # bubble (acts as landing padding)

# BEQ not taken: r1 != r2 -> execute next
beq  r1  r2  r0  2
addi r11 r11 r11 77      # executes (not taken)
addi r0  r0  r0  0       # bubble

# BLT taken: 1 < 2
blt  r1  r2  r0  2
addi r12 r12 r12 55      # skipped
addi r0  r0  r0  0       # bubble

# BGT taken: 3 > 2
bgt  r3  r2  r0  2
addi r13 r13 r13 44      # skipped
addi r0  r0  r0  0       # bubble
