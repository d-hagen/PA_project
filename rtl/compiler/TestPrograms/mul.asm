// ===== Setup =====
addi r0 r0 r1   7        // r1 = 7
addi r0 r0 r2   9        // r2 = 9
addi r0 r0 r9   1        // r9 = 1
addi r0 r0 r30  0        // r30 = base addr 0
addi r10 r10 r10 200     // r10 += 200  (depends on your encoding)

// ===== MUL chain (tests mul_issue_stall / busy gating) =====
mul  r1 r2 r3   0        // MUL1 -> r3
addi r0 r0 r3   1        // r3 = 1 (younger overwrite of r3; good ROB test)

mul  r1 r2 r4   0        // MUL2 -> r4 (should stall while MUL1 in-flight)
mul  r1 r2 r20  0        // MUL3 -> r20 (stalls behind MUL2)
mul  r1 r2 r21  0        // MUL4
mul  r1 r2 r22  0        // MUL5

// ===== Force WB conflicts right when M5 completes =====
addi r0 r0 r1   3
addi r0 r0 r1   4
addi r0 r0 r1   5
addi r0 r0 r1   6
load r0 r0 r14  48       // keep if you want WB conflict with loads
addi r0 r0 r1   8
addi r0 r0 r1   9

// ===== RAW deps on MUL results =====
add  r3  r20 r5  0       // needs r20 from MUL3, r3 is the renamed/latest
add  r4  r20 r6  0       // needs r4 from MUL2 and r20 from MUL3

// ===== ROB drain window =====
// 64 NOPs so all older ops definitely commit before we hit the final terminator
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0

addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0

addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0

addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0

addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0

addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0

addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0

addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0
addi r0 r0 r0  0