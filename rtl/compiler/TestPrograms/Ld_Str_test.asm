xor   r2  r2  r2   0
addi  r2  r2  r2   300     # r2 = 300 -> expect 44

xor   r3  r3  r3   0
addi  r3  r3  r3   421     # r3 = 421 -> expect 165

xor   r4  r4  r4   0
addi  r4  r4  r4   256     # r4 = 256 -> expect 0

xor   r5  r5  r5   0
addi  r5  r5  r5   511     # r5 = 511 -> expect 255

# Store only a byte from each (addresses 40..43)
strb  r0  r2  r0   40      # MEM[40] = r2 & 0xFF = 44
strb  r0  r3  r0   41      # MEM[41] = r3 & 0xFF = 165
strb  r0  r4  r0   42      # MEM[42] = r4 & 0xFF = 0
strb  r0  r5  r0   43      # MEM[43] = r5 & 0xFF = 255

addi  r0  r0  r0   0       # bubble NOP
addi  r0  r0  r0   0       # bubble NOP

# Load bytes back
ldb   r0  r0  r20  40      # r30 = 44
ldb   r0  r0  r21  41      # r31 = 165
ldb   r0  r0  r22  42      # r32 = 0
ldb   r0  r0  r23  43      # r33 = 255


