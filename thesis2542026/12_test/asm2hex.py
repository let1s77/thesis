#!/usr/bin/env python3
"""Minimal RISC-V RV32I assembler — converts .s files to $readmemh hex.

Supports the instruction subset used by IPU/SOC demo assembly:
  R-type:  add, sub, and, or, xor, sll, srl, sra, slt, sltu
  I-type:  addi, andi, ori, xori, slti, sltiu, slli, srli, srai
  Load:    lb, lh, lw, lbu, lhu
  Store:   sb, sh, sw
  Branch:  beq, bne, blt, bge, bltu, bgeu
  Jump:    jal, jalr
  Upper:   lui, auipc
  Pseudo:  li, mv, nop, j, ret, beqz, bnez, call

Usage:
    python asm2hex.py ../11_asm/ipu_apb_test.s -o ipu_apb_test.hex
    python asm2hex.py ../11_asm/ipu_apb_test.s  (outputs to same dir)
"""

import argparse
import os
import re
import sys
from pathlib import Path

# -----------------------------------------------------------------------
# Register name → number
# -----------------------------------------------------------------------
REG_ABI = {
    "zero": 0, "ra": 1, "sp": 2, "gp": 3, "tp": 4,
    "t0": 5, "t1": 6, "t2": 7,
    "s0": 8, "fp": 8, "s1": 9,
    "a0": 10, "a1": 11, "a2": 12, "a3": 13,
    "a4": 14, "a5": 15, "a6": 16, "a7": 17,
    "s2": 18, "s3": 19, "s4": 20, "s5": 21,
    "s6": 22, "s7": 23, "s8": 24, "s9": 25,
    "s10": 26, "s11": 27,
    "t3": 28, "t4": 29, "t5": 30, "t6": 31,
}
for i in range(32):
    REG_ABI[f"x{i}"] = i


def parse_reg(s: str) -> int:
    s = s.strip().lower()
    if s in REG_ABI:
        return REG_ABI[s]
    raise ValueError(f"Unknown register: {s}")


def parse_imm(s: str, labels: dict, pc: int, is_branch: bool = False) -> int:
    s = s.strip()
    if s in labels:
        if is_branch:
            return labels[s] - pc
        return labels[s]
    s_lower = s.lower()
    if s_lower.startswith("0x") or s_lower.startswith("-0x"):
        return int(s, 16)
    if s_lower.startswith("0b"):
        return int(s, 2)
    return int(s)


def bits(val: int, hi: int, lo: int) -> int:
    mask = (1 << (hi - lo + 1)) - 1
    return (val >> lo) & mask


def sext(val: int, width: int) -> int:
    if val & (1 << (width - 1)):
        val -= 1 << width
    return val


# -----------------------------------------------------------------------
# Encoding helpers
# -----------------------------------------------------------------------
def encode_r(funct7: int, rs2: int, rs1: int, funct3: int, rd: int, opcode: int) -> int:
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def encode_i(imm12: int, rs1: int, funct3: int, rd: int, opcode: int) -> int:
    imm12 &= 0xFFF
    return (imm12 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def encode_s(imm12: int, rs2: int, rs1: int, funct3: int, opcode: int) -> int:
    imm12 &= 0xFFF
    return (bits(imm12, 11, 5) << 25) | (rs2 << 20) | (rs1 << 15) | \
           (funct3 << 12) | (bits(imm12, 4, 0) << 7) | opcode


def encode_b(imm: int, rs2: int, rs1: int, funct3: int) -> int:
    imm &= 0x1FFF
    return (bits(imm, 12, 12) << 31) | (bits(imm, 10, 5) << 25) | \
           (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | \
           (bits(imm, 4, 1) << 8) | (bits(imm, 11, 11) << 7) | 0x63


def encode_u(imm20: int, rd: int, opcode: int) -> int:
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | opcode


def encode_j(imm: int, rd: int) -> int:
    imm &= 0x1FFFFF
    return (bits(imm, 20, 20) << 31) | (bits(imm, 10, 1) << 21) | \
           (bits(imm, 11, 11) << 20) | (bits(imm, 19, 12) << 12) | \
           (rd << 7) | 0x6F


# -----------------------------------------------------------------------
# Memory-access operand parser: "offset(reg)" → (offset, reg_num)
# -----------------------------------------------------------------------
MEM_RE = re.compile(r"(-?\w+)\((\w+)\)")


def parse_mem(s: str, labels: dict, pc: int) -> tuple:
    m = MEM_RE.match(s.strip())
    if not m:
        raise ValueError(f"Bad memory operand: {s}")
    offset = parse_imm(m.group(1), labels, pc)
    reg = parse_reg(m.group(2))
    return offset, reg


# -----------------------------------------------------------------------
# Instruction assembly (2-pass)
# -----------------------------------------------------------------------
def assemble_insn(mnemonic: str, operands: list[str], labels: dict, pc: int) -> int:
    op = mnemonic.lower()
    ops = [o.strip() for o in operands]

    # --- Pseudo-instructions ---
    if op == "nop":
        return encode_i(0, 0, 0, 0, 0x13)  # addi x0, x0, 0
    if op == "mv":
        return encode_i(0, parse_reg(ops[1]), 0, parse_reg(ops[0]), 0x13)
    if op == "li":
        rd = parse_reg(ops[0])
        imm = parse_imm(ops[1], labels, pc)
        if -2048 <= imm <= 2047:
            return encode_i(imm, 0, 0, rd, 0x13)  # addi rd, x0, imm
        # li with large immediate: lui + addi (return lui, addi added as second word)
        upper = (imm + 0x800) >> 12
        lower = imm - (upper << 12)
        return encode_u(upper, rd, 0x37)  # only lui; caller must handle 2-insn
    if op == "j":
        offset = parse_imm(ops[0], labels, pc, is_branch=True)
        return encode_j(offset, 0)
    if op == "ret":
        return encode_i(0, 1, 0, 0, 0x67)  # jalr x0, ra, 0
    if op == "beqz":
        rs = parse_reg(ops[0])
        offset = parse_imm(ops[1], labels, pc, is_branch=True)
        return encode_b(offset, 0, rs, 0)
    if op == "bnez":
        rs = parse_reg(ops[0])
        offset = parse_imm(ops[1], labels, pc, is_branch=True)
        return encode_b(offset, 0, rs, 1)
    if op == "call":
        offset = parse_imm(ops[0], labels, pc, is_branch=True)
        return encode_j(offset, 1)  # jal ra, offset

    # --- R-type ---
    r_insns = {
        "add":  (0x00, 0), "sub":  (0x20, 0), "sll":  (0x00, 1),
        "slt":  (0x00, 2), "sltu": (0x00, 3), "xor":  (0x00, 4),
        "srl":  (0x00, 5), "sra":  (0x20, 5), "or":   (0x00, 6),
        "and":  (0x00, 7),
    }
    if op in r_insns:
        f7, f3 = r_insns[op]
        return encode_r(f7, parse_reg(ops[2]), parse_reg(ops[1]), f3, parse_reg(ops[0]), 0x33)

    # --- I-type ALU ---
    i_alu = {
        "addi": 0, "slti": 2, "sltiu": 3, "xori": 4, "ori": 6, "andi": 7,
    }
    if op in i_alu:
        return encode_i(
            parse_imm(ops[2], labels, pc), parse_reg(ops[1]),
            i_alu[op], parse_reg(ops[0]), 0x13
        )

    # --- I-type shifts ---
    if op == "slli":
        shamt = parse_imm(ops[2], labels, pc) & 0x1F
        return encode_i(shamt, parse_reg(ops[1]), 1, parse_reg(ops[0]), 0x13)
    if op == "srli":
        shamt = parse_imm(ops[2], labels, pc) & 0x1F
        return encode_i(shamt, parse_reg(ops[1]), 5, parse_reg(ops[0]), 0x13)
    if op == "srai":
        shamt = (parse_imm(ops[2], labels, pc) & 0x1F) | 0x400
        return encode_i(shamt, parse_reg(ops[1]), 5, parse_reg(ops[0]), 0x13)

    # --- Loads ---
    loads = {"lb": 0, "lh": 1, "lw": 2, "lbu": 4, "lhu": 5}
    if op in loads:
        rd = parse_reg(ops[0])
        off, rs1 = parse_mem(ops[1], labels, pc)
        return encode_i(off, rs1, loads[op], rd, 0x03)

    # --- Stores ---
    stores = {"sb": 0, "sh": 1, "sw": 2}
    if op in stores:
        rs2 = parse_reg(ops[0])
        off, rs1 = parse_mem(ops[1], labels, pc)
        return encode_s(off, rs2, rs1, stores[op], 0x23)

    # --- Branches ---
    branches = {"beq": 0, "bne": 1, "blt": 4, "bge": 5, "bltu": 6, "bgeu": 7}
    if op in branches:
        rs1 = parse_reg(ops[0])
        rs2 = parse_reg(ops[1])
        offset = parse_imm(ops[2], labels, pc, is_branch=True)
        return encode_b(offset, rs2, rs1, branches[op])

    # --- lui / auipc ---
    if op == "lui":
        rd = parse_reg(ops[0])
        imm = parse_imm(ops[1], labels, pc)
        return encode_u(imm, rd, 0x37)
    if op == "auipc":
        rd = parse_reg(ops[0])
        imm = parse_imm(ops[1], labels, pc)
        return encode_u(imm, rd, 0x17)

    # --- jal / jalr ---
    if op == "jal":
        if len(ops) == 1:
            return encode_j(parse_imm(ops[0], labels, pc, is_branch=True), 1)
        rd = parse_reg(ops[0])
        offset = parse_imm(ops[1], labels, pc, is_branch=True)
        return encode_j(offset, rd)
    if op == "jalr":
        if len(ops) == 1:
            return encode_i(0, parse_reg(ops[0]), 0, 1, 0x67)
        rd = parse_reg(ops[0])
        off, rs1 = parse_mem(ops[1], labels, pc)
        return encode_i(off, rs1, 0, rd, 0x67)

    raise ValueError(f"Unknown instruction: {mnemonic}")


def handle_li_multi(mnemonic: str, operands: list[str], labels: dict, pc: int) -> list[int]:
    """Handle 'li' that might need lui+addi (2 instructions)."""
    if mnemonic.lower() != "li":
        return [assemble_insn(mnemonic, operands, labels, pc)]

    rd = parse_reg(operands[0].strip())
    imm = parse_imm(operands[1].strip(), labels, pc)

    if -2048 <= imm <= 2047:
        return [encode_i(imm, 0, 0, rd, 0x13)]

    upper = (imm + 0x800) >> 12
    lower = imm - (upper << 12)
    insns = [encode_u(upper & 0xFFFFF, rd, 0x37)]  # lui
    if lower != 0:
        insns.append(encode_i(lower & 0xFFF, rd, 0, rd, 0x13))  # addi
    return insns


# -----------------------------------------------------------------------
# Parser
# -----------------------------------------------------------------------
COMMENT_RE = re.compile(r"[#;].*$")
LABEL_RE = re.compile(r"^(\w+):\s*(.*)")


def parse_line(line: str) -> tuple:
    """Return (label_or_None, mnemonic_or_None, operands_list)."""
    line = COMMENT_RE.sub("", line).strip()
    if not line:
        return None, None, []

    m = LABEL_RE.match(line)
    label = None
    if m:
        label = m.group(1)
        line = m.group(2).strip()

    if not line:
        return label, None, []

    parts = line.split(None, 1)
    mnemonic = parts[0]
    operands = []
    if len(parts) > 1:
        # Split operands by comma, but not inside parentheses
        raw = parts[1]
        depth = 0
        current = []
        for ch in raw:
            if ch == '(':
                depth += 1
            elif ch == ')':
                depth -= 1
            if ch == ',' and depth == 0:
                operands.append(''.join(current).strip())
                current = []
            else:
                current.append(ch)
        if current:
            operands.append(''.join(current).strip())

    return label, mnemonic, operands


def assemble(lines: list[str]) -> list[int]:
    """Two-pass assembly. Returns list of 32-bit machine code words."""

    # --- Pass 1: collect labels, compute sizes ---
    labels = {}
    insn_list = []  # (pc, mnemonic, operands)
    pc = 0

    for line in lines:
        label, mnemonic, operands = parse_line(line)
        if label:
            if label.startswith("_"):
                labels[label] = pc
            else:
                labels[label] = pc

        if mnemonic:
            # Estimate size for li (could be 1 or 2 insns)
            if mnemonic.lower() == "li" and len(operands) >= 2:
                try:
                    imm = parse_imm(operands[1].strip(), {}, pc)
                    size = 4 if -2048 <= imm <= 2047 else 8
                except Exception:
                    size = 8  # assume worst case
            else:
                size = 4
            insn_list.append((pc, mnemonic, operands, size))
            pc += size

        if label and not label.startswith("_"):
            labels[label] = insn_list[-1][0] if insn_list and insn_list[-1][0] == pc - (insn_list[-1][3] if insn_list else 0) else pc
            # Re-assign: label points to current instruction start
            labels[label] = pc - (insn_list[-1][3] if insn_list and insn_list[-1][0] == pc - insn_list[-1][3] else 0)

    # Re-do pass 1 properly
    labels = {}
    entries = []
    pc = 0
    for line in lines:
        label, mnemonic, operands = parse_line(line)
        if label:
            labels[label] = pc
        if mnemonic:
            if mnemonic.lower() == "li" and len(operands) >= 2:
                try:
                    imm = parse_imm(operands[1].strip(), labels, pc)
                    size = 4 if -2048 <= imm <= 2047 else 8
                except Exception:
                    size = 8
            else:
                size = 4
            entries.append((pc, mnemonic, operands))
            pc += size

    # --- Pass 2: encode ---
    code = []
    pc = 0
    for entry_pc, mnemonic, operands in entries:
        pc = entry_pc
        words = handle_li_multi(mnemonic, operands, labels, pc)
        code.extend(words)
        pc += len(words) * 4

    return code


def main():
    parser = argparse.ArgumentParser(description="RISC-V RV32I assembler → $readmemh hex")
    parser.add_argument("input", help="Input assembly file (.s)")
    parser.add_argument("-o", "--output", default=None, help="Output hex file")
    parser.add_argument("--binary", action="store_true", help="Also output raw binary")
    args = parser.parse_args()

    input_path = os.path.abspath(args.input)
    if not os.path.isfile(input_path):
        print(f"ERROR: File not found: {input_path}")
        sys.exit(1)

    with open(input_path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    code = assemble(lines)
    print(f"Assembled: {input_path}")
    print(f"  {len(code)} instructions, {len(code)*4} bytes")

    # Output hex
    if args.output:
        hex_path = os.path.abspath(args.output)
    else:
        base = os.path.splitext(os.path.basename(input_path))[0]
        hex_path = os.path.join(os.path.dirname(input_path), f"{base}.hex")

    with open(hex_path, "w") as f:
        for word in code:
            f.write(f"{word & 0xFFFFFFFF:08X}\n")
    print(f"  HEX: {hex_path}")

    if args.binary:
        bin_path = os.path.splitext(hex_path)[0] + ".bin"
        with open(bin_path, "wb") as f:
            for word in code:
                f.write((word & 0xFFFFFFFF).to_bytes(4, "little"))
        print(f"  BIN: {bin_path}")

    # Print disassembly preview
    print("\n  Disassembly preview (first 20 words):")
    for i, word in enumerate(code[:20]):
        print(f"    {i*4:04X}: {word & 0xFFFFFFFF:08X}")


if __name__ == "__main__":
    main()
