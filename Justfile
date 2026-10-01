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
test:
    v -W -N test .

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
