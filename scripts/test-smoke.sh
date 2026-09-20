#!/usr/bin/env bash
set -euo pipefail
# === test-smoke: Read-only API smoke checks ===
# Requires: FRONTEND_URL (default http://localhost:5173)
#           TEST_JWT  (session_jwt cookie value)
#
# All endpoints are read-only, no side effects.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

FRONTEND="${FRONTEND_URL:-http://localhost:5173}"
JWT="${TEST_JWT:-}"

PASS=0
FAIL=0

if [ -z "$JWT" ]; then
  echo "${YELLOW}Set TEST_JWT env var (session_jwt cookie value) to run smoke tests.${NC}"
  exit 0
fi

http_get() {
  local path="$1"
  local expect="${2:-200}"
  curl -s -o /dev/null -w "%{http_code}" \
       --cookie "session_jwt=$JWT" \
       "$FRONTEND$path"
}

check() {
  local name="$1"
  local path="$2"
  local expect="${3:-200}"
  printf "  %-50s " "${name}..."
  local code
  code=$(http_get "$path" "$expect")
  if [ "$code" = "$expect" ]; then
    printf "${GREEN}PASS${NC} (HTTP $code)\n"
    PASS=$((PASS + 1))
  else
    printf "${RED}FAIL${NC} (HTTP $code, expected $expect)\n"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "${BOLD}=== Layer 2: Smoke Tests (read-only)${NC}"
echo ""

check "GET /api/ping"                         "/api/ping"
check "GET /api/admin/class-levels"           "/api/admin/class-levels"
check "GET /api/admin/credentials"            "/api/admin/credentials"
check "GET /api/admin/session-terms"          "/api/admin/session-terms"
check "GET /api/admin/active-session-term"    "/api/admin/active-session-term"
check "GET /api/admin/terms"                  "/api/admin/terms"
check "GET /api/admin/students/list"          "/api/admin/students/list"
check "GET /api/admin/parents/list"           "/api/admin/parents/list"
check "GET /api/admin/class-subjects"         "/api/admin/class-subjects"

echo ""
printf "  ${BOLD}Results: ${GREEN}%d passed${NC}, ${RED}%d failed${NC}\n" "$PASS" "$FAIL"
echo ""

if [ "$FAIL" -gt 0 ]; then exit 1; fi
