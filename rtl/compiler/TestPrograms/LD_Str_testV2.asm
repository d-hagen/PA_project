; =========================
; Setup constants (imm <= 1023)
; =========================
addi  r2  r2  r2   1000        ; r2 = 1000 (0x000003E8)
addi  r3  r3  r3   200         ; r3 = 200  (0x000000C8)
addi  r4  r4  r4   300         ; r4 = 300  (0x0000012C)
addi  r5  r5  r5   400         ; r5 = 400  (0x00000190)
addi  r6  r6  r6   500         ; r6 = 500  (0x000001F4)

addi  r7  r7  r7   170         ; 0xAA
addi  r8  r8  r8   187         ; 0xBB
addi  r9  r9  r9   204         ; 0xCC
addi  r10 r10 r10  221         ; 0xDD

addi  r11 r11 r11  777         ; r11 = 777 (0x00000309)
addi  r12 r12 r12  90          ; r12 = 0x5A

; =========================
; Baseline aligned stores (line 0xA0..0xAF)
; =========================
store r0  r2   r0   160         ; [160] = 1000
store r0  r9   r0   164         ; [164] = 0x000000CC (for later mix)
store r0  r10  r0   168         ; [168] = 0x000000DD
store r0  r5   r0   172         ; [172] = 400

; =========================
; Unaligned WORD store inside one line (overlaps [160..163])
; =========================
store r0  r11  r0   161         ; [161..164] = 777 (crosses word boundary, same 16B line)

; =========================
; Unaligned WORD store crossing 16B line boundary (175 -> into next line)
; =========================
store r0  r11  r0   175         ; [175]=09 [176]=03 [177]=00 [178]=00

; =========================
; Byte stores (including line boundary case)
; =========================
strb  r0  r12  r0   163         ; [163] = 0x5A (overwrites within 161-store)
strb  r0  r7   r0   179         ; [179] = 0xAA (in second line word @176, lane3)

; =========================
; Loads: verify partial forwarding + cross-line assembly
; =========================
load  r0  r0   r20  160         ; should see mixed from 161-store + strb@163
load  r0  r0   r21  161         ; unaligned load within line (bytes 161..164)
load  r0  r0   r22  172         ; aligned load that is overlapped by store@175 on byte175
load  r0  r0   r23  175         ; unaligned cross-line load (bytes175..178)

; =========================
; Byte loads: verify per-byte forwarding
; =========================
ldb   r0  r0   r24  163         ; should be 0x5A
ldb   r0  r0   r25  175         ; should be 0x09
ldb   r0  r0   r26  176         ; should be 0x03
ldb   r0  r0   r27  179         ; should be 0xAA

; =========================
; Control loads (addresses not overlapped by any unaligned store)
; =========================
load  r0  r0   r28  168         ; should stay 0x000000DD (aligned, untouched by odd stores)
load  r0  r0   r29  164         ; depends on your init+777 overlap (see expected below)

; =========================
; Spacing / drain time
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
