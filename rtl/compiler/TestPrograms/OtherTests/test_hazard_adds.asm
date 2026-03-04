addi  r0  r0  r1   5      # r1 = 5
addi  r1  r0  r2   7      # r2 = r1 + 7          (EX->D forward r1)
add   r1  r2  r3   0      # r3 = r1 + r2         (MEM->D r1, EX->D r2)

addi  r0  r0  r4   1      # r4 = 1
add   r2  r4  r5   0      # r5 = r2 + r4         (WB->D r2, EX->D r4)

addi  r0  r0  r12  28     # r12 = 28 (address of next instr after jlx)
jlx   r12 r0  r0   0      # jump to r12+0; also r31 = PC+4

addi  r31 r0  r6   1      # r6 = r31 + 1         (EX jlx-type forward)
addi  r0  r0  r7   2      # r7 = 2
add   r31 r7  r8   0      # r8 = r31 + r7        (MEM jlx-type forward)

addi  r0  r0  r9   3      # r9 = 3
addi  r0  r0  r10  4      # r10 = 4
add   r31 r10 r11  0      # r11 = r31 + r10      (WB jlx-type forward)
