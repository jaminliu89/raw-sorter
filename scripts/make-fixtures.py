#!/usr/bin/env python3
"""生成无照片内容的 TIFF/EXIF 样本，CI 不读取或上传用户原片。"""
import pathlib
import struct
import sys

def fixture(path, clock, subsecond, serial):
    exif = [(0x9003, clock), (0x9011, "+08:00"), (0x9291, subsecond), (0xA431, serial)]
    root_count = 3
    exif_offset = 8 + 2 + root_count * 12 + 4
    data_offset = exif_offset + 2 + len(exif) * 12 + 4
    payload = bytearray()

    def ascii_entry(tag, text):
        raw = text.encode("ascii") + b"\0"
        if len(raw) <= 4:
            field = raw.ljust(4, b"\0")
        else:
            field = struct.pack("<I", data_offset + len(payload))
            payload.extend(raw)
            if len(payload) % 2:
                payload.append(0)
        return struct.pack("<HHI", tag, 2, len(raw)) + field

    entries = [ascii_entry(0x010F, "SONY"), ascii_entry(0x0110, "ILCE-7M4"),
               struct.pack("<HHII", 0x8769, 4, 1, exif_offset)]
    exif_entries = [ascii_entry(tag, text) for tag, text in exif]
    data = b"II" + struct.pack("<HIH", 42, 8, root_count)
    data += b"".join(entries) + struct.pack("<IH", 0, len(exif))
    data += b"".join(exif_entries) + struct.pack("<I", 0) + payload
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)

if __name__ == "__main__":
    root = pathlib.Path(sys.argv[1])
    fixture(root / "A.ARW", "2026:10:22 05:52:46", "696", "SYNTHETIC-A")
    fixture(root / "B.ARW", "2026:10:22 06:12:51", "553", "SYNTHETIC-B")
    print(root)
