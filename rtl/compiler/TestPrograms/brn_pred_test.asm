#for 10 loop with out predictor 554 cycles with 398 (14.11 (state: Icache yes D cache no , shared mem no , bypass yes))

addi r3  r3  r3  10     # r 3= 2
addi r2  r2  r2  1     
add  r0  r0  r1  0     # r1 = 0
addi r1  r1  r1  1     # 
addi r4  r4  r4  1      # r4 + 1
blt  r1  r3  r0  -8   # 
addi r2  r2  r2  1     
blt  r2  r3  r0  8     #
JLx  r0  r0  r0  40
beq  r0  r0  r0  -28     #PC    
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










