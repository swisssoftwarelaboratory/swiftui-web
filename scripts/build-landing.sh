#!/usr/bin/env bash
# Builds the landing page as a static site for GitHub Pages: Examples/Landing/dist holds
# index.html and the wasm bundle. Usage: scripts/build-landing.sh [--debug]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$ROOT/scripts/gen-progress.py"
"$ROOT/scripts/build-wasm.sh" Examples/Landing ${1:+"$1"}
DIST="$ROOT/Examples/Landing/dist"
rm -rf "$DIST" && mkdir -p "$DIST"
# The bundle lives under a name unique to this build, so browsers that cached the previous
# index.js and wasm (Pages sends max-age=600; Safari keeps modules longer) fetch the new ones.
BUNDLE="bundle-$(git -C "$ROOT" rev-parse --short HEAD)-$(date +%Y%m%d%H%M)"
cp -R "$ROOT/Examples/Landing/.build/wasm/plugins/PackageToJS/outputs/Package" "$DIST/$BUNDLE"
# The page's loading bar measures the download against the wasm size (Pages serves it gzip
# compressed, so the response's Content-Length is not the byte count the stream delivers).
WASM="$DIST/$BUNDLE/Landing.wasm"
BYTES=$(stat -f%z "$WASM" 2>/dev/null || stat -c%s "$WASM")
sed -e "s|./.build/wasm/plugins/PackageToJS/outputs/Package/|./$BUNDLE/|" -e "s|data-wasm-bytes=\"\"|data-wasm-bytes=\"$BYTES\"|" \
  "$ROOT/Examples/Landing/index.html" > "$DIST/index.html"
# The gallery (decision 0016): a release build of every fixture with its source and steps at
# /gallery/, with the same loading screen; the deploy refuses a bundle over its budget.
"$ROOT/scripts/build-wasm.sh" Examples/Gallery ${1:+"$1"}
GALLERY="$DIST/gallery"
mkdir -p "$GALLERY"
GBUNDLE="bundle-$(git -C "$ROOT" rev-parse --short HEAD)-$(date +%Y%m%d%H%M)"
cp -R "$ROOT/Examples/Gallery/.build/wasm/plugins/PackageToJS/outputs/Package" "$GALLERY/$GBUNDLE"
GWASM="$GALLERY/$GBUNDLE/Gallery.wasm"
GBYTES=$(stat -f%z "$GWASM" 2>/dev/null || stat -c%s "$GWASM")
sed -e "s|./.build/wasm/plugins/PackageToJS/outputs/Package/|./$GBUNDLE/|g" -e "s|data-wasm-bytes=\"\"|data-wasm-bytes=\"$GBYTES\"|" \
  "$ROOT/Examples/Gallery/index.html" > "$GALLERY/index.html"
if [[ -z "${1:-}" ]]; then
  # The size line (raw and brotli) and the gate: 4 MB brotli (3.53 MB at the first release build, 2026-09-18).
  "$ROOT/scripts/size-gate.sh" Examples/Gallery 4194304
fi
# The progress page (decision 0016): counts, the full matrix, the todo list, at /progress/.
"$ROOT/scripts/build-wasm.sh" Examples/Progress ${1:+"$1"}
PROGRESS="$DIST/progress"
mkdir -p "$PROGRESS"
PBUNDLE="bundle-$(git -C "$ROOT" rev-parse --short HEAD)-$(date +%Y%m%d%H%M)"
cp -R "$ROOT/Examples/Progress/.build/wasm/plugins/PackageToJS/outputs/Package" "$PROGRESS/$PBUNDLE"
PWASM="$PROGRESS/$PBUNDLE/Progress.wasm"
PBYTES=$(stat -f%z "$PWASM" 2>/dev/null || stat -c%s "$PWASM")
sed -e "s|./.build/wasm/plugins/PackageToJS/outputs/Package/|./$PBUNDLE/|g" -e "s|data-wasm-bytes=\"\"|data-wasm-bytes=\"$PBYTES\"|" \
  -e "s|data-commit=\"\"|data-commit=\"$(git -C "$ROOT" rev-parse --short HEAD)\"|" \
  "$ROOT/Examples/Progress/index.html" > "$PROGRESS/index.html"
if [[ -z "${1:-}" ]]; then "$ROOT/scripts/size-gate.sh" Examples/Progress 3670016; fi
# The apps (decision 0021): the three unmodified iOS apps, each a release build at /apps/<app>/,
# from Apps/index.html with the bundle path, name and wasm size filled in. The submodules must be
# checked out at their pins (scripts/check-apps.sh --verify). SwiftUI2048 needs the Objective-C
# runtime SDK (decision 0023), installed where this runs; it goes last because the Apps scratch
# path's bundle is the one last built (build-wasm.sh copies the other SDK's bundle into it).
"$ROOT/scripts/check-apps.sh" --verify
OBJC_SDK="swift-6.3.3-RELEASE_wasm-objc"   # built for Swift 6.3.3 only (decisions 0023, 0026)
# shellcheck disable=SC1091
. "$ROOT/scripts/env.sh"
swift sdk list | grep -qx "$OBJC_SDK" || { echo "build-landing: the Objective-C runtime SDK $OBJC_SDK is not installed (decision 0023); SwiftUI2048 cannot be built"; exit 1; }
app_page() {   # app_page <dir> <Product> <name shown while loading>
  local APP="$DIST/apps/$1" ABUNDLE="bundle-$(git -C "$ROOT" rev-parse --short HEAD)-$(date +%Y%m%d%H%M)"
  mkdir -p "$APP"
  cp -R "$ROOT/Apps/.build/wasm/plugins/PackageToJS/outputs/Package" "$APP/$ABUNDLE"
  local AWASM="$APP/$ABUNDLE/$2.wasm" ABYTES
  ABYTES=$(stat -f%z "$AWASM" 2>/dev/null || stat -c%s "$AWASM")
  sed -e "s|./.build/wasm/plugins/PackageToJS/outputs/Package/|./$ABUNDLE/|g" -e "s|data-wasm-bytes=\"\"|data-wasm-bytes=\"$ABYTES\"|" \
    -e "s|data-wasm=\"\"|data-wasm=\"$2.wasm\"|" -e "s|data-app=\"\"|data-app=\"$3\"|" -e "s|<title>App — SwiftUIWeb</title>|<title>$3 — SwiftUIWeb</title>|" \
    "$ROOT/Apps/index.html" > "$APP/index.html"
}
"$ROOT/scripts/build-wasm.sh" Apps ${1:+"$1"} --product Scrumdinger && app_page scrumdinger Scrumdinger "Scrumdinger"
"$ROOT/scripts/build-wasm.sh" Apps ${1:+"$1"} --product Ember && app_page ember Ember "Ember"
SWIFTUIWEB_WASM_SDK="$OBJC_SDK" "$ROOT/scripts/build-wasm.sh" Apps ${1:+"$1"} --product SwiftUI2048 && app_page 2048 SwiftUI2048 "SwiftUI 2048"
touch "$DIST/.nojekyll"
echo "Site: $DIST ($(du -sh "$DIST" | cut -f1); gallery $(du -sh "$GALLERY" | cut -f1); progress $(du -sh "$PROGRESS" | cut -f1); apps $(du -sh "$DIST/apps" | cut -f1)); serve with: python3 -m http.server --directory $DIST"
