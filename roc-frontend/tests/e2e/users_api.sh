#!/bin/sh
# User management over the API: the profile row is the app's own data, the login (its email and
# whether it is enabled) belongs to Authentik, and a delete has to take the login away with the row.
#
# Writes student_profile/teacher_profile rows and calls the mock Authentik, so point it at a sandbox
# backend (see README.md) — never at prod. It also reads the sandbox database directly, because
# "soft-deleted" can only be seen there (the listings filter the row out).
#
#   APP_URL=http://127.0.0.1:8000 MOCK_AUTHENTIK_URL=http://127.0.0.1:9000 \
#   SURREAL_URL=http://127.0.0.1:8002/sql sh tests/e2e/users_api.sh

B=${APP_URL:-http://127.0.0.1:8000}
MOCK=${MOCK_AUTHENTIK_URL:-http://127.0.0.1:9000}
DB=${SURREAL_URL:-http://127.0.0.1:8002/sql}
NS=${SURREAL_NS:-main}
DB_NAME=${SURREAL_DB:-lessons}
DB_USER=${SURREAL_USER:-root}
DB_PASS=${SURREAL_PASS:-root}
T="Authorization: Bearer ${AUTH_TOKEN:-dev-skip}"
C="Content-Type: application/json"
STAMP=$(date +%s)
pass=0; fail=0
check() { # $1 label, $2 actual, $3 expected substring
  case "$2" in *"$3"*) echo "PASS  $1"; pass=$((pass+1));; *) echo "FAIL  $1 — got: $(echo "$2" | head -c 160)"; fail=$((fail+1));; esac
}
status() { # the HTTP status of a request, without its body
  curl -s -o /dev/null -w '%{http_code}' "$@"
}
db_query() { # $1 SurrealQL
  curl -s -u "$DB_USER:$DB_PASS" -X POST "$DB" -H "surreal-ns: $NS" -H "surreal-db: $DB_NAME" -H 'Accept: application/json' --data-binary "$1"
}
mock_user() { # $1 pk -> that login as one line of JSON, "" when Authentik does not have it
  curl -s "$MOCK/api/v3/core/users/?page_size=200" | MOCK_PK="$1" python3 -c "
import json,os,sys
users = json.load(sys.stdin)['results']
user = next((u for u in users if str(u.get('pk')) == os.environ['MOCK_PK']), None)
print(json.dumps(user, separators=(',', ':')) if user else '')"
}
listing() { # $1 role -> the listing's rows as one JSON array
  curl -s "$B/api/users?role=$1" -H "$T" | python3 -c "
import json,sys
print(json.dumps(json.load(sys.stdin)[0]['result'], separators=(',', ':')))"
}
row_of() { # $1 bare pk (stdin: rows) -> that row as one line, "" when the listing does not have it
  ROW_PK="$1" python3 -c "
import json,os,sys
pk = os.environ['ROW_PK']
row = next((r for r in json.load(sys.stdin) if str(r.get('id', '')).endswith(':' + pk)), None)
print(json.dumps(row, separators=(',', ':')) if row else '')"
}
present() { # $1 bare pk (stdin: rows) -> 1 when the listing has that row, 0 when it does not
  ROW_PK="$1" python3 -c "
import json,os,sys
pk = os.environ['ROW_PK']
print(1 if any(str(r.get('id', '')).endswith(':' + pk) for r in json.load(sys.stdin)) else 0)"
}

# --- 1. a new student: the listing reads the login's address and its enabled state from Authentik ---
EMAIL="users_api_${STAMP}@example.com"
CREATE=$(curl -s -X POST "$B/api/users" -H "$T" -H "$C" -d "{\"role\":\"Student\",\"email\":\"$EMAIL\",\"first_name\":\"Api\",\"surname\":\"Check${STAMP}\",\"date_of_birth\":\"2011-02-03\",\"class_level\":\"jss_1\",\"passport\":\"https://example.com/api-check.jpg\"}")
ID=$(echo "$CREATE" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['result'][0]['id'])" 2>/dev/null)
PK=${ID#student_profile:}
check "the student is created" "$ID" "student_profile:"
check "Authentik holds the login with that address" "$(mock_user "$PK")" "\"email\":\"$EMAIL\""
ROW=$(listing Student | row_of "$PK")
check "the listing has the new row" "$ROW" "\"id\":\"$ID\""
check "the listing carries the login's email" "$ROW" "\"email\":\"$EMAIL\""
check "the listing reports the login as active" "$ROW" "\"is_active\":true"

# --- 2. a new email goes to Authentik first, and the listing follows it ---
NEW_EMAIL="users_api_${STAMP}.new@example.com"
check "the email update is accepted" "$(curl -s -X PUT "$B/api/users" -H "$T" -H "$C" -d "{\"id\":\"$ID\",\"email\":\"$NEW_EMAIL\"}")" "\"id\":\"$ID\""
check "Authentik now holds the new address" "$(mock_user "$PK")" "\"email\":\"$NEW_EMAIL\""
check "the listing shows the new address" "$(listing Student | row_of "$PK")" "\"email\":\"$NEW_EMAIL\""

# --- 3. unknown ids and a malformed address are still refused, before Authentik is called ---
check "an unknown id is a 400" "$(status -X PUT "$B/api/users" -H "$T" -H "$C" -d '{"id":"nonsense","email":"a@b.co"}')" "400"
check "and the message names a profile row" "$(curl -s -X PUT "$B/api/users" -H "$T" -H "$C" -d '{"id":"nonsense","email":"a@b.co"}')" "id must name a profile row"
check "a malformed email is a 400" "$(status -X PUT "$B/api/users" -H "$T" -H "$C" -d "{\"id\":\"$ID\",\"email\":\"not-an-address\"}")" "400"
check "and it never reaches Authentik" "$(mock_user "$PK")" "\"email\":\"$NEW_EMAIL\""
check "an unknown id is a 400 for DELETE too" "$(status -X DELETE "$B/api/users" -H "$T" -H "$C" -d '{"id":"nonsense"}')" "400"

# --- 4. deleting hides the profile row and disables the login ---
check "delete answers the soft-deleted row" "$(curl -s -X DELETE "$B/api/users" -H "$T" -H "$C" -d "{\"id\":\"$ID\"}")" '"deleted_at":"'
check "the login is disabled in Authentik" "$(mock_user "$PK")" '"is_active":false'
check "the listing drops the row" "$(listing Student | present "$PK")" "0"
SOFT=$(db_query "SELECT id, deleted_at FROM student_profile:${PK};")
check "the profile row is still stored" "$SOFT" "\"id\":\"student_profile:${PK}\""
check "with deleted_at set (soft delete)" "$SOFT" '"deleted_at":"'

# --- 5. the merge is not student-specific: a teacher's row reads its login too ---
T_EMAIL="users_api_teacher_${STAMP}@example.com"
T_CREATE=$(curl -s -X POST "$B/api/users" -H "$T" -H "$C" -d "{\"role\":\"Teacher\",\"email\":\"$T_EMAIL\",\"first_name\":\"Api\",\"surname\":\"Teacher${STAMP}\",\"passport\":\"https://example.com/api-teacher.jpg\"}")
T_ID=$(echo "$T_CREATE" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['result'][0]['id'])" 2>/dev/null)
T_PK=${T_ID#teacher_profile:}
check "the teacher is listed on its own tab" "$(listing Teacher | row_of "$T_PK")" "\"email\":\"$T_EMAIL\""
check "and reads as active there too" "$(listing Teacher | row_of "$T_PK")" '"is_active":true'
check "a teacher listing is not shown under students" "$(listing Student | present "$T_PK")" "0"
curl -s -X DELETE "$B/api/users" -H "$T" -H "$C" -d "{\"id\":\"$T_ID\"}" > /dev/null
check "deleting the teacher disables that login" "$(mock_user "$T_PK")" '"is_active":false'

# --- 6. a login Authentik cannot disable is reported, not answered as success ---
# A profile row whose pk has no login (as if the login had been removed by hand): the row is hidden,
# but the reply says the login could not be disabled, because a live login is what still lets the
# user in.
GHOST="users_api_ghost_${STAMP}"
db_query "CREATE student_profile:${GHOST} SET first_name = 'Ghost', surname = 'Login', display_name = 'Ghost Login', date_of_birth = <datetime> '2011-03-04', current_class = type::record('class_levels', 'jss_1'), class_enrolled = type::record('class_levels', 'jss_1'), passport = 'https://example.com/ghost.jpg', created_at = time::now();" > /dev/null
GHOST_REPLY=$(curl -s -w ' HTTP %{http_code}' -X DELETE "$B/api/users" -H "$T" -H "$C" -d "{\"id\":\"student_profile:${GHOST}\"}")
check "an undisableable login answers 502" "$GHOST_REPLY" "HTTP 502"
check "and the message says the login is still live" "$GHOST_REPLY" "the user can still sign in"
check "the ghost's profile is hidden all the same" "$(db_query "SELECT id, deleted_at FROM student_profile:${GHOST};")" '"deleted_at":"'

# --- 7. a row whose login is not in Authentik gets no invented identity columns ---
# The fixture's student_profile:dev_user has no login in Authentik (it is the dev-skip caller, not
# a created account), which is also what every row looks like when Authentik is unreachable. The
# row still lists; in particular it must not carry is_active:false, which would report a disabled
# login nobody observed.
UNMATCHED=$(listing Student | row_of dev_user)
check "a row without a login is still listed" "$UNMATCHED" '"id":"student_profile:dev_user"'
check "and carries no invented is_active" "$(echo "$UNMATCHED" | grep -c is_active)" "0"
check "and no invented email" "$(echo "$UNMATCHED" | grep -c email)" "0"

echo ""
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]