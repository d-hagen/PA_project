; =========================
; Init values (imm <= 1023)
; =========================
addi  r2  r0  r2   1000
addi  r3  r0  r3   200
addi  r4  r0  r4   300
addi  r5  r0  r5   400
addi  r6  r0  r6   500

addi  r7  r0  r7   170        ; 0xAA
addi  r8  r0  r8   187        ; 0xBB
addi  r9  r0  r9   204        ; 0xCC
addi  r10 r0  r10  221        ; 0xDD

; =========================
; Aligned base stores
; =========================
store  r0  r2  r0   160        ; [160] = 1000   line base (0xA0)
store  r0  r3  r0   164        ; [164] = 200
store  r0  r4  r0   168        ; [168] = 300
store  r0  r5  r0   172        ; [172] = 400

; =========================
; Byte stores (strb) into existing words
; =========================
strb   r0  r7  r0   161        ; overwrite byte at [161] (inside word @160)
strb   r0  r8  r0   162        ; overwrite byte at [162]
strb   r0  r9  r0   167        ; overwrite byte at [167] (inside word @164)
strb   r0  r10 r0   168        ; overwrite byte at [168] (inside word @168)

; =========================
; Unaligned word stores (split across words)
; =========================
addi   r11 r0  r11  777        ; pattern word <= 1023
store  r0  r11 r0   161        ; spans [161..164] (overlaps bytes in two words)
store  r0  r11 r0   175        ; spans [175..178] crosses 16B line (160..175 -> 176..191)

; =========================
; Forwarding: immediate unaligned loads
; =========================
load   r0  r0  r20  161        ; unaligned load (should merge/forward bytes)
load   r0  r0  r21  162        ; unaligned load overlap
load   r0  r0  r22  175        ; cross-line unaligned load (forward + assemble)
load   r0  r0  r23  176        ; overlaps second word of the split store

; =========================
; Byte loads (ldb) with forwarding
; =========================
ldb    r0  r0  r24  161        ; forwarded byte
ldb    r0  r0  r25  162        ; forwarded byte
ldb    r0  r0  r26  175        ; forwarded byte (line end)
ldb    r0  r0  r27  176        ; forwarded byte (next line)

; =========================
; Mixed overlap: byte store then word load
; =========================
addi   r12 r0  r12  90         ; 0x5A
strb   r0  r12 r0   163        ; change a single byte inside prior unaligned store footprint
load   r0  r0  r28  161        ; must reflect newest byte for [163] and older bytes for others

; =========================
; Drain spacing
; =========================
addi r1  r1  r1  1
addi r1  r1  r1  1
addi r1  r1  r1  1
addi r1  r1  r1  1
addi r1  r1  r1  1
addi r1  r1  r1  1
addi r1  r1  r1  1
addi r1  r1  r1  1
addi r1  r1  r1  1
addi r1  r1  r1  1
addi r1  r1  r1  1
addi r1  r1  r1  1
addi r1  r1  r1  1

; =========================
; Post-drain verification loads
; =========================
load   r0  r0  r29  160        ; final word @160 after byte+unaligned stores
load   r0  r0  r30  164        ; final word @164 after overlaps
load   r0  r0  r31  172        ; untouched aligned control (should still be 400)
