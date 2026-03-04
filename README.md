# Simple 32-bit Out-of-Order RISC CPU

A custom **32-bit RISC-style processor** implementing a small fixed-width ISA together with modern microarchitectural features including **branch prediction, register renaming, and speculative execution**.

---

# ISA Overview

All instructions are **32 bits** wide.

| opcode (6) | ra (5) | rb (5) | rd (5) | imm (11) |

Field description:

- **opcode [31:26]** – instruction opcode  
- **ra [25:21]** – source register A  
- **rb [20:16]** – source register B  
- **rd [15:11]** – destination register or control sub-operation  
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

Executed in an **independent multiply execution stage**.

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

The **rd field selects the operation**.

| rd | Instruction | Condition |
|---|---|---|
| 00000 | JMP | unconditional |
| 00001 | BEQ | ra == rb |
| 00010 | BLT | ra < rb |
| 00011 | BGT | ra > rb |

Branch targets use the **immediate offset**.

### JLx

Variant of `JMP` where:

```
rd[3:0] = 0000
rd[4]   = 1
```

Used for extended / link-style jumps.

---

## Privileged Instruction

| Instruction | Opcode | Description |
|---|---|---|
| IRET | 111111 | Return from interrupt/exception (admin mode only) |

Raises an exception if executed outside admin mode.

---

# Microarchitecture Features

The processor uses a **speculative out-of-order pipeline** with the following components.

### Branch Prediction
- Dynamic **branch predictor**
- Reduces control hazards

### Instruction Cache
- **I-Cache**
- Includes a **simple instruction prefetcher**

### Data Cache
- **D-Cache** for load/store operations

### Virtual Memory
- **ITLB** – Instruction TLB  
- **DTLB** – Data TLB  
- **Hardware Page Table Walker (PTW)**

### Register Renaming
- **Rename Unit** removes false dependencies

### Reorder Buffer
- **ROB** ensures in-order commit and precise exceptions

### Independent MUL Stage
- Dedicated multiply execution unit

---

# Summary

Features:

- 32-bit fixed instruction width
- 6-bit opcode ISA
- ALU, memory, control, and multiply instructions
- Out-of-order execution
- Branch prediction
- Instruction and data caches
- Virtual memory with hardware page table walker
- Register renaming and reorder buffer
