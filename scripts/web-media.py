#!/usr/bin/env python3
"""An app's bundled files in formats every browser reads, and the list of them (new-website#746).

    scripts/web-media.py <bundle>/assets --manifest <bundle>/assets/manifest.js [--cache DIR]

iOS reads a bundle's HEIC pictures, HEVC clips and Apple Lossless sounds; Chrome and Firefox
read none of them, and the runtime decodes no HEIC at all. Each such file is converted once, by
file type, never by name:

- `.heic` / `.heif` -> WebP (lossy q85, alpha q90), alpha kept. The app keeps asking for
  `a000.heic`; the list maps that name to the WebP, and `UIImage(data:)` reads the bytes.
- `.mov` / `.mp4` clips stay (Safari plays HEVC with alpha), and a VP9 WebM with alpha is
  written beside each (`<name>.webm`), which Chrome and Firefox play with its alpha.
- `.caf` (Apple Lossless and the like) -> 16-bit PCM WAV under the same name, which every
  browser decodes and `AVAudioFile` reads at once.

A clip's duration and size go in the manifest too (`window.__swiftuiwebAssets.clips`), since
iOS knows them at once. Then the list of every file under the assets, as the app names them, is appended to the
manifest script (`window.__swiftuiwebAssets.files`): `Bundle.url(forResource:)` answers nil
for a file the bundle doesn't have, as iOS does, `FileManager.fileExists` answers without a
request, and a renamed file is read from its new name.

Conversions are cached by the source's hash (`--cache`), so a rebuild converts only what changed.
Tools: `sips` (macOS) or `heif-dec`/`heif-convert` (libheif) for HEIC, `cwebp`, and `ffmpeg`
(a build that decodes HEVC's alpha layer, 8 or newer, for the WebM). A missing tool leaves the
file as it is, with a warning: the app then finds it missing in browsers that can't read it.
"""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

PICTURES = {".heic", ".heif"}
CLIPS = {".mov", ".mp4", ".m4v"}
SOUNDS = {".caf"}
# Files the list leaves out: the page's own scripts, not the app's files.
UNLISTED = {"manifest.js", "symbol-metrics.txt"}


def warn(message):
    print(f"web-media: {message}", file=sys.stderr)


def tool(*names):
    return next((shutil.which(n) for n in names if shutil.which(n)), None)


def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()[:32]


def run(command):
    return subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)


def has_alpha_stream(path):
    """Whether a clip carries an alpha layer (HEVC with alpha), so its WebM keeps one."""
    probe = tool("ffprobe")
    if not probe:
        return True
    out = subprocess.run([probe, "-v", "error", "-show_entries", "stream_tags:stream=codec_name", "-of", "json", str(path)],
                         capture_output=True, text=True).stdout
    return "alpha" in out.lower() or "hevc" in out.lower()


def picture_to_webp(source, target):
    with tempfile.TemporaryDirectory() as scratch:
        png = Path(scratch) / "frame.png"
        if tool("sips") and sys.platform == "darwin":
            r = run(["sips", "-s", "format", "png", str(source), "--out", str(png)])
        elif tool("heif-dec", "heif-convert"):
            r = run([tool("heif-dec", "heif-convert"), str(source), str(png)])
        else:
            return "no HEIC decoder (sips, or libheif's heif-dec)"
        if r.returncode or not png.exists():
            return r.stderr.strip() or "HEIC decode failed"
        r = run([tool("cwebp"), "-quiet", "-q", "85", "-alpha_q", "90", "-exact", str(png), "-o", str(target)]) if tool("cwebp") else None
        if r is None:
            return "no cwebp"
        return r.stderr.strip() or "cwebp failed" if r.returncode else None


def clip_facts(path):
    """A clip's duration and picture size, which iOS knows at once (`AVURLAsset.duration`) and a
    page learns only once a video element has read the file."""
    probe = tool("ffprobe")
    if not probe:
        return None
    out = subprocess.run([probe, "-v", "error", "-select_streams", "v:0", "-show_entries", "format=duration:stream=width,height",
                          "-of", "json", str(path)], capture_output=True, text=True).stdout
    try:
        facts = json.loads(out)
        stream = facts["streams"][0]
        return {"duration": round(float(facts["format"]["duration"]), 4), "width": stream["width"], "height": stream["height"]}
    except (ValueError, KeyError, IndexError):
        return None


def clip_to_webm(source, target):
    ffmpeg = tool("ffmpeg")
    if not ffmpeg:
        return "no ffmpeg"
    alpha = has_alpha_stream(source)
    command = [ffmpeg, "-v", "error", "-y", "-i", str(source), "-an", "-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "28",
               "-row-mt", "1", "-deadline", "good", "-cpu-used", "2"]
    command += ["-pix_fmt", "yuva420p", "-auto-alt-ref", "0"] if alpha else ["-pix_fmt", "yuv420p"]
    r = run(command + [str(target)])
    return r.stderr.strip() or "ffmpeg failed" if r.returncode else None


def sound_to_wav(source, target):
    ffmpeg = tool("ffmpeg")
    if not ffmpeg:
        return "no ffmpeg"
    r = run([ffmpeg, "-v", "error", "-y", "-i", str(source), "-c:a", "pcm_s16le", "-f", "wav", str(target)])
    return r.stderr.strip() or "ffmpeg failed" if r.returncode else None


def convert(job, cache):
    """One file: (relative path, kind). Returns (relative, stored relative or None, extra files)."""
    assets, relative, kind = job
    source = assets / relative
    key = digest(source)
    if kind == "picture":
        stored, make = relative.with_suffix(".webp"), picture_to_webp
    elif kind == "clip":
        stored, make = relative.with_suffix(".webm"), clip_to_webm
    else:
        stored, make = relative, sound_to_wav   # same name: the app names the file, the bytes are a WAV
    cached = cache / f"{key}{'.wav' if kind == 'sound' else stored.suffix}"
    if not cached.exists():
        with tempfile.TemporaryDirectory() as scratch:
            made = Path(scratch) / ("out" + cached.suffix)
            error = make(source, made)
            if error or not made.exists():
                return relative, None, f"{relative}: {error or 'nothing written'}"
            shutil.move(str(made), cached)
    shutil.copyfile(cached, assets / stored)
    if kind == "picture":
        source.unlink()
    return relative, stored, None


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("assets", help="the bundle's assets directory")
    parser.add_argument("--manifest", help="the manifest script to append the file list to")
    parser.add_argument("--cache", default=os.path.join(os.environ.get("TMPDIR", "/tmp"), "swiftuiweb-media"),
                        help="where converted files are kept between builds")
    args = parser.parse_args()
    assets = Path(args.assets).resolve()
    cache = Path(args.cache)
    cache.mkdir(parents=True, exist_ok=True)

    jobs = []
    for path in sorted(assets.rglob("*")):
        if not path.is_file():
            continue
        suffix = path.suffix.lower()
        kind = "picture" if suffix in PICTURES else "clip" if suffix in CLIPS else "sound" if suffix in SOUNDS else None
        if kind:
            jobs.append((assets, path.relative_to(assets), kind))

    renames, failed = {}, []
    with ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as pool:
        for relative, stored, error in pool.map(lambda j: convert(j, cache), jobs):
            if error:
                failed.append(error)
            elif stored != relative and stored.suffix != ".webm":
                renames[relative.as_posix()] = stored.as_posix()
    for error in failed[:10]:
        warn(error)
    if len(failed) > 10:
        warn(f"... and {len(failed) - 10} more")

    # Every file as the app names it: a renamed one under its old name, pointing at its new one.
    listed = {}
    stored_names = set(renames.values())
    for path in sorted(assets.rglob("*")):
        if not path.is_file() or path.name.startswith("."):
            continue
        relative = path.relative_to(assets).as_posix()
        if relative in UNLISTED or relative in stored_names:
            continue
        listed[relative] = 1
    for old, new in renames.items():
        listed[old] = new
    clips = {}
    for assets_, relative, kind in jobs:
        if kind == "clip" and (facts := clip_facts(assets / relative)):
            clips[relative.as_posix()] = facts
    if args.manifest:
        with open(args.manifest, "a") as f:
            f.write("(function(){var m=window.__swiftuiwebAssets;if(m){m.files=" + json.dumps(dict(sorted(listed.items())), separators=(",", ":"))
                    + ";m.clips=" + json.dumps(clips, separators=(",", ":"), sort_keys=True)
                    # A WGSL twin means the app draws with Metal: the page asks for a GPU device while it loads.
                    + (";m.gpu=true" if any(k.startswith("Shaders/") and k.endswith(".wgsl") for k in listed) else "") + ";}})();\n")
    converted = {k: sum(1 for j in jobs if j[2] == k) for k in ("picture", "clip", "sound")}
    print(f"web-media: {len(listed)} file(s) listed; converted {converted['picture']} picture(s) to WebP, "
          f"{converted['clip']} clip(s) to WebM beside them, {converted['sound']} sound(s) to WAV; {len(failed)} failed",
          file=sys.stderr)


if __name__ == "__main__":
    main()
