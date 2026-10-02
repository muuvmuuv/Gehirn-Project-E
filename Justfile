# gehirn's one entry point for the checks, the build and the mock missions.
# CONTRIBUTING.md "Checks" says when each runs; lefthook.yml calls the same recipes on what is staged.

# Runs every check on the working tree.
check: fmt vet test py

# Verifies that V files are formatted; `v fmt -w` fixes them.
fmt *paths=".":
    v fmt -verify {{ paths }}

# Checks that every pub fn has a doc comment that starts with its name.
vet *paths=".":
    v vet -W {{ paths }}

# Runs every _test.v; warnings and notices fail the build.
test: zenoh
    v -W -N test .

# Fetches the pinned zenoh-c release for this host into thirdparty/zenoh-c, which zenoh/zenoh.c.v links.
zenoh:
    #!/usr/bin/env bash
    set -euo pipefail
    version=1.10.1
    # ponytail: macOS on Apple Silicon and musl Linux only; another host needs its target and checksum here.
    case "$(uname -s)-$(uname -m)" in
        Darwin-arm64) target=aarch64-apple-darwin sum=82da6e95eb895413369f55d1a53eb5b621b22ab8afc446b041b7760eec240ff4 ;;
        Linux-aarch64) target=aarch64-unknown-linux-musl sum=de99cc82c7ae93eaa2aa5a0c8bcfcefed7624b0e0f85c679f7dba9c54ccdff9c ;;
        Linux-x86_64) target=x86_64-unknown-linux-musl sum=293866bb632fd579fb0603bbfdb8d383e7c2d4eadc8ec3ae199fafa1dbc99c55 ;;
        *) echo "zenoh: no pinned zenoh-c build for $(uname -s)-$(uname -m)" >&2; exit 1 ;;
    esac
    if [ "$(uname -s)" = Linux ] && ! ls /lib/ld-musl-* >/dev/null 2>&1; then
        echo "zenoh: the pinned Linux builds are for musl, and this host runs another libc" >&2
        exit 1
    fi
    dir=thirdparty/zenoh-c
    if [ "$(cat "$dir/VERSION" 2>/dev/null)" = "$version $target" ]; then
        exit 0
    fi
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

# Runs every tools/test_*.py self check and compiles the Python files.
py *paths="tools/*.py sidecar/*.py":
    for t in tools/test_*.py; do python3 "$t" || exit 1; done
    python3 -m py_compile {{ paths }}

# Builds the release binary ./gehirn.
build:
    v -prod -o gehirn .

# Flies the mock missions and puts the adversarial scenarios to the mock MAGI.
missions runs="10": build
    #!/usr/bin/env bash
    set -euo pipefail
    # The mock holds port 8081, the port of the llama.cpp preset.
    python3 tools/mock_endpoint.py --quiet &
    mock=$!
    trap 'kill $mock' EXIT
    export TYPESAFE_URL=http://127.0.0.1:8081/v1/systemone TYPESAFE_API_KEY=mock
    python3 tools/trials.py --runs {{ runs }} --jobs 3
    ./gehirn magi-eval 3
