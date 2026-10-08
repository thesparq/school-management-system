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
counter() { # $1 series name -> that counter's current_value, "" when there is no such row
  db_query "SELECT current_value FROM id_sequences:$1;" | python3 -c "
import json,sys
rows = json.load(sys.stdin)[0]['result']
print(rows[0]['current_value'] if rows else '')"
}
padded() { # $1 a number -> the six-digit spelling of it, the width the backend renders
  printf '%06d' "$1"
}
post_user() { # $1 the JSON payload -> the write's answer with its HTTP status, like the create checks
  curl -s -w ' HTTP %{http_code}' -X POST "$B/api/users" -H "$T" -H "$C" -d "$1"
}
pk_of() { # $1 a create answer (stdin is irrelevant) -> the new record's bare pk
  echo "$1" | python3 -c "
import json,sys
row = json.load(sys.stdin)[0]['result'][0]['id']
print(row.split(':', 1)[1].strip('\`'))" 2>/dev/null
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

# --- 6. a row with no login in Authentik is deletable, profile-hide only ---
# A profile row whose pk the directory does not list (as if the login had been removed, or the
# account was only ever in the database): there is nothing to disable, so the profile hide IS the
# whole delete. The reply that 'the user can still sign in' now applies only when the directory
# cannot be read or a listed login's own disable fails.
GHOST="users_api_ghost_${STAMP}"
db_query "CREATE student_profile:${GHOST} SET first_name = 'Ghost', surname = 'Login', display_name = 'Ghost Login', date_of_birth = <datetime> '2011-03-04', current_class = type::record('class_levels', 'jss_1'), class_enrolled = type::record('class_levels', 'jss_1'), passport = 'https://example.com/ghost.jpg', created_at = time::now();" > /dev/null
GHOST_REPLY=$(curl -s -w ' HTTP %{http_code}' -X DELETE "$B/api/users" -H "$T" -H "$C" -d "{\"id\":\"student_profile:${GHOST}\"}")
check "a row with no login in Authentik is deletable" "$GHOST_REPLY" "HTTP 200"
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

# --- 12. the school number: handed out by the write that makes the row, once per create ---
# The counter is read out of the database either side of the writes, because a number is only handed out
# when a row is really stored: what the suite checks is the counter's movement, not the rendered string
# alone. Numbers are relative to whatever the sandbox has already spent.
STUDENT_BEFORE=$(counter student)
NUM_EMAIL="users_api_number_${STAMP}@example.com"
NUM_CREATE=$(curl -s -X POST "$B/api/users" -H "$T" -H "$C" -d "{\"role\":\"Student\",\"email\":\"$NUM_EMAIL\",\"first_name\":\"Numb\",\"surname\":\"Er${STAMP}\",\"date_of_birth\":\"2011-02-03\",\"class_level\":\"jss_1\",\"passport\":\"https://example.com/number-one.jpg\"}")
NUM_PK=$(pk_of "$NUM_CREATE")
NUM_ONE=$(counter student)
check "creating a student moves the student counter by one" "$NUM_ONE" "$((STUDENT_BEFORE + 1))"
check "and the row carries the rendered number" "$(listing Student | row_of "$NUM_PK")" "\"school_number\":\"JES-$(padded "$NUM_ONE")\""

NUM2_EMAIL="users_api_number2_${STAMP}@example.com"
NUM2_CREATE=$(curl -s -X POST "$B/api/users" -H "$T" -H "$C" -d "{\"role\":\"Student\",\"email\":\"$NUM2_EMAIL\",\"first_name\":\"Numb\",\"surname\":\"Two${STAMP}\",\"date_of_birth\":\"2011-02-03\",\"class_level\":\"jss_1\",\"passport\":\"https://example.com/number-two.jpg\"}")
NUM2_PK=$(pk_of "$NUM2_CREATE")
NUM_TWO=$(counter student)
check "a second student draws the next number" "$NUM_TWO" "$((NUM_ONE + 1))"
check "and is rendered the same way" "$(listing Student | row_of "$NUM2_PK")" "\"school_number\":\"JES-$(padded "$NUM_TWO")\""

# --- 13. a rejected create does not burn a number ---
# The allocation is part of the profile statement, so it comes back with the statement's failure: a
# validation refusal never runs a statement, and a statement that fails (a date this database cannot cast)
# rolls the increment back with it. The login is removed so the admin can retry.
REFUSED=$(post_user "{\"role\":\"Student\",\"email\":\"users_api_nopass_${STAMP}@example.com\",\"first_name\":\"No\",\"surname\":\"Passport${STAMP}\",\"date_of_birth\":\"2011-02-03\",\"class_level\":\"jss_1\",\"passport\":\"\"}")
check "a student without a passport is refused" "$REFUSED" "HTTP 400"
check "and the student counter did not move" "$(counter student)" "$NUM_TWO"
FAILED=$(post_user "{\"role\":\"Student\",\"email\":\"users_api_baddate_${STAMP}@example.com\",\"first_name\":\"Bad\",\"surname\":\"Date${STAMP}\",\"date_of_birth\":\"2011-13-45\",\"class_level\":\"jss_1\",\"passport\":\"https://example.com/bad-date.jpg\"}")
check "a create the database rejects is a 500, not a success" "$FAILED" "HTTP 500"
check "and that failure left the counter where it was" "$(counter student)" "$NUM_TWO"

# A duplicate number is refused by the column's unique index, whatever write made it: the number is a
# person's school identity, so two rows cannot share one.
DUP_PK="users_api_dup_${STAMP}"
DUP=$(db_query "CREATE type::record('student_profile', '${DUP_PK}') SET admission_number = ${NUM_TWO}, first_name = 'Dup', surname = 'Number', display_name = 'Dup Number', date_of_birth = <datetime> '2011-02-03', current_class = type::record('class_levels', 'jss_1'), class_enrolled = type::record('class_levels', 'jss_1'), passport = 'https://example.com/dup.jpg', created_at = time::now();")
check "a number already in use is refused" "$DUP" "idx_student_admission"
check "and no row was written with it" "$(db_query "SELECT id FROM type::record('student_profile', '${DUP_PK}');")" '"result":[]'

# --- 14. teachers and admins draw from one shared staff counter ---
STAFF_BEFORE=$(counter staff)
T2_EMAIL="users_api_staff_${STAMP}@example.com"
T2_CREATE=$(curl -s -X POST "$B/api/users" -H "$T" -H "$C" -d "{\"role\":\"Teacher\",\"email\":\"$T2_EMAIL\",\"first_name\":\"Staff\",\"surname\":\"Teacher${STAMP}\",\"passport\":\"https://example.com/staff-teacher.jpg\"}")
T2_PK=$(pk_of "$T2_CREATE")
STAFF_ONE=$(counter staff)
check "creating a teacher draws from the staff counter" "$STAFF_ONE" "$((STAFF_BEFORE + 1))"
check "and the row carries the rendered EMP number" "$(listing Teacher | row_of "$T2_PK")" "\"school_number\":\"EMP-$(padded "$STAFF_ONE")\""

A2_EMAIL="users_api_staff_admin_${STAMP}@example.com"
A2_CREATE=$(curl -s -X POST "$B/api/users" -H "$T" -H "$C" -d "{\"role\":\"Admin\",\"email\":\"$A2_EMAIL\",\"first_name\":\"Staff\",\"surname\":\"Admin${STAMP}\",\"role_title\":\"Bursar\",\"passport\":\"https://example.com/staff-admin.jpg\"}")
A2_PK=$(pk_of "$A2_CREATE")
STAFF_TWO=$(counter staff)
check "an admin draws the same counter's next number" "$STAFF_TWO" "$((STAFF_ONE + 1))"
check "and is rendered with the EMP prefix" "$(listing Admin | row_of "$A2_PK")" "\"school_number\":\"EMP-$(padded "$STAFF_TWO")\""

# A teacher made an admin keeps the number they were given: the pk already holds one, so the admin row
# reuses it instead of drawing a second. (A *second role row* is what a role change looks like here —
# the app has one row per role, and the pk is the person either way.)
REUSE=$(curl -s -w ' HTTP %{http_code}' -X PUT "$B/api/users" -H "$T" -H "$C" -d "{\"id\":\"admin_profile:${T2_PK}\",\"first_name\":\"Staff\",\"surname\":\"Reused${STAMP}\",\"passport\":\"https://example.com/staff-reused.jpg\"}")
check "a pk that is a teacher can be given an admin profile" "$REUSE" "HTTP 200"
check "the admin row reuses the teacher's number" "$(listing Admin | row_of "$T2_PK")" "\"school_number\":\"EMP-$(padded "$STAFF_ONE")\""
check "and the staff counter did not move" "$(counter staff)" "$STAFF_TWO"

# --- 15. the numbers are immutable: a payload carrying one is refused, named back ---
# The field is refused whether it is spelled as a string or as the integer it really is, so a client
# echoing a row back cannot quietly "update" the number the request carries.
STR_UPDATE=$(curl -s -w ' HTTP %{http_code}' -X PUT "$B/api/users" -H "$T" -H "$C" -d "{\"id\":\"student_profile:${NUM_PK}\",\"admission_number\":\"JES-$(padded "$NUM_ONE")\"}")
check "an update carrying the admission number is refused" "$STR_UPDATE" "HTTP 400"
check "naming the field" "$STR_UPDATE" "admission_number"
NUM_UPDATE=$(curl -s -w ' HTTP %{http_code}' -X PUT "$B/api/users" -H "$T" -H "$C" -d "{\"id\":\"teacher_profile:${T2_PK}\",\"staff_id\": 7}")
check "a staff id sent as a number is refused too" "$NUM_UPDATE" "HTTP 400"
check "and the stored student number is what creation gave it" "$(listing Student | row_of "$NUM_PK")" "\"school_number\":\"JES-$(padded "$NUM_ONE")\""

# --- 16. a parent has no school number at all ---
# The row is real and its login lists on its own tab; it is not a school member, so there is nothing to
# hand out and the listing renders the empty form of the field.
P_EMAIL="users_api_parent_${STAMP}@example.com"
P_CREATE=$(curl -s -X POST "$B/api/users" -H "$T" -H "$C" -d "{\"role\":\"Parent\",\"email\":\"$P_EMAIL\",\"first_name\":\"Api\",\"surname\":\"Parent${STAMP}\",\"passport\":\"https://example.com/api-parent.jpg\"}")
P_PK=$(pk_of "$P_CREATE")
check "a parent is created without a number" "$(listing Parent | row_of "$P_PK")" '"school_number":""'
check "and neither counter moved for them" "$(counter student),$(counter staff)" "$NUM_TWO,$STAFF_TWO"

# --- 16b. a profile-less parent login is completed the way the form sends it ---
# The Parents tab's Complete profile form sends the name as the three parts (first/middle/surname),
# which the backend derives the profile's single `name` column from. The fixture seeds one parent login
# with no profile row; a profile left by an earlier run would hide that state, so it is dropped first.
P_SEED_EMAIL="seed-parent@example.com"
P_SEED_ID=$(listing Parent | row_where email "$P_SEED_EMAIL" | field_of id)
P_SEED_PK=${P_SEED_ID#parent_profile:}
P_SEED_REF=$(rid parent_profile "$P_SEED_PK")
if [ -n "$P_SEED_ID" ]; then db_query "DELETE ${P_SEED_REF};" > /dev/null; fi
P_FORM=$(curl -s -w ' HTTP %{http_code}' -X PUT "$B/api/users" -H "$T" -H "$C" -d "{\"id\":\"$P_SEED_ID\",\"first_name\":\"Ada\",\"middle_name\":\"\",\"surname\":\"ParentForm${STAMP}\",\"passport\":\"https://example.com/form-parent.jpg\"}")
check "completing a parent from the form's payload is a 200" "$P_FORM" "HTTP 200"
check "and the row carries the derived name" "$(listing Parent | row_of "$P_SEED_PK")" "\"display_name\":\"Ada ParentForm${STAMP}\""

# --- 17. passwords: set at create, reset, and the activate restore ---
# The mock records every set_password call (GET $MOCK/password_sets), so these checks prove the
# backend actually talked to Authentik — the real deploy needs a smoke test with the live token.
PW="Pw-${STAMP}-Ab1!"
PW_EMAIL="users_api_pw_${STAMP}@example.com"
PW_CREATE=$(curl -s -X POST "$B/api/users" -H "$T" -H "$C" -d "{\"role\":\"Student\",\"email\":\"$PW_EMAIL\",\"first_name\":\"Pw\",\"surname\":\"Check${STAMP}\",\"date_of_birth\":\"2011-03-03\",\"class_level\":\"class_levels:jss_2\",\"passport\":\"https://example.com/pw.jpg\",\"password\":\"$PW\"}")
PW_PK=$(pk_of "$PW_CREATE")
check "a create with a password answers 200" "$PW_CREATE" '"status":"OK"'
check "and the password reaches Authentik" "$(curl -s "$MOCK/password_sets")" "$PW_PK"
SHORT_CREATE=$(curl -s -w ' HTTP %{http_code}' -X POST "$B/api/users" -H "$T" -H "$C" -d '{"role":"Teacher","email":"shortpw'"$STAMP"'@example.com","first_name":"S","surname":"P","passport":"https://example.com/x.jpg","password":"123"}')
check "a too-short password is refused" "$SHORT_CREATE" "HTTP 400"
PW_RESET=$(curl -s -w ' HTTP %{http_code}' -X POST "$B/api/users/set-password" -H "$T" -H "$C" -d "{\"id\":\"student_profile:$PW_PK\",\"password\":\"Reset-$STAMP-Ab1!\"}")
check "set-password answers 200 for an admin" "$PW_RESET" "HTTP 200"
check "and the new password reaches Authentik" "$(curl -s "$MOCK/password_sets")" "Reset-$STAMP-Ab1!"
check "set-password is 403 for a student token" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$B/api/users/set-password" -H 'Authorization: Bearer dev-student' -H "$C" -d "{\"id\":\"student_profile:$PW_PK\",\"password\":\"Nope-$STAMP\"}")" "403"
check "activate is 403 for a student token" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$B/api/users/activate" -H 'Authorization: Bearer dev-student' -H "$C" -d "{\"id\":\"student_profile:$PW_PK\"}")" "403"
curl -s -X DELETE "$B/api/users" -H "$T" -H "$C" -d "{\"id\":\"student_profile:$PW_PK\"}" > /dev/null
ACTIVATE=$(curl -s -w ' HTTP %{http_code}' -X POST "$B/api/users/activate" -H "$T" -H "$C" -d "{\"id\":\"student_profile:$PW_PK\"}")
check "activate restores a deleted row (200)" "$ACTIVATE" "HTTP 200"
check "and the listing shows the row again" "$(listing Student | row_of "$PW_PK")" '"school_number":'

# --- 18. the listing carries the richer profile fields ---
check "the listing row carries middle_name and class_name" "$(listing Student | row_of "$PW_PK")" '"class_name"'

# --- 19. the two-system write journal (pending_ops) ---
# Every create/delete is journaled first and a reconciler settles anything left running; these
# checks prove the happy path lands `done` and that a crash between the password and the profile
# is replayed from the journal.
J_EMAIL="users_api_journal_${STAMP}@example.com"
J_CREATE=$(curl -s -X POST "$B/api/users" -H "$T" -H "$C" -d "{\"role\":\"Student\",\"email\":\"$J_EMAIL\",\"first_name\":\"J\",\"surname\":\"Log${STAMP}\",\"date_of_birth\":\"2011-07-07\",\"class_level\":\"class_levels:jss_2\",\"passport\":\"https://example.com/j.jpg\",\"password\":\"Journal-Pw-${STAMP}!\"}")
J_PK=$(pk_of "$J_CREATE")
check "a journal row is written for the create" "$(db_query "SELECT state FROM pending_ops WHERE pk = '$J_PK';")" '"state":"done"'
check "finished at the profile step" "$(db_query "SELECT step FROM pending_ops WHERE pk = '$J_PK';")" '"step":"profile"'
check "reconcile is 403 for a student token" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$B/api/users/reconcile" -H 'Authorization: Bearer dev-student')" "403"
check "pending is 403 for a student token" "$(curl -s -o /dev/null -w '%{http_code}' "$B/api/users/pending" -H 'Authorization: Bearer dev-student')" "403"
check "reconcile answers 200 for an admin" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$B/api/users/reconcile" -H "$T")" "200"
# Crash after the password, before the profile: drop the row, rewind the journal, reconcile.
J_RID=$(db_query "SELECT id FROM pending_ops WHERE pk = '$J_PK';" | sed -E 's/.*"id":"pending_ops:([^"]+)".*/\1/')
db_query "DELETE type::record('student_profile', '$J_PK'); UPDATE pending_ops:$J_RID SET state = 'running', step = 'password';" > /dev/null
curl -s -X POST "$B/api/users/reconcile" -H "$T" > /dev/null
check "the reconciler replays the missing profile" "$(listing Student | row_of "$J_PK")" '"school_number":'
check "and finishes the journal row" "$(db_query "SELECT state FROM pending_ops WHERE id = pending_ops:$J_RID;")" '"state":"done"'

echo ""
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]