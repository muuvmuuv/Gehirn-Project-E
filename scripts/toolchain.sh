#!/usr/bin/env bash
# Fetches the V, just, shellcheck and shfmt that CI pins for this host into dir, each checked
# against its sha256, and links them into dir/bin, which CI puts on PATH. CONTRIBUTING.md,
# Continuous integration, names the four versions. Dir lies outside the repository, since
# `v fmt`, `v vet` and `v test` would walk V's own sources inside it.
set -euo pipefail
dir=${1:-${RUNNER_TEMP:-/tmp}/gehirn-toolchain}

# V's release archive is built from 7647ce1, one commit past the 45ae01d that Homebrew builds,
# which adds V's changelog only.
# ponytail: the hosts CI runs on only; another host needs its four downloads and checksums here.
case "$(uname -s)-$(uname -m)" in
    Darwin-arm64)
        v_zip=v_macos_arm64.zip v_sum=e539a8dc3aeea47267f3cf00c25c4f0a364d8037fb13f5379d2a574a7abac8ee
        just_target=aarch64-apple-darwin just_sum=50ae3e996c974a0bf32ea7d10f495070df33f1b43e0616b2769e3d4821ed8f48
        sc_target=darwin.aarch64 sc_sum=339b930feb1ea764467013cc1f72d09cd6b869ebf1013296ba9055ab2ffbd26f
        shfmt_target=darwin_arm64 shfmt_sum=b7c872db63553ccffc7253aba3ed7d4885a27d83f1ba567b1138c6315a5847e5
        ;;
    Linux-x86_64)
        v_zip=v_linux.zip v_sum=86caf9e70c3342d48ef19eb4f6c47b709f18c90ae86255520d5c29df6b482e23
        just_target=x86_64-unknown-linux-musl just_sum=4a5cc2f53e6f0f8c59092a6cc38291eb729d46a7dd95d3ae582008881b84931d
        sc_target=linux.x86_64 sc_sum=b7af85e41cc99489dcc21d66c6d5f3685138f06d34651e6d34b42ec6d54fe6f6
        shfmt_target=linux_amd64 shfmt_sum=76e77641faa025814b77f153b29796b8e6fa2fca03e0c76a691608b86c7ea7bf
        ;;
    Linux-aarch64)
        v_zip=v_linux_arm64.zip v_sum=7e102f0ecc722bc59fea83ab1c99ae49c2f7be8f30abee9443220e452a439ed3
        just_target=aarch64-unknown-linux-musl just_sum=748237128c4c40cbdabc65e841d05ceba13cc23a91eaba395495894c1d9764df
        sc_target=linux.aarch64 sc_sum=68a8133197a50beb8803f8d42f9908d1af1c5540d4bb05fdfca8c1fa47decefc
        shfmt_target=linux_arm64 shfmt_sum=5f2db09dae91fca848f7adbdd014632e921a383863a2ad7e0450ad3aba0c6489
        ;;
    *)
        echo "toolchain: no pinned toolchain for $(uname -s)-$(uname -m)" >&2
        exit 1
        ;;
esac

# fetch downloads url to file and fails unless the file's sha256 is sum.
fetch() {
    curl -fsSL -o "$2" "$1"
    got=$( (sha256sum 2>/dev/null || shasum -a 256) <"$2" | cut -d' ' -f1)
    if [ "$got" != "$3" ]; then
        echo "toolchain: checksum mismatch for $1" >&2
        exit 1
    fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$dir/bin"
fetch "https://github.com/vlang/v/releases/download/0.5.2/$v_zip" "$tmp/v.zip" "$v_sum"
unzip -oq "$tmp/v.zip" -d "$dir"
ln -sf ../v/v "$dir/bin/v"
fetch "https://github.com/casey/just/releases/download/1.58.0/just-1.58.0-$just_target.tar.gz" "$tmp/just.tar.gz" "$just_sum"
tar -xzf "$tmp/just.tar.gz" -C "$dir/bin" just
fetch "https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.$sc_target.tar.gz" "$tmp/shellcheck.tar.gz" "$sc_sum"
tar -xzf "$tmp/shellcheck.tar.gz" -C "$tmp"
mv "$tmp/shellcheck-v0.11.0/shellcheck" "$dir/bin/shellcheck"
fetch "https://github.com/mvdan/sh/releases/download/v3.14.1/shfmt_v3.14.1_$shfmt_target" "$dir/bin/shfmt" "$shfmt_sum"
chmod +x "$dir/bin/shfmt"
echo "$dir/bin"
