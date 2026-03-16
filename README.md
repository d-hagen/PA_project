# 32-bit Out-of-Order RISC CPU

A custom **32-bit RISC-style processor** implementing a fixed-width ISA with modern microarchitectural features including out-of-order execution, branch prediction, register renaming, caches, and virtual memory. Built in SystemVerilog and simulated with Icarus Verilog.

---

# Instruction Set Architecture (ISA)

All instructions are **32 bits** wide with a fixed encoding:

| opcode [31:26] | ra [25:21] | rb [20:16] | rd [15:11] | imm [10:0] |
|---|---|---|---|---|
| 6 bits | 5 bits | 5 bits | 5 bits | 11 bits |

- **opcode** – selects the operation
- **ra** – source register A
- **rb** – source register B
- **rd** – destination register (or control sub-op for branches)
- **imm** – immediate value / memory offset

**r0** is hardwired to zero — reads always return 0, writes are ignored.

---

# Instruction Set

## ALU Operations

| Instruction | Opcode   | Effect                        |
|-------------|----------|-------------------------------|
| ADD         | `000000` | rd ← ra + rb                  |
| SUB         | `000001` | rd ← ra − rb                  |
| AND         | `000010` | rd ← ra & rb                  |
| OR          | `000011` | rd ← ra \| rb                 |
| XOR         | `000100` | rd ← ra ^ rb                  |
| NOT         | `000101` | rd ← ~ra                      |
| SHL         | `000110` | rd ← ra << rb[4:0]            |
| SHR         | `000111` | rd ← ra >> rb[4:0]            |
| ADDI        | `001000` | rd ← ra + imm                 |
| LT          | `001001` | rd ← 1 if ra < rb, else 0    |
| GT          | `001010` | rd ← 1 if ra > rb, else 0    |

## Multiply

| Instruction | Opcode   | Effect       |
|-------------|----------|--------------|
| MUL         | `001110` | rd ← ra * rb |

Runs in a **dedicated independent multiply stage**, separate from the main ALU pipeline.

## Memory Operations

Address is computed as `addr = ra + imm`.
`opcode[5]` selects word (`0`) or byte (`1`) access.

| Instruction | Opcode    | Effect                          |
|-------------|-----------|---------------------------------|
| LOAD.W      | `0_01011` | rd ← MEM[addr] (32-bit word)   |
| LOAD.B      | `1_01011` | rd ← MEM[addr] (8-bit byte)    |
| STORE.W     | `0_01100` | MEM[addr] ← rb (32-bit word)   |
| STORE.B     | `1_01100` | MEM[addr] ← rb (8-bit byte)    |

## Control Flow

All branches share `opcode = 001101`. The `rd` field selects the variant.

| rd      | Instruction | Condition          | Effect                            |
|---------|-------------|--------------------|-----------------------------------|
| `00000` | JMP         | Unconditional      | PC ← ra + imm                    |
| `00001` | BEQ         | ra == rb           | PC ← ra + imm if equal           |
| `00010` | BLT         | ra < rb            | PC ← ra + imm if less than       |
| `00011` | BGT         | ra > rb            | PC ← ra + imm if greater than    |
| `1xxxx` | JLx         | Unconditional      | PC ← ra + imm, link return addr  |

## Privileged

| Instruction | Opcode   | Effect                                        |
|-------------|----------|-----------------------------------------------|
| IRET        | `111111` | Return from interrupt/exception (admin only)  |

---

# Microarchitecture

## Pipeline

5-stage in-order pipeline with out-of-order execution support:

```
Fetch → Decode → Execute → Memory → Writeback
```

Pipeline registers: `F_to_D` → `D_to_EX` → `EX_to_MEM` → `MEM_to_WB`

---

## Instruction Cache (I-Cache)

| Property        | Value                          |
|-----------------|--------------------------------|
| Entries         | 4 lines, fully associative     |
| Line size       | 16 bytes (4 × 32-bit words)    |
| Total size      | 64 bytes                       |
| Replacement     | FIFO                           |
| Prefetch        | Yes — next sequential line prefetched automatically after a fill |

On a miss the pipeline stalls until the line is fetched from memory. On a hit, the cache immediately issues a prefetch for the next line if it is not already present.

---

## Data Cache (D-Cache)

| Property        | Value                          |
|-----------------|--------------------------------|
| Entries         | 4 lines, fully associative     |
| Line size       | 16 bytes (byte-addressable)    |
| Total size      | 64 bytes                       |
| Replacement     | FIFO                           |
| Write policy    | Write-back with dirty bits     |
| Writeback       | Dirty lines evicted to memory on replacement |
| Cross-line load | Supported — word reads spanning two cache lines handled correctly |
| Store forwarding| Loads can bypass the cache via the store buffer |

---

## Branch Predictor

| Property     | Value                                              |
|--------------|----------------------------------------------------|
| Type         | Branch Target Buffer (BTB), fully associative      |
| Entries      | 8                                                  |
| Replacement  | FIFO (newest entry at index 0)                     |
| Direction    | 1-bit last-outcome — remembers taken/not-taken     |
| Target       | Stores resolved target PC per branch               |
| Miss default | Predict not-taken, fall through to PC+4            |
| Update       | Resolved at Execute stage, updates direction and target |

---

## Out-of-Order Execution

### Register Renaming
Eliminates false WAR (write-after-read) and WAW (write-after-write) data dependencies, allowing more instructions to execute in parallel.

### Reorder Buffer (ROB)
Tracks all in-flight instructions and ensures **in-order commit** even when instructions complete out of order. Enables safe speculative execution — mis-speculated instructions are rolled back before committing.

### Store Buffer
Pending stores are held in a store buffer and drained to the D-Cache in order. Loads can forward directly from the store buffer without going to the cache.

---

## Virtual Memory

| Component | Description                                              |
|-----------|----------------------------------------------------------|
| ITLB      | Instruction TLB — caches virtual-to-physical translations for fetch |
| DTLB      | Data TLB — caches translations for load/store           |
| PTW       | Hardware Page Table Walker — automatically walks 2-level page tables on TLB miss |

---

## Hazard Handling

A dedicated **Hazard Unit** detects and resolves data and control hazards, issuing stalls or forwarding signals as needed.

---

# Assembling Programs

Programs are written in a plain-text assembly format:

```
opcode ra rb rd imm
```

Example:

```
addi r1 r0 r1 10
add  r2 r1 r1 0
store r0 r2 r0 0
```

The provided **Python assembler** (`compiler/assembler.py`):

- Encodes instructions into 32-bit binary
- Inserts required NOPs and IRET handlers
- Builds a 2-level page table
- Outputs a memory image (`program.hex`) loaded by the simulator

```bash
python3 compiler/assembler.py program.asm -o rtl/program.hex
```

---

# Running the Simulation

The project uses **Icarus Verilog** with the file list `rtl/paths.f`.

```bash
# Compile RTL
cd rtl
iverilog -g2012 -f paths.f -o cpu_sim

# Run simulation
vvp cpu_sim

# View waveforms (optional)
gtkwave dump.vcd
```

---

# Project Structure

```
rtl/
 ├─ cpu/                  # Top-level CPU and control wiring
 ├─ Stages/               # Pipeline stage modules (ALU, Decode, MUL)
 ├─ Memory/               # Register file, ROB, joined memory
 ├─ pipeline_brakes/      # Pipeline register modules
 ├─ Extras/
 │   ├─ Branch_Predictor.v
 │   ├─ rename.v
 │   ├─ storeBuffer.v
 │   ├─ exceptionHandler.v
 │   ├─ Hazard_unit.v
 │   ├─ tlbs/             # ITLB, DTLB, PTW
 │   └─ Caches/           # I-Cache, D-Cache
 ├─ paths.f               # File list for iverilog
 └─ tb_cpu.v              # Testbench
compiler/
 ├─ assembler.py          # Python assembler
 └─ TestPrograms/         # Example assembly programs
```
