#!/usr/bin/env bash
# Builds gehirn with -d mujoco as a static aarch64 musl binary, the field unit on the MuJoCo base
# as Invariant 9 asks field tier code to build (ADR-0008, Action Item 2), and puts it with the
# licenses of MuJoCo and the dependencies it links into OUT, its argument, musl-mujoco unless
# given. The justfile's musl-mujoco recipe runs it. OUT is a new or empty directory or one an
# earlier build filled, which it replaces, never one in thirdparty/, and a relative OUT starts at
# the repository root. An alpine:3.22 container builds it as release.yml's musl job builds the
# default field unit, from a copy of the files git would commit, so .env and thirdparty stay
# here; it fetches V, zenoh-c and MuJoCo into that copy, runs the tests of mujoco, body and armor
# built with -d mujoco and mounts nothing, so it never writes thirdparty/ here.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
root=$(pwd -P)
out=${1:-musl-mujoco}

# Alpine 3.22.6, pinned by the digest of its index of platforms. Its packages float within 3.22,
# as in release.yml, since Alpine drops a superseded version from its mirrors.
image=alpine:3.22@sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8

# names lists a directory's entries in one order on every host.
names() { LC_ALL=C ls -A "$1"; }

# OUT resolved through symlinks up to its nearest existing directory, so a worktree's
# thirdparty, a link to the main checkout's, counts as thirdparty.
d=$out rest=
until [ -d "$d" ]; do
    rest=/$(basename "$d")$rest
    d=$(dirname "$d")
done
case $rest/ in
    */../*)
        echo "musl: $out climbs out of a directory that does not exist yet" >&2
        exit 2
        ;;
esac
dest=$(cd "$d" && pwd -P)$rest
tp=$(cd thirdparty 2>/dev/null && pwd -P || true)
case $dest/ in
    "$root"/thirdparty/* | "${tp:-$root/thirdparty}"/*)
        echo "musl: $out lies in thirdparty/, which holds this host's own libraries" >&2
        exit 2
        ;;
esac
if [ -e "$dest" ] && [ -n "$(names "$dest")" ] &&
    ! { [ "$(names "$dest")" = "$(printf 'gehirn\nmujoco')" ] &&
        [ "$(names "$dest/mujoco")" = "$(printf 'LICENSE\nlicenses')" ]; }; then
    echo "musl: $out holds more than an earlier build put there" >&2
    exit 2
fi

if ! command -v docker >/dev/null; then
    echo "musl: the static musl build needs docker, which is not on PATH" >&2
    exit 1
fi
if ! docker info >/dev/null 2>&1; then
    echo "musl: the static musl build needs docker, whose daemon does not answer" >&2
    exit 1
fi
echo "musl: building gehirn with -d mujoco for aarch64 musl in $image, about three and a half minutes"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/gehirn-musl.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

# git ls-files lists files deleted from the working tree too, which tar cannot read.
git ls-files -z --cached --others --exclude-standard | while IFS= read -r -d '' f; do
    if [ -e "$f" ]; then
        printf '%s\0' "$f"
    fi
done | COPYFILE_DISABLE=1 tar -c --no-xattrs --null -T - -f - |
    docker run --rm -i --platform linux/arm64 -e V_C_ERROR_BUG_REPORT_DISABLED=1 "$image" sh -euc '
        exec 3>&1 1>&2
        apk add --no-cache -q bash curl unzip tar gcc g++ musl-dev patch cmake samurai git gcompat gc-dev gc-static
        mkdir /work
        cd /work
        tar -x
        PATH="$(scripts/toolchain.sh /opt/toolchain):$PATH"
        scripts/zenoh.sh
        scripts/mujoco.sh
        v -d mujoco -W -N test mujoco/ body/ armor/
        v -prod -d mujoco -cflags -static -o gehirn .
        tar -c gehirn -C thirdparty mujoco/LICENSE mujoco/licenses >&3
    ' | tar -x -C "$tmp"
mkdir -p "$dest"
rm -rf "${dest:?}/gehirn" "${dest:?}/mujoco"
mv "$tmp/gehirn" "$tmp/mujoco" "$dest/"
echo "musl: built $out/gehirn with the licenses of MuJoCo and its dependencies in $out/mujoco"
