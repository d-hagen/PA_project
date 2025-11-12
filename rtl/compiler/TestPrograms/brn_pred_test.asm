# [00] init
addi r2  r2  r2  0      # r2 = 0
addi r3  r3  r3  30     # r3 = 30 (stop value)

# [02] loop body
addi r2  r2  r2  1      # r2++
beq  r2  r3  r0  28     # if r2 == r3 -> jump to [31] and stop
beq  r0  r0  r0  30     # wrap: from [04] -> 4+30=34 ≡ [02] mod 32

# [05..30] (don’t care / unused)
addi r0  r0  r0  0
addi r0  r0  r0  0
addi r0  r0  r0  0
addi r0  r0  r0  0
addi r0  r0  r0  0
addi r0  r0  r0  0
addi r0  r0  r0  0
addi r0  r0  r0  0
addi r0  r0  r0  0
addi r0  r0  r0  0
addi r0  r0  r0  0
addi r0  r0  r0  0
addi r0  r0  r0  0
addi r0  r0  r0  0
addi r0  r0  r0  0
addi r0  r0  r0  0
addi r0  r0  r0  0
addi r0  r0  r0  0
addi r0  r0  r0  0
addi r0  r0  r0  0
addi r0  r0  r0  0
addi r0  r0  r0  0
addi r0  r0  r0  0
addi r0  r0  r0  0
addi r0  r0  r0  0
addi r0  r0  r0  0

# [31] halt
addi r0  r0  r0  0
