# ----------------------------------------
# Init small constants (no branches/loads)
# ----------------------------------------
addi r1  r1  r1  1       # r1 = 1
addi r2  r2  r2  2       # r2 = 2
addi r3  r3  r3  3       # r3 = 3
addi r4  r4  r4  4       # r4 = 4
addi r0  r0  r0  0       # bubble

# -------------------------------------------------------------
# Test 1: RAW on ra (consumer immediately after producer)
# r5 = r1 + r2; then r6 = r5 + r3 (must forward r5 -> ra)
# -------------------------------------------------------------
add  r1  r2  r5  0       # r5 = 1 + 2 = 3
add  r5  r3  r6  0       # r6 = 3 + 3 = 6  (forward r5 -> ra)
addi r0  r0  r0  0       # bubble

# -------------------------------------------------------------
# Test 2: RAW on rb (forward to rb)
# r7 = r2 + r3; then r8 = r1 + r7 (must forward r7 -> rb)
# -------------------------------------------------------------
add  r2  r3  r7  0       # r7 = 2 + 3 = 5
add  r1  r7  r8  0       # r8 = 1 + 5 = 6  (forward r7 -> rb)
addi r0  r0  r0  0       # bubble

# -------------------------------------------------------------
# Test 3: Same-dest chain (WAW + RAW on ra)
# r9 = r1 + r2; r9 = r9 + r3 (must forward prior r9)
# -------------------------------------------------------------
add  r1  r2  r9  0       # r9 = 3
add  r9  r3  r9  0       # r9 = 3 + 3 = 6  (forward r9 -> ra)
addi r0  r0  r0  0       # bubble

# -------------------------------------------------------------
# Test 4: Two-deep chain (EX->EX twice)
# r10 = r1 + r2; r11 = r10 + r3; r12 = r11 + r4
# -------------------------------------------------------------
add  r1  r2  r10 0       # r10 = 3
add  r10 r3  r11 0       # r11 = 3 + 3 = 6  (forward r10)
add  r11 r4  r12 0       # r12 = 6 + 4 = 10 (forward r11)
addi r0  r0  r0  0       # bubble

# -------------------------------------------------------------
# Test 5: SUB with back-to-back RAWs (both ra and rb)
# r13 = r3 - r1; r14 = r13 - r2; r15 = r14 - r13
# -------------------------------------------------------------
sub  r3  r1  r13 0       # r13 = 3 - 1 = 2
sub  r13 r2  r14 0       # r14 = 2 - 2 = 0 (forward r13 -> ra)
sub  r14 r13 r15 0       # r15 = 0 - 2 = -2 (mod 2^XLEN) (forward both)
addi r0  r0  r0  0       # bubble

# -------------------------------------------------------------
# Test 6: Mixed add/sub immediate RAW to both inputs
# r16 = r1 + r2; r17 = r16 - r16 = 0
# -------------------------------------------------------------
add  r1  r2  r16 0       # r16 = 3
sub  r16 r16 r17 0       # r17 = 0 (forward r16 to ra & rb)
addi r0  r0  r0  0       # bubble

# -------------------------------------------------------------
# Test 7: Fan-out (one result feeds two consumers in a row)
# r18 = r2 + r3; r19 = r18 + r1; r20 = r18 + r4
# -------------------------------------------------------------
add  r2  r3  r18 0       # r18 = 5
add  r18 r1  r19 0       # r19 = 5 + 1 = 6  (forward r18)
add  r18 r4  r20 0       # r20 = 5 + 4 = 9  (forward r18 again)
addi r0  r0  r0  0       # bubble

# -------------------------------------------------------------
# Test 8: No-forwarding baseline with bubble inserted
# r21 = r1 + r2; NOP; r22 = r21 + r3 (should still be correct)
# -------------------------------------------------------------
add  r1  r2  r21 0       # r21 = 3
addi r0  r0  r0  0       # bubble ensures WB path available
add  r21 r3  r22 0       # r22 = 3 + 3 = 6 (no hazard now)
addi r0  r0  r0  0       # bubble

# Expected (mod 2^XLEN): r6=6, r8=6, r9=6, r12=10, r14=0, r15=0xFFFF_FFFE,
#                        r17=0, r19=6, r20=9, r22=6
