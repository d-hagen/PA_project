// ==========================================================
// Combined STORE -> LOAD -> (ADD + MUL) forwarding / stall test
// - Stores deterministic values to memory
// - Loads feed an ADD (load->add forwarding)
// - Loads feed a MUL (load->mul forwarding)
// - Results are further consumed so they can't be optimized away
// ==========================================================

// ===== Setup base address and constants =====
addi r0  r0  r30  0        // r30 = base addr (scratch RAM)
addi r0  r0  r9   6        // r9  = 6   (A)
addi r0  r0  r10  7        // r10 = 7   (B)

// ===== Store known values =====
store r30 r9   r0  0        // MEM[r30 + 0] = 6
store r30 r10  r0  4        // MEM[r30 + 4] = 7

// ===== Load values back (A,B) =====
load  r30 r0   r23 0        // r23 = A = 6
load  r30 r0   r24 4        // r24 = B = 7

// ===== Test 1: LOAD -> ADD forwarding / stalling =====
add   r23 r24  r25 0        // r25 = A + B = 13

// ===== Test 2: LOAD -> MUL forwarding / stalling =====
mul   r23 r24  r26 0        // r26 = A * B = 42

// ===== Consume both results (keep them live / check chaining) =====
add   r25 r9   r27 0        // r27 = 13 + 6 = 19
add   r26 r9   r28 0        // r28 = 42 + 6 = 48

// ===== Optional drain window (commit/ROB clarity) =====
addi r0  r0  r0  0
addi r0  r0  r0  0
addi r0  r0  r0  0
addi r0  r0  r0  0
addi r0  r0  r0  0
addi r0  r0  r0  0
addi r0  r0  r0  0
addi r0  r0  r0  0

// Expected architectural results:
// r23 = 6
// r24 = 7
// r25 = 13
// r26 = 42
// r27 = 19
// r28 = 48
