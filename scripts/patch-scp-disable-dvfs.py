#!/usr/bin/env python3
"""Disable the broken MediaTek SCP DVFS path in a copy of scp.ko.

The RMX3630 vendor driver can loop forever when the scp_dvfs platform
device fails to probe.  This patch mirrors the documented DT
``scp-dvfs-disable`` path without changing the phone's vendor_boot:

* scp_dvfs_init() returns success without registering the DVFS driver;
* wait_scp_dvfs_init_done() returns immediately;
* scp_dvfs_feature_enable() always reports disabled.

Only ELF64 little-endian relocatable AArch64 modules are accepted.  Symbol
locations are resolved from the module's own symbol table instead of being
hard-coded for one build.
"""

from __future__ import annotations

import argparse
import hashlib
import struct
from dataclasses import dataclass
from pathlib import Path


ELF_HEADER = struct.Struct("<16sHHIQQQIHHHHHH")
SECTION_HEADER = struct.Struct("<IIQQQQIIQQ")
SYMBOL = struct.Struct("<IBBHQQ")

# AArch64: mov w0, #0; ret
RETURN_ZERO = bytes.fromhex("00008052c0035fd6")
# AArch64: ret
RETURN_VOID = bytes.fromhex("c0035fd6")


@dataclass(frozen=True)
class Section:
    name_offset: int
    section_type: int
    offset: int
    size: int
    link: int
    entry_size: int


def c_string(blob: bytes, offset: int) -> str:
    end = blob.find(b"\0", offset)
    if end < 0:
        raise ValueError("unterminated ELF string")
    return blob[offset:end].decode("ascii")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    original = args.input.read_bytes()
    data = bytearray(original)
    if len(data) < ELF_HEADER.size:
        raise ValueError("input is too small to be an ELF file")

    (
        ident,
        elf_type,
        machine,
        _version,
        _entry,
        _phoff,
        section_offset,
        _flags,
        _ehsize,
        _phentsize,
        _phnum,
        section_entry_size,
        section_count,
        section_names_index,
    ) = ELF_HEADER.unpack_from(data)

    if ident[:6] != b"\x7fELF\x02\x01":
        raise ValueError("expected ELF64 little-endian input")
    if elf_type != 1 or machine != 183:
        raise ValueError("expected an AArch64 relocatable module")
    if section_entry_size != SECTION_HEADER.size:
        raise ValueError("unexpected ELF section-header size")

    sections: list[Section] = []
    for index in range(section_count):
        values = SECTION_HEADER.unpack_from(
            data, section_offset + index * section_entry_size
        )
        sections.append(
            Section(
                name_offset=values[0],
                section_type=values[1],
                offset=values[4],
                size=values[5],
                link=values[6],
                entry_size=values[9],
            )
        )

    section_names = sections[section_names_index]
    section_name_blob = bytes(
        data[section_names.offset : section_names.offset + section_names.size]
    )
    names = [c_string(section_name_blob, section.name_offset) for section in sections]

    try:
        symtab_index = names.index(".symtab")
    except ValueError as exc:
        raise ValueError("module has no .symtab") from exc
    symtab = sections[symtab_index]
    if symtab.entry_size != SYMBOL.size:
        raise ValueError("unexpected ELF symbol size")
    strtab = sections[symtab.link]
    symbol_names = bytes(data[strtab.offset : strtab.offset + strtab.size])

    wanted = {
        "scp_dvfs_init": RETURN_ZERO,
        "wait_scp_dvfs_init_done": RETURN_VOID,
        "scp_dvfs_feature_enable": RETURN_ZERO,
    }
    found: dict[str, tuple[int, int, bytes]] = {}

    for offset in range(symtab.offset, symtab.offset + symtab.size, symtab.entry_size):
        name_offset, _info, _other, section_index, value, size = SYMBOL.unpack_from(
            data, offset
        )
        if not name_offset or section_index == 0:
            continue
        name = c_string(symbol_names, name_offset)
        replacement = wanted.get(name)
        if replacement is None:
            continue
        if size < len(replacement):
            raise ValueError(f"symbol {name} is unexpectedly short")
        section = sections[section_index]
        file_offset = section.offset + value
        found[name] = (file_offset, size, replacement)

    missing = sorted(set(wanted) - set(found))
    if missing:
        raise ValueError(f"missing symbols: {', '.join(missing)}")

    print(f"input sha256:  {sha256(original)}")
    for name in wanted:
        file_offset, size, replacement = found[name]
        before = bytes(data[file_offset : file_offset + len(replacement)])
        print(
            f"{name}: file+0x{file_offset:x}, size={size}, "
            f"{before.hex()} -> {replacement.hex()}"
        )
        data[file_offset : file_offset + len(replacement)] = replacement

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(data)
    print(f"output sha256: {sha256(data)}")
    print(f"wrote: {args.output}")


if __name__ == "__main__":
    main()
