# ============================================================
# N = 4
# A base = 0x48000
# B base = 0x5C000
# C base = 0x70000
#
# Fill:
#   A[idx] = idx
#   B[idx] = idx
#
# Build:
#   C[i,j] = sum_k ( A[i,k] + B[k,j] )
#
# Check:
#   r10 = C[0][0]  (expected = 30)
# ============================================================

marker

# -----------------------------
# Build VA bases using <<12
# -----------------------------
addi r0  r0  r2   12          # r2 = 12

addi r0  r0  r5   72
shl  r5  r2  r5   0           # r5 = 0x48000 (A)

addi r0  r0  r6   92
shl  r6  r2  r6   0           # r6 = 0x5C000 (B)

addi r0  r0  r7   112
shl  r7  r2  r7   0           # r7 = 0x70000 (C)

# -----------------------------
# Constants
# -----------------------------
addi r0  r0  r30  2           # r30 = log2(4 bytes)  (idx->byte shift)

addi r0  r0  r13  128          # r13 = N
addi r0  r0  r14  7        # r14 = log2(N)  (for *N)

add  r14 r30 r28  0     # r28 = log2(N) + log2(4) = log2(N*4)
shl  r13 r30 r27  0           # r27 = strideBytes = N*4
shl  r13 r14 r3   0           # r3  = total = N*N

# ============================================================
# Fill A: A[idx] = idx   (1D pointer walk)
# ============================================================
addi r0  r0  r1   0           # idx = 0
addi r5  r0  r4   0           # ptrA = baseA

# A_FILL_LOOP:
store r4  r1  r0   0
addi  r4  r4  r4   4
addi  r1  r1  r1   1
blt   r1  r3  r0  -12          # back 3 instr

# ============================================================
# Fill B: B[idx] = idx   (1D pointer walk)
# ============================================================
addi r0  r0  r1   0           # idx = 0
addi r6  r0  r4   0           # ptrB = baseB

# B_FILL_LOOP:
store r4  r1  r0   0
addi  r4  r4  r4   4
addi  r1  r1  r1   1
blt   r1  r3  r0  -12          # back 3 instr

# ============================================================
# Build C: pointer-walking + k unroll x2
# C[i,j] = sum_k (A[i,k] + B[k,j])
# ============================================================
addi r0  r0  r10  0           # i = 0

# I_TOP:
shl  r10 r28 r15  0           # rowByteOff = i*(N*4)
add  r5  r15 r16  0           # rowA_base  = baseA + rowByteOff
add  r7  r15 r17  0           # rowC_base  = baseC + rowByteOff
addi r0  r0  r11  0           # j = 0

# J_TOP:
shl  r11 r30 r18  0           # colByteOff = j*4

addi r16 r0  r19  0           # ptrA = rowA_base
add  r6  r18 r20  0           # ptrB = baseB + colByteOff
add  r17 r18 r21  0           # ptrC = rowC_base + colByteOff

addi r0  r0  r22  0           # acc = 0
addi r0  r0  r12  0           # k = 0

# K_TOP (unrolled x2):
# ---- k ----
load r19 r0  r23  0
load r20 r0  r24  0
mul  r23 r24 r25  0         ## add/mul a*+b
add  r22 r25 r22  0
addi r19 r19 r19  4
add  r20 r27 r20  0

# ---- k+1 ----
load r19 r0  r23  0
load r20 r0  r24  0
mul  r23 r24 r25  0          ## add/mul a*+b
add  r22 r25 r22  0
addi r19 r19 r19  4
add  r20 r27 r20  0

addi r12 r12 r12  2
blt  r12 r13 r0  -52          # back 13 instr (13*4=52)

# store C[i,j]
store r21 r22 r0  0

addi r11 r11 r11  1
blt  r11 r13 r0  -88          # back 22 instr (22*4=88)

addi r10 r10 r10  1
blt  r10 r13 r0  -108         # back 27 instr (27*4=108)

# ============================================================
# Check: load C[0][0] into r10
# ============================================================
load r7  r0  r10  0           # r10 = C[0][0]

end
