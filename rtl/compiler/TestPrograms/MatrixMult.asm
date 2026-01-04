# ============================================================
# Matrices A, B, C placed far apart in PHYSICAL memory,
# while load/store use VIRTUAL addresses.
#
# Your translation demo is: PA = VA + 0x8000
# So to place arrays at:
#   A at PA 0x50000, B at PA 0x64000, C at PA 0x78000
# we must use VA bases:
#   A VA = 0x48000, B VA = 0x5C000, C VA = 0x70000
#
# Because your shl uses RB (register) as shift amount:
#   EX_alu_out = EX_a << EX_b[SHW-1:0]
# we load shift amount 12 into a register (r2).
# ============================================================

# -----------------------------
# Bases (VA) using rb-based shift
# -----------------------------
marker
addi r0  r0  r2   12          # r2 = shift amount = 12

addi r0  r0  r5   72          # r5 = 0x48
shl  r5  r2  r5   0           # r5 = 0x48 << 12 = 0x48000  (maps to PA 0x50000)

addi r0  r0  r6   92          # r6 = 0x5C
shl  r6  r2  r6   0           # r6 = 0x5C << 12 = 0x5C000  (maps to PA 0x64000)

addi r0  r0  r7   112         # r7 = 0x70
shl  r7  r2  r7   0           # r7 = 0x70 << 12 = 0x70000  (maps to PA 0x78000)

# ============================================================
# Fill A: A[k] = k
# ============================================================
# Build r3 = 16385 using rb-based shift:
# r3 = (1 << 14) + 1
addi r0  r0  r2   11      # r2 = shift amount 14
addi r0  r0  r3   1        # r3 = 1
shl  r3  r2  r3   0        # r3 = r3 << r2 = 1<<14 = 16384
addi r3  r0  r3   1        # r3 = 16384 + 1 = 16385


addi r5  r0  r4   0           # r4 = ptrA = baseA

# A_loop:
store r4  r1  r0   0          # *ptrA = k
addi  r4  r4  r4   4          # ptrA += 4
addi  r1  r1  r1   1          # k++
blt   r1  r3  r0  -12         # if (k < 16) loop

# ============================================================
# Fill B: comment says B[k] = 15-k, but original code stores k.
# Keeping your behavior unchanged (stores k).
# ============================================================
addi r0  r0  r1   0           # r1 = k = 0
addi r6  r0  r4   0           # r4 = ptrB = baseB

# B_loop:
store r4  r1  r0   0          # *ptrB = k
addi  r4  r4  r4   4          # ptrB += 4
addi  r1  r1  r1   1          # k++
blt   r1  r3  r0  -12         # if (k < 16) loop

# ============================================================
# Build C: C[k] = A[k] + B[k]
# ============================================================
addi r0  r0  r1   0           # r1 = k = 0

addi r5  r0  r4   0           # r4 = ptrA = baseA
addi r6  r0  r8   0           # r8 = ptrB = baseB
addi r7  r0  r9   0           # r9 = ptrC = baseC

# C_loop:
load  r4  r0  r2   0          # r2 = *ptrA     (reuses r2; shift is done already)
load  r8  r0  r12  0          # r12 = *ptrB
add   r2  r12 r2   0          # r2 = r2 + r12
store r9  r2  r0   0          # *ptrC = r2

addi  r4  r4  r4   4          # ptrA += 4
addi  r8  r8  r8   4          # ptrB += 4
addi  r9  r9  r9   4          # ptrC += 4
addi  r1  r1  r1   1          # k++
blt   r1  r3  r0  -32         # if (k < 16) loop

# ============================================================
# Load C into registers x10..x25
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
load r7  r0  r25  800
