#!/usr/bin/env bash
# Reproduces the development environment on a clean macOS or Linux machine.
set -euo pipefail
SWIFT_VERSION="$(cat "$(dirname "$0")/../.swift-version")"
WASM_SDK_URL="https://download.swift.org/swift-${SWIFT_VERSION}-release/wasm-sdk/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE_wasm.artifactbundle.tar.gz"
WASM_SDK_CHECKSUM="83baca83553f8c443cda7b84800912e6e709c3acd2e7ebf277794ca5836c0da5"  # 6.4.2; update with .swift-version

if ! command -v swiftly >/dev/null; then
  if [[ "$(uname)" == "Darwin" ]]; then brew install swiftly binaryen
  else
    curl -O https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz
    tar zxf swiftly-$(uname -m).tar.gz && ./swiftly init --assume-yes --skip-install --no-modify-profile
  fi
fi
[[ -f "$HOME/.swiftly/config.json" ]] || swiftly init --assume-yes --skip-install --no-modify-profile
# shellcheck disable=SC1091
. "$(dirname "$0")/env.sh"
swiftly install "$SWIFT_VERSION" --use --assume-yes
swift sdk list | grep -q "swift-${SWIFT_VERSION}-RELEASE_wasm" || \
  swift sdk install "$WASM_SDK_URL" --checksum "$WASM_SDK_CHECKSUM"
swift --version
swift sdk list
echo "OK. Add '. ~/.swiftly/env.sh' to your shell profile."
