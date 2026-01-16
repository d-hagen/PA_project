; -------------------------
; Seed known data
; -------------------------
addi  r3  r3  r3   200        ; r3 = 200  (0x000000C8)
addi  r4  r4  r4   300        ; r4 = 300  (0x0000012C)
addi  r5  r5  r5   400        ; r5 = 400  (0x00000190)
addi  r6  r6  r6   500        ; r6 = 500  (0x000001F4)

addi  r7  r7  r7   17         ; r7 = 17   (0x00000011)
addi  r7  r7  r7   17         ; r7 = 34   (0x00000022)
addi  r7  r7  r7   17         ; r7 = 51   (0x00000033)
addi  r7  r7  r7   17         ; r7 = 68   (0x00000044)
; r7 = 68, not a fancy pattern, but it makes [112] non-zero & deterministic

store r0  r3  r0   96         ; [96]  = 200
store r0  r4  r0   100        ; [100] = 300
store r0  r5  r0   104        ; [104] = 400
store r0  r6  r0   108        ; [108] = 500
store r0  r7  r0   112        ; [112] = 68   (ensures bytes 112..115 are known)

; -------------------------
; Aligned sanity loads (optional but nice)
; -------------------------
load  r0  r0  r21  96         ; r21 = [96]  (should be 200)
load  r0  r0  r22  100        ; r22 = [100] (should be 300)

; -------------------------
; Unaligned word loads (same-line inside 96..111)
; -------------------------
load  r0  r0  r25  97         ; reads bytes 97..100 (unaligned, same line)
load  r0  r0  r26  101        ; reads bytes 101..104 (unaligned, same line)

; -------------------------
; Cross-line word load (111 crosses into next 16B line)
; line0: 96..111, line1: 112..127
; -------------------------
load  r0  r0  r29  111        ; reads bytes 111..114 (cross-line)

; -------------------------
; Some filler so you can observe WB
; -------------------------
addi r1  r1  r1  1
addi r1  r1  r1  1
addi r1  r1  r1  1
marker
marker
