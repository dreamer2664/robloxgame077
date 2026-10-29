#!/usr/bin/env bash
# Regenerates the test build (which rewrites module requires for the CLI),
# exports the world layout, then renders the screenshot set.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOLS="${TOOLS_DIR:-/home/user/.tools}"
cd "$ROOT"
python3 tools/test_build.py >/dev/null
"$TOOLS/luau" tools/render/export_layout.luau > tools/render/world.json
python3 tools/render/render_world.py
