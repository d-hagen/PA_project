# ===== init R0..R15 with their index =====
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

# ===== memory test: STORE then LOAD (address = r0 + imm) =====
# store r5 (value 5) to mem[4]
store r0  r5  r0  4
add   r0  r0  r0  0   # NOP (1)
add   r0  r0  r0  0   # NOP (2)

# load back into r10 from mem[4]
load  r0  r0  r10 4
add   r0  r0  r0  0   # NOP (WB pipeline spacing 1)
add   r0  r0  r0  0   # NOP (WB pipeline spacing 2)
add   r0  r0  r0  0   # NOP (WB pipeline spacing 3)

# use the loaded value (no hazard now)
xor   r10 r10 r11 0   # r11 = r10 ^ r10 = 0

# ===== control flow: BLT taken, then BGT taken, then JMP =====
blt   r1  r2  r0  2   # 1 < 2 -> branch +2 (skip next two)
add   r7  r7  r7  0   # (skipped if BLT taken)
add   r0  r0  r0  0   # NOP / delay slot

bgt   r2  r1  r0  2   # 2 > 1 -> branch +2 (skip next)
add   r8  r8  r8  0   # (skipped if BGT taken)
add   r0  r0  r0  0   # NOP / delay slot

jmp   r0  r0  r0  1   # jump forward by 1 to the final NOP (PC+1)
# The assembler will force slot [31] to: 00000000 // [31] NOP (end of program)
