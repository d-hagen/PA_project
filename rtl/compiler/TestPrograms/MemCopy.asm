# r1  = i
# r3  = limit (128)
# r4  = ptr_a
# r6  = ptr_b
# r5  = temp load
# r7  = constant 5
# r9  = base 1000
# r31 = probe load after fill (should read 5)

# -----------------------------
# Setup
# -----------------------------
addi r0  r0  r1   0        # i = 0
addi r0  r0  r3   128      # limit = 128
addi r0  r0  r9   1000     # r9 = 1000
addi r0  r0  r7   5        # r7 = 5

# a base = 1000
addi r9  r9  r4   0        # r4 = &a[0]

# -----------------------------
# Loop 1: a[i] = 5
# -----------------------------
# fill_a_loop:
store r4  r7  r0   0        # a[i] = 5
addi  r4  r4  r4   4        # ptr_a += 4
addi  r1  r1  r1   1        # i++
blt   r1  r3  r0  -12       # if (i < 128) repeat


# -----------------------------
# Reset i and pointers
# -----------------------------
addi r0  r0  r1   0        # i = 0

# b base = 1800 = 1000 + 800 (gap)
addi r9  r9  r6   800      # r6 = &b[0]
addi r9  r9  r4   0        # r4 = &a[0] again

# -----------------------------
# Loop 2: b[i] = a[i]
# -----------------------------
# copy_loop:
load  r4  r0  r5   0        # r5 = a[i]
store r6  r5  r0   0        # b[i] = r5
addi  r4  r4  r4   4        # ptr_a += 4
addi  r6  r6  r6   4        # ptr_b += 4
addi  r1  r1  r1   1        # i++
blt   r1  r3  r0  -20       # if (i < 128) repeat


