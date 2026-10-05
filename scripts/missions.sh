#!/usr/bin/env bash
# Flies the mock missions and puts the adversarial scenarios to the mock MAGI. The justfile's
# missions recipe runs it once ./gehirn is built; by hand, run `just build` first, since it flies
# the ./gehirn that is there. Its arguments are RUNS, 10 unless given, and PORT, the mock's, 8081
# unless given, the port of the llama.cpp preset and gehirn's default GEHIRN_URL.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
runs=${1:-10} port=${2:-8081}

python3 tools/mock_endpoint.py --listen "127.0.0.1:$port" --quiet &
mock=$!
trap 'kill $mock' EXIT
export GEHIRN_URL=http://127.0.0.1:$port/v1/chat/completions
export TYPESAFE_URL=http://127.0.0.1:$port/v1/systemone TYPESAFE_API_KEY=mock
python3 tools/trials.py --runs "$runs" --jobs 3
./gehirn magi-eval 3
