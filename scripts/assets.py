#!/usr/bin/env python3
"""Reads Xcode asset catalogs (`*.xcassets`) the way actool would, without Xcode, and writes what
SwiftUIWeb needs at run time: a manifest of image sets (variants per scale, idiom and appearance,
pixel sizes, template intent) and colour sets, plus a copy of every image file it references.

    scripts/assets.py <dir> --out <bundle-dir>/assets   # every *.xcassets under <dir>
    scripts/assets.py Fixtures --json Fixtures/Assets.manifest.json --out .build/assets

Outputs (all optional): --json <file> the manifest as JSON; --js <file> the same wrapped as
`window.__swiftuiwebAssets = …` for a <script> tag; --out <dir> the referenced files, laid out as
<catalog>/<set>.imageset/<file> so names never collide. File paths in the manifest are relative to
--out. Names follow the catalog: a folder with `provides-namespace` prefixes its contents
("Folder/nested"), any other folder is transparent. Vector images: an SVG is copied as it is (the
browser draws it at any scale; its point size comes from its width/height or viewBox) and a PDF
is rasterised at 1×, 2× and 3× with `sips` as Xcode's actool does (skipped with a warning where
`sips` is missing). Slicing metadata (`resizing`) becomes `capInsets` and `tilesCenter` on the set.
Unsupported: symbol sets, sprite atlases, high-contrast and Display P3 variants (recorded but
ignored by the runtime), data sets, app icons. Each is reported on stderr."""
import argparse, json, re, shutil, struct, subprocess, sys
from pathlib import Path

SKIPPED_DIRS = {".build", "node_modules", ".git", ".swiftpm"}
IDIOMS = {"universal", "mac", "iphone", "ipad", "tv", "watch", "car", "vision"}



def _rglob(root, pattern):
    """`Path.rglob` that also follows linked folders (an app's checkout linked in as `upstream/<app>`),
    which `rglob` skips before Python 3.13. A `.build` folder is never searched."""
    import fnmatch, os
    found = []
    for directory, folders, files in os.walk(root, followlinks=True):
        folders[:] = [f for f in folders if f != ".build"]
        for name in folders + files:
            if fnmatch.fnmatch(name, pattern):
                found.append(Path(directory) / name)
    return found

def warn(message):
    print(f"assets: {message}", file=sys.stderr)


def read_contents(directory):
    file = directory / "Contents.json"
    if not file.exists(): return {}
    try:
        return json.loads(file.read_text())
    except json.JSONDecodeError as error:
        warn(f"{file}: {error}")
        return {}


def image_size(path):
    """(width, height) in pixels for PNG, JPEG and GIF; None for anything else."""
    data = path.read_bytes()
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return struct.unpack(">II", data[16:24])
    if data[:6] in (b"GIF87a", b"GIF89a"):
        return struct.unpack("<HH", data[6:10])
    if data[:2] == b"\xff\xd8":
        i = 2
        while i + 9 < len(data):
            if data[i] != 0xFF: i += 1; continue
            marker = data[i + 1]
            if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7: i += 2; continue
            length = struct.unpack(">H", data[i + 2:i + 4])[0]
            if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                height, width = struct.unpack(">HH", data[i + 5:i + 9])
                return (width, height)
            i += 2 + length
    return None


def svg_size(path):
    """(width, height) in points from an SVG's width/height (px or unitless) or its viewBox."""
    head = path.read_text(errors="replace")[:4000]
    match = re.search(r"<svg\b[^>]*>", head, re.S)
    if not match: return None
    tag = match.group(0)
    def attribute(name):
        found = re.search(r'\b' + name + r'\s*=\s*["\']([^"\']*)["\']', tag)
        return found.group(1).strip() if found else None
    def length(text):
        if text is None: return None
        found = re.match(r"([0-9.]+)\s*(px)?$", text)
        return float(found.group(1)) if found else None
    width, height = length(attribute("width")), length(attribute("height"))
    if width and height: return (width, height)
    box = attribute("viewBox")
    if box:
        parts = box.replace(",", " ").split()
        if len(parts) == 4:
            try: return (float(parts[2]), float(parts[3]))
            except ValueError: pass
    return None


def pdf_size(path):
    """(width, height) in points of the first page's MediaBox."""
    data = path.read_bytes()
    match = re.search(rb"/MediaBox\s*\[\s*([-0-9.]+)\s+([-0-9.]+)\s+([-0-9.]+)\s+([-0-9.]+)\s*\]", data)
    if not match: return None
    x0, y0, x1, y1 = (float(v) for v in match.groups())
    return (abs(x1 - x0), abs(y1 - y0))


def appearance(entry):
    """'any', 'light' or 'dark', plus flags for the variants the runtime ignores."""
    value, contrast = "any", None
    for item in entry.get("appearances", []):
        if item.get("appearance") == "luminosity": value = item.get("value", "any")
        elif item.get("appearance") == "contrast": contrast = item.get("value")
    return value, contrast


def component(text):
    """Colour components come as "0.533", "0x88" or "136"."""
    text = str(text).strip()
    if text.lower().startswith("0x"): return int(text, 16) / 255
    if "." in text: return float(text)
    return int(text) / 255


class Catalog:
    def __init__(self, out):
        self.out = out
        self.images = {}
        self.colors = {}

    def read(self, root):
        self.root = root
        self.walk(root, "")

    def walk(self, directory, prefix):
        for child in sorted(directory.iterdir()):
            if not child.is_dir(): continue
            if child.suffix == ".imageset": self.imageset(child, prefix + child.stem)
            elif child.suffix == ".colorset": self.colorset(child, prefix + child.stem)
            elif child.suffix in (".appiconset", ".launchimage", ".brandassets", ".imagestack", ".cubetextureset", ".textureset"):
                pass
            elif child.suffix in (".symbolset", ".dataset", ".spriteatlas"):
                warn(f"{child.relative_to(self.root.parent)}: {child.suffix[1:]} is not supported")
            elif child.suffix == "":
                properties = read_contents(child).get("properties", {})
                self.walk(child, prefix + child.name + "/" if properties.get("provides-namespace") else prefix)

    def imageset(self, directory, name):
        doc = read_contents(directory)
        variants = []
        for entry in doc.get("images", []):
            filename = entry.get("filename")
            if not filename: continue           # an empty slot Xcode leaves for a scale
            path = directory / filename
            if not path.exists():
                warn(f"{name}: missing file {filename}"); continue
            idiom = entry.get("idiom", "universal")
            if idiom not in IDIOMS:
                warn(f"{name}: unknown idiom {idiom!r} for {filename}")
            luminosity, contrast = appearance(entry)
            def record(file, scale, size, vector=False):
                variant = {"file": file, "scale": scale, "width": size[0], "height": size[1],
                           "idiom": idiom, "appearance": luminosity}
                if vector: variant["vector"] = True
                if contrast: variant["contrast"] = contrast
                if entry.get("display-gamut"): variant["gamut"] = entry["display-gamut"]
                if entry.get("subtype"): variant["subtype"] = entry["subtype"]
                variants.append(variant)
            suffix = path.suffix.lower()
            if suffix == ".svg":
                size = svg_size(path)
                if size is None:
                    warn(f"{name}: cannot read the size of {filename}"); continue
                size = tuple(int(v) if v == int(v) else v for v in size)
                record(self.copy(path), 1, size, vector=True)
                continue
            if suffix == ".pdf":
                size = pdf_size(path)
                if size is None:
                    warn(f"{name}: cannot read the size of {filename}"); continue
                if shutil.which("sips") is None:
                    warn(f"{name}: {filename} needs sips to rasterise (not found)"); continue
                for scale in (1, 2, 3):
                    pixels = (int(round(size[0] * scale)), int(round(size[1] * scale)))
                    rendered = self.rasterize(path, pixels, scale)
                    if rendered is None:
                        warn(f"{name}: sips could not rasterise {filename} at {scale}x"); break
                    record(rendered, scale, pixels)
                continue
            size = image_size(path)
            if size is None:
                warn(f"{name}: cannot read the size of {filename}"); continue
            scale_text = entry.get("scale", "1x")
            try:
                scale = int(scale_text.rstrip("x"))
            except ValueError:
                warn(f"{name}: unknown scale {scale_text!r} for {filename}"); continue
            record(self.copy(path), scale, size)
        if not variants:
            warn(f"{name}: no usable image"); return
        if name in self.images: warn(f"{name}: defined twice; the later one wins")
        properties = doc.get("properties", {})
        image = {"variants": variants}
        intent = properties.get("template-rendering-intent")
        if intent == "template": image["template"] = True
        if intent == "original": image["template"] = False
        resizing = properties.get("resizing")
        if resizing:
            # Xcode's slicing: the centre's rect in points of the 1× image; the caps are the rest.
            mode = resizing.get("mode", "9-part")
            caps = resizing.get("cap-insets", {})
            insets = {"top": caps.get("top", 0), "leading": caps.get("left", 0), "bottom": caps.get("bottom", 0), "trailing": caps.get("right", 0)}
            if mode == "3-part-horizontal": insets["top"] = insets["bottom"] = 0
            if mode == "3-part-vertical": insets["leading"] = insets["trailing"] = 0
            image["capInsets"] = insets
            if resizing.get("center", {}).get("mode") == "tile": image["tilesCenter"] = True
        self.images[name] = image

    def colorset(self, directory, name):
        doc = read_contents(directory)
        variants = []
        for entry in doc.get("colors", []):
            color = entry.get("color", {})
            components = color.get("components", {})
            if not components: continue
            luminosity, contrast = appearance(entry)
            variant = {"idiom": entry.get("idiom", "universal"), "appearance": luminosity,
                       "colorSpace": color.get("color-space", "srgb")}
            try:
                for key in ("red", "green", "blue", "alpha"):
                    variant[key] = component(components.get(key, "1.0" if key == "alpha" else "0"))
            except ValueError as error:
                warn(f"{name}: bad component ({error})"); continue
            if contrast: variant["contrast"] = contrast
            if entry.get("display-gamut"): variant["gamut"] = entry["display-gamut"]
            variants.append(variant)
        if not variants:
            warn(f"{name}: no usable colour"); return
        self.colors[name] = {"variants": variants}

    def rasterize(self, path, pixels, scale):
        """Rasterises a PDF page at `pixels` as <set>/<stem>@<scale>x.png in the output layout (or
        next to the PDF when only a manifest is written, so the manifest's files exist)."""
        relative = path.relative_to(self.root.parent).with_name(f"{path.stem}{'' if scale == 1 else f'@{scale}x'}.png")
        destination = (self.out / relative) if self.out else (self.root.parent / relative)
        destination.parent.mkdir(parents=True, exist_ok=True)
        result = subprocess.run(["sips", "-s", "format", "png", "-z", str(pixels[1]), str(pixels[0]), str(path), "--out", str(destination)],
                                capture_output=True)
        if result.returncode != 0 or not destination.exists(): return None
        return relative.as_posix()

    def copy(self, path):
        relative = path.relative_to(self.root.parent)
        if self.out:
            target = self.out / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
        return relative.as_posix()


FONT_SUFFIXES = {".ttf", ".otf"}


def font_tables(data):
    """The table directory of a TrueType/OpenType font: tag -> (offset, length)."""
    if len(data) < 12: return {}
    count = struct.unpack(">H", data[4:6])[0]
    tables = {}
    for index in range(count):
        record = 12 + 16 * index
        if record + 16 > len(data): break
        tag = data[record:record + 4].decode("latin-1")
        offset, length = struct.unpack(">II", data[record + 8:record + 16])
        tables[tag] = (offset, length)
    return tables


def font_name(data, tables, wanted):
    """A `name` table entry (1 family, 2 subfamily, 4 full, 6 PostScript), Windows Unicode first."""
    if "name" not in tables: return None
    base, _ = tables["name"]
    count, strings = struct.unpack(">HH", data[base + 2:base + 6])
    best = None
    for index in range(count):
        record = base + 6 + 12 * index
        platform, encoding, language, name_id, length, offset = struct.unpack(">HHHHHH", data[record:record + 12])
        if name_id != wanted: continue
        start = base + strings + offset
        raw = data[start:start + length]
        if platform == 3 and encoding in (0, 1) and (best is None or language == 0x409):
            best = raw.decode("utf-16-be", "replace")
        elif platform == 1 and best is None:
            best = raw.decode("mac-roman", "replace")
    return best


def font_metrics(path):
    """What the runtime needs from a font file: its names and the vertical metrics in font units
    (`head`, `hhea`, `OS/2`, `post`), so no binary parsing happens in the browser."""
    data = path.read_bytes()
    tables = font_tables(data)
    if "head" not in tables or "hhea" not in tables:
        warn(f"{path.name}: not a TrueType/OpenType font")
        return None
    head, _ = tables["head"]
    hhea, _ = tables["hhea"]
    metrics = {
        "file": None,
        "family": font_name(data, tables, 1) or path.stem,
        "postScriptName": font_name(data, tables, 6) or path.stem,
        "fullName": font_name(data, tables, 4) or path.stem,
        "unitsPerEm": struct.unpack(">H", data[head + 18:head + 20])[0],
        "ascender": struct.unpack(">h", data[hhea + 4:hhea + 6])[0],
        "descender": struct.unpack(">h", data[hhea + 6:hhea + 8])[0],
        "lineGap": struct.unpack(">h", data[hhea + 8:hhea + 10])[0],
    }
    if "OS/2" in tables:
        os2, length = tables["OS/2"]
        version = struct.unpack(">H", data[os2:os2 + 2])[0]
        metrics["weightClass"] = struct.unpack(">H", data[os2 + 4:os2 + 6])[0]
        metrics["typoAscender"], metrics["typoDescender"], metrics["typoLineGap"] = struct.unpack(">hhh", data[os2 + 68:os2 + 74])
        metrics["winAscent"], metrics["winDescent"] = struct.unpack(">HH", data[os2 + 74:os2 + 78])
        metrics["useTypoMetrics"] = bool(struct.unpack(">H", data[os2 + 62:os2 + 64])[0] & 0x80)
        if version >= 2 and length >= 90:
            metrics["xHeight"], metrics["capHeight"] = struct.unpack(">hh", data[os2 + 86:os2 + 90])
    if "post" in tables:
        post, _ = tables["post"]
        metrics["underlinePosition"], metrics["underlineThickness"] = struct.unpack(">hh", data[post + 8:post + 12])
    return metrics


def find_localizations(source):
    """The languages the package is localised into, as `Bundle.localizations` lists them on iOS:
    every language a string catalog (`*.xcstrings`, JSON with `sourceLanguage` and per-string
    `localizations`) holds plus every `<lang>.lproj` folder; the development language is the
    first catalog's `sourceLanguage` (else the first `Base`/`en`). Empty when there is nothing."""
    languages, sources = set(), []
    for path in sorted(_rglob(source, "*.xcstrings")):
        if any(part in SKIPPED_DIRS for part in path.relative_to(source).parts): continue
        try:
            doc = json.loads(path.read_text())
        except (json.JSONDecodeError, OSError) as error:
            warn(f"{path}: {error}"); continue
        if doc.get("sourceLanguage"):
            languages.add(doc["sourceLanguage"]); sources.append(doc["sourceLanguage"])
        for entry in doc.get("strings", {}).values():
            languages.update(entry.get("localizations", {}).keys())
    for path in sorted(_rglob(source, "*.lproj")):
        if any(part in SKIPPED_DIRS for part in path.relative_to(source).parts): continue
        languages.add(path.stem)
    if "Base" in languages and len(languages) > 1: languages.discard("Base")
    return {"languages": sorted(languages), "source": sources[0] if sources else (
        "en" if "en" in languages else (sorted(languages)[0] if languages else None))}


def string_tables(source):
    """The string tables `Bundle.localizedString(forKey:value:table:)` reads, per language: every
    string catalog's (`<Table>.xcstrings`) translations and every `<lang>.lproj/<Table>.strings`,
    as {language: {table: {key: value}}}. A string with plural or device variations keeps its
    `other` (else its first) form."""
    tables = {}
    def unit_value(localization):
        unit = localization.get("stringUnit")
        if unit and "value" in unit: return unit["value"]
        for kinds in (localization.get("variations") or {}).values():
            if not isinstance(kinds, dict) or not kinds: continue
            chosen = kinds.get("other") or next(iter(kinds.values()))
            if isinstance(chosen, dict):
                found = unit_value(chosen)
                if found is not None: return found
        return None
    for path in sorted(_rglob(source, "*.xcstrings")):
        if any(part in SKIPPED_DIRS for part in path.relative_to(source).parts): continue
        try:
            doc = json.loads(path.read_text())
        except (json.JSONDecodeError, OSError):
            continue
        for key, entry in doc.get("strings", {}).items():
            for language, localization in entry.get("localizations", {}).items():
                value = unit_value(localization)
                if value is not None:
                    tables.setdefault(language, {}).setdefault(path.stem, {})[key] = value
    def unescape(text):   # a .strings literal's escapes (\n, \", \\, \U…) read as JSON's
        return json.loads('"' + text.replace("\n", "\\n") + '"') if "\\" in text else text
    pair = re.compile(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;')
    for folder in sorted(_rglob(source, "*.lproj")):
        if any(part in SKIPPED_DIRS for part in folder.relative_to(source).parts) or not folder.is_dir(): continue
        for path in sorted(folder.glob("*.strings")):
            try:
                text = path.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                text = path.read_text(encoding="utf-16")
            for key, value in pair.findall(text):
                tables.setdefault(folder.stem, {}).setdefault(path.stem, {})[unescape(key)] = unescape(value)
    return tables


def find_fonts(source):
    found = []
    for suffix in sorted(FONT_SUFFIXES):
        for path in sorted(_rglob(source, "*" + suffix)):
            if any(part in SKIPPED_DIRS for part in path.relative_to(source).parts): continue
            found.append(path)
    return found


def find_catalogs(source):
    if source.suffix == ".xcassets": return [source]
    found = []
    for path in sorted(_rglob(source, "*.xcassets")):
        if any(part in SKIPPED_DIRS for part in path.relative_to(source).parts): continue
        found.append(path)
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("source", help="a directory to search for *.xcassets, or one catalog")
    parser.add_argument("--out", help="directory to copy the image files into")
    parser.add_argument("--json", help="write the manifest as JSON to this file")
    parser.add_argument("--js", help="write the manifest as a script setting window.__swiftuiwebAssets")
    args = parser.parse_args()
    source = Path(args.source).resolve()
    out = Path(args.out).resolve() if args.out else None
    catalogs = find_catalogs(source)
    if not catalogs:
        warn(f"no *.xcassets under {source}")
    catalog = Catalog(out)
    for path in catalogs:
        catalog.read(path)
    # Font files anywhere under the source (an app bundles them as loose resources): keyed by
    # PostScript name, which `Font.custom` names, with the file copied beside the images.
    fonts = {}
    for path in find_fonts(source):
        metrics = font_metrics(path)
        if metrics is None: continue
        relative = path.relative_to(source)
        if out:
            target = out / "Fonts" / path.name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
        metrics["file"] = ("Fonts/" + path.name) if out else relative.as_posix()
        fonts[metrics["postScriptName"]] = metrics
    localizations = find_localizations(source)
    # The string tables beside the images: `<lang>.lproj/<Table>.strings.json`, which the
    # bundle reads when a string is looked up (WebFoundation's Bundle.swift).
    if out:
        for language, by_table in string_tables(source).items():
            for table, strings in by_table.items():
                target = out / f"{language}.lproj" / f"{table}.strings.json"
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(json.dumps(strings, ensure_ascii=False, sort_keys=True))
    manifest = {"version": 1, "catalogs": [p.name for p in catalogs],
                "images": dict(sorted(catalog.images.items())), "colors": dict(sorted(catalog.colors.items())),
                "fonts": dict(sorted(fonts.items())),
                "localizations": localizations["languages"], "sourceLanguage": localizations["source"]}
    text = json.dumps(manifest, indent=2, sort_keys=True)
    if args.json:
        Path(args.json).parent.mkdir(parents=True, exist_ok=True)
        Path(args.json).write_text(text + "\n")
    if args.js:
        Path(args.js).parent.mkdir(parents=True, exist_ok=True)
        # `base` resolves image files relative to this script's own URL, wherever the page lives.
        Path(args.js).write_text("(function(){var s=document.currentScript;var base=s&&s.src?s.src.replace(/[^/]*$/,''):'';"
                                 "var m=" + json.dumps(manifest, separators=(",", ":")) + ";m.base=base;window.__swiftuiwebAssets=m;})();\n")
    print(f"assets: {len(catalog.images)} image set(s), {len(catalog.colors)} colour set(s) from {len(catalogs)} catalog(s), {len(fonts)} font(s)", file=sys.stderr)


if __name__ == "__main__":
    main()
