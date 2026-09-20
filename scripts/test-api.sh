#!/usr/bin/env bash
set -euo pipefail
# === test-api: Full CRUD integration tests ===
# Requires: FRONTEND_URL (default http://localhost:5173)
#           TEST_JWT  (session_jwt cookie value)
#           AUTHENTIK_HOST, AUTHENTIK_SERVICE_ACCOUNT_TOKEN (for group lookup)
#
# Creates a user per role, verifies profile, edits, then deletes.
# All created users are cleaned up even on failure.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

FRONTEND="${FRONTEND_URL:-http://localhost:5173}"
JWT="${TEST_JWT:-}"
AUTH_HOST="${AUTHENTIK_HOST:-}"
AUTH_TOKEN="${AUTHENTIK_SERVICE_ACCOUNT_TOKEN:-}"

PASS=0
FAIL=0
CLEANUP_PKS=()

if [ -z "$JWT" ]; then
  echo "${YELLOW}Set TEST_JWT to run API integration tests.${NC}"
  echo "  export TEST_JWT='<your-session-jwt-cookie>'"
  exit 0
fi
if [ -z "$AUTH_HOST" ] || [ -z "$AUTH_TOKEN" ]; then
  echo "${YELLOW}Set AUTHENTIK_HOST and AUTHENTIK_SERVICE_ACCOUNT_TOKEN for group lookup.${NC}"
  exit 0
fi

# ── helpers ────────────────────────────────────────────────

http() {
  local method="$1" path="$2" body="${3:-}" expect="${4:-200}"
  local url="$FRONTEND$path"
  local code
  if [ -n "$body" ]; then
    code=$(curl -s -o /tmp/test_resp.json -w "%{http_code}" \
      --cookie "session_jwt=$JWT" \
      -H "Content-Type: application/json" \
      -X "$method" -d "$body" \
      "$url")
  else
    code=$(curl -s -o /tmp/test_resp.json -w "%{http_code}" \
      --cookie "session_jwt=$JWT" \
      -X "$method" \
      "$url")
  fi
  echo "$code"
}

json_field() {
  jq -r ".data.${1} // .${1} // empty" /tmp/test_resp.json 2>/dev/null || echo ""
}

assert() {
  local name="$1" expect="$2" actual="$3"
  printf "    %-48s " "${name}..."
  if [ "$actual" = "$expect" ]; then
    printf "${GREEN}PASS${NC}\n"
    PASS=$((PASS + 1))
  else
    printf "${RED}FAIL${NC} (got '${actual}', expected '${expect}')\n"
    FAIL=$((FAIL + 1))
  fi
}

check_status() {
  local name="$1" method="$2" path="$3" body="${4:-}" expect="${5:-200}"
  printf "  %-50s " "${name}..."
  local code
  code=$(http "$method" "$path" "$body" "$expect")
  if [ "$code" = "$expect" ]; then
    printf "${GREEN}PASS${NC} (HTTP $code)\n"
    PASS=$((PASS + 1))
  else
    printf "${RED}FAIL${NC} (HTTP $code, expected $expect)\n"
    local err=$(json_field "error.message" 2>/dev/null || true)
    [ -n "$err" ] && printf "    Error: %s\n" "$err"
    FAIL=$((FAIL + 1))
  fi
}

get_group_pk() {
  local name="$1"
  local encoded
  encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$name'))" 2>/dev/null || echo "$name")
  curl -s -H "Authorization: Bearer $AUTH_TOKEN" \
    "https://${AUTH_HOST}/api/v3/core/groups/?page_size=100&search=${encoded}" \
    | jq -r ".results[] | select(.name | ascii_downcase == \"${name}\") | .pk" 2>/dev/null || echo ""
}

generate_password() {
  python3 -c "import secrets,string; print(''.join(secrets.choice(string.ascii_letters+string.digits) for _ in range(16)))" 2>/dev/null || echo "TestPass123!"
}

cleanup() {
  echo ""
  echo "  Cleaning up ${#CLEANUP_PKS[@]} created users..."
  for pk in "${CLEANUP_PKS[@]}"; do
    local role="${CLEANUP_ROLES[$pk]:-unknown}"
    local uuid="${CLEANUP_UUIDS[$pk]:-unknown}"
    http "DELETE" "/api/admin/users/${pk}?uuid=${uuid}&role=${role}" "" "200" > /dev/null 2>&1 || true
  done
}
trap cleanup EXIT

# ── resolve groups ─────────────────────────────────────────

echo ""
echo "${BOLD}=== Layer 3: API Integration Tests${NC}"
echo ""

echo "  Resolving group PKs from Authentik..."
STUDENT_GP=$(get_group_pk "student")
TEACHER_GP=$(get_group_pk "teacher")
ADMIN_GP=$(get_group_pk "admin")
PARENT_GP=$(get_group_pk "parent")

if [ -z "$STUDENT_GP" ] || [ -z "$TEACHER_GP" ] || [ -z "$ADMIN_GP" ] || [ -z "$PARENT_GP" ]; then
  echo "  ${RED}Missing one or more group PKs. Ensure groups 'student', 'teacher', 'admin', 'parent' exist in Authentik.${NC}"
  exit 1
fi
echo "  Groups resolved ✓"

# ── class level lookup ─────────────────────────────────────

echo ""
CLASS_LEVEL=$(http "GET" "/api/admin/class-levels" "" "200" > /dev/null && json_field "0.name")
if [ -z "$CLASS_LEVEL" ]; then
  echo "  ${YELLOW}No class levels found — student create will fail.${NC}"
fi

# ── generate unique suffix ─────────────────────────────────

TS=$(date +%s)
declare -A CLEANUP_ROLES
declare -A CLEANUP_UUIDS

# ── test student CRUD ──────────────────────────────────────

echo ""
echo "  ${BOLD}--- Student CRUD ---${NC}"

ST_PASS=$(generate_password)
ST_BODY=$(jq -nc --arg u "test-student-$TS" --arg e "test-student-$TS@example.com" \
  --arg p "$ST_PASS" --arg g "$STUDENT_GP" --arg cl "$CLASS_LEVEL" \
  '{username:$u,surname:"Test",first_name:"Student",email:$e,password:$p,is_active:true,group_pk:$g,role:"student",class_level:$cl,date_of_birth:"2005-01-15",passport_url:"https://example.com/passport.jpg"}')

check_status "POST /api/admin/users (create student)" "POST" "/api/admin/users" "$ST_BODY" "201"

ST_PK=$(json_field "pk")
ST_UUID=$(json_field "uuid")
if [ -n "$ST_PK" ] && [ -n "$ST_UUID" ]; then
  CLEANUP_PKS+=("$ST_PK")
  CLEANUP_ROLES["$ST_PK"]="student"
  CLEANUP_UUIDS["$ST_PK"]="$ST_UUID"

  check_status "GET profile (student)" "GET" "/api/admin/users/${ST_UUID}/profile?role=student" "" "200"
  assert "  has class_name" "0" "$(json_field "class_name" | grep -c . || echo 0)"

  ED_BODY=$(jq -nc --arg pk "$ST_PK" --arg u "test-student-$TS" --arg e "test-student-$TS@example.com" \
    --arg cl "$CLASS_LEVEL" \
    '{authentik_pk:($pk|tonumber),username:$u,surname:"Test",first_name:"StudentEdit",display_name:"Test StudentEdit",email:$e,role:"student",class_level:$cl,date_of_birth:"2005-01-15",passport_url:"https://example.com/passport2.jpg",target_user_id:$u}')
  check_status "POST edit-profile (student)" "POST" "/api/admin/users/${ST_UUID}/edit-profile" "$ED_BODY" "200"

  check_status "POST activate (student)" "POST" "/api/admin/users/${ST_PK}/activate-authentik" "" "200"
  check_status "POST deactivate (student)" "POST" "/api/admin/users/${ST_PK}/deactivate-authentik" "" "200"

  check_status "DELETE user (student)" "DELETE" "/api/admin/users/${ST_PK}?uuid=${ST_UUID}&role=student" "" "200"
  unset 'CLEANUP_ROLES[$ST_PK]'
  unset 'CLEANUP_UUIDS[$ST_PK]'
fi

# ── test teacher CRUD ──────────────────────────────────────

echo ""
echo "  ${BOLD}--- Teacher CRUD ---${NC}"

TCH_PASS=$(generate_password)
TCH_BODY=$(jq -nc --arg u "test-teacher-$TS" --arg e "test-teacher-$TS@example.com" \
  --arg p "$TCH_PASS" --arg g "$TEACHER_GP" \
  '{username:$u,surname:"Test",first_name:"Teacher",email:$e,password:$p,is_active:true,group_pk:$g,role:"teacher",passport_url:"https://example.com/passport.jpg"}')

check_status "POST /api/admin/users (create teacher)" "POST" "/api/admin/users" "$TCH_BODY" "201"

TCH_PK=$(json_field "pk")
TCH_UUID=$(json_field "uuid")
if [ -n "$TCH_PK" ] && [ -n "$TCH_UUID" ]; then
  CLEANUP_PKS+=("$TCH_PK")
  CLEANUP_ROLES["$TCH_PK"]="teacher"
  CLEANUP_UUIDS["$TCH_PK"]="$TCH_UUID"

  check_status "GET profile (teacher)" "GET" "/api/admin/users/${TCH_UUID}/profile?role=teacher" "" "200"
  assert "  has surname" "Test" "$(json_field "surname")"

  check_status "DELETE user (teacher)" "DELETE" "/api/admin/users/${TCH_PK}?uuid=${TCH_UUID}&role=teacher" "" "200"
  unset 'CLEANUP_ROLES[$TCH_PK]'
  unset 'CLEANUP_UUIDS[$TCH_PK]'
fi

# ── test admin CRUD ────────────────────────────────────────

echo ""
echo "  ${BOLD}--- Admin CRUD ---${NC}"

AD_PASS=$(generate_password)
AD_BODY=$(jq -nc --arg u "test-admin-$TS" --arg e "test-admin-$TS@example.com" \
  --arg p "$AD_PASS" --arg g "$ADMIN_GP" \
  '{username:$u,surname:"Test",first_name:"Admin",email:$e,password:$p,is_active:true,group_pk:$g,role:"admin",passport_url:"https://example.com/passport.jpg"}')

check_status "POST /api/admin/users (create admin)" "POST" "/api/admin/users" "$AD_BODY" "201"

AD_PK=$(json_field "pk")
AD_UUID=$(json_field "uuid")
if [ -n "$AD_PK" ] && [ -n "$AD_UUID" ]; then
  CLEANUP_PKS+=("$AD_PK")
  CLEANUP_ROLES["$AD_PK"]="admin"
  CLEANUP_UUIDS["$AD_PK"]="$AD_UUID"

  check_status "GET profile (admin)" "GET" "/api/admin/users/${AD_UUID}/profile?role=admin" "" "200"
  assert "  has surname" "Test" "$(json_field "surname")"

  check_status "DELETE user (admin)" "DELETE" "/api/admin/users/${AD_PK}?uuid=${AD_UUID}&role=admin" "" "200"
  unset 'CLEANUP_ROLES[$AD_PK]'
  unset 'CLEANUP_UUIDS[$AD_PK]'
fi

# ── test parent CRUD ───────────────────────────────────────

echo ""
echo "  ${BOLD}--- Parent CRUD ---${NC}"

PR_PASS=$(generate_password)
PR_BODY=$(jq -nc --arg u "test-parent-$TS" --arg e "test-parent-$TS@example.com" \
  --arg p "$PR_PASS" --arg g "$PARENT_GP" \
  '{username:$u,name:"Test Parent",email:$e,password:$p,is_active:true,group_pk:$g,role:"parent",students:[],passport_url:"https://example.com/passport.jpg"}')

check_status "POST /api/admin/users (create parent)" "POST" "/api/admin/users" "$PR_BODY" "201"

PR_PK=$(json_field "pk")
PR_UUID=$(json_field "uuid")
if [ -n "$PR_PK" ] && [ -n "$PR_UUID" ]; then
  CLEANUP_PKS+=("$PR_PK")
  CLEANUP_ROLES["$PR_PK"]="parent"
  CLEANUP_UUIDS["$PR_PK"]="$PR_UUID"

  check_status "GET profile (parent)" "GET" "/api/admin/users/${PR_UUID}/profile?role=parent" "" "200"
  assert "  has name" "Test Parent" "$(json_field "name")"

  check_status "DELETE user (parent)" "DELETE" "/api/admin/users/${PR_PK}?uuid=${PR_UUID}&role=parent" "" "200"
  unset 'CLEANUP_ROLES[$PR_PK]'
  unset 'CLEANUP_UUIDS[$PR_PK]'
fi

# ── credential CRUD ────────────────────────────────────────

echo ""
echo "  ${BOLD}--- Credential CRUD ---${NC}"

CRED_BODY='{"name":"Test Credential '${TS}'"}'
check_status "POST create credential" "POST" "/api/admin/credentials" "$CRED_BODY" "201"

CRED_ID=$(json_field "id")
if [ -n "$CRED_ID" ]; then
  check_status "DELETE credential" "DELETE" "/api/admin/credentials/${CRED_ID}" "" "200"
fi

# ── summary ────────────────────────────────────────────────

echo ""
echo "  ${BOLD}Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}"
echo ""

if [ "$FAIL" -gt 0 ]; then exit 1; fi
