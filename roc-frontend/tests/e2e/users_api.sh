#!/bin/sh
# User management over the API: the profile row is the app's own data, the login (its email and
# whether it is enabled) belongs to Authentik, and a delete has to take the login away with the row.
#
# The listing is the directory as well as the tables: a login Authentik lists for a role with no
# profile row behind it is listed too (`has_profile:false`), and PUT attaches a profile to it — the
# state an admin is in after creating users in Authentik itself. The fixture seeds one such login per
# role (plus two in no role group, which belong to no tab), so this suite drives that login as well.
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
row_where() { # $1 field name, $2 value (stdin: rows) -> that row as one line, "" when the listing has none
  ROW_FIELD="$1" ROW_VALUE="$2" python3 -c "
import json,os,sys
rows = json.load(sys.stdin)
row = next((r for r in rows if str(r.get(os.environ['ROW_FIELD'], '')) == os.environ['ROW_VALUE']), None)
print(json.dumps(row, separators=(',', ':')) if row else '')"
}
field_of() { # $1 field name (stdin: one row of JSON) -> that field's value, "" when the row or field is missing
  ROW_FIELD="$1" python3 -c "
import json,os,sys
raw = sys.stdin.read().strip()
print(json.loads(raw).get(os.environ['ROW_FIELD'], '') if raw else '')"
}
rid() { # $1 table, $2 bare pk -> that record as a SurrealQL reference, the way the backend writes one
  # A pk that looks like a number is still a *string* id part: `student_profile:14` in a raw statement
  # is a number part, a different record from the one the app writes and reads through
  # type::record('student_profile','14'). The app never spells an id by hand; this suite does, so it
  # spells it the same way record_ref! does.
  echo "type::record('$1', '$2')"
}
tabs_with() { # $1 display name -> the tabs whose listing carries a row with that name, comma separated
  found=""
  for role in Student Teacher Parent Admin; do
    if [ -n "$(listing "$role" | row_where display_name "$1")" ]; then found="${found:+$found,}$role"; fi
  done
  echo "$found"
}
check_no_tab() { # $1 label, $2 the tabs a row was found in ("" is the pass)
  if [ -z "$2" ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1 — found in: $2"; fail=$((fail+1)); fi
}

# --- 1. a new student: the listing reads the login's address and its enabled state from Authentik ---
EMAIL="users_api_${STAMP}@example.com"
CREATE=$(curl -s -X POST "$B/api/users" -H "$T" -H "$C" -d "{\"role\":\"Student\",\"email\":\"$EMAIL\",\"first_name\":\"Api\",\"surname\":\"Check${STAMP}\",\"date_of_birth\":\"2011-02-03\",\"class_level\":\"jss_1\",\"passport\":\"https://example.com/api-check.jpg\"}")
ID=$(echo "$CREATE" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['result'][0]['id'])" 2>/dev/null)
# The write's own answer carries SurrealDB's rendering of the id, and a part that looks like a number
# comes back quoted (`student_profile:`14``) — the listings spell ids `student_profile:14` and PUT and
# DELETE accept either. A numeric pk is what the real directory hands out, so the quotes come off here.
PK=$(echo "${ID#*:}" | tr -d '`')
ID="student_profile:${PK}"
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
PK_REF=$(rid student_profile "$PK")
SOFT=$(db_query "SELECT id, deleted_at FROM ${PK_REF};")
# The answer renders an id part that looks like a number quoted; the row and its soft delete are what
# this is about, so that rendering is normalized away before the id is compared.
SOFT_NORM=$(echo "$SOFT" | tr -d '`')
check "the profile row is still stored" "$SOFT_NORM" "\"id\":\"student_profile:${PK}\""
check "with deleted_at set (soft delete)" "$SOFT" '"deleted_at":"'

# --- 5. the merge is not student-specific: a teacher's row reads its login too ---
T_EMAIL="users_api_teacher_${STAMP}@example.com"
T_CREATE=$(curl -s -X POST "$B/api/users" -H "$T" -H "$C" -d "{\"role\":\"Teacher\",\"email\":\"$T_EMAIL\",\"first_name\":\"Api\",\"surname\":\"Teacher${STAMP}\",\"passport\":\"https://example.com/api-teacher.jpg\"}")
T_ID=$(echo "$T_CREATE" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['result'][0]['id'])" 2>/dev/null)
# As above: the write's answer quotes an id part that looks like a number.
T_PK=$(echo "${T_ID#*:}" | tr -d '`')
T_ID="teacher_profile:${T_PK}"
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

# --- 8. the login the directory lists and the profile tables do not ---
# The fixture's Authentik starts with an admin-made login per role and the sandbox database seeds no
# profile row for them, so the tab lists the login alone. Its pk carries the mock's pid, so the id is
# read out of the listing instead of being hard-coded.
SEED_EMAIL="seed-student@example.com"
SEED_ID=$(listing Student | row_where email "$SEED_EMAIL" | field_of id)
SEED_PK=${SEED_ID#student_profile:}
SEED_REF=$(rid student_profile "$SEED_PK")

# A profile attached by an earlier run of this suite (or of e2e_users_directory.cjs) would hide the
# state these checks need — a login, and no row — so any row left behind is dropped first. A hard
# delete, so nothing stays hidden behind `deleted_at`; the login is Authentik's and is left alone.
# (Guarded: an empty id would be a statement with nothing in its place, and the checks below are the
# ones that should report a sandbox without the fixture's logins.)
if [ -n "$SEED_ID" ]; then db_query "DELETE ${SEED_REF};" > /dev/null; fi

SEEDLESS=$(listing Student | row_where email "$SEED_EMAIL")
check "a login only the directory lists is listed" "$SEEDLESS" "\"id\":\"$SEED_ID\""
check "as a login with no profile" "$SEEDLESS" '"has_profile":false'
check "carrying the login's own address" "$SEEDLESS" "\"email\":\"$SEED_EMAIL\""
check "and no school data invented for it" "$(echo "$SEEDLESS" | python3 -c "
import json,sys
row = json.load(sys.stdin)
print(sum(1 for field in ['first_name', 'surname', 'passport', 'created_at', 'current_class'] if row.get(field)))")" "0"

# A login in no role group belongs to no tab: neither the fixture's groupless login nor the one in an
# unrelated group is listed anywhere. (The control: the seeded student is on its own tab and no other.)
check "the seeded login is on its own tab only" "$(tabs_with 'Seed Student')" "Student"
check_no_tab "a login in no group is on no tab" "$(tabs_with 'Seed Service Account')"
check_no_tab "a login in an unrelated group is on no tab" "$(tabs_with 'Seed Outpost')"

# --- 9. PUT attaches a profile to a login that has none ---
# The row has to be made from this payload alone (the tables are SCHEMAFULL), so the create path's
# required fields are checked first and the 400 names the one that is missing.
INCOMPLETE="{\"id\":\"$SEED_ID\",\"first_name\":\"Seed\"}"
check "completing without the required fields is a 400" "$(status -X PUT "$B/api/users" -H "$T" -H "$C" -d "$INCOMPLETE")" "400"
check "and names the field that is missing" "$(curl -s -X PUT "$B/api/users" -H "$T" -H "$C" -d "$INCOMPLETE")" "surname is required"
check "and wrote no row" "$(db_query "SELECT id FROM ${SEED_REF};")" '"result":[]'

# No email (the login's address is Authentik's and is not patched) and no role (the table comes from
# the id's prefix, `student_profile:<pk>`). The reply is the row the statement made.
ATTACH="{\"id\":\"$SEED_ID\",\"first_name\":\"Seeded\",\"surname\":\"Profile\",\"date_of_birth\":\"2011-02-03\",\"class_level\":\"jss_1\",\"passport\":\"https://example.com/seeded.jpg\"}"
ATTACHED=$(curl -s -w ' HTTP %{http_code}' -X PUT "$B/api/users" -H "$T" -H "$C" -d "$ATTACH")
check "the full student set attaches a profile" "$ATTACHED" "HTTP 200"
check "answering the row it made" "$ATTACHED" "\"id\":\"student_profile:${SEED_PK}\""
PROFILED=$(listing Student | row_of "$SEED_PK")
check "the row now reports a profile" "$PROFILED" '"has_profile":true'
check "rendered from the profile, not the directory" "$PROFILED" '"display_name":"Seeded Profile"'
check "with the student's own class link" "$PROFILED" '"current_class":"class_levels:jss_1"'
check "and the login's address still attached to it" "$PROFILED" "\"email\":\"$SEED_EMAIL\""

# --- 10. a second PUT is a patch: what its payload leaves out keeps its stored value ---
CREATED_AT=$(listing Student | row_of "$SEED_PK" | field_of created_at)
curl -s -X PUT "$B/api/users" -H "$T" -H "$C" -d "{\"id\":\"$SEED_ID\",\"surname\":\"Patched\",\"passport\":\"https://example.com/patched.jpg\"}" > /dev/null
PATCHED=$(listing Student | row_of "$SEED_PK")
check "a second PUT writes what it carries" "$PATCHED" '"surname":"Patched"'
check "and leaves a field it does not carry alone" "$PATCHED" '"first_name":"Seeded"'
check "as well as a display name it does not carry" "$PATCHED" '"display_name":"Seeded Profile"'
check "without rewriting created_at" "$(echo "$PATCHED" | field_of created_at)" "$CREATED_AT"

# --- 11. a delete hides the profile, and a PUT brings it back ---
check "deleting the completed profile answers the soft-deleted row" "$(curl -s -X DELETE "$B/api/users" -H "$T" -H "$C" -d "{\"id\":\"$SEED_ID\"}")" '"deleted_at":"'
check "so the tab lists the bare login again" "$(listing Student | row_of "$SEED_PK")" '"has_profile":false'
check "and it is the same login, with its address" "$(listing Student | row_of "$SEED_PK")" "\"email\":\"$SEED_EMAIL\""
check "a PUT brings the profile back" "$(curl -s -X PUT "$B/api/users" -H "$T" -H "$C" -d "$ATTACH")" "\"id\":\"student_profile:${SEED_PK}\""
check "so the row lists with a profile again" "$(listing Student | row_of "$SEED_PK")" '"has_profile":true'
check "with deleted_at cleared" "$(db_query "SELECT id, deleted_at FROM ${SEED_REF};")" '"deleted_at":null'

echo ""
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]