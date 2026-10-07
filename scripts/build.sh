#!/usr/bin/env bash
# Builds BINARY, gehirn unless given, as `v -o BINARY` with the arguments after it, `-prod .`
# unless given, or keeps it when BINARY.stamp, which git ignores, shows that the same command
# built it from the same inputs, as make would but by content rather than by modification time.
# The justfile's build and bridge recipes run it, since a release build takes about a minute on
# the Mac and the demo, the scenes and the missions build first. The stamp goes before v starts
# and comes back only once v has succeeded, so a failed or interrupted build leaves none.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
out=${1:-gehirn}
[ $# -gt 1 ] || set -- "$out" -prod .
shift

# V 0.5.2 uploads the failing C line and the V source around it to bugs.vlang.io when a C build
# fails, and a run by hand has no justfile to export this (CONTRIBUTING.md, V 0.5.2 rule 9).
export V_C_ERROR_BUG_REPORT_DISABLED=1

# inputs prints one hash of the command, the variables V and clang read, the C compiler's
# version, and the path and content of every file the build reads: the v executable, v.mod,
# every V file it parses, vlib's among them, every file under a path that a #flag or
# #include names below @VMODROOT, every archive a #flag names by its absolute path, such as
# Homebrew's libgc.a, and every file an $embed_file names, both in the working directory, where V
# looks first, and beside its own file. vlib's C files change only with the v executable. It
# fails when V cannot parse the sources, which the build then reports, or the scan fails.
inputs() {
    local files hits list vexe
    files=$(v -print-v-files -o "$out" "$@" 2>/dev/null | sed 's/:parse_text$//' | LC_ALL=C sort -u) || return

    # `command -v v` may name a shim, such as proto's, whose content no V version changes, so the
    # compiler hashed is the one beside the vlib that V parses.
    vexe=$(printf '%s\n' "$files" | awk '!f && sub(/\/vlib\/builtin\/.*/, "/v") { print; f = 1 }')
    [ -n "$vexe" ] || vexe=$(command -v v)
    hits=$(printf '%s\n' "$files" | tr '\n' '\0' |
        xargs -0 grep -Ho -e '@VMODROOT/[^"'\'' @]*' -e '[$]embed_file(['\''"][^'\''"]*' -e '#flag.* /[^"'\'' @]*\.a') || return
    list=$(
        {
            printf '%s\n' "$files" "$vexe" v.mod
            {
                printf '%s\n' "$hits" | sed -e 's|^.*@VMODROOT/||' -e 's|^[^#]*:#flag.* /|/|' -e 's|[^/]*:[$]embed_file(.||' -e 's|@DIR/||'
                printf '%s\n' "$hits" | sed -n 's|^.*:[$]embed_file(.||p'
            } | while read -r p; do [ ! -e "$p" ] || find -L "$p" -type f || exit; done
        } | LC_ALL=C sort -u
    ) || return
    {
        printf '%s\n' "$out" "$*" "$(cc --version 2>&1)" "${VFLAGS-}" "${CFLAGS-}" "${LDFLAGS-}" \
            "${MACOSX_DEPLOYMENT_TARGET-}" "${SDKROOT-}" "${DEVELOPER_DIR-}" "${CPATH-}" "${C_INCLUDE_PATH-}" \
            "${OBJC_INCLUDE_PATH-}" "${LIBRARY_PATH-}" "$list"
        printf '%s\n' "$list" | git hash-object --no-filters --stdin-paths
    } | git hash-object --stdin
}

stamp=$out.stamp
want=$(inputs "$@") || want=""
had=$(cat "$stamp" 2>/dev/null) || had=""
if [ ! -f "$out" ]; then
    why="there is none"
elif [ -z "$had" ]; then
    why="it has no stamp"
elif [ "${had% *}" != "$want" ]; then
    why="the command or an input changed"
elif [ "${had#* }" != "$(git hash-object --no-filters "$out")" ]; then
    why="something else wrote it since"
else
    echo "build: kept $out, which v -o $out $* built from the same inputs" >&2
    exit 0
fi
echo "build: building $out with v -o $out $*, since $why" >&2
rm -f "$stamp"
v -o "$out" "$@"

# An input that changed while v ran may or may not be in the binary, so it gets no stamp.
# ponytail: one changed back before v ended still gets one, as with make; building from a copy of
# the inputs would close that.
if [ -n "$want" ] && [ "$(inputs "$@")" = "$want" ]; then
    echo "$want $(git hash-object --no-filters "$out")" >"$stamp"
fi
