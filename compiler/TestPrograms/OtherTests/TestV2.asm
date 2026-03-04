# ===== init R0..R15 with their index =====
addi r0  r0  r0   0
addi r1  r1  r1   1
addi r2  r2  r2   2
addi r3  r3  r3   3
addi r4  r4  r4   4
addi r5  r5  r5   5
addi r6  r6  r6   6
addi r7  r7  r7   7
addi r8  r8  r8   8
addi r9  r9  r9   9
addi r10 r10 r10 10
addi r11 r11 r11 11
addi r12 r12 r12 12
addi r13 r13 r13 13
addi r14 r14 r14 14
addi r15 r15 r15 15

# ===== ALU updates to new regs, plus a NOT that changes r6 =====
add  r1  r1  r1   0     # r1 = 1+1 = 2
sub  r2  r2  r2   0     # r2 = 2-2 = 0
and  r3  r3  r3   0     # r3 = 3&3 = 3
or   r4  r5  r16  0     # r16 = 4|5 = 5
xor  r6  r5  r17  0     # r17 = 6^5 = 3
not  r6  r6  r6   0     # r6 = ~6 = 0xFFFF_FFF9

# ===== shift + compare (write to fresh regs) =====
shr  r14 r1  r19  0     # r19 = 14 >> 2 = 3
lt   r10 r12 r21  0     # r21 = (10<12)?1:0 = 1

# ===== memory: store then load back, with spacing to avoid hazards =====
store r0  r7  r0  12    # MEM[12] = 7
add   r0  r0  r0   0    # NOP
load  r0  r0  r20 12    # r20 = MEM[12] = 7
add   r0  r0  r0   0    # NOP (1)
add   r0  r0  r0   0    # NOP (2)
add   r20 r1  r23  0    # r23 = 7 + 2 = 9  (consumer after two bubbles)

# extra deterministic change (no hazard)
xor  r10 r10 r11  0     # r11 = 10 ^ 10 = 0

# assembler will pad with NOPs and force [31] to NOP (end)
