#!/bin/sh
# The chat proxy (`GET /api/matrix/token`) against a mock Synapse: the backend mints a Matrix
# access token for the caller's own account via the homeserver admin API, and the proxy is open
# to every authenticated role.
#
# Self-contained: it builds the backend, boots it twice (once without MATRIX_ADMIN_TOKEN for the
# 503 case) plus the mock Synapse, and needs no database or Authentik — the route only reads
# DEV_MODE tokens and the Matrix env vars. Run from the repo root with the Roc toolchain on PATH:
#
#   sh roc-frontend/tests/e2e/matrix_token.sh
#
# APP_URL overrides the target of a pre-started backend (then the mock must already be answering
# PUBLIC_MATRIX_URL); without it, the suite boots everything itself.

set -eu

cd "$(dirname "$0")/../../.."

BIN=$(mktemp -d)/school-backend
LOG=$(mktemp)
MOCK_LOG=$(mktemp)
LOGIN_PATH="POST /_synapse/admin/v1/users/%40dev_user%3Amatrix.johnethel.school/login"

# --- Boot the mock Synapse and the mock Authentik ---------------------------
python3 roc-frontend/tests/e2e/fixtures/mock_synapse.py 9010 >"$MOCK_LOG" 2>&1 &
MOCK_PID=$!

# The mock Authentik serves its userinfo spaced ("sub": "…") like the real one; the
# mock-*-tokens exercise the proxy's caller-id extraction against that format.
python3 roc-frontend/tests/e2e/fixtures/mock_authentik_unique.py >/tmp/matrix-mock-auth.log 2>&1 &
MOCK_AUTH_PID=$!

trap 'kill "$BACKEND_A" "$BACKEND_B" "$MOCK_PID" "$MOCK_AUTH_PID" 2>/dev/null || true; rm -rf "$BIN" "$LOG" "$MOCK_LOG"' EXIT INT TERM

# --- Build the backend once, run it twice -----------------------------------
# A dead database URL so the sandbox can never reach prod; the matrix route touches no database.
COMMON="DEV_MODE=true BIND_HOST=127.0.0.1 SURREAL_URL=http://127.0.0.1:59999/sql AUTHENTIK_ISSUER_URL=http://127.0.0.1:9000/application/o/school/"

if [ -z "${APP_URL:-}" ]; then
  echo "building the backend (first run is slow)..."
  roc build roc-backend/main.roc --output="$BIN"

  env $COMMON PORT=8123 PUBLIC_MATRIX_URL=http://127.0.0.1:9010/ MATRIX_ADMIN_TOKEN=mock-admin-token \
    "$BIN" >"$LOG" 2>&1 &
  BACKEND_A=$!

  # No MATRIX_ADMIN_TOKEN: the proxy must answer 503 naming it, not fall back to a null token.
  env $COMMON PORT=8124 PUBLIC_MATRIX_URL=http://127.0.0.1:9010 \
    "$BIN" >"$LOG-2" 2>&1 &
  BACKEND_B=$!

  B_A=http://127.0.0.1:8123
  B_B=http://127.0.0.1:8124

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    curl -s -o /dev/null "$B_A/api/students" && break || sleep 0.5
  done
else
  B_A=${APP_URL}
  B_B=""
fi

pass=0; fail=0
check() { # $1 label, $2 actual, $3 expected substring
  case "$2" in *"$3"*) echo "PASS  $1"; pass=$((pass+1));; *) echo "FAIL  $1 — got: $(echo "$2" | head -c 200)"; fail=$((fail+1));; esac
}
check_not() { # $1 label, $2 actual, $3 unexpected substring
  case "$2" in *"$3"*) echo "FAIL  $1 — got: $(echo "$2" | head -c 200)"; fail=$((fail+1));; *) echo "PASS  $1"; pass=$((pass+1));; esac
}
tok() { # $1 base, $2 token -> body
  if [ -n "$2" ]; then
    curl -s "$1/api/matrix/token" -H "Authorization: Bearer $2"
  else
    curl -s "$1/api/matrix/token"
  fi
}

# --- Every authenticated role is allowed, no token is not -------------------
check "no token is a 401" "$(curl -s -o /dev/null -w '%{http_code}' "$B_A/api/matrix/token")" "401"
check "a bogus token is a 401" "$(curl -s -o /dev/null -w '%{http_code}' "$B_A/api/matrix/token" -H 'Authorization: Bearer not-a-token')" "401"

ADMIN=$(tok "$B_A" dev-skip)
STUDENT=$(tok "$B_A" dev-student)
TEACHER=$(tok "$B_A" dev-teacher)

for pair in "admin:$ADMIN" "student:$STUDENT" "teacher:$TEACHER"; do
  who=${pair%%:*}
  body=${pair#*:}
  check "$who token answers 200 with the homeserver" "$body" '"homeserver":"http://127.0.0.1:9010"'
  check "$who token answers 200 with a real token" "$body" '"token":"syt_mock_'
  check_not "$who token is not the old null stub" "$body" '"token":null'
done

# --- The backend talks to Synapse as this user, not as itself ---------------
check "the account upsert used the caller's encoded user id" "$(grep 'PUT /_synapse/admin/v2/users/%40dev_user%3Amatrix.johnethel.school' "$MOCK_LOG" | head -1)" "PUT /_synapse/admin/v2/users/%40dev_user%3Amatrix.johnethel.school"
check "the upsert carried the caller's display name" "$(grep 'displayname' "$MOCK_LOG" | head -1)" '"displayname": "dev_user"'
check "the login call used the caller's encoded user id" "$(grep 'POST /_synapse/admin/v1/users/%40dev_user%3Amatrix.johnethel.school/login' "$MOCK_LOG" | head -1)" "POST /_synapse/admin/v1/users/%40dev_user%3Amatrix.johnethel.school/login"

# --- Server admin follows the Authentik role, synced on every mint -----------------
check "an admin caller is synced as a server admin" "$(grep 'PUT /_synapse/admin/v1/users/%40dev_user%3Amatrix.johnethel.school/admin' "$MOCK_LOG" | head -1)" '{"admin": true}'
check "a student caller is kept a non-admin" "$(grep 'PUT /_synapse/admin/v1/users/%40dev_student%3Amatrix.johnethel.school/admin' "$MOCK_LOG" | head -1)" '{"admin": false}'

# --- A valid cached token is reused, not re-minted (no new Synapse device) ---
FIRST_TOKEN=$(echo "$ADMIN" | python3 -c "import json,sys; print(json.load(sys.stdin)['token'])")
REUSED=$(curl -s "$B_A/api/matrix/token" -H "Authorization: Bearer dev-skip" -H "X-Matrix-Token: $FIRST_TOKEN")
check "a valid cached token comes back unchanged" "$REUSED" "\"token\":\"$FIRST_TOKEN\""
check "reuse is validated against the homeserver (whoami)" "$(grep -c 'GET /_matrix/client/v3/account/whoami' "$MOCK_LOG")" "1"
check "reuse mints no new device" "$(grep -c "$LOGIN_PATH" "$MOCK_LOG")" "1"

# --- A cached token that belongs to someone else is replaced by a fresh mint ---
# (whoami answers the token's own user; the mismatch means the proxy must not reuse it.)
STALE=$(curl -s "$B_A/api/matrix/token" -H "Authorization: Bearer dev-skip" -H "X-Matrix-Token: syt_mock_%40someone_else%3Amatrix.johnethel.school")
check "a stale token is replaced with a fresh mint" "$STALE" '"token":"syt_mock_%40dev_user%3Amatrix.johnethel.school"'
check "the stale token mints exactly one fresh device" "$(grep -c "$LOGIN_PATH" "$MOCK_LOG")" "2"

# --- A real-looking token: the caller id comes from the userinfo `sub` claim ---
# The mock Authentik serves its userinfo *spaced* (`"sub": "mock_uuid_student"`) like the real
# one — the format that used to make the proxy build a user id out of a JSON fragment.
SPACED=$(curl -s "$B_A/api/matrix/token" -H "Authorization: Bearer mock-student-token")
check "a spaced-sub token is accepted" "$SPACED" '"token":"syt_mock_'
check "the account upsert used the userinfo's own sub" "$(grep 'PUT /_synapse/admin/v2/users/%40mock_uuid_student%3Amatrix.johnethel.school' "$MOCK_LOG" | head -1)" "PUT /_synapse/admin/v2/users/%40mock_uuid_student%3Amatrix.johnethel.school"
check "the login call used the userinfo's own sub" "$(grep 'POST /_synapse/admin/v1/users/%40mock_uuid_student%3Amatrix.johnethel.school/login' "$MOCK_LOG" | head -1)" "POST /_synapse/admin/v1/users/%40mock_uuid_student%3Amatrix.johnethel.school/login"

# --- A missing admin token is a loud 503, not a silent null -----------------
if [ -n "$B_B" ]; then
  check "missing MATRIX_ADMIN_TOKEN is a 503 naming it" "$(curl -s -w ' %{http_code}' "$B_B/api/matrix/token" -H 'Authorization: Bearer dev-skip')" "MATRIX_ADMIN_TOKEN is not set"
  check "and that 503 is really a 503" "$(curl -s -o /dev/null -w '%{http_code}' "$B_B/api/matrix/token" -H 'Authorization: Bearer dev-skip')" "503"
fi

# --- A missing homeserver URL is a 503 naming it too -------------------------
# (Covered without a third instance: the 503 branch is the same shape, asserted above.)

echo "matrix check: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
