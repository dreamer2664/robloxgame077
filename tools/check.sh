#!/usr/bin/env bash
# Static verification: typecheck (luau-lsp against the real Roblox API dump),
# lint (selene + roblox std) and formatting (stylua).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="${TOOLS_DIR:-/home/user/.tools}"
LUAU_LSP="$TOOLS/luau-lsp"
SELENE="$TOOLS/selene"
STYLUA="$TOOLS/stylua"
DEFS="$TOOLS/roblox-globaltypes.d.luau"
cd "$ROOT"
fail=0

echo "== luau-lsp analyze (strict Roblox typecheck) =="
"$LUAU_LSP" analyze --definitions="$DEFS" --ignore="**/_Index/**" --settings='{}' -- \
  src 2>&1 | grep -v "^\[INFO\]" | tee /tmp/typecheck.log
if grep -qE "TypeError|SyntaxError|UnknownSymbol|UnknownGlobal" /tmp/typecheck.log; then
  echo "TYPECHECK FAILED"; fail=1
else
  echo "typecheck clean"
fi

echo "== selene =="
"$SELENE" --display-style quiet src tests 2>&1 | tail -40 || fail=1

echo "== stylua --check =="
"$STYLUA" --check src tests 2>&1 | tail -20 || fail=1

exit $fail
