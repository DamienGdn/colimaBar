#!/usr/bin/env python3
"""Pack build/AppIcon.iconset into Resources/AppIcon.icns without iconutil.

`make icons` uses Apple's iconutil on macOS; this is the portable fallback
(Linux / CI). PNG payloads are valid for every entry on macOS 10.7+.
"""
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ICONSET = ROOT / "build" / "AppIcon.iconset"
OUT = ROOT / "Resources" / "AppIcon.icns"

# OSType -> iconset file
ENTRIES = [
    ("icp4", "icon_16x16.png"),
    ("ic11", "icon_16x16@2x.png"),
    ("icp5", "icon_32x32.png"),
    ("ic12", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic13", "icon_128x128@2x.png"),
    ("ic08", "icon_256x256.png"),
    ("ic14", "icon_256x256@2x.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png"),
]


def main() -> int:
    chunks = b""
    for ostype, name in ENTRIES:
        data = (ICONSET / name).read_bytes()
        if not data.startswith(b"\x89PNG"):
            print(f"{name} is not a PNG", file=sys.stderr)
            return 1
        chunks += ostype.encode("ascii") + struct.pack(">I", len(data) + 8) + data
    OUT.write_bytes(b"icns" + struct.pack(">I", len(chunks) + 8) + chunks)
    print(f"Wrote {OUT.relative_to(ROOT)} ({len(ENTRIES)} entries)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
