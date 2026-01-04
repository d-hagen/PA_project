# ============================================================
# Bases: A=0x48000, B=0x5C000, C=0x70000 (VA)
# Mapping demo: PA = VA + 0x8000
# ============================================================

marker
addi r0  r0  r2   12          # r2 = 12 (for <<12)

addi r0  r0  r5   72          # r5 = 0x48
shl  r5  r2  r5   0           # r5 = 0x48000

addi r0  r0  r6   92          # r6 = 0x5C
shl  r6  r2  r6   0           # r6 = 0x5C000

addi r0  r0  r7   112         # r7 = 0x70
shl  r7  r2  r7   0           # r7 = 0x70000  (C base stays SAME)


# ============================================================
# Use SAME N register as matmul loops (for now N=4)
# ============================================================
addi r0  r0  r13  4           # r13 = N = 4
addi r0  r0  r14  2           # r14 = shamt=2  (mult by 4)


# ============================================================
# Fill A with 2 loops:
# A[i*4 + j] = i*4 + j
# ============================================================
addi r0  r0  r10  0           # i = 0

# A_I_TOP:
addi r0  r0  r11  0           # j = 0
shl  r10 r14 r15  0           # i_row = i*4

# A_J_TOP:
add  r15 r11 r1   0           # idx = i_row + j
shl  r1  r14 r18  0           # byteoff = idx*4
add  r5  r18 r4   0           # ptrA = baseA + byteoff
store r4  r1  r0   0          # A[idx] = idx
addi r11 r11 r11  1           # j++
blt  r11 r13 r0  -20          # back to A_J_TOP (PC+imm)

addi r10 r10 r10  1           # i++
blt  r10 r13 r0  -36          # back to A_I_TOP (PC+imm)

# ============================================================
# Fill B with 2 loops:
# B[i*4 + j] = i*4 + j
# ============================================================
addi r0  r0  r10  0           # i = 0

# B_I_TOP:
addi r0  r0  r11  0           # j = 0
shl  r10 r14 r15  0           # i_row = i*4

# B_J_TOP:
add  r15 r11 r1   0           # idx = i_row + j
shl  r1  r14 r18  0           # byteoff = idx*4
add  r6  r18 r4   0           # ptrB = baseB + byteoff
store r4  r1  r0   0          # B[idx] = idx
addi r11 r11 r11  1           # j++
blt  r11 r13 r0  -20          # back to B_J_TOP (PC+imm)

addi r10 r10 r10  1           # i++
blt  r10 r13 r0  -36          # back to B_I_TOP (PC+imm)

# ============================================================
# Triple-loop build C for N=4 (shamt=2)
# (UNCHANGED from your block)
# ============================================================

addi r0  r0  r13  4
addi r0  r0  r14  2

addi r0  r0  r10  0

addi r0  r0  r11  0
shl  r10 r14 r15  0

addi r0  r0  r22  0
addi r0  r0  r12  0

add  r15 r12 r17  0
shl  r17 r14 r18  0
add  r5  r18 r19  0
load r19 r0  r20  0

shl  r12 r14 r16  0
add  r16 r11 r17  0
shl  r17 r14 r18  0
add  r6  r18 r19  0
load r19 r0  r21  0

add  r22 r20 r22  0
add  r22 r21 r22  0

addi r12 r12 r12  1
blt  r12 r13 r0  -48

add  r15 r11 r17  0
shl  r17 r14 r18  0
add  r7  r18 r19  0
store r19 r22 r0  0

addi r11 r11 r11  1
blt  r11 r13 r0  -80

addi r10 r10 r10  1
blt  r10 r13 r0  -96

# ============================================================
# Load C[0..15] into r10..r25 (offsets 0..60)
# ============================================================
load r7  r0  r10  0
load r7  r0  r11  4
load r7  r0  r12  8
load r7  r0  r13  12
load r7  r0  r14  16
load r7  r0  r15  20
load r7  r0  r16  24
load r7  r0  r17  28
load r7  r0  r18  32
load r7  r0  r19  36
load r7  r0  r20  40
load r7  r0  r21  44
load r7  r0  r22  48
load r7  r0  r23  52
load r7  r0  r24  56
load r7  r0  r25  60

end
