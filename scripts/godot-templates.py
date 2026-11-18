"""Extract one release template from Godot's official 4.7.2 bundle using HTTP ranges."""
from io import BytesIO
from pathlib import Path
import os
import struct
import subprocess
import sys
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / ".cache"
RELEASE = "https://godot-releases.nbg1.your-objectstorage.com/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"
# The per-file checksums and offsets are from the central directory of the official TPZ.
# Pin the release, so a truncated download or a changed bundle fails before export.
TEMPLATES = {
    "web": ("web_nothreads_release.zip", 1053533745, 10221889, 10245903, 0x795d38e9),
    "mac": ("macos.zip", 863271834, 122879384, 123597580, 0x2986734b),
}

def extract(kind):
    name, start, length, raw_length, crc = TEMPLATES[kind]
    dest = CACHE / "templates" / name
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and dest.stat().st_size == raw_length and zlib.crc32(dest.read_bytes()) == crc:
        print(dest)
        return
    part = CACHE / f"template-{kind}.part"
    if not part.exists() or part.stat().st_size != length:
        pending = part.with_suffix(".download")
        subprocess.run(["curl", "-fLSs", "--retry", "2", "--range", f"{start}-{start + length - 1}",
                        RELEASE, "-o", str(pending)], check=True)
        if pending.stat().st_size != length:
            raise ValueError("Official server did not return the requested template range")
        os.replace(pending, part)
    data = part.read_bytes()
    sig, _, _, method, _, _, stored_crc, size, _, namesize, extrasize = struct.unpack_from("<4s5H3I2H", data)
    if (sig, method, stored_crc, data[30:30 + namesize]) != (b"PK\x03\x04", 8, crc, f"templates/{name}".encode()):
        raise ValueError(f"Invalid template header in {part}")
    offset = 30 + namesize + extrasize
    raw = zlib.decompress(data[offset:offset + size], -15)
    if len(raw) != raw_length or zlib.crc32(raw) != crc:
        raise ValueError(f"Checksum failed in {part}")
    with zipfile.ZipFile(BytesIO(raw)) as inner:
        invalid = inner.testzip()
        if invalid:
            raise ValueError(f"Invalid zip member {invalid}")
    temp = dest.with_suffix(".tmp")
    temp.write_bytes(raw)
    os.replace(temp, dest)
    print(dest)

if __name__ == "__main__":
    extract(sys.argv[1])
