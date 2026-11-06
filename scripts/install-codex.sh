#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
command -v python3 >/dev/null 2>&1 || { printf 'Python 3.11+ required (standard library only)\n' >&2; exit 1; }
exec python3 "$ROOT/scripts/install-codex.py" "$@"
