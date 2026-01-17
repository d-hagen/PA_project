#!/usr/bin/env python3
import argparse, sys, re, pathlib
from typing import Optional, List, Tuple, Dict, Set

# ===================== OPCODES (match decode.v) =====================
OPCODES = {
    "add":   0b000000,
    "sub":   0b000001,
    "and":   0b000010,
    "or":    0b000011,
    "xor":   0b000100,
    "not":   0b000101,
    "shl":   0b000110,
    "shr":   0b000111,
    "addi":  0b001000,
    "lt":    0b001001,
    "gt":    0b001010,
    "load":  0b001011,
    "store": 0b001100,
    "ldb":   0b101011,
    "strb":  0b101100,
    "ctrl":  0b001101,
    "jmp":   0b001101,
    "beq":   0b001101,
    "blt":   0b001101,
    "bgt":   0b001101,
    "jlx":   0b001101,
    "mul":   0b001110,
    "iret":  0b111111,
}

RD_JMP = 0b00000
RD_BEQ = 0b00001
RD_BLT = 0b00010
RD_BGT = 0b00011
RD_JLX = 0b10000

CTRL_RD_FOR = {
    "jmp": RD_JMP,
    "beq": RD_BEQ,
    "blt": RD_BLT,
    "bgt": RD_BGT,
    "jlx": RD_JLX,
}

# ===================== MARKER =====================
MARKER_WORD = 0x00000000
MARKER_MNEMONICS = {"marker", "mark", "end"}

# ===================== REGEX =====================
REG_RE = re.compile(r"^r(\d+)$", re.IGNORECASE)

def parse_reg(tok: str) -> int:
    m = REG_RE.match(tok)
    if not m:
        raise ValueError(f"Bad register '{tok}' (use r0..r31)")
    n = int(m.group(1))
    if not (0 <= n <= 31):
        raise ValueError(f"Register out of range '{tok}'")
    return n

def parse_imm(tok: str) -> int:
    val = int(tok, 0)
    if not (-0x400 <= val <= 0x3FF):
        raise ValueError(f"Immediate out of 11-bit signed range (-1024..1023): {tok}")
    return val & 0x7FF

# ===================== ASSEMBLE LINE =====================
def assemble_line(line: str, lineno: int) -> Optional[int]:
    raw = line.rstrip("\n")
    clean = re.split(r"//|#|;", raw, maxsplit=1)[0].strip()
    if not clean:
        return None

    parts = re.split(r"[,\s]+", clean)

    if len(parts) == 1:
        op = parts[0].lower()
        if op in MARKER_MNEMONICS:
            return MARKER_WORD
        raise ValueError(f"Line {lineno}: unknown single-token instruction '{op}'")

    if len(parts) != 5:
        raise ValueError(
            f"Line {lineno}: expected 5 tokens (opcode ra rb rd imm); got {parts}"
        )

    op, ra_t, rb_t, rd_t, imm_t = parts
    op_l = op.lower()
    if op_l not in OPCODES:
        raise ValueError(f"Line {lineno}: unknown opcode '{op}'")

    ra  = parse_reg(ra_t)
    rb  = parse_reg(rb_t)
    rd  = parse_reg(rd_t)
    imm = parse_imm(imm_t)

    if op_l in CTRL_RD_FOR:
        opc = OPCODES["ctrl"]
        rd  = CTRL_RD_FOR[op_l]
    else:
        opc = OPCODES[op_l]

    word = ((opc & 0x3F) << 26) \
         | ((ra  & 0x1F) << 21) \
         | ((rb  & 0x1F) << 16) \
         | ((rd  & 0x1F) << 11) \
         | ( imm & 0x7FF)

    return word

# ===================== NOPS / FIXED WORDS =====================
NOP_BUBBLE = ((OPCODES["addi"] & 0x3F) << 26)
NOP_BUBBLE_COMMENT = "NOP (addi r0 r0 r0 0)"
NOP_END = 0x00000000
NOP_END_COMMENT = "NOP / marker (end of program)"

IRET_WORD = (OPCODES["iret"] & 0x3F) << 26

def assemble_file(in_path: pathlib.Path) -> List[Tuple[int, str]]:
    lines = in_path.read_text().splitlines()
    assembled: List[Tuple[int, str]] = []

    assembled.append((NOP_BUBBLE, NOP_BUBBLE_COMMENT))

    for i, line in enumerate(lines, start=1):
        try:
            w = assemble_line(line, i)
            if w is not None:
                assembled.append((w, line.strip()))
        except Exception as e:
            print(f"ERROR line {i}: {e}", file=sys.stderr)
            sys.exit(1)

    assembled.append((NOP_END, NOP_END_COMMENT))
    return assembled

# ===================== PAGE TABLE LOGIC =====================
VA_WIDTH          = 32
PC_BITS           = 20
PAGE_OFFSET_WIDTH = 12
VPN_WIDTH         = VA_WIDTH - PAGE_OFFSET_WIDTH
PPN_WIDTH         = PC_BITS - PAGE_OFFSET_WIDTH  # 8

ROOT_PPN    = 0x30
L2_PPN_BASE = 0x31

# VA -> PA mapping (UNCHANGED)
VA_TO_PA_BIAS_BYTES = 0x8000
BIAS_PAGES = VA_TO_PA_BIAS_BYTES >> PAGE_OFFSET_WIDTH  # 8 pages

# ===================== PROGRAM PLACEMENT =====================
# Program is physically written at PA = 0x9000
PROGRAM_PA_BASE_BYTES = 0x9000
PROGRAM_PA_BASE_WORD  = PROGRAM_PA_BASE_BYTES >> 2

START_PC_VA   = 0x00000000
DATA_BASE_VA  = 0x00000000
DATA_SIZE     = 0x00020000

def vpns_for_region(base_va: int, size_bytes: int) -> Set[int]:
    if size_bytes <= 0:
        return set()
    first = base_va >> PAGE_OFFSET_WIDTH
    last  = (base_va + size_bytes - 1) >> PAGE_OFFSET_WIDTH
    return set(range(first, last + 1))

def compute_used_vpns(num_instrs: int, max_word: int) -> Set[int]:
    used: Set[int] = set()
    if num_instrs > 0:
        used |= vpns_for_region(START_PC_VA, num_instrs * 4)
    used |= vpns_for_region(DATA_BASE_VA, DATA_SIZE)
    if max_word < 0:
        raise ValueError("--max-word must be >= 0")
    used |= vpns_for_region(0x00000000, (max_word + 1) * 4)
    return used

def make_pte(ppn: int) -> int:
    return (ppn << PAGE_OFFSET_WIDTH) | 1

def build_page_tables(used_vpns: Set[int]) -> Dict[int, int]:
    mem: Dict[int, int] = {}
    l1_base_word = (ROOT_PPN << PAGE_OFFSET_WIDTH) >> 2

    l2_map: Dict[int, int] = {}
    next_l2 = L2_PPN_BASE

    groups: Dict[int, Set[int]] = {}
    for vpn in used_vpns:
        vpn1 = (vpn >> 10) & 0x3FF
        vpn0 = vpn & 0x3FF
        groups.setdefault(vpn1, set()).add(vpn0)

    for vpn1, vpn0s in sorted(groups.items()):
        if vpn1 not in l2_map:
            l2_map[vpn1] = next_l2
            next_l2 += 1
        l2_ppn = l2_map[vpn1]

        mem[l1_base_word + vpn1] = make_pte(l2_ppn)
        l2_base_word = (l2_ppn << PAGE_OFFSET_WIDTH) >> 2

        for vpn0 in vpn0s:
            vpn = (vpn1 << 10) | vpn0
            ppn = vpn + BIAS_PAGES
            if ppn >= (1 << PPN_WIDTH):
                continue
            mem[l2_base_word + vpn0] = make_pte(ppn)

    return mem

def write_program_with_pagetables(
    assembled: List[Tuple[int, str]],
    out_path: pathlib.Path,
    max_word: int
) -> None:
    used_vpns = compute_used_vpns(len(assembled), max_word)
    mem_words = build_page_tables(used_vpns)

    with out_path.open("w") as f:
        # Forced NOP at PA 0
        f.write("@0\n")
        f.write(f"{NOP_BUBBLE:08x}    // [PA 0x0000] forced NOP\n")

        # Fixed IRET at PA 0x1000 (@400) + 5 NOPs
        f.write("@400\n")
        f.write(f"{IRET_WORD:08x}    // [PA 0x1000] iret\n")
        for k in range(5):
            f.write(f"{NOP_BUBBLE:08x}    // [PA 0x{0x1004 + 4*k:04X}] nop after iret ({k+1}/5)\n")

        # Fixed IRET at PA 0x8000 (@2000) + 5 NOPs
        f.write("@2000\n")
        f.write(f"{IRET_WORD:08x}    // [PA 0x8000] iret\n")
        for k in range(5):
            f.write(f"{NOP_BUBBLE:08x}    // [PA 0x{0x8004 + 4*k:04X}] nop after iret ({k+1}/5)\n")

        # Program at PA 0x9000 (@2400)
        f.write(f"@{PROGRAM_PA_BASE_WORD:X}\n")
        for idx, (w, comment) in enumerate(assembled):
            f.write(f"{w:08x}    // [VA PC {idx*4}] {comment}\n")

        # Page tables
        if mem_words:
            cur = None
            for idx in sorted(mem_words):
                if cur is None or idx != cur + 1:
                    f.write(f"@{idx:X}\n")
                f.write(f"{mem_words[idx]:08X}\n")
                cur = idx

    print(
        f"Wrote NOP @PA 0x0, IRET+5NOPs @0x1000 and @0x8000, "
        f"{len(assembled)} instructions at PA 0x{PROGRAM_PA_BASE_BYTES:X} "
        f"(word @{PROGRAM_PA_BASE_WORD:X}), "
        f"+ {len(mem_words)} PTE words to {out_path}\n"
        f"Mapping: PA = VA + 0x{VA_TO_PA_BIAS_BYTES:X} (PPN = VPN + {BIAS_PAGES})"
    )

def main():
    ap = argparse.ArgumentParser(description="Assembler + 2-level PT, mapping PA=VA+0x8000 demo")
    ap.add_argument("input", help="assembly source")
    ap.add_argument("-o", "--output", default="program.hex")
    ap.add_argument("--max-word", type=int, default=1000000,
                    help="Generate PTEs for VA word addresses 0..max-word (default: 1000000)")
    args = ap.parse_args()

    assembled = assemble_file(pathlib.Path(args.input))
    write_program_with_pagetables(assembled, pathlib.Path(args.output), args.max_word)

if __name__ == "__main__":
    main()
