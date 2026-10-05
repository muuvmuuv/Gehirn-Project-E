#!/usr/bin/env bash
# Links the MuJoCo installed on this Mac into thirdparty/mujoco, the layout a V module's #flag lines
# expect: include/mujoco holds the headers, which name each other as <mujoco/...>, and lib/libmujoco.dylib
# the library. MuJoCo's framework has no top level binary, so -framework mujoco cannot link it. The
# justfile's mujoco recipe runs it; nothing in the checks needs MuJoCo yet.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
version=3.14.0
app=/Applications/MuJoCo.app/Contents/Frameworks

# ponytail: macOS only, from Homebrew's mujoco cask; how Linux and the field tier get MuJoCo is the
# Phase 3 simulator ADR's to decide (Invariant 9).
if [ "$(uname -s)" != Darwin ]; then
    echo "mujoco: no MuJoCo setup for $(uname -s) yet; PLAN Phase 3's simulator ADR decides it" >&2
    exit 1
fi
lib="$app/mujoco.framework/Versions/A/libmujoco.$version.dylib"
if [ ! -f "$lib" ]; then
    echo "mujoco: MuJoCo $version not found at $app; install it with brew install --cask mujoco" >&2
    exit 1
fi
dir=thirdparty/mujoco
if [ "$(cat "$dir/VERSION" 2>/dev/null)" = "$version" ]; then
    exit 0
fi
rm -rf "$dir"
mkdir -p "$dir/include" "$dir/lib"
ln -s "$app/mujoco.framework/Headers" "$dir/include/mujoco"
ln -s "$lib" "$dir/lib/libmujoco.dylib"
echo "$version" >"$dir/VERSION"
echo "mujoco: linked MuJoCo $version into $dir"
