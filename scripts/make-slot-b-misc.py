#!/usr/bin/env python3
"""Create an RMX3630 misc image with controlled A/B boot metadata."""

from __future__ import annotations

import argparse
import hashlib
import struct
import zlib
from pathlib import Path


BOOT_CONTROL_OFFSET = 0x800
BOOT_CONTROL_SIZE = 32
CRC_OFFSET = 28
BOOT_CTRL_MAGIC = b"BCAB"


def slot_info(data: bytes, offset: int) -> str:
    flags = data[offset]
    extra = data[offset + 1]
    return (
        f"priority={flags & 0x0F}, tries={(flags >> 4) & 0x07}, "
        f"successful={(flags >> 7) & 0x01}, "
        f"verity_corrupted={extra & 0x01}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument(
        "--target-slot",
        choices=("a", "b"),
        default="b",
        help="B is a persistent rescue boot; A is a one-shot test boot",
    )
    parser.add_argument(
        "--persistent",
        action="store_true",
        help="mark the selected slot successful instead of consuming boot tries",
    )
    args = parser.parse_args()

    if args.persistent and args.target_slot != "a":
        parser.error("--persistent is currently supported only with --target-slot a")

    source = bytearray(args.input.read_bytes())
    base = BOOT_CONTROL_OFFSET
    end = base + BOOT_CONTROL_SIZE
    if len(source) < end:
        raise SystemExit(f"Input is too short: {len(source)} bytes; need at least {end}")

    block = source[base:end]
    suffix = bytes(block[0:4]).rstrip(b"\x00").decode("ascii", errors="replace")
    if bytes(block[4:8]) != BOOT_CTRL_MAGIC:
        raise SystemExit(
            f"Bad boot-control magic at 0x{base + 4:X}: {bytes(block[4:8]).hex()}"
        )
    if block[8] != 1 or (block[9] & 0x07) != 2:
        raise SystemExit(
            f"Unexpected boot-control header: version={block[8]}, nb_slot={block[9] & 0x07}"
        )

    stored_crc = struct.unpack_from("<I", block, CRC_OFFSET)[0]
    computed_crc = zlib.crc32(block[:CRC_OFFSET]) & 0xFFFFFFFF
    if stored_crc != computed_crc:
        raise SystemExit(
            f"CRC mismatch: stored=0x{stored_crc:08X}, computed=0x{computed_crc:08X}"
        )

    print(f"Input: {args.input}")
    print(f"Size: {len(source)} bytes")
    print(f"Current suffix: {suffix!r}")
    print(f"Slot A before: {slot_info(block, 12)}")
    print(f"Slot B before: {slot_info(block, 14)}")
    print(f"CRC before: 0x{stored_crc:08X} (valid)")

    if args.target_slot == "b":
        # Persistent rescue boot: A is not bootable and B is successful.
        source[base : base + 4] = b"_b\x00\x00"
        source[base + 12] = 0x0E  # A: priority 14, tries 0, not successful
        source[base + 13] = 0x00
        source[base + 14] = 0xFF  # B: priority 15, tries 7, successful
        source[base + 15] = 0x00
    elif args.persistent:
        # Persistent Linux boot: A is already known to reach userspace, so do
        # not let LK consume a final try and silently fall back to recovery B.
        source[base : base + 4] = b"_a\x00\x00"
        source[base + 12] = 0xFF  # A: priority 15, tries 7, successful
        source[base + 13] = 0x00
        source[base + 14] = 0xFE  # B: priority 14, tries 7, successful rescue
        source[base + 15] = 0x00
    else:
        # One-shot test boot: LK consumes A's only try before booting it. If
        # Linux fails or does not mark the slot successful, the next reset
        # falls back to the known-good B slot automatically.
        source[base : base + 4] = b"_a\x00\x00"
        source[base + 12] = 0x1F  # A: priority 15, tries 1, not successful
        source[base + 13] = 0x00
        source[base + 14] = 0xFE  # B: priority 14, tries 7, successful
        source[base + 15] = 0x00

    new_crc = zlib.crc32(source[base : base + CRC_OFFSET]) & 0xFFFFFFFF
    struct.pack_into("<I", source, base + CRC_OFFSET, new_crc)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(source)

    result = bytes(source[base:end])
    print(f"Slot A after:  {slot_info(result, 12)}")
    print(f"Slot B after:  {slot_info(result, 14)}")
    print(f"CRC after:  0x{new_crc:08X}")
    print(f"Output: {args.output}")
    print(f"SHA256: {hashlib.sha256(source).hexdigest()}")


if __name__ == "__main__":
    main()
