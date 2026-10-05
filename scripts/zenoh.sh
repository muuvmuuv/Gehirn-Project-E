#!/usr/bin/env bash
# Fetches the pinned zenoh-c release for this host into thirdparty/zenoh-c, which zenoh/zenoh.c.v
# links, unless it is there already. The Justfile's zenoh recipe runs it before test, build and
# bridge.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
version=1.10.1

# Asks getconf for glibc, since a glibc host with Debian's or Ubuntu's musl package also has /lib/ld-musl-*.
libc=musl
if getconf GNU_LIBC_VERSION >/dev/null 2>&1; then
    libc=gnu
fi

# ponytail: macOS on Apple Silicon and Linux on aarch64 and x86_64 only; another host needs its target and checksum here.
case "$(uname -s)-$(uname -m)-$libc" in
    Darwin-arm64-*) target=aarch64-apple-darwin sum=82da6e95eb895413369f55d1a53eb5b621b22ab8afc446b041b7760eec240ff4 ;;
    Linux-aarch64-musl) target=aarch64-unknown-linux-musl sum=de99cc82c7ae93eaa2aa5a0c8bcfcefed7624b0e0f85c679f7dba9c54ccdff9c ;;
    Linux-aarch64-gnu) target=aarch64-unknown-linux-gnu sum=65970bbed6dc10fec4fa39d05f3876e85fcb9b0f87d5be0a54bd7517240db501 ;;
    Linux-x86_64-musl) target=x86_64-unknown-linux-musl sum=293866bb632fd579fb0603bbfdb8d383e7c2d4eadc8ec3ae199fafa1dbc99c55 ;;
    Linux-x86_64-gnu) target=x86_64-unknown-linux-gnu sum=9ee0f2d732b0f3042a7e1cd3076042a2bc3ac0415587c40bc3ed7b8b62fbde11 ;;
    *) echo "zenoh: no pinned zenoh-c build for $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac
dir=thirdparty/zenoh-c
if [ "$(cat "$dir/VERSION" 2>/dev/null)" = "$version $target" ]; then
    exit 0
fi
echo "zenoh: fetching zenoh-c $version for $target into $dir"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/zenoh-c.zip" "https://github.com/eclipse-zenoh/zenoh-c/releases/download/$version/zenoh-c-$version-$target-standalone.zip"
got=$( (sha256sum 2>/dev/null || shasum -a 256) < "$tmp/zenoh-c.zip" | cut -d' ' -f1)
if [ "$got" != "$sum" ]; then
    echo "zenoh: checksum mismatch for zenoh-c $version $target" >&2
    exit 1
fi
rm -rf "$dir"
mkdir -p "$dir"
unzip -q "$tmp/zenoh-c.zip" -d "$dir"
echo "$version $target" > "$dir/VERSION"
