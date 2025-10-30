# A couple of values to see movement
addi r4  r4  r4  4       # r4 = 4
addi r15 r15 r15 15      # r15 = 15

# Jump over a write to r14
jmp  r0  r0  r0  2       # jump +2
addi r14 r14 r14 33      # should be skipped
addi r0  r0  r0  0       # bubble pad at target

# Another visible write after jump landed
addi r5  r5  r5  5       # executes (not skipped)
