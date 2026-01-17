# r1 = i
# r2 = sum
# r3 = limit (12)
# r4 = ptr (&a[i])
# r5 = temp (loaded value)
# r9 = base for large addresses (1000)

# -----------------------------
# Array initialization at base = 1004
# -----------------------------
addi r1  r1  r1  0     # r 3= 2
addi r3  r3  r3  128     # r 3= 2
addi r0  r0  r4   1004     # r4 = &a[0]
addi r0  r0  r9   1000     # r9 = 1000

# fill_loop:
store r4  r1  r0   0        # a[i] = i
addi  r4  r4  r4   4        # ptr += 4
addi  r1  r1  r1   1        # i++
blt   r1  r3  r0  -12       # if (i < 12) repeat fill_loop

marker
# -----------------------------
# Sum phase
# -----------------------------
addi r0  r0  r1   0        # i = 0
addi r0  r0  r2   0        # sum = 0
addi r0  r0  r4   1004     # r4 = &a[0]

# sum_loop:
load  r4  r0  r5   0        # r5 = a[i]
add   r2  r5  r2   0        # sum += r5
addi  r4  r4  r4   4        # ptr += 4
addi  r1  r1  r1   1        # i++
blt   r1  r3  r0  -16       # if (i < 12) repeat sum_loop

# -----------------------------
# Store sum
# 12 elements: sum = 0+1+...+11 = 66
# -----------------------------
store r0  r2  r0  200     ; [200] = sum   (pick any addr you want)
load  r0  r0  r20 200     ; r20 = sum     (read it back)

store r9  r0  r0   1000      # mem[1516] = sum


load r9   r0   r30  1000
load r9   r0   r30  1000
load r9   r0   r30  1000



