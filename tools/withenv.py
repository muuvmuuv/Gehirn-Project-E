#!/usr/bin/env python3
"""Run a command with the variables of a dotenv file added to its environment.

Variables the environment already sets win over the file, so a value given on the command
line overrides it. Values are handed to the command and never printed.

    python3 tools/withenv.py .env ./gehirn
"""

import os
import string
import sys


def load_env(path: str) -> dict[str, str]:
    """Read a dotenv file: KEY=VALUE lines, optional export and quotes, ${NAME} expanded."""
    found: dict[str, str] = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.removeprefix("export ").split("=", 1)
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
                value = value[1:-1]
            found[key.strip()] = string.Template(value).safe_substitute({**os.environ, **found})
    return found


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit("usage: withenv.py FILE COMMAND [ARG...]")
    try:
        found = load_env(sys.argv[1])
    except OSError as e:
        sys.exit(f"withenv: cannot read {sys.argv[1]}: {e.strerror}")
    os.execvpe(sys.argv[2], sys.argv[2:], {**found, **os.environ})


if __name__ == "__main__":
    main()
