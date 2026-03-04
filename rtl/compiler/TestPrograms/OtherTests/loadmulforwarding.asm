// ==========================================================
// Combined LOAD->ADD and LOAD->MUL forwarding test
// with big STORE/LOAD storm to thrash:
//   - D-cache (capacity/conflict pressure)
//   - DTLB (8 entries, 4KB pages -> touch >=16 distinct pages)
//   - Store buffer (many outstanding stores)
//
// Key idea:
//   1) Store A,B at a "known" location
//   2) Hammer lots of other pages with stores+loads (evict cache/TLB, fill SB)
//   3) Load A,B (now likely cache miss + DTLB miss)
//   4) Immediately consume via ADD and MUL (tests load->op wakeup/forwarding)
// ==========================================================

// ===== Setup base address and constants =====
addi r0  r0  r30  0        // r30 = base addr (scratch RAM)
addi r0  r0  r9   6        // r9  = 6   (A)
addi r0  r0  r10  7        // r10 = 7   (B)
addi r0  r0  r12  1        // r12 = 1   (small constant)
addi r0  r0  r11  1020     // r11 = 1024 (used to build 4KB strides)

// ===== Store known values A,B (these are what we will load-use later) =====
store r30 r9   r0  0        // MEM[r30 + 0] = 6
store r30 r10  r0  4        // MEM[r30 + 4] = 7

// ----------------------------------------------------------
// Build a thrash pointer r15 = r30 + 8192 (2 pages away)
// (avoid clobbering the A/B words at r30+0,4)
// 8192 = 8 * 1024
// ----------------------------------------------------------
addi r30 r30 r15  0
add  r15 r11 r15  0
add  r15 r11 r15  0
add  r15 r11 r15  0
add  r15 r11 r15  0
add  r15 r11 r15  0
add  r15 r11 r15  0
add  r15 r11 r15  0
add  r15 r11 r15  0        // r15 = r30 + 8192

// ----------------------------------------------------------
// THRASH REGION: touch 16 distinct 4KB pages (> 8-entry DTLB)
// For each page:
//   - do multiple STORES (pressure store buffer + dirty cache lines)
//   - do multiple LOADS   (pressure cache + ensure TLB fill path exercised)
// Page stride = 4096 = 4 * 1024  (we do 4 adds of r11)
// ----------------------------------------------------------

// ---- Page 0 ----
store r15 r9   r0  0
store r15 r10  r0  64
store r15 r9   r0  128
store r15 r10  r0  192
load  r15 r0   r20 0
load  r15 r0   r21 64
load  r15 r0   r22 128
load  r15 r0   r23 192

// advance r15 += 4096 (4KB)
add  r15 r11 r15 0
add  r15 r11 r15 0
add  r15 r11 r15 0
add  r15 r11 r15 0

// ---- Page 1 ----
store r15 r9   r0  0
store r15 r10  r0  64
store r15 r9   r0  128
store r15 r10  r0  192
load  r15 r0   r20 0
load  r15 r0   r21 64
load  r15 r0   r22 128
load  r15 r0   r23 192

add  r15 r11 r15 0
add  r15 r11 r15 0
add  r15 r11 r15 0
add  r15 r11 r15 0

// ---- Page 2 ----
store r15 r9   r0  0
store r15 r10  r0  64
store r15 r9   r0  128
store r15 r10  r0  192
load  r15 r0   r20 0
load  r15 r0   r21 64
load  r15 r0   r22 128
load  r15 r0   r23 192

add  r15 r11 r15 0
add  r15 r11 r15 0
add  r15 r11 r15 0
add  r15 r11 r15 0

// ---- Page 3 ----
store r15 r9   r0  0
store r15 r10  r0  64
store r15 r9   r0  128
store r15 r10  r0  192
load  r15 r0   r20 0
load  r15 r0   r21 64
load  r15 r0   r22 128
load  r15 r0   r23 192

add  r15 r11 r15 0
add  r15 r11 r15 0
add  r15 r11 r15 0
add  r15 r11 r15 0

// ---- Page 4 ----
store r15 r9   r0  0
store r15 r10  r0  64
store r15 r9   r0  128
store r15 r10  r0  192
load  r15 r0   r20 0
load  r15 r0   r21 64
load  r15 r0   r22 128
load  r15 r0   r23 192

add  r15 r11 r15 0
add  r15 r11 r15 0
add  r15 r11 r15 0
add  r15 r11 r15 0

// ---- Page 5 ----
store r15 r9   r0  0
store r15 r10  r0  64
store r15 r9   r0  128
store r15 r10  r0  192
load  r15 r0   r20 0
load  r15 r0   r21 64
load  r15 r0   r22 128
load  r15 r0   r23 192

add  r15 r11 r15 0
add  r15 r11 r15 0
add  r15 r11 r15 0
add  r15 r11 r15 0

// ---- Page 6 ----
store r15 r9   r0  0
store r15 r10  r0  64
store r15 r9   r0  128
store r15 r10  r0  192
load  r15 r0   r20 0
load  r15 r0   r21 64
load  r15 r0   r22 128
load  r15 r0   r23 192

add  r15 r11 r15 0
add  r15 r11 r15 0
add  r15 r11 r15 0
add  r15 r11 r15 0

// ---- Page 7 ----
store r15 r9   r0  0
store r15 r10  r0  64
store r15 r9   r0  128
store r15 r10  r0  192
load  r15 r0   r20 0
load  r15 r0   r21 64
load  r15 r0   r22 128
load  r15 r0   r23 192

add  r15 r11 r15 0
add  r15 r11 r15 0
add  r15 r11 r15 0
add  r15 r11 r15 0

// ---- Page 8 ----
store r15 r9   r0  0
store r15 r10  r0  64
store r15 r9   r0  128
store r15 r10  r0  192
load  r15 r0   r20 0
load  r15 r0   r21 64
load  r15 r0   r22 128
load  r15 r0   r23 192

add  r15 r11 r15 0
add  r15 r11 r15 0
add  r15 r11 r15 0
add  r15 r11 r15 0

// ---- Page 9 ----
store r15 r9   r0  0
store r15 r10  r0  64
store r15 r9   r0  128
store r15 r10  r0  192
load  r15 r0   r20 0
load  r15 r0   r21 64
load  r15 r0   r22 128
load  r15 r0   r23 192

add  r15 r11 r15 0
add  r15 r11 r15 0
add  r15 r11 r15 0
add  r15 r11 r15 0

// ---- Page 10 ----
store r15 r9   r0  0
store r15 r10  r0  64
store r15 r9   r0  128
store r15 r10  r0  192
load  r15 r0   r20 0
load  r15 r0   r21 64
load  r15 r0   r22 128
load  r15 r0   r23 192

add  r15 r11 r15 0
add  r15 r11 r15 0
add  r15 r11 r15 0
add  r15 r11 r15 0

// ---- Page 11 ----
store r15 r9   r0  0
store r15 r10  r0  64
store r15 r9   r0  128
store r15 r10  r0  192
load  r15 r0   r20 0
load  r15 r0   r21 64
load  r15 r0   r22 128
load  r15 r0   r23 192

add  r15 r11 r15 0
add  r15 r11 r15 0
add  r15 r11 r15 0
add  r15 r11 r15 0

// ---- Page 12 ----
store r15 r9   r0  0
store r15 r10  r0  64
store r15 r9   r0  128
store r15 r10  r0  192
load  r15 r0   r20 0
load  r15 r0   r21 64
load  r15 r0   r22 128
load  r15 r0   r23 192

add  r15 r11 r15 0
add  r15 r11 r15 0
add  r15 r11 r15 0
add  r15 r11 r15 0

// ---- Page 13 ----
store r15 r9   r0  0
store r15 r10  r0  64
store r15 r9   r0  128
store r15 r10  r0  192
load  r15 r0   r20 0
load  r15 r0   r21 64
load  r15 r0   r22 128
load  r15 r0   r23 192

add  r15 r11 r15 0
add  r15 r11 r15 0
add  r15 r11 r15 0
add  r15 r11 r15 0

// ---- Page 14 ----
store r15 r9   r0  0
store r15 r10  r0  64
store r15 r9   r0  128
store r15 r10  r0  192
load  r15 r0   r20 0
load  r15 r0   r21 64
load  r15 r0   r22 128
load  r15 r0   r23 192

add  r15 r11 r15 0
add  r15 r11 r15 0
add  r15 r11 r15 0
add  r15 r11 r15 0

// ---- Page 15 ----
store r15 r9   r0  0
store r15 r10  r0  64
store r15 r9   r0  128
store r15 r10  r0  192
load  r15 r0   r20 0
load  r15 r0   r21 64
load  r15 r0   r22 128
load  r15 r0   r23 192

// ----------------------------------------------------------
// Now A/B should be cold (likely DTLB miss + cache miss).
// Do the real dependency test *immediately* after the loads.
// ----------------------------------------------------------
load  r30 r0   r23 0        // r23 = A  (cold load)
load  r30 r0   r24 4        // r24 = B  (cold load)

// ===== Test 1: LOAD -> ADD forwarding / stalling =====
add   r23 r24  r25 0        // r25 = 6 + 7 = 13

// ===== Test 2: LOAD -> MUL forwarding / stalling =====
mul   r23 r24  r26 0        // r26 = 6 * 7 = 42

// ===== Consume results (keep them live) =====
add   r25 r9   r27 0        // r27 = 13 + 6 = 19
add   r26 r9   r28 0        // r28 = 42 + 6 = 48

// ===== Optional drain window =====
addi r0  r0   r0  0
addi r0  r0   r0  0
addi r0  r0   r0  0
addi r0  r0   r0  0
addi r0  r0   r0  0
addi r0  r0   r0  0
addi r0  r0   r0  0
addi r0  r0   r0  0

// Expected architectural results at end:
// r23 = 6
// r24 = 7
// r25 = 13
// r26 = 42
// r27 = 19
// r28 = 48
