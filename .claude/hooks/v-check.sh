#!/usr/bin/env bash
# PostToolUse hook for Edit|Write: formats an edited V file, then type checks it with
# warnings as errors (CONTRIBUTING.md, Checks). `v -check .` skips _test.v files, so an
# edited test is checked on its own. Exit 2 hands the compiler output back to Claude.
set -uo pipefail

file=$(jq -r '.tool_input.file_path // empty')
case "$file" in
    *.v | *.vsh) ;;
    *) exit 0 ;;
esac

v fmt -w "$file" >/dev/null 2>&1
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
target=.
case "$file" in *_test.v) target=$file ;; esac
if ! out=$(v -W -check "$target" 2>&1); then
    printf '%s\n' "$out" >&2
    exit 2
fi
