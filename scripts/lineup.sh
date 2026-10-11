#!/usr/bin/env bash
# Refuses an unknown lineup or scene, a canon scene on any lineup but the mock, hosted models
# without their keys, and the hosted lineup when its core does not answer. Its arguments are
# LINEUP, mock unless given, and SCENE, the name of a script in scripts/scenes, demo unless given.
# The justfile's _lineup runs it before anything builds, scripts/record.sh before it builds the
# bridge that records, and scripts/stage.sh for every scene, so a scene run by hand stops here too
# rather than at a beat.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
lineup=${1:-mock} scene=${2-demo}

# The name becomes a path, so it holds no slash and no dot. The letters are listed, since bash
# 3.2 matches a-z by the locale's collation, which takes uppercase too, and APFS ignores case.
case "$scene" in
    *[!abcdefghijklmnopqrstuvwxyz0123456789-]*) scene="" ;;
esac
if [ -z "$scene" ] || [ ! -f "scripts/scenes/$scene.sh" ]; then
    echo "scene: no scene \"${2:-}\" in scripts/scenes; docs/scenes.md lists them" >&2
    exit 2
fi
if [ "$scene" != demo ] && [ "$lineup" != mock ]; then
    echo "scene: $scene is staged on the mock, so it flies on lineup=mock only" >&2
    exit 2
fi
case "$lineup" in
    mock) ;;
    hosted | magi)
        if [ -z "${GEHIRN_KEY:-}" ] || [ -z "${TYPESAFE_API_KEY:-}" ]; then
            echo "lineup: $lineup needs GEHIRN_KEY and TYPESAFE_API_KEY; python3 tools/withenv.py .env just lineup=$lineup demo passes them from .env" >&2
            exit 2
        fi
        ;;
    *)
        echo "lineup: \"$lineup\" is not mock, hosted or magi" >&2
        exit 2
        ;;
esac

# The hosted lineup's core runs on uzu (docs/running.md, Hosted models), at the default URL that
# scripts/stage.sh repeats, unless CORE_URL or CORE_MODEL names another; a core that CORE_MODEL
# names alone goes to GEHIRN_URL with the units. Any HTTP answer will do: uzu answers a GET there
# with 404.
if [ "$lineup" = hosted ] && { [ -n "${CORE_URL:-}" ] || [ -z "${CORE_MODEL:-}" ]; }; then
    core=${CORE_URL:-http://127.0.0.1:8083/v1/chat/completions}
    if ! curl -s -o /dev/null -m 5 "$core"; then
        echo "lineup: hosted needs its core at $core, which does not answer; docs/running.md, Hosted models, starts it on uzu" >&2
        exit 2
    fi
fi
