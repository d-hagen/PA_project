# ==== Verilog source file list for Icarus Verilog ====
# (Do not include .hex or .f files themselves)


cpu.v
pc.v


# ==== Stages====
Stages/alu.v
Stages/decode.v

# ==== Reg and Mem====
Memory/regfile.v
Memory/joined_mem.v




# ==== Pipeline registers ====
pipeline_brakes/fetch.v
pipeline_brakes/memory.v
pipeline_brakes/execute.v
pipeline_brakes/decode.v


# ==== Add ons====
Extras/Hazard_unit.v
Extras/Branch_Predictor.v

# ==== VM====

Extras/tlbs/itlb.v
Extras/tlbs/ptw_new.v


# ==== Caches====
Extras/Caches/Icache.v
Extras/Caches/Dcache.v

# ==== Testbench ====
tb_cpu.v
