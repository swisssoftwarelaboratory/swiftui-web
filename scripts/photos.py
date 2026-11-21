#!/usr/bin/env python3
"""The drawn phone's photo library for one build (Docs/elements/PhotosPicker.md).

    scripts/photos.py <app Photos folder> <everyday folder> --out <bundle>/assets/photos

Copies the app's own demo photos, then the everyday set every app shares, into --out and writes
--out/photos.json: {"photos": [{"file", "width", "height"}]}, newest first. Within each folder
the names sort that way: the first name is the newest photo (name them 01-front.jpg, 02-…).
Width and height are upright pixels (a JPEG's EXIF orientation applied). Either folder may be
missing; JPEG, PNG and GIF files are taken, anything else (credits, notes) is left out.
"""
import argparse
import json
import pathlib
import shutil
import struct
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from assets import image_size  # noqa: E402


def exif_orientation(data):
    """The EXIF orientation of JPEG bytes (1 when there is none)."""
    i = 2
    while i + 4 < len(data) and data[i] == 0xFF:
        marker = data[i + 1]
        length = struct.unpack(">H", data[i + 2:i + 4])[0]
        if marker == 0xE1 and data[i + 4:i + 10] == b"Exif\0\0":
            tiff = data[i + 10:i + 2 + length]
            endian = "<" if tiff[:2] == b"II" else ">"
            ifd = struct.unpack(endian + "I", tiff[4:8])[0]
            count = struct.unpack(endian + "H", tiff[ifd:ifd + 2])[0]
            for n in range(count):
                entry = tiff[ifd + 2 + 12 * n:ifd + 14 + 12 * n]
                if struct.unpack(endian + "H", entry[:2])[0] == 0x0112:
                    return struct.unpack(endian + "H", entry[8:10])[0]
            return 1
        if marker == 0xDA:
            break
        i += 2 + length
    return 1


def photos(folder):
    if not folder.is_dir():
        return []
    return sorted(p for p in folder.iterdir() if p.suffix.lower() in (".jpg", ".jpeg", ".png", ".gif"))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("app")
    parser.add_argument("everyday")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    out = pathlib.Path(args.out)
    shutil.rmtree(out, ignore_errors=True)
    entries = []
    for group, folder in (("app", pathlib.Path(args.app)), ("everyday", pathlib.Path(args.everyday))):
        for path in photos(folder):
            size = image_size(path)
            if size is None:
                print(f"photos.py: {path} is not an image this script can read, left out", file=sys.stderr)
                continue
            width, height = size
            if path.suffix.lower() in (".jpg", ".jpeg") and exif_orientation(path.read_bytes()) in (5, 6, 7, 8):
                width, height = height, width
            name = f"{group}/{path.name}"
            (out / group).mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, out / name)
            entries.append({"file": name, "width": width, "height": height})
    out.mkdir(parents=True, exist_ok=True)
    (out / "photos.json").write_text(json.dumps({"photos": entries}, indent=1) + "\n")


if __name__ == "__main__":
    main()
