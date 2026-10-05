# gehirn's one entry point for the checks, the build and the mock missions.
# CONTRIBUTING.md "Checks" says when each runs; lefthook.yml calls the same recipes on what is staged.

# V 0.5.2 uploads the failing C line and the V source around it to bugs.vlang.io when a C build fails.
export V_C_ERROR_BUG_REPORT_DISABLED := "1"

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
    @scripts/zenoh.sh

# Runs every tools/test_*.py self check and compiles the Python files.
py *paths="tools/*.py sidecar/*.py":
    for t in tools/test_*.py; do python3 "$t" || exit 1; done
    python3 -m py_compile {{ paths }}

# Builds the release binary ./gehirn.
build: zenoh
    v -prod -o gehirn .

# Builds the bridge, ./gehirn-bridge, which runs on its own machine (ADR-0005).
bridge: zenoh
    v -prod -o gehirn-bridge bridge/

# Builds the gamepad bridge, ./gehirn-gamepad, which runs on the pilot's machine and alone needs SDL2 (ADR-0006).
gamepad:
    v -prod -o gehirn-gamepad gamepad/

# Flies the mock missions and puts the adversarial scenarios to the mock MAGI; port is the mock's.
missions runs="10" port="8081": build
    #!/usr/bin/env bash
    set -euo pipefail
    # 8081 is the port of the llama.cpp preset and gehirn's default GEHIRN_URL.
    python3 tools/mock_endpoint.py --listen 127.0.0.1:{{ port }} --quiet &
    mock=$!
    trap 'kill $mock' EXIT
    export GEHIRN_URL=http://127.0.0.1:{{ port }}/v1/chat/completions
    export TYPESAFE_URL=http://127.0.0.1:{{ port }}/v1/systemone TYPESAFE_API_KEY=mock
    python3 tools/trials.py --runs {{ runs }} --jobs 3
    ./gehirn magi-eval 3

# Which models `just demo` and `just demo-record` fly: mock, scripted by tools/mock_endpoint.py
# without keys; hosted, README's hosted lineup; or magi, the hosted MAGI judging the mock's
# scripted core, which proposes the release at the beacon whatever the human does. The last two
# take GEHIRN_KEY and TYPESAFE_API_KEY: `python3 tools/withenv.py .env just lineup=magi demo`.
lineup := "mock"

# Flies one narrated mission with HQ, the field unit and the bridge apart, on lineup's models.
[no-exit-message]
demo mock="8081" umbilical="7447" watch="7448" plug="7777" dir="": _lineup build bridge
    @scripts/scenes/demo.sh {{ quote(justfile_directory() / "gehirn-bridge") }} {{ quote(mock) }} {{ quote(umbilical) }} {{ quote(watch) }} {{ quote(plug) }} {{ quote(dir) }} {{ quote(lineup) }}

# Records `just demo` from the bridge's frames into an MP4 and a looping GIF; needs ffmpeg.
[no-exit-message]
demo-record mock="8081" umbilical="7447" watch="7448" plug="7777" dir="": _lineup build
    @scripts/record.sh demo {{ quote(mock) }} {{ quote(umbilical) }} {{ quote(watch) }} {{ quote(plug) }} {{ quote(dir) }} {{ quote(lineup) }}

# Refuses an unknown lineup, and hosted models without their keys, before anything builds.
[no-exit-message]
[private]
_lineup:
    #!/usr/bin/env bash
    lineup={{ quote(lineup) }}
    case "$lineup" in
        mock) ;;
        hosted | magi)
            if [ -z "${GEHIRN_KEY:-}" ] || [ -z "${TYPESAFE_API_KEY:-}" ]; then
                echo "demo: lineup $lineup needs GEHIRN_KEY and TYPESAFE_API_KEY; python3 tools/withenv.py .env just lineup=$lineup demo passes them from .env" >&2
                exit 2
            fi
            ;;
        *)
            echo "demo: lineup is \"$lineup\", not mock, hosted or magi" >&2
            exit 2
            ;;
    esac
