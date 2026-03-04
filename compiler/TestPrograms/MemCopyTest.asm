# r1  = i
# r3  = limit
# r4  = ptr_a
# r6  = ptr_b
# r5  = temp load
# r9  = base 1000
# r31 = probe load after fill

# -----------------------------
# Setup
# -----------------------------
addi r0  r0  r1   1        # i = 1        (CHANGED: was 0)
addi r0  r0  r3   129      # limit = 129  (CHANGED: was 128)
addi r0  r0  r9   1000     # r9 = 1000

# a base = 1000
addi r9  r9  r4   0        # r4 = &a[0]

# -----------------------------
# Loop 1: a[k] = k+1  (via i starting at 1)
# Loop body unchanged (4 instr), blt offset unchanged (-12)
# -----------------------------
# fill_a_loop:
store r4  r1  r0   0        # a[...] = i   (stores 1..128)
addi  r4  r4  r4   4        # ptr_a += 4
addi  r1  r1  r1   1        # i++
blt   r1  r3  r0  -12       # while (i < 129)

# -----------------------------
# Probe: load a[37] into r31
# Expected: a[37] = 38  (since a[0]=1)
# -----------------------------
addi r9  r9  r4   0        # r4 = &a[0]
load r4  r0  r31  148      # r31 = a[37]

# -----------------------------
# Reset i and pointers (copy loop unchanged)
# -----------------------------
addi r0  r0  r1   0        # i = 0

# b base = 1800 = 1000 + 800 (gap)
addi r9  r9  r6   800      # r6 = &b[0]
addi r9  r9  r4   0        # r4 = &a[0] again

# -----------------------------
# Loop 2: b[i] = a[i]   (unchanged)
# -----------------------------
# copy_loop:
load  r4  r0  r5   0        # r5 = a[i]
store r6  r5  r0   0        # b[i] = r5
addi  r4  r4  r4   4        # ptr_a += 4
addi  r6  r6  r6   4        # ptr_b += 4
addi  r1  r1  r1   1        # i++
blt   r1  r3  r0  -20       # NOTE: uses r3; see note below

# -----------------------------
# Test loads at end (same indices)
# -----------------------------
addi r9  r9  r4   0        # r4 = &a[0]
addi r9  r9  r6   800      # r6 = &b[0]

# i = 0
load r6  r0  r10  0        # b[0]  -> 1
load r4  r0  r20  0        # a[0]  -> 1

# i = 1
load r6  r0  r11  4        # b[1]  -> 2
load r4  r0  r21  4        # a[1]  -> 2

# i = 63
load r6  r0  r12  252      # b[63] -> 64
load r4  r0  r22  252      # a[63] -> 64

# i = 64
load r6  r0  r13  256      # b[64] -> 65
load r4  r0  r23  256      # a[64] -> 65

# i = 126
load r6  r0  r14  504      # b[126] -> 127
load r4  r0  r24  504      # a[126] -> 127

# i = 127
load r6  r0  r15  508      # b[127] -> 128
load r4  r0  r25  508      # a[127] -> 128
