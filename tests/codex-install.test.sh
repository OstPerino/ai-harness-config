#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
PYTHONDONTWRITEBYTECODE=1 python3 "$ROOT/tests/codex_install_cases.py" "$ROOT"
