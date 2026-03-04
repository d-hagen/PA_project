# init R0..R15 with their index (rb unused for addi but we keep fixed 5-field form)
addi r0  r0  r0  0
addi r1  r1  r1  1
addi r2  r2  r2  2
addi r3  r3  r3  3
addi r4  r4  r4  4
addi r5  r5  r5  5
addi r6  r6  r6  6
addi r7  r7  r7  7
addi r8  r8  r8  8
addi r9  r9  r9  9
addi r10 r10 r10 10
addi r11 r11 r11 11
addi r12 r12 r12 12
addi r13 r13 r13 13
addi r14 r14 r14 14
addi r15 r15 r15 15

# ALU tests
add  r1  r1  r1  0
sub  r2  r2  r2  0
and  r3  r3  r3  0
or   r4  r5  r4  0
xor  r6  r5  r5  0
not  r6  r6  r6  0

# padding
addi r0 r0 r0 0
addi r0 r0 r0 0
