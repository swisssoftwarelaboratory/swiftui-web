#!/usr/bin/env bash
# The apps of decision 0021 (Apps/README.md): verifies that every upstream tree is exactly its
# pinned commit with no file changed, added or missing (Apps/upstream/*.sha256 lists every
# tracked file's SHA-256 at the pin), then builds each app for wasm from those sources.
#
#   scripts/check-apps.sh            verify the pins and build every app
#   scripts/check-apps.sh --verify   verify only
#   scripts/check-apps.sh --pin      rewrite the SHA-256 manifests from the checked-out trees
#                                    (after moving a pin on purpose)
set -euo pipefail
cd "$(dirname "$0")/.."

mode="${1:-build}"
status=0

apps=(SwiftUI-2048 Scrumdinger ember-hackernews Swift-Charts-Examples buttoncraft pompaddo CloudStorage swiftdata-transferrable simple-swiftui)

if [[ "$mode" == "--pin" ]]; then
  for app in "${apps[@]}"; do
    (cd "Apps/upstream/$app" && git ls-files -z | sort -z | xargs -0 shasum -a 256) > "Apps/upstream/$app.sha256"
    echo "pinned $app at $(git -C "Apps/upstream/$app" rev-parse HEAD) ($(wc -l < "Apps/upstream/$app.sha256" | tr -d ' ') files)"
  done
  exit 0
fi

for app in "${apps[@]}"; do
  dir="Apps/upstream/$app"
  if [[ ! -f "$dir/.git" && ! -d "$dir/.git" ]]; then
    echo "✗ $app: submodule not checked out (git submodule update --init)"; status=1; continue
  fi
  pinned=$(git ls-files --stage "$dir" | awk '{print $2}')  # the gitlink in the index
  head=$(git -C "$dir" rev-parse HEAD)
  if [[ "$pinned" != "$head" ]]; then
    echo "✗ $app: checked out at $head, pinned at $pinned"; status=1
  fi
  # Modified, deleted or untracked files inside the upstream tree.
  dirty=$(git -C "$dir" status --porcelain --untracked-files=all)
  if [[ -n "$dirty" ]]; then
    echo "✗ $app: upstream tree differs from the pin:"; echo "$dirty" | sed 's/^/    /'; status=1
  fi
  # Every tracked file's hash against the recorded manifest (belt and braces: the manifest is
  # reviewable in a diff, the git index is not).
  if [[ ! -f "$dir.sha256" ]]; then
    echo "✗ $app: no manifest $dir.sha256 (scripts/check-apps.sh --pin)"; status=1
  elif ! (cd "$dir" && shasum -a 256 --check --quiet --strict "../$app.sha256"); then
    echo "✗ $app: files differ from $dir.sha256"; status=1
  else
    echo "✓ $app at $head: $(wc -l < "$dir.sha256" | tr -d ' ') files unchanged"
  fi
done

[[ "$mode" == "--verify" || $status -ne 0 ]] && exit $status

# shellcheck disable=SC1091
. scripts/env.sh
for product in SwiftUI2048 Scrumdinger Ember ChartsExamples Buttoncraft Pompaddo SimpleScores SimpleToDo; do
  echo "== $product (wasm)"
  if (cd Apps && swift build --swift-sdk "${SWIFTUIWEB_WASM_SDK:-swift-$(cat ../.swift-version)-RELEASE_wasm}" --product "$product" 2>&1 | grep -E "error:|warning:" | sort -u | sed 's/^/    /'; test "${PIPESTATUS[0]}" -eq 0); then
    echo "✓ $product builds"
  else
    echo "✗ $product does not build"; status=1
  fi
done
exit $status
