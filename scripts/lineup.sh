#!/usr/bin/env bash
# Refuses an unknown lineup, and hosted models without their keys. Its one argument is LINEUP,
# mock unless given. The justfile's _lineup runs it before anything builds, and scripts/stage.sh
# for every scene, so a scene run by hand stops here too rather than at a beat.
set -euo pipefail
lineup=${1:-mock}
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
