// ===== Setup =====
addi r0 r0 r1  7        // r1 = 7
addi r0 r0 r2  9        // r2 = 9
addi r0 r0 r9  1        // r9 = 1

// ===== MUL1 starts =====
mul  r1 r2 r3  0        // r3 = 63 (MUL1 in flight)

// Try MUL2 immediately -> should trigger mul_issue_stall while MUL1 busy
mul  r1 r2 r4  0        // r4 = 63 (MUL2 must wait until MUL1 done)
mul  r1 r2 r20  0        // r4 = 63 (MUL2 must wait until MUL1 done)
mul  r1 r2 r21 0        // r4 = 63 (MUL2 must wait until MUL1 done)
mul  r1 r2 r22 0        // r4 = 63 (MUL2 must wait until MUL1 done)


// Keep WB busy with ALU writes so MUL1 (and/or MUL2) should hit WB-conflict at M5
add  r9  r9  r10 0      // r10 = 2
add  r10 r9  r11 0      // r11 = 3
add  r11 r9  r12 0      // r12 = 4
add  r12 r9  r13 0      // r13 = 5
add  r13 r9  r14 0      // r14 = 6
add  r14 r9  r15 0      // r15 = 7
add  r15 r9  r16 0      // r16 = 8
add  r16 r9  r17 0      // r17 = 9

// RAW dependency on MUL1 result (must stall until r3 written)
add  r3  r9  r5  0      // r5 = 64

// RAW dependency on MUL2 result (must stall until r4 written)
add  r4  r9  r6  0      // r6 = 64
