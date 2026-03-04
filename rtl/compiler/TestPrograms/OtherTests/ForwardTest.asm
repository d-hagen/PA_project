marker
addi r0 r0 r1 0
addi r0 r0 r2 1

# r1 = r1 + 1 ; if (r1 < 1) should be false
addi r1 r1 r1 1          # r1 becomes 1
blt  r1 r2 r0  8         # if (r1 < 1) branch to BAD (skip next 2 instr)
                         # imm=8 means PC = PC+4+8 -> skip over good path

# GOOD path:
addi r0 r0 r10 111       # expected
blt  r0 r2 r0  8         # unconditional skip over BAD (0 < 1 always true)

# BAD path (should not execute):
addi r0 r0 r10 222

end
