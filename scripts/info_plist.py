#!/usr/bin/env python3
"""The app's Info dictionary as Xcode builds it, without Xcode (new-website#663): the target's
`INFOPLIST_FILE` plus the `INFOPLIST_KEY_*` build settings Xcode writes into it, and the bundle
keys its build settings give (`CFBundleIdentifier` from `PRODUCT_BUNDLE_IDENTIFIER` and so on).
`Bundle.main.infoDictionary` answers from it, and the host reads `UIUserInterfaceStyle` from it,
so an app set to Light stays light in a dark browser as it does on a dark iPhone.

    scripts/info_plist.py <dir> [--product Name] [--debug]   # prints the dictionary as JSON

The app's project is the `*.xcodeproj` under <dir>; its application target is the one named
--product, else the only one, else the first. The Release configuration unless --debug. Nothing
is found (an app with no Xcode project): an empty dictionary."""
import argparse, json, os, plistlib, re, sys
from pathlib import Path

SKIPPED_DIRS = {".build", "node_modules", ".git", ".swiftpm"}


def parse_openstep(text):
    """An old-style (OpenStep) property list, the format of `project.pbxproj`: dictionaries
    `{ key = value; }`, arrays `( a, b, )`, quoted or bare strings, `/* comments */`."""
    i, n = 0, len(text)

    def skip():
        nonlocal i
        while i < n:
            if text[i].isspace(): i += 1
            elif text.startswith("/*", i):
                end = text.find("*/", i + 2); i = n if end < 0 else end + 2
            elif text.startswith("//", i):
                end = text.find("\n", i); i = n if end < 0 else end + 1
            else: break

    def value():
        nonlocal i
        skip()
        c = text[i]
        if c == "{":
            i += 1; result = {}
            while True:
                skip()
                if text[i] == "}": i += 1; return result
                key = value(); skip()
                assert text[i] == "=", f"expected = at {i}"; i += 1
                result[key] = value(); skip()
                if text[i] == ";": i += 1
        if c == "(":
            i += 1; result = []
            while True:
                skip()
                if text[i] == ")": i += 1; return result
                result.append(value()); skip()
                if text[i] == ",": i += 1
        if c == '"':
            i += 1; out = []
            while text[i] != '"':
                if text[i] == "\\":
                    i += 1
                    out.append({"n": "\n", "t": "\t", "r": "\r"}.get(text[i], text[i]))
                else: out.append(text[i])
                i += 1
            i += 1; return "".join(out)
        start = i
        while i < n and (text[i].isalnum() or text[i] in "_$/.-:+"): i += 1
        assert i > start, f"unexpected {text[i]!r} at {i}"
        return text[start:i]

    if text.startswith("// !$*UTF8*$!"): text = text[text.index("\n") + 1:]; n = len(text)
    return value()


def expand(text, settings, depth=0):
    """`$(NAME)`, `${NAME}` and `$(NAME:rfc1034identifier)`-style references, from `settings`."""
    if not isinstance(text, str) or depth > 8: return text
    def one(match):
        name = match.group(1) or match.group(2)
        name = name.split(":")[0]
        return str(expand(settings.get(name, ""), settings, depth + 1))
    return re.sub(r"\$\(([^)]+)\)|\$\{([^}]+)\}", one, text)


def find_projects(source):
    found = []
    for directory, dirs, _ in os.walk(source, followlinks=True):
        dirs[:] = sorted(d for d in dirs if d not in SKIPPED_DIRS)
        for d in list(dirs):
            if d.endswith(".xcodeproj") and (Path(directory) / d / "project.pbxproj").is_file():
                found.append(Path(directory) / d)
                dirs.remove(d)
    return found


def application_targets(objects):
    return [o for o in objects.values() if o.get("isa") == "PBXNativeTarget"
            and o.get("productType") == "com.apple.product-type.application"]


def build_settings(objects, owner, configuration):
    """The named configuration's settings in `owner`'s configuration list (Release, else the
    list's default, else its first)."""
    configs = [objects[c] for c in objects.get(owner.get("buildConfigurationList"), {}).get("buildConfigurations", [])]
    if not configs: return {}
    default = objects[owner["buildConfigurationList"]].get("defaultConfigurationName")
    chosen = next((c for c in configs if c.get("name") == configuration), None) \
        or next((c for c in configs if c.get("name") == default), configs[0])
    return dict(chosen.get("buildSettings", {}))


def setting_value(key, raw):
    """A build setting's text as the Info.plist value Xcode writes: YES and NO as booleans, an
    orientation list as an array, everything else as text."""
    if raw in ("YES", "NO"): return raw == "YES"
    if isinstance(raw, list): return raw
    if key.startswith("UISupportedInterfaceOrientations"): return raw.split()
    return raw


def plain(value):
    """A plist value as JSON can hold it (dates and data as text)."""
    if isinstance(value, dict): return {str(k): plain(v) for k, v in value.items()}
    if isinstance(value, list): return [plain(v) for v in value]
    if isinstance(value, (str, bool, int, float)) or value is None: return value
    if isinstance(value, bytes): return value.hex()
    return str(value)


def info_dictionary(source, product=None, configuration="Release"):
    for project in find_projects(Path(source)):
        document = parse_openstep((project / "project.pbxproj").read_text(encoding="utf-8"))
        objects = document["objects"]
        targets = application_targets(objects)
        if not targets: continue
        target = next((t for t in targets if product and t.get("name") == product), None) or targets[0]
        root = objects[document["rootObject"]]
        settings = {"TARGET_NAME": target.get("name", ""), "PROJECT_NAME": project.stem,
                    "SRCROOT": str(project.parent), "PROJECT_DIR": str(project.parent)}
        settings.update(build_settings(objects, root, configuration))
        settings.update(build_settings(objects, target, configuration))
        info = {}
        if settings.get("INFOPLIST_FILE"):
            path = project.parent / expand(settings["INFOPLIST_FILE"], settings)
            if path.is_file():
                with open(path, "rb") as handle: info.update(plistlib.load(handle))
        # Xcode's generated keys go in under the file's own (the file wins where both name a key).
        generated = {}
        for key, raw in settings.items():
            if not key.startswith("INFOPLIST_KEY_"): continue
            name = key[len("INFOPLIST_KEY_"):]
            if name.endswith("_Generation"): continue
            generated[name] = setting_value(name, expand(raw, settings) if isinstance(raw, str) else raw)
        for name, key in (("CFBundleIdentifier", "PRODUCT_BUNDLE_IDENTIFIER"), ("CFBundleName", "PRODUCT_NAME"),
                          ("CFBundleShortVersionString", "MARKETING_VERSION"), ("CFBundleVersion", "CURRENT_PROJECT_VERSION")):
            if key in settings: generated[name] = expand(settings[key], settings)
        # The app icon's set, as Xcode's asset compiler names it in the built Info.plist (the drawn
        # iPhone's home screen finds the icon by it, new-website#638).
        if settings.get("ASSETCATALOG_COMPILER_APPICON_NAME"):
            icon = expand(settings["ASSETCATALOG_COMPILER_APPICON_NAME"], settings)
            generated["CFBundleIcons"] = {"CFBundlePrimaryIcon": {"CFBundleIconName": icon}}
        info = {**generated, **{k: expand(v, settings) for k, v in info.items()}}
        return plain(info)
    return {}


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("source")
    parser.add_argument("--product")
    parser.add_argument("--debug", action="store_true")
    args = parser.parse_args()
    json.dump(info_dictionary(args.source, args.product, "Debug" if args.debug else "Release"), sys.stdout, indent=2, sort_keys=True)
    print()


if __name__ == "__main__":
    main()
