#!/usr/bin/env python3
"""Patch selected CRC values in a Linux module's __versions ELF section."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path


def elf_sections(data: bytes) -> dict[str, tuple[int, int]]:
    if data[:4] != b"\x7fELF" or data[4] != 2 or data[5] != 1:
        raise SystemExit("expected a little-endian ELF64 module")

    section_offset = struct.unpack_from("<Q", data, 0x28)[0]
    section_size = struct.unpack_from("<H", data, 0x3A)[0]
    section_count = struct.unpack_from("<H", data, 0x3C)[0]
    names_index = struct.unpack_from("<H", data, 0x3E)[0]

    def section_header(index: int) -> tuple[int, int, int]:
        offset = section_offset + index * section_size
        name_offset = struct.unpack_from("<I", data, offset)[0]
        file_offset = struct.unpack_from("<Q", data, offset + 0x18)[0]
        file_size = struct.unpack_from("<Q", data, offset + 0x20)[0]
        return name_offset, file_offset, file_size

    _, names_offset, names_size = section_header(names_index)
    names = data[names_offset : names_offset + names_size]
    result: dict[str, tuple[int, int]] = {}
    for index in range(section_count):
        name_offset, file_offset, file_size = section_header(index)
        name_end = names.find(b"\0", name_offset)
        name = names[name_offset:name_end].decode("ascii")
        result[name] = (file_offset, file_size)
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--set", action="append", default=[], metavar="SYMBOL=CRC")
    parser.add_argument(
        "--set-file",
        action="append",
        default=[],
        type=Path,
        metavar="PATH",
        help="read SYMBOL CRC pairs from a whitespace-delimited file",
    )
    parser.add_argument(
        "--ignore-missing",
        action="store_true",
        help="skip mappings for symbols absent from this module",
    )
    args = parser.parse_args()

    replacements: dict[str, int] = {}
    for item in args.set:
        symbol, separator, crc = item.partition("=")
        if not separator or not symbol:
            raise SystemExit(f"invalid --set value: {item}")
        replacements[symbol] = int(crc, 0)

    for mapping_path in args.set_file:
        for line_number, line in enumerate(
            mapping_path.read_text(encoding="utf-8").splitlines(), start=1
        ):
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            fields = stripped.split()
            if len(fields) != 2:
                raise SystemExit(
                    f"{mapping_path}:{line_number}: expected SYMBOL CRC"
                )
            symbol, crc = fields
            replacements[symbol] = int(crc, 0)

    data = bytearray(args.input.read_bytes())
    sections = elf_sections(data)
    if "__versions" not in sections:
        raise SystemExit("module has no __versions section")
    versions_offset, versions_size = sections["__versions"]
    # ELF64 modules use struct modversion_info { u64 crc; char name[56]; }.
    # Searching the section as a byte string is unsafe: "schedule\0" also
    # occurs inside "preempt_schedule\0" and would corrupt that record.
    record_size = 64
    if versions_size % record_size:
        raise SystemExit(
            f"unexpected __versions size {versions_size} for ELF64 records"
        )

    record_offsets: dict[str, int] = {}
    for relative_offset in range(0, versions_size, record_size):
        name_start = versions_offset + relative_offset + 8
        name_end = data.find(b"\0", name_start, name_start + 56)
        if name_end < 0:
            raise SystemExit("unterminated symbol name in __versions")
        name = data[name_start:name_end].decode("ascii")
        record_offsets[name] = versions_offset + relative_offset

    for symbol, crc in replacements.items():
        crc_offset = record_offsets.get(symbol)
        if crc_offset is None:
            if args.ignore_missing:
                continue
            raise SystemExit(f"symbol not found in __versions: {symbol}")
        previous = struct.unpack_from("<Q", data, crc_offset)[0]
        struct.pack_into("<Q", data, crc_offset, crc)
        print(f"{symbol}: 0x{previous:08x} -> 0x{crc:08x}")

    args.output.write_bytes(data)


if __name__ == "__main__":
    main()
