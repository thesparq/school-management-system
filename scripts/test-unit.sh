#!/usr/bin/env bash
set -euo pipefail
# === test-unit: Compile-time checks for MoonBit agents ===

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0

run() {
  local name="$1"
  shift
  printf "  %-50s " "${name}..."
  if "$@" > /dev/null 2>&1; then
    printf "${GREEN}PASS${NC}\n"
    PASS=$((PASS + 1))
  else
    printf "${RED}FAIL${NC}\n"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "${BOLD}=== Layer 1: Compile Checks${NC}"
echo ""

run "moon check --target wasm (agents)"  bash -c "cd agents && moon check --target wasm"
run "moon check (shared)"                bash -c "cd shared && moon check"
run "pnpm check (frontend)"              pnpm --filter frontend run check

echo ""
printf "  ${BOLD}Results: ${GREEN}%d passed${NC}, ${RED}%d failed${NC}\n" "$PASS" "$FAIL"
echo ""

if [ "$FAIL" -gt 0 ]; then exit 1; fi
