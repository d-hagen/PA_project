#!/usr/bin/env python3
import argparse, sys, re, pathlib
from typing import Optional

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
    "addi":  0b001000,   # add immediate
    "lt":    0b001001,
    "gt":    0b001010,
    "load":  0b001011,
    "store": 0b001100,
    "ldb":    0b101011,
    "strb":   0b101100,
    "ctrl":  0b001101,   # used internally for jmp/beq/blt/bgt
    "mul":   0b001110,   

    # Shorthands for control ops (mapped to OPC_CTRL with rd sub-op):
    "jmp":   0b001101,
    "beq":   0b001101,
    "blt":   0b001101,
    "bgt":   0b001101,
}

# CTRL subop codes in the RD field
RD_JMP = 0b00000
RD_BEQ = 0b00001
RD_BLT = 0b00010
RD_BGT = 0b00011
CTRL_RD_FOR = {"jmp": RD_JMP, "beq": RD_BEQ, "blt": RD_BLT, "bgt": RD_BGT}

# ============================ utils ================================
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
    val = int(tok, 0)  # supports 0x.., 0b.., decimal
    if not (0 <= val <= 0x7FF):  # 11-bit zero-extended immediate
        raise ValueError(f"Immediate out of 11-bit unsigned range (0..2047): {tok}")
    return val

# ========================== assembler ==============================
def assemble_line(line: str, lineno: int) -> Optional[int]:
    raw = line.rstrip("\n")
    # strip inline comments
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

    # Map control shorthands to OPC_CTRL and force RD subop
    if op_l in CTRL_RD_FOR:
        opc = OPCODES["ctrl"]
        rd  = CTRL_RD_FOR[op_l]

    word = ((opc & 0x3F) << 26) \
         | ((ra  & 0x1F) << 21) \
         | ((rb  & 0x1F) << 16) \
         | ((rd  & 0x1F) << 11) \
         | ( imm & 0x7FF)
    return word

# Precompute the bubble NOP: addi r0 r0 r0 0 = 0x20000000
NOP_BUBBLE = ((OPCODES["addi"] & 0x3F) << 26)  # rest zeros
NOP_BUBBLE_COMMENT = "NOP (addi r0 r0 r0 0)"
NOP_END = 0x00000000
NOP_END_COMMENT = "NOP (end of program)"

# ============================= main ================================
def main():
    ap = argparse.ArgumentParser(description="Assembler -> program.hex (32 lines; bubble NOP=ADDI r0,r0,r0,0; last NOP=0)")
    ap.add_argument("input", help="assembly source (each line: opcode ra rb rd imm)")
    ap.add_argument("-o", "--output", default="program.hex", help="output hex file (default: program.hex)")
    args = ap.parse_args()

    in_path  = pathlib.Path(args.input)
    out_path = pathlib.Path(args.output)

    lines = in_path.read_text().splitlines()
    assembled = []  # list[(word:int, original:str)]

    for i, line in enumerate(lines, start=1):
        try:
            w = assemble_line(line, i)
            if w is not None:
                assembled.append((w, line.strip()))
        except Exception as e:
            print(f"ERROR line {i}: {e}", file=sys.stderr)
            sys.exit(1)

    MAX_WORDS = 32

    # Ensure at most 32 user words (we’ll force last to END NOP anyway)
    if len(assembled) > MAX_WORDS:
        print(f"Warning: input has {len(assembled)} instructions; truncating to {MAX_WORDS}.", file=sys.stderr)
        assembled = assembled[:MAX_WORDS]

    # Pad with bubble NOP (0x20000000) up to slot 31
    while len(assembled) < MAX_WORDS:
        assembled.append((NOP_BUBBLE, NOP_BUBBLE_COMMENT))

    # Force the last slot [31] to END NOP (0x00000000)
    assembled[-1] = (NOP_END, "[31] " + NOP_END_COMMENT)

    # Write out with index and original asm
    with out_path.open("w") as f:
        for idx, (w, original) in enumerate(assembled):
            f.write(f"{w:08x}    // [{idx}] {original}\n")

    print(f"Wrote {len(assembled)} instructions to {out_path}")

if __name__ == "__main__":
    main()
