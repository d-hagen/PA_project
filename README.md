# Simple 32-bit RISC-like ISA Specification

## Overview
This document defines the **instruction encoding**, **register conventions**, and **operation groups** for a simple 32-bit processor architecture. It includes ALU, memory, and control operations.

---

## Instruction Encoding

Each instruction is **32 bits** wide, encoded as follows:

```text
| opcode (6) | ra (5) | rb (5) | rd (5) | imm (11) |
```

**Field breakdown:**
- **opcode [31:26]** – Operation code  
- **ra [25:21]** – Source register A  
- **rb [20:16]** – Source register B  
- **rd [15:11]** – Destination register  
- **imm [10:0]** – Immediate value (zero-extended)

**Immediates:** Currently treated as **unsigned 11-bit** values (zero-extended to 32 bits).

---

## Register Conventions

- **x0 (r0)**: Hard-wired to `0`.  
  - Reads always return `0`.  
  - Writes are ignored.

---

## ALU Group (Opcode ≤ `GT`)

| Instruction | Opcode (binary) | Operation | Description |
|--------------|----------------|------------|--------------|
| **ADD** | `000000` | `rd ← ra + rb` | Integer addition |
| **SUB** | `000001` | `rd ← ra − rb` | Integer subtraction |
| **AND** | `000010` | `rd ← ra & rb` | Bitwise AND |
| **OR**  | `000011` | `rd ← ra | rb` | Bitwise OR |
| **XOR** | `000100` | `rd ← ra ^ rb` | Bitwise XOR |
| **NOT** | `000101` | `rd ← ~ra` | Bitwise NOT (rb ignored) |
| **SHL** | `000110` | `rd ← ra << (rb[4:0])` | Logical left shift by low 5 bits of rb |
| **SHR** | `000111` | `rd ← ra >> (rb[4:0])` | Logical right shift (or arithmetic, depending on ALU) |
| **ADDI** | `001000` | `rd ← ra + imm` | Add immediate (imm zero-extended) |
| **LT** | `001001` | `rd ← (ra < rb) ? 1 : 0` | Set-on-less-than |
| **GT** | `001010` | `rd ← (ra > rb) ? 1 : 0` | Set-on-greater-than |

> **Note:** Comparison operations are currently **unsigned**, unless the ALU internally casts operands to signed.

---

## Memory Operations

| Instruction | Opcode (binary) | Operation | Description |
|--------------|----------------|------------|--------------|
| **LOAD** | `001011` | `rd ← MEM[ ra + imm ]` | Load word from memory |
| **STORE** | `001100` | `MEM[ ra + imm ] ← rb` | Store word to memory |

- The **address** is computed as `ra + imm` using the ALU.  
- For **LOAD**, memory is assumed to be **combinationally readable**.  
- For **STORE**, data is taken from the **rb** register (pipeline should pass `D_b2` to MEM stage).

---

## Control Operations

Control instructions share the **opcode `001101`**, with the **rd field** specifying the sub-operation.

| Sub-op (rd) | Mnemonic | Condition | Operation |
|--------------|-----------|------------|------------|
| `00000` | **JMP** | Unconditional | `pc ← pc + imm` |
| `00001` | **BEQ** | `ra == rb` | `pc ← pc + imm` |
| `00010` | **BLT** | `ra < rb` | `pc ← pc + imm` |
| `00011` | **BGT** | `ra > rb` | `pc ← pc + imm` |

---

## Summary

This ISA defines:
- 6-bit opcodes  
- 32-bit fixed-width instructions  
- 11-bit zero-extended immediates  
- One special register (`r0` = constant 0)  
- ALU, memory, and control operation groups  

---

© 2025 — Custom RISC ISA Specification
