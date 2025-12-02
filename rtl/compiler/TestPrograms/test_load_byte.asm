############################################
#   Initialize registers
############################################

addi r1  r1  r1   1      # r1 = 1 (base addr for bytes)
addi r2  r2  r2   2      # r2 = 2
addi r3  r3  r3   3      # r3 = 3
addi r4  r4  r4   4      # r4 = 4
addi r5  r5  r5   5      # r5 = 5

addi r8  r8  r8   8      # r8 = 8 (base addr for words)
addi r9  r9  r9   9      # r9 = 9 (data to store)
addi r10 r10 r10 10      # r10 = 10
addi r11 r11 r11 11      # r11 = 11

############################################
#   BYTE STORES
############################################
strb r1  r2  r0   0      # MEM[1 + 0] = 0x02
strb r1  r3  r0   1      # MEM[1 + 1] = 0x03
strb r1  r4  r0   2      # MEM[1 + 2] = 0x04
strb r1  r5  r0   3      # MEM[1 + 3] = 0x05

############################################
#   WORD STORE
############################################
store r8  r9  r0   0     # MEM[8] = 9   (full word write)
store r8  r10 r0   4     # MEM[12] = 10 (full word write)

############################################
#   MIXED BYTE + WORD LOADS
############################################

# Load the stored bytes
ldb  r1  r0  r20  0      # r20 = 2
ldb  r1  r0  r21  1      # r21 = 3
ldb  r1  r0  r22  2      # r22 = 4
ldb  r1  r0  r23  3      # r23 = 5

# Load the stored words
load r8  r0  r24  0      # r24 = 9
load r8  r0  r25  4      # r25 = 10

############################################
#   Overwrite bytes at same addresses to verify mixing
############################################
addi r6  r6  r6   6      # r6 = 6
addi r7  r7  r7   7      # r7 = 7

strb  r8  r6  r0   0     # MEM[8 + 0] = 0x06  (overwrite word-start byte)
strb  r8  r7  r0   1     # MEM[8 + 1] = 0x07

############################################
#   Load word again to see byte overwrite effect
############################################
load r8  r0  r26  0      # r26 = NEW word at addr 8 after byte overwrites

############################################
#   Combine results to make correctness visible
############################################
add  r20 r21 r30  0      # r30 = 2 + 3 = 5
add  r22 r23 r31  0      # r31 = 4 + 5 = 9
