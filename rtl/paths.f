# ==== Verilog source file list for Icarus Verilog ====
# (Do not include .hex or .f files themselves)

memory.v
cpu.v
alu.v
decode.v
pc.v
regfile.v
instruct_reg.v

# ==== Pipeline registers ====
pipeline_brakes/fetch.v
pipeline_brakes/memory.v
pipeline_brakes/execute.v
pipeline_brakes/decode.v
pipeline_brakes/Hazard_unit.v


# ==== Testbench ====
tb_cpu.v
