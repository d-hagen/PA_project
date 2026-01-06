# ============================================================
# Bases: A=0x48000, B=0x5C000, C=0x70000 (VA)
# N = 128
#
# Debug (during BUILD C):
#   r27 = snapshot of r13 right before k-loop compare (what BLT "sees")
#   r28 = k-body execution counter for current (i,j)
#   r26 = saved copy of r28 after k-loop completes (for i=0,j=0 you'll see it)
#   r29 = snapshot of r13 right after k-loop completes
# ============================================================

marker
addi r0  r0  r2   12          # r2 = 12 (for <<12)

addi r0  r0  r5   72          # r5 = 0x48
shl  r5  r2  r5   0           # r5 = 0x48000

addi r0  r0  r6   92          # r6 = 0x5C
shl  r6  r2  r6   0           # r6 = 0x5C000

addi r0  r0  r7   112         # r7 = 0x70
shl  r7  r2  r7   0           # r7 = 0x70000  (C base)

addi r0  r0  r30  2           # r30 = log2(4) bytes/word

# ============================================================
# N and shamt
# ============================================================
addi r0  r0   r13  32
addi r0  r0  r14  5           # r14 = log2(N)

# ============================================================
# Fill A with 2 loops:
# A[i*N + j] = i*N + j
# ============================================================
addi r0  r0  r10  0           # i = 0

# A_I_TOP:
addi r0  r0  r11  0           # j = 0
shl  r10 r14 r15  0           # i_row = i*N

# A_J_TOP:
add  r15 r11 r1   0           # idx = i_row + j
shl  r1  r30 r18  0           # byteoff = idx*4
add  r5  r18 r4   0           # ptrA = baseA + byteoff
store r4  r1  r0   0          # A[idx] = idx
addi r11 r11 r11  1           # j++
blt  r11 r13 r0  -20          # back to A_J_TOP

addi r10 r10 r10  1           # i++
blt  r10 r13 r0  -36          # back to A_I_TOP

# ============================================================
# Fill B with 2 loops:
# B[i*N + j] = i*N + j
# ============================================================
addi r0  r0  r10  0           # i = 0

# B_I_TOP:
addi r0  r0  r11  0           # j = 0
shl  r10 r14 r15  0           # i_row = i*N

# B_J_TOP:
add  r15 r11 r1   0           # idx = i_row + j
shl  r1  r30 r18  0           # byteoff = idx*4
add  r6  r18 r4   0           # ptrB = baseB + byteoff
store r4  r1  r0   0          # B[idx] = idx
addi r11 r11 r11  1           # j++
blt  r11 r13 r0  -20          # back to B_J_TOP

addi r10 r10 r10  1           # i++
blt  r10 r13 r0  -36          # back to B_I_TOP


# ============================================================
# Build C (triple loop):
# C[i,j] = sum_k (A[i,k] + B[k,j])
# ============================================================

# (re-assert, like your original)
addi r0  r0   r13  32
addi r0  r0  r14  7           # r14 = log2(N)

addi r0  r0  r10  0           # i = 0

# I_TOP:
addi r0  r0  r11  0           # j = 0
shl  r10 r14 r15  0           # i_row = i*N

# J_TOP:
addi r0  r0  r22  0           # acc = 0
addi r0  r0  r12  0           # k = 0
addi r0  r0  r28  0           # DBG: k_exec_count = 0

# K_TOP:
add  r15 r12 r17  0           # idxA = i_row + k
shl  r17 r30 r18  0           # byteoffA = idxA*4
add  r5  r18 r19  0           # ptrA
load r19 r0  r20  0           # a = A[i,k]

shl  r12 r14 r16  0           # k_row = k*N
add  r16 r11 r17  0           # idxB = k_row + j
shl  r17 r30 r18  0           # byteoffB = idxB*4
add  r6  r18 r19  0           # ptrB
load r19 r0  r21  0           # b = B[k,j]

add  r22 r20 r22  0           # acc += a
add  r22 r21 r22  0           # acc += b

addi r28 r28 r28  1           # DBG: count one k-body
addi r12 r12 r12  1           # k++

add  r13 r0  r27  0           # DBG: snapshot r13 before compare
blt  r12 r13 r0  -56          # back to K_TOP  (14*4)

# after k-loop:
add  r13 r0  r29  0           # DBG: snapshot r13 after loop
add  r28 r0  r26  0           # DBG: save k_exec_count

add  r15 r11 r17  0           # idxC = i_row + j
shl  r17 r30 r18  0           # byteoffC = idxC*4
add  r7  r18 r19  0           # ptrC
store r19 r22 r0  0           # C[i,j] = acc

addi r11 r11 r11  1           # j++
blt  r11 r13 r0  -100         # back to J_TOP (25*4)

addi r10 r10 r10  1           # i++
blt  r10 r13 r0  -116         # back to I_TOP (29*4)

# ============================================================
# Load only C[0][0] and C[0][1]
# ============================================================

load r7  r0  r23  -4           # r10 = C[0][0]
load r7  r0  r23  -4           # r10 = C[0][0]
load r7  r0  r23  -4           # r10 = C[0][0]

load r7  r0  r14  -40           # r10 = C[0][0]
load r7  r0  r14  -40           # r10 = C[0][0]
load r7  r0  r14  -40           # r10 = C[0][0]

load r7  r0  r10  0           # r10 = C[0][0]
load r7  r0  r10  0           # r10 = C[0][0]
load r7  r0  r11  4           # r11 = C[0][1]
load r7  r0  r11  4           # r11 = C[0][1]
load r7  r0  r11  4           # r11 = C[0][1]


end
