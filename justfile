# gehirn's one entry point for the checks, the build and the mock missions.
# CONTRIBUTING.md "Checks" says when each runs; lefthook.yml calls the same recipes on what is staged.

# V 0.5.2 uploads the failing C line and the V source around it to bugs.vlang.io when a C build fails.
export V_C_ERROR_BUG_REPORT_DISABLED := "1"

# Runs every check on the working tree, and verifies that this file is formatted; `just --fmt` fixes it.
check: fmt vet test py shell
    @{{ just_executable() }} --justfile {{ quote(justfile()) }} --fmt --check

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

# Checks shell scripts with shellcheck, following sources, and their format; `shfmt -i 4 -ci -w` fixes it.
shell *paths="scripts/*.sh scripts/scenes/*.sh .claude/hooks/*.sh":
    shellcheck -x {{ paths }}
    shfmt -i 4 -ci -d {{ paths }}

# Builds the release binary ./gehirn.
build: zenoh
    v -prod -o gehirn .

# Builds the bridge, ./gehirn-bridge, which runs on its own machine (ADR-0005).
bridge: zenoh
    v -prod -o gehirn-bridge bridge/

# Builds the gamepad bridge, ./gehirn-gamepad, which runs on the pilot's machine and alone needs SDL2 (ADR-0006).
gamepad:
    v -prod -o gehirn-gamepad gamepad/

# Renders the brand's raster files from the SVG masters in assets/brand; needs uv and rsvg-convert.
assets:
    uv run --script assets/build.py

# Flies the mock missions and puts the adversarial scenarios to the mock MAGI; port is the mock's.
missions runs="10" port="8081": build
    @scripts/missions.sh {{ quote(runs) }} {{ quote(port) }}

# Which models `just demo` and `just demo-record` fly: mock, scripted by tools/mock_endpoint.py
# without keys; hosted, the hosted lineup of docs/running.md; or magi, the hosted MAGI judging
# the mock's scripted core, which proposes the release at the beacon whatever the human does.
# The last two take GEHIRN_KEY and TYPESAFE_API_KEY:
# `python3 tools/withenv.py .env just lineup=magi demo`.
lineup := "mock"

# Which story `just demo` and `just demo-record` fly: demo, the whole mission, or a canon scene,
# the name of a script in scripts/scenes such as ep13-iruel, which docs/scenes.md describes.
# Scenes are staged on the mock, so they fly on lineup=mock only: `just scene=ep13-iruel demo`.
scene := "demo"

# Flies one narrated mission, or the scene that scene names, with HQ, the field unit and the
# bridge apart, on lineup's models.
[no-exit-message]
demo mock="8081" umbilical="7447" watch="7448" plug="7777" dir="": _lineup build bridge
    @{{ quote("scripts/scenes/" + scene + ".sh") }} {{ quote(justfile_directory() / "gehirn-bridge") }} {{ quote(mock) }} {{ quote(umbilical) }} {{ quote(watch) }} {{ quote(plug) }} {{ quote(dir) }} {{ quote(lineup) }}

# Records `just demo`, or the scene that scene names, from the bridge's frames into an MP4 and
# a looping GIF of MAGI; needs ffmpeg.
[no-exit-message]
demo-record mock="8081" umbilical="7447" watch="7448" plug="7777" dir="": _lineup build
    @scripts/record.sh {{ quote(scene) }} {{ quote(mock) }} {{ quote(umbilical) }} {{ quote(watch) }} {{ quote(plug) }} {{ quote(dir) }} {{ quote(lineup) }}

# Refuses an unknown lineup or scene, a scene on hosted models, and hosted models without their
# keys, before anything builds.
[no-exit-message]
[private]
_lineup:
    @scripts/lineup.sh {{ quote(lineup) }} {{ quote(scene) }}
