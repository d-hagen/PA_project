#!/usr/bin/env python3
import argparse, sys, re, pathlib
from typing import Optional, List, Tuple, Dict, Set

# ===================== OPCODES (match decode.v) =====================
# NOTE: OPCODES["iret"] MUST match your decode.v choice for the iret opcode.
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

    # NEW: separate opcode for iret (placeholder = 0b111111)
    # Change this to whatever you implement in decode.v
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

def assemble_line(line: str, lineno: int) -> Optional[int]:
    raw = line.rstrip("\n")
    clean = re.split(r"//|#|;", raw, maxsplit=1)[0].strip()
    if not clean:
        return None

    parts = re.split(r"[,\s]+", clean)
    if len(parts) != 5:
        raise ValueError(f"Line {lineno}: expected 5 tokens (opcode ra rb rd imm); got {parts}")

    op, ra_t, rb_t, rd_t, imm_t = parts
    op_l = op.lower()
    if op_l not in OPCODES:
        raise ValueError(f"Line {lineno}: unknown opcode '{op}'")

    # Parse fields (even if some ops ignore them, we keep your 5-token format)
    ra  = parse_reg(ra_t)
    rb  = parse_reg(rb_t)
    rd  = parse_reg(rd_t)
    imm = parse_imm(imm_t)

    # CTRL-family encoding uses OPC_CTRL and overloads rd field
    if op_l in CTRL_RD_FOR:
        opc = OPCODES["ctrl"]
        rd  = CTRL_RD_FOR[op_l]
        word = ((opc & 0x3F) << 26) \
             | ((ra  & 0x1F) << 21) \
             | ((rb  & 0x1F) << 16) \
             | ((rd  & 0x1F) << 11) \
             | ( imm & 0x7FF)
        return word

    # NEW: iret is a standalone opcode; we ignore ra/rb/rd/imm (but still encode them as given)
    if op_l == "iret":
        opc = OPCODES["iret"]
        word = ((opc & 0x3F) << 26) \
             | ((ra  & 0x1F) << 21) \
             | ((rb  & 0x1F) << 16) \
             | ((rd  & 0x1F) << 11) \
             | ( imm & 0x7FF)
        return word

    # Normal R/R/I encoding
    opc = OPCODES[op_l]
    word = ((opc & 0x3F) << 26) \
         | ((ra  & 0x1F) << 21) \
         | ((rb  & 0x1F) << 16) \
         | ((rd  & 0x1F) << 11) \
         | ( imm & 0x7FF)
    return word

NOP_BUBBLE = ((OPCODES["addi"] & 0x3F) << 26)
NOP_BUBBLE_COMMENT = "NOP (addi r0 r0 r0 0)"
NOP_END = 0x00000000
NOP_END_COMMENT = "NOP (end of program)"

# =====================================================================
#  FUNCTION 1: assemble_file (NO CAP)
# =====================================================================
def assemble_file(in_path: pathlib.Path) -> List[Tuple[int, str]]:
    """
    Assemble the input .s file with NO instruction cap.

    Always appends:
      - 1 NOP bubble (as you had)
      - 1 final NOP_END
    """
    lines = in_path.read_text().splitlines()
    assembled: List[Tuple[int, str]] = []

    for _ in range(1):
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

# =====================================================================
#  PAGE TABLE LOGIC
# =====================================================================
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
    first_vpn = base_va >> PAGE_OFFSET_WIDTH
    last_vpn  = (base_va + size_bytes - 1) >> PAGE_OFFSET_WIDTH
    return set(range(first_vpn, last_vpn + 1))

def compute_used_vpns(num_instrs: int) -> Set[int]:
    used_vpns: Set[int] = set()

    if num_instrs > 0:
        used_vpns |= vpns_for_region(START_PC, num_instrs * 4)

    used_vpns |= vpns_for_region(DATA_BASE, DATA_SIZE)

    for vpn in used_vpns:
        if vpn >= (1 << PPN_WIDTH):
            raise ValueError(f"VPN {vpn} exceeds physical PPN capacity")

    return used_vpns

def make_pte(ppn: int, valid: bool = True) -> int:
    return (ppn << PAGE_OFFSET_WIDTH) | (1 if valid else 0)

def build_page_tables(used_vpns: Set[int]) -> Dict[int, int]:
    mem_words: Dict[int, int] = {}

    l1_base_word_idx = (ROOT_PPN << PAGE_OFFSET_WIDTH) >> 2
    l2_ppn_for_vpn1: Dict[int, int] = {}
    next_l2_ppn = L2_PPN_BASE

    vpn_groups: Dict[int, Set[int]] = {}
    for vpn in used_vpns:
        vpn1 = (vpn >> 10) & 0x3FF
        vpn0 = vpn & 0x3FF
        vpn_groups.setdefault(vpn1, set()).add(vpn0)

    for vpn1, vpn0s in vpn_groups.items():
        if vpn1 not in l2_ppn_for_vpn1:
            l2_ppn_for_vpn1[vpn1] = next_l2_ppn
            next_l2_ppn += 1

        l2_ppn = l2_ppn_for_vpn1[vpn1]
        mem_words[l1_base_word_idx + vpn1] = make_pte(l2_ppn)

        l2_base_word_idx = (l2_ppn << PAGE_OFFSET_WIDTH) >> 2
        for vpn0 in vpn0s:
            vpn = (vpn1 << 10) | vpn0
            mem_words[l2_base_word_idx + vpn0] = make_pte(vpn)

    return mem_words

def write_program_with_pagetables(
    assembled: List[Tuple[int, str]],
    out_path: pathlib.Path
) -> None:
    num_instrs = len(assembled)
    used_vpns = compute_used_vpns(num_instrs)
    mem_words = build_page_tables(used_vpns)

    with out_path.open("w") as f:
        for idx, (w, original) in enumerate(assembled):
            f.write(f"{w:08x}    // [step {idx*4}] {original}\n")

        if mem_words:
            current = None
            for idx in sorted(mem_words):
                if current is None or idx != current + 1:
                    f.write(f"@{idx:X}\n")
                f.write(f"{mem_words[idx]:08X}\n")
                current = idx

    print(f"Wrote {num_instrs} instructions + {len(mem_words)} PTE words to {out_path}")

# ============================= main ================================
def main():
    ap = argparse.ArgumentParser(
        description="Assembler + region-based page table generator")
    ap.add_argument("input", help="assembly source")
    ap.add_argument("-o", "--output", default="program.hex")
    args = ap.parse_args()

    assembled = assemble_file(pathlib.Path(args.input))
    write_program_with_pagetables(assembled, pathlib.Path(args.output))

if __name__ == "__main__":
    main()
