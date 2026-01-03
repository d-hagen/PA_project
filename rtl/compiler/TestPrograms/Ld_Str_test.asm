addi  r2  r2  r2   1000
addi  r3  r3  r3   200
addi  r4  r4  r4   300
addi  r5  r5  r5   400
addi  r6  r6  r6   500

store  r2  r2  r0   160      ; [160] = 1000   (was 100)
store  r0  r3  r0   96       ; [96]  = 200    (was 48)
store  r0  r4  r0   100      ; [100] = 300    (was 52)
store  r0  r5  r0   104      ; [104] = 400    (was 56)
store  r0  r6  r0   108      ; [108] = 500    (was 60)

load   r2  r0  r20  160      ; r20 = [160] = 1000 (was 100)
load   r0  r0  r21  96       ; r21 = [96]  = 200  (was 48)
load   r0  r0  r22  100      ; r22 = [100] = 300  (was 52)
load   r0  r0  r23  104      ; r23 = [104] = 400  (was 56)
load   r0  r0  r24  108      ; r24 = [108] = 500  (was 60)

addi r1  r1  r1  1       # r1 = 1
addi r1  r1  r1  1       # r1 = 1
addi r1  r1  r1  1       # r1 = 1
addi r1  r1  r1  1       # r1 = 1
addi r1  r1  r1  1       # r1 = 1
addi r1  r1  r1  1       # r1 = 1
addi r1  r1  r1  1       # r1 = 1
addi r1  r1  r1  1       # r1 = 1
addi r1  r1  r1  1       # r1 = 1
addi r1  r1  r1  1       # r1 = 1
addi r1  r1  r1  1       # r1 = 1
addi r1  r1  r1  1       # r1 = 1
addi r1  r1  r1  1       # r1 = 1


