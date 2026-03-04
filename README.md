# Simple 32-bit Out-of-Order RISC CPU

A custom **32-bit RISC-style processor** implementing a small fixed-width ISA together with modern microarchitectural features such as **branch prediction, register renaming, speculative execution, caches, and virtual memory**.

---

# ISA Overview

All instructions are **32 bits** wide.

| opcode (6) | ra (5) | rb (5) | rd (5) | imm (11) |

Field description:

- **opcode [31:26]** – instruction opcode  
- **ra [25:21]** – source register A  
- **rb [20:16]** – source register B  
- **rd [15:11]** – destination register or control sub-op  
- **imm [10:0]** – immediate / offset

---

# Register Convention

- **r0 (x0)** is hardwired to **0**
- Reads always return **0**
- Writes are ignored

---

# Instruction Set

## ALU Operations

| Instruction | Opcode | Operation |
|---|---|---|
| ADD | 000000 | rd ← ra + rb |
| SUB | 000001 | rd ← ra − rb |
| AND | 000010 | rd ← ra & rb |
| OR  | 000011 | rd ← ra \| rb |
| XOR | 000100 | rd ← ra ^ rb |
| NOT | 000101 | rd ← ~ra |
| SHL | 000110 | rd ← ra << rb[4:0] |
| SHR | 000111 | rd ← ra >> rb[4:0] |
| ADDI | 001000 | rd ← ra + imm |
| LT | 001001 | rd ← (ra < rb) |
| GT | 001010 | rd ← (ra > rb) |

---

## Multiply

| Instruction | Opcode | Operation |
|---|---|---|
| MUL | 001110 | rd ← ra * rb |

Executed in an **independent multiply stage**.

---

## Memory Operations

Address calculation:

```
addr = ra + imm
```

| Instruction | Opcode Pattern | Operation |
|---|---|---|
| LOAD.W  | 0_01011 | rd ← MEM[addr] |
| LOAD.B  | 1_01011 | rd ← MEM8[addr] |
| STORE.W | 0_01100 | MEM[addr] ← rb |
| STORE.B | 1_01100 | MEM8[addr] ← rb |

`opcode[5]` selects **word or byte access**.

---

## Control Flow

All control instructions use:

```
opcode = 001101
```

| rd | Instruction | Condition |
|---|---|---|
| 00000 | JMP | unconditional |
| 00001 | BEQ | ra == rb |
| 00010 | BLT | ra < rb |
| 00011 | BGT | ra > rb |

### JLx

Variant of `JMP` where:

```
rd[3:0] = 0000
rd[4]   = 1
```

---

## Privileged Instruction

| Instruction | Opcode | Description |
|---|---|---|
| IRET | 111111 | Return from interrupt/exception (admin mode only) |

---

# Microarchitecture Features

### Branch Predictor
Dynamic **branch prediction** reduces control hazards.

### Instruction Cache
- **I-Cache**
- Includes **simple instruction prefetch**

### Data Cache
- **D-Cache** for load/store operations.

### Virtual Memory
- **ITLB** – Instruction TLB  
- **DTLB** – Data TLB  
- **Hardware Page Table Walker (PTW)**

### Register Renaming
- **Rename Unit** removes false dependencies.

### Reorder Buffer
- **ROB** enables speculative execution and ensures **in-order commit**.

### Independent MUL Stage
- Dedicated multiply execution unit.

---

# Assembling Programs

Programs are written in a simple assembly format:

```
opcode ra rb rd imm
```

Example:

```
addi r1 r0 r1 10
add  r2 r1 r1 0
store r0 r2 r0 0
```

The provided **Python assembler**:

- Encodes instructions
- Generates required **NOPs and IRET handlers**
- Builds **2-level page tables**
- Outputs a **memory image (`program.hex`)**

### Compile Assembly

```
python3 compiler/assembler.py program.asm -o rtl/program.hex
```

The simulator loads instructions from this file into memory.

---

# Running the CPU Simulation

The project uses **Icarus Verilog** with the file list `paths.f`.

### Compile RTL

```
cd rtl
iverilog -g2012 -f paths.f -o cpu_sim
```

### Run Simulation

```
vvp cpu_sim
```

Optional waveform viewing:

```
gtkwave dump.vcd
```

---

# Project Structure

```
rtl/
 ├─ cpu/
 ├─ Stages/
 ├─ Memory/
 ├─ pipeline_brakes/
 ├─ Extras/
 │   ├─ Branch_Predictor
 │   ├─ rename
 │   ├─ storeBuffer
 │   ├─ exceptionHandler
 │   ├─ tlbs/
 │   └─ Caches/
 ├─ paths.f
 └─ tb_cpu.v
```

---

# Summary

Features:

- 32-bit fixed-width ISA
- Out-of-order execution
- Register renaming
- Reorder buffer
- Branch predictor
- Instruction cache with prefetch
- Data cache
- Virtual memory (ITLB, DTLB, PTW)
- Independent multiply execution stage
