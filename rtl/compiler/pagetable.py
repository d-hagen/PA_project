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
}

RD_JMP = 0b00000
RD_BEQ = 0b00001
RD_BLT = 0b00010
RD_BGT = 0b00011
CTRL_RD_FOR = {"jmp": RD_JMP, "beq": RD_BEQ, "blt": RD_BLT, "bgt": RD_BGT}

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

    opc = OPCODES[op_l]
    ra  = parse_reg(ra_t)
    rb  = parse_reg(rb_t)
    rd  = parse_reg(rd_t)
    imm = parse_imm(imm_t)

    if op_l in CTRL_RD_FOR:
        opc = OPCODES["ctrl"]
        rd  = CTRL_RD_FOR[op_l]

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
#  FUNCTION 1: assemble_file -> list of (word, comment)
# =====================================================================
def assemble_file(in_path: pathlib.Path, max_words: int = 32
                  ) -> List[Tuple[int, str]]:
    """
    Assemble the input .s file into up to max_words instructions.

    Returns:
      List[(word, original_comment_string)], padded with NOPs to max_words,
      and last entry forced to NOP_END.
    """
    lines = in_path.read_text().splitlines()
    assembled: List[Tuple[int, str]] = []

    for i, line in enumerate(lines, start=1):
        try:
            w = assemble_line(line, i)
            if w is not None:
                assembled.append((w, line.strip()))
        except Exception as e:
            print(f"ERROR line {i}: {e}", file=sys.stderr)
            sys.exit(1)

    if len(assembled) > max_words:
        assembled = assembled[:max_words]

    # Pad with NOP bubbles
    while len(assembled) < max_words:
        assembled.append((NOP_BUBBLE, NOP_BUBBLE_COMMENT))

    # Last word is hard NOP end
    assembled[-1] = (NOP_END, "[31] " + NOP_END_COMMENT)

    return assembled

# =====================================================================
#  FUNCTION 2: write_program_with_pagetables (region-based)
# =====================================================================

# --- MMU / PTW parameters (match your Verilog) ---
VA_WIDTH          = 32
PC_BITS           = 20
PAGE_OFFSET_WIDTH = 12                           # 4 KiB pages
VPN_WIDTH         = VA_WIDTH - PAGE_OFFSET_WIDTH  # 20
PPN_WIDTH         = PC_BITS - PAGE_OFFSET_WIDTH   # 8

# Where page tables live in PHYSICAL memory:
# L1 root at PPN = 0x09 -> phys 0x9000
# L2 tables start at PPN = 0x0A -> phys 0xA000, etc.
ROOT_PPN    = 0x09
L2_PPN_BASE = 0x0A

# --------- REGION DEFINITIONS (VA) ----------
# Assume program starts at VA 0 (reset PC = 0).
# If your fetch starts at 0x1000, change START_PC accordingly.
START_PC   = 0x00000000

# Data region: anything your loads/stores will reasonably touch.
# This region will cover addresses like 20000 decimal (0x4E20).
DATA_BASE  = 0x00000000
DATA_SIZE  = 0x00020000   # 128 KiB of data region

def vpns_for_region(base_va: int, size_bytes: int) -> Set[int]:
    """Return all VPNs touched by [base_va, base_va + size_bytes)."""
    if size_bytes <= 0:
        return set()
    first_vpn = base_va >> PAGE_OFFSET_WIDTH
    last_vpn  = (base_va + size_bytes - 1) >> PAGE_OFFSET_WIDTH
    return set(range(first_vpn, last_vpn + 1))

def compute_used_vpns(num_instrs: int) -> Set[int]:
    """
    Region-based mapping, OS-style:

      - Map the code region: [START_PC, START_PC + code_bytes)
      - Map a fixed data region: [DATA_BASE, DATA_BASE + DATA_SIZE)

    Any VA inside those regions will have a valid translation.
    VA outside will be unmapped (would cause a page fault in a real OS).
    """
    used_vpns: Set[int] = set()

    # Code region (text)
    if num_instrs > 0:
        text_bytes = num_instrs * 4
        used_vpns |= vpns_for_region(START_PC, text_bytes)

    # Data region (globals/heap/scratch)
    used_vpns |= vpns_for_region(DATA_BASE, DATA_SIZE)

    # Sanity: we only identity-map VPNs that fit in 8-bit PPN
    for vpn in used_vpns:
        if vpn >= (1 << PPN_WIDTH):
            raise ValueError(
                f"VPN {vpn} exceeds physical PPN capacity for identity mapping")

    return used_vpns

def make_pte(ppn: int, valid: bool = True) -> int:
    """
    PTE format:
      bits [PPN_WIDTH+PAGE_OFFSET_WIDTH-1 : PAGE_OFFSET_WIDTH] = PPN
      bit 0 = valid
    For PC_BITS=20, PAGE_OFFSET_WIDTH=12 -> bits [19:12] = PPN.
    """
    v_bit = 1 if valid else 0
    return (ppn << PAGE_OFFSET_WIDTH) | v_bit

def build_page_tables(used_vpns: Set[int]) -> Dict[int, int]:
    """
    Build sparse L1 + L2 tables for the set of used_vpns (region-based).

    Returns:
      mem_words: dict mapping word_index -> 32-bit PTE word
      (word_index is byte_addr >> 2, for use with $readmemh and @<index>).
    """
    mem_words: Dict[int, int] = {}

    # L1 base word index
    l1_base_word_idx = (ROOT_PPN << PAGE_OFFSET_WIDTH) >> 2

    # Map from vpn1 to L2 PPN
    l2_ppn_for_vpn1: Dict[int, int] = {}
    next_l2_ppn = L2_PPN_BASE

    # Group VPNs by vpn1
    vpn_groups: Dict[int, Set[int]] = {}
    for vpn in used_vpns:
        vpn1 = (vpn >> 10) & 0x3FF    # top 10 bits
        vpn0 = vpn & 0x3FF            # low 10 bits
        vpn_groups.setdefault(vpn1, set()).add(vpn0)

    for vpn1, vpn0_set in vpn_groups.items():
        if vpn1 not in l2_ppn_for_vpn1:
            l2_ppn_for_vpn1[vpn1] = next_l2_ppn
            next_l2_ppn += 1
            if next_l2_ppn >= (1 << PPN_WIDTH):
                raise ValueError("Out of PPNs for L2 tables!")

        l2_ppn = l2_ppn_for_vpn1[vpn1]

        # ----- L1 entry -----
        l1_word_index = l1_base_word_idx + vpn1
        mem_words[l1_word_index] = make_pte(l2_ppn, valid=True)

        # ----- L2 entries -----
        l2_base_word_idx = (l2_ppn << PAGE_OFFSET_WIDTH) >> 2

        for vpn0 in vpn0_set:
            vpn  = (vpn1 << 10) | vpn0
            ppn  = vpn  # identity map VPN -> PPN (for small VPNs)
            if ppn >= (1 << PPN_WIDTH):
                raise ValueError(
                    f"Cannot identity-map VPN {vpn}: exceeds 8-bit PPN")

            l2_word_index = l2_base_word_idx + vpn0
            mem_words[l2_word_index] = make_pte(ppn, valid=True)

    return mem_words

def write_program_with_pagetables(
    assembled: List[Tuple[int, str]],
    out_path: pathlib.Path
) -> None:
    """
    Write a single program.hex that:
      - Places the assembled instructions starting at word index 0.
      - Places page tables in memory at their proper physical locations
        using @<word-index> directives (e.g., L1 at 0x9000, L2 at 0xA000).

    assembled: list of (word, comment_string)
    """
    num_instrs = len(assembled)
    used_vpns = compute_used_vpns(num_instrs)
    mem_words = build_page_tables(used_vpns)

    with out_path.open("w") as f:
        # --- 1) Write instructions at the beginning (word index 0..) ---
        for idx, (w, original) in enumerate(assembled):
            step = idx * 4
            f.write(f"{w:08x}    // [step {step}] {original}\n")

        # --- 2) Write page table words with @<index> sections ---
        if mem_words:
            sorted_indices = sorted(mem_words.keys())
            current_base = None

            for idx in sorted_indices:
                value = mem_words[idx] & 0xFFFFFFFF

                # If we're jumping to a new region, emit @<index>
                if current_base is None or idx != current_base + 1:
                    f.write(f"@{idx:X}\n")
                current_base = idx

                f.write(f"{value:08X}\n")

    print(f"Wrote {num_instrs} instructions + {len(mem_words)} PTE words to {out_path}")

# ============================= main ================================
def main():
    ap = argparse.ArgumentParser(
        description="Assembler + region-based page table generator -> single program.hex")
    ap.add_argument("input", help="assembly source")
    ap.add_argument("-o", "--output", default="program.hex")
    args = ap.parse_args()

    in_path  = pathlib.Path(args.input)
    out_path = pathlib.Path(args.output)

    assembled = assemble_file(in_path, max_words=32)
    write_program_with_pagetables(assembled, out_path)

if __name__ == "__main__":
    main()
