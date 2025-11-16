xor   r1 r1 r1 0
addi  r1 r1 r1 4      # address 4
xor   r2 r2 r2 0
addi  r2 r2 r2 123    # data = 123

store r0 r2 r0 4      # write data once

# LOAD SAME WORD MANY TIMES (cache should hit after first miss)
load  r0 r0 r10 4
load  r0 r0 r11 4
load  r0 r0 r12 4
load  r0 r0 r13 4
load  r0 r0 r14 4
load  r0 r0 r15 4
load  r0 r0 r16 4
load  r0 r0 r17 4
load  r0 r0 r18 4
load  r0 r0 r19 4


# STORE SAME WORD MANY TIMES (cache should hit every time)
addi  r3 r3 r3 200
addi  r4 r4 r4 201
addi  r5 r5 r5 202
addi  r6 r6 r6 203

store r0 r3 r0 4
store r0 r4 r0 4
load  r0 r0 r21 4
store r0 r5 r0 4
store r0 r6 r0 4

# LOAD AGAIN AFTER WRITES
load  r0 r0 r20 4
load  r0 r0 r22 4
load  r0 r0 r23 4

addi  r8 r8 r8 7
addi  r0 r0 r0 0
addi  r0 r0 r0 0
addi  r0 r0 r0 0
addi  r0 r0 r0 0
addi  r0 r0 r0 0
addi  r0 r0 r0 0
