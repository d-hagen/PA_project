# Set up some source values
addi r7  r7  r7  7       # r7 = 7
addi r1  r1  r1  1       # r1 = 1

# STORE then LOAD same address; space to avoid hazards
store r0  r7  r0  12     # MEM[12] = r7 (7)
addi r0  r0  r0  0       # bubble NOP
addi r0  r0  r0  0       # bubble NOP

load  r0  r0  r20 12     # r20 = MEM[12] = 7
addi r0  r0  r0  0       # bubble NOP (1)
addi r0  r0  r0  0       # bubble NOP (2)

add   r20 r1  r23  0     # r23 = r20 + r1 = 7 + 1 = 8
xor   r20 r20 r24  0     # r24 = r20 ^ r20 = 0

# (compiler will pad to 32 and set [31] to 0x00000000)
