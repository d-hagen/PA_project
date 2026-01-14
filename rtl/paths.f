# ==== Verilog source file list for Icarus Verilog ====
# (Do not include .hex or .f files themselves)


cpu.v
pc.v


# ==== Stages====
Stages/alu.v
Stages/decode.v
Stages/mul.v

# ==== Reg and Mem====
Memory/regfile.v
Memory/joined_mem.v
Memory/ROB.v





# ==== Pipeline registers ====
pipeline_brakes/F_to_D.v
pipeline_brakes/MEM_to_WB.v
pipeline_brakes/EX_to_MEM.v
pipeline_brakes/D_to_EX.v


# ==== Add ons====
Extras/Hazard_unit.v
Extras/Branch_Predictor.v
Extras/storeBuffer.v
Extras/rename.v
Extras/exceptionHandler.v




# ==== VM====

Extras/tlbs/itlb.v
Extras/tlbs/dtlb.v
Extras/tlbs/ptw_new.v


# ==== Caches====
Extras/Caches/Icache.v
Extras/Caches/Dcache.v

# ==== Testbench ====
tb_fast.v          
