# -----------------------------
# Initialize registers
# -----------------------------
addi  r2  r2  r2   1000
addi  r3  r3  r3   200
addi  r4  r4  r4   300
addi  r5  r5  r5   400
addi  r6  r6  r6   500

# -----------------------------
# UNALIGNED STORES
# -----------------------------
# offset % 4 != 0

store r2  r0  r0   101    # offset = 1  (crosses word)
store r3  r0  r0   102    # offset = 2
store r4  r0  r0   103    # offset = 3

store r5  r0  r0   127    # offset = 3, crosses cache line if line = 128B
store r6  r0  r0   129    # offset = 1, new line

# -----------------------------
# Delay (let cache/ptw settle)
# -----------------------------
addi  r0  r0  r0   0
addi  r0  r0  r0   0
addi  r0  r0  r0   0
addi  r0  r0  r0   0
addi  r0  r0  r0   0
addi  r0  r0  r0   0

# -----------------------------
# UNALIGNED LOADS (same addrs)
# -----------------------------
load  r20 r0  r0   101
load  r21 r0  r0   102
load  r22 r0  r0   103

load  r23 r0  r0   127
load  r24 r0  r0   129

# -----------------------------
# Post-check marker
# -----------------------------
addi  r8  r8  r8   7

addi  r0  r0  r0   0
addi  r0  r0  r0   0
