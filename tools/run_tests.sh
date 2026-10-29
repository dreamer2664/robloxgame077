#!/usr/bin/env bash
# Builds the standalone-Luau test tree and executes it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="${TOOLS_DIR:-/home/user/.tools}"
cd "$ROOT"
python3 tools/test_build.py
"$TOOLS/luau" tests/.build/run.luau
