# ==== Verilog source file list for Icarus Verilog ====
# (Do not include .hex or .f files themselves)


cpu.v
pc.v


# ==== Stages and Registers====
Stages/memory.v
Stages/alu.v
Stages/decode.v
Stages/regfile.v
Stages/instruct_reg.v

# ==== Pipeline registers ====
pipeline_brakes/fetch.v
pipeline_brakes/memory.v
pipeline_brakes/execute.v
pipeline_brakes/decode.v


# ==== Add ons====
Extras/Hazard_unit.v
Extras/Branch_Predictor.v


# ==== Testbench ====
tb_cpu.v
