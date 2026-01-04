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

    # Standalone opcode
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

    # -------- Marker (no operands) --------
    if len(parts) == 1:
        op = parts[0].lower()
        if op in MARKER_MNEMONICS:
            return MARKER_WORD
        raise ValueError(
            f"Line {lineno}: unknown single-token instruction '{op}'"
        )

    # -------- Normal 5-token format --------
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

    # CTRL-family
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

# ===================== NOPS =====================
NOP_BUBBLE = ((OPCODES["addi"] & 0x3F) << 26)
NOP_BUBBLE_COMMENT = "NOP (addi r0 r0 r0 0)"
NOP_END = 0x00000000
NOP_END_COMMENT = "NOP / marker (end of program)"

# ===================== ASSEMBLE FILE =====================
def assemble_file(in_path: pathlib.Path) -> List[Tuple[int, str]]:
    lines = in_path.read_text().splitlines()
    assembled: List[Tuple[int, str]] = []

    # Initial bubble
    assembled.append((NOP_BUBBLE, NOP_BUBBLE_COMMENT))

    for i, line in enumerate(lines, start=1):
        try:
            w = assemble_line(line, i)
            if w is not None:
                assembled.append((w, line.strip()))
        except Exception as e:
            print(f"ERROR line {i}: {e}", file=sys.stderr)
            sys.exit(1)

    # Final marker
    assembled.append((NOP_END, NOP_END_COMMENT))
    return assembled

# ===================== PAGE TABLE LOGIC =====================
VA_WIDTH          = 32
PC_BITS           = 20
PAGE_OFFSET_WIDTH = 12
VPN_WIDTH         = VA_WIDTH - PAGE_OFFSET_WIDTH
PPN_WIDTH         = PC_BITS - PAGE_OFFSET_WIDTH

ROOT_PPN    = 0x09
L2_PPN_BASE = 0x0A

START_PC   = 0x00000000
DATA_BASE  = 0x00000000
DATA_SIZE  = 0x00020000

def vpns_for_region(base_va: int, size_bytes: int) -> Set[int]:
    if size_bytes <= 0:
        return set()
    first = base_va >> PAGE_OFFSET_WIDTH
    last  = (base_va + size_bytes - 1) >> PAGE_OFFSET_WIDTH
    return set(range(first, last + 1))

def compute_used_vpns(num_instrs: int) -> Set[int]:
    used = set()
    if num_instrs > 0:
        used |= vpns_for_region(START_PC, num_instrs * 4)
    used |= vpns_for_region(DATA_BASE, DATA_SIZE)
    return used

def make_pte(ppn: int) -> int:
    return (ppn << PAGE_OFFSET_WIDTH) | 1

def build_page_tables(used_vpns: Set[int]) -> Dict[int, int]:
    mem = {}
    l1_base = (ROOT_PPN << PAGE_OFFSET_WIDTH) >> 2
    l2_map = {}
    next_l2 = L2_PPN_BASE

    groups = {}
    for vpn in used_vpns:
        vpn1 = (vpn >> 10) & 0x3FF
        vpn0 = vpn & 0x3FF
        groups.setdefault(vpn1, set()).add(vpn0)

    for vpn1, vpn0s in groups.items():
        if vpn1 not in l2_map:
            l2_map[vpn1] = next_l2
            next_l2 += 1

        l2_ppn = l2_map[vpn1]
        mem[l1_base + vpn1] = make_pte(l2_ppn)
        l2_base = (l2_ppn << PAGE_OFFSET_WIDTH) >> 2

        for vpn0 in vpn0s:
            mem[l2_base + vpn0] = make_pte((vpn1 << 10) | vpn0)

    return mem

# ===================== WRITE OUTPUT =====================
def write_program_with_pagetables(
    assembled: List[Tuple[int, str]],
    out_path: pathlib.Path
) -> None:
    used_vpns = compute_used_vpns(len(assembled))
    mem_words = build_page_tables(used_vpns)

    with out_path.open("w") as f:
        for idx, (w, comment) in enumerate(assembled):
            f.write(f"{w:08x}    // [PC {idx*4}] {comment}\n")

        if mem_words:
            cur = None
            for idx in sorted(mem_words):
                if cur is None or idx != cur + 1:
                    f.write(f"@{idx:X}\n")
                f.write(f"{mem_words[idx]:08X}\n")
                cur = idx

    print(f"Wrote {len(assembled)} instructions + {len(mem_words)} PTE words to {out_path}")

# ===================== MAIN =====================
def main():
    ap = argparse.ArgumentParser(
        description="Assembler with marker instruction + page tables")
    ap.add_argument("input", help="assembly source")
    ap.add_argument("-o", "--output", default="program.hex")
    args = ap.parse_args()

    assembled = assemble_file(pathlib.Path(args.input))
    write_program_with_pagetables(assembled, pathlib.Path(args.output))

if __name__ == "__main__":
    main()
