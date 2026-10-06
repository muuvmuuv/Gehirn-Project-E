#!/usr/bin/env bash
# Builds gehirn with -d mujoco as a static aarch64 musl binary, the field unit on the MuJoCo base
# as Invariant 9 asks field tier code to build (ADR-0008, Action Item 2), and puts it with the
# licenses of MuJoCo and its fetched dependencies into musl-mujoco/, which git ignores and which
# changes only once a build has succeeded. The justfile's musl-mujoco recipe runs it. An
# alpine:3.22 container builds it as release.yml's musl job builds the default field unit, from
# the regular files git tracks or does not ignore, as they stand here, so .env and thirdparty stay
# here; it fetches V, zenoh-c and MuJoCo into that copy, runs the tests of mujoco, body and armor
# built with -d mujoco and mounts nothing, so it never writes thirdparty/ here.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Alpine 3.22.6, pinned by the digest of its index of platforms. Its packages float within 3.22,
# as in release.yml, since Alpine drops a superseded version from its mirrors.
image=alpine:3.22@sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8

if ! command -v docker >/dev/null; then
    echo "musl: the static musl build needs docker, which is not on PATH" >&2
    exit 1
fi
if ! docker info >/dev/null 2>&1; then
    echo "musl: the static musl build needs docker, whose daemon does not answer" >&2
    exit 1
fi
echo "musl: building gehirn with -d mujoco for aarch64 musl in $image, about three and a half minutes"

# Docker signals the container only when its own CLI gets the signal, and the container's sh, as
# PID 1, ignores TERM and HUP, so the EXIT trap removes the container by name. bash runs no trap
# while a foreground pipeline runs, hence the pipeline in the background.
tmp=$(mktemp -d "${TMPDIR:-/tmp}/gehirn-musl.XXXXXX")
name=gehirn-musl-$$
trap 'docker rm -f "$name" >/dev/null 2>&1 || true; rm -rf "$tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# git ls-files lists files deleted from the working tree, which tar cannot read, and an untracked
# repository as one directory, which tar would copy whole with its .git and .env.
git ls-files -z --cached --others --exclude-standard | while IFS= read -r -d '' f; do
    if [ -f "$f" ]; then
        printf '%s\0' "$f"
    fi
done | COPYFILE_DISABLE=1 tar -c --no-xattrs --null -T - -f - |
    docker run --rm -i --name "$name" --platform linux/arm64 -e V_C_ERROR_BUG_REPORT_DISABLED=1 "$image" sh -euc '
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
    ' | tar -x -C "$tmp" &
wait $!
chmod 755 "$tmp"
rm -rf musl-mujoco
mv "$tmp" musl-mujoco
echo "musl: built musl-mujoco/gehirn with the licenses of MuJoCo and its dependencies in musl-mujoco/mujoco"
