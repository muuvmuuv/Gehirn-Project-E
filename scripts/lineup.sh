#!/usr/bin/env bash
# Refuses an unknown lineup or scene, a canon scene on any lineup but the mock, and hosted models
# without their keys. Its arguments are LINEUP, mock unless given, and SCENE, the name of a script
# in scripts/scenes, demo unless given. The justfile's _lineup runs it before anything builds,
# scripts/record.sh before it builds the bridge that records, and scripts/stage.sh for every
# scene, so a scene run by hand stops here too rather than at a beat.
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
