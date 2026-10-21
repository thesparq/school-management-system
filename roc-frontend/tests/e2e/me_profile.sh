#!/bin/sh
# The Settings page's own details (`GET /api/me/profile`): the school's record of the caller, keyed by the
# caller and never by a payload id, with the role's own rows — a teacher's qualifications and class-subject
# pairs, a student's class and number, an administrator's type and ticks. Read-only by construction: the route
# answers GET and nothing else.
#
#   APP_URL=http://127.0.0.1:8000 sh tests/e2e/me_profile.sh
#
# Sandbox backend with the mock Authentik (see README.md). Each created login is driven by a JWT whose `sub`
# names it, which is how the mock's userinfo answers for a login it has.

B=${APP_URL:-http://127.0.0.1:8000}
C="Content-Type: application/json"
T="Authorization: Bearer ${AUTH_TOKEN:-dev-skip}"
STAMP=$(date +%s)
pass=0; fail=0
has() { # $1 label, $2 haystack, $3 needle -> PASS when the needle is there
  case "$2" in *"$3"*) echo "PASS  $1"; pass=$((pass+1));; *) echo "FAIL  $1 — got: $(echo "$2" | head -c 220)"; fail=$((fail+1));; esac
}
hasnt() { # $1 label, $2 haystack, $3 needle -> PASS when the needle is absent
  case "$2" in *"$3"*) echo "FAIL  $1 — found: $3"; fail=$((fail+1));; *) echo "PASS  $1"; pass=$((pass+1));; esac
}
call() { # $1 token, $2 method, $3 path, $4 body (optional)
  if [ -n "$4" ]; then
    curl -s -X "$2" "$B$3" -H "Authorization: Bearer $1" -H "$C" -d "$4"
  else
    curl -s -X "$2" "$B$3" -H "Authorization: Bearer $1"
  fi
}
jwt() { # $1 sub, $2 group
  python3 - "$1" "$2" <<'PY'
import base64, json, sys, time
sub, group = sys.argv[1], sys.argv[2]
def b64u(o):
    return base64.urlsafe_b64encode(json.dumps(o).encode()).decode().rstrip('=')
claims = {'iss': 'https://auth.johnethel.school/application/o/school-management-system/',
          'sub': sub, 'exp': int(time.time()) + 3600, 'email': f'{sub}@example.com',
          'name': 'Profile Check', 'groups': [group]}
print(b64u({'alg': 'RS256', 'typ': 'JWT'}) + '.' + b64u(claims) + '.sig')
PY
}
pk_of() { # stdin: a create's answer -> the bare pk
  python3 -c "import json,sys; print(str(json.load(sys.stdin)[0]['result'][0]['id']).split(':')[1].strip(chr(96)))"
}
field() { # $1 json, $2 python expression on `rows` -> a printed value
  python3 -c "
import json,sys
rows = json.loads(sys.argv[1])
print($2)
" "$1"
}
value_of() { # $1 rows json, $2 key -> the value of that row, "" when there is none
  field "$1" "next((r['value'] for r in rows if r['key'] == '$2'), '')"
}

# --- 1. A student's own rows -----------------------------------------------------------
S_CREATE=$(curl -s -X POST "$B/api/users" -H "$T" -H "$C" \
  -d "{\"role\":\"Student\",\"email\":\"me_student_${STAMP}@example.com\",\"first_name\":\"Me\",\"surname\":\"Student${STAMP}\",\"date_of_birth\":\"2011-02-03\",\"class_level\":\"class_levels:jss_1\",\"passport\":\"https://example.com/me-student.jpg\"}")
S_PK=$(echo "$S_CREATE" | pk_of)
S_TOK=$(jwt "$S_PK" "Students")
S_ROWS=$(call "$S_TOK" GET /api/me/profile)
has "a student's own details answer" "$S_ROWS" '"key":"name"'
has "with the name the school has" "$(value_of "$S_ROWS" name)" "Me Student${STAMP}"
has "their own address" "$(value_of "$S_ROWS" email)" "me_student_${STAMP}@example.com"
has "the role, in the API's own word" "$(value_of "$S_ROWS" role)" "student"
has "their class, by name" "$(value_of "$S_ROWS" class)" "JSS 1"
has "their date of birth, as a day" "$(value_of "$S_ROWS" date_of_birth)" "2011-02-03"
has "their admission number, as the school writes it" "$(value_of "$S_ROWS" student_number)" "JES-"
has "and their passport" "$(value_of "$S_ROWS" passport)" "me-student.jpg"
hasnt "and none of a teacher's rows" "$S_ROWS" '"key":"qualifications"'
hasnt "nor an administrator's" "$S_ROWS" '"key":"permissions"'

# --- 2. A teacher's own rows: qualifications and pairs, by name -----------------------
CRED=$(curl -s -X POST "$B/api/credentials" -H "$T" -H "$C" -d "{\"name\":\"Profile Check ${STAMP}\"}")
CRED_ID=$(echo "$CRED" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['result'][0]['id'])" 2>/dev/null)
# The *seeded* teacher: a login created through the API carries no group in the mock, so its token would
# resolve to the fallback role (student) — which is why the student case below can use a created login and this
# one cannot. The seeded login's pk belongs to the mock's process, so it is read out of the listing, the same
# way `authz.sh` reads the seeded administrator's.
T_PK=$(curl -s "$B/api/users?role=Teacher" -H "$T" | python3 -c "
import json,sys
rows = json.load(sys.stdin)[0]['result']
hit = [r for r in rows if r.get('display_name') == 'Seed Teacher' and (r.get('email') or '')]
print(str(hit[0]['id']).split(':')[1].strip(chr(96)) if hit else '')
")
# Its profile, with a qualification and a date employed, through the same routes the admin screens use.
curl -s -o /dev/null -X PUT "$B/api/users" -H "$T" -H "$C" \
  -d "{\"id\":\"teacher_profile:${T_PK}\",\"first_name\":\"Seed\",\"surname\":\"Teacher\",\"passport\":\"https://example.com/me-teacher.jpg\",\"date_employed\":\"2024-09-02\",\"qualifications\":[\"${CRED_ID}\"]}"
EDGE=$(curl -s "$B/api/class-subjects" -H "$T" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['result'][0]['edge_id'])" 2>/dev/null)
curl -s -o /dev/null -X POST "$B/api/teacher-assignments" -H "$T" -H "$C" \
  -d "{\"teacher_id\":\"teacher_profile:${T_PK}\",\"pairs\":[{\"edge_id\":\"${EDGE}\"}]}"
T_TOK=$(jwt "$T_PK" "Teachers")
T_ROWS=$(call "$T_TOK" GET /api/me/profile)
has "a teacher's own details answer" "$T_ROWS" '"key":"qualifications"'
has "their role" "$(value_of "$T_ROWS" role)" "teacher"
has "their qualification, by name" "$(value_of "$T_ROWS" qualifications)" "Profile Check ${STAMP}"
hasnt "and never as a raw record id" "$(value_of "$T_ROWS" qualifications)" "credentials:"
has "their date employed, as a day" "$(value_of "$T_ROWS" date_employed)" "2024-09-02"
# The row names the class and the subject that were assigned, in the school's words — read back from the same
# catalog the Assign dialog uses, so the check is about the pair rather than about the fixture's order.
EDGE_NAMES=$(curl -s "$B/api/class-subjects" -H "$T" | python3 -c "
import json,sys
rows = json.load(sys.stdin)[0]['result']
edge = next((r for r in rows if r['edge_id'] == '$EDGE'), None)
print(f\"{edge['class_level_name']} · {edge['subject_name']}\" if edge else '')
")
has "their class-subject pair names the class and subject that were assigned" "$(value_of "$T_ROWS" pairs)" "$EDGE_NAMES"
hasnt "and none of a student's rows" "$T_ROWS" '"key":"class"'
hasnt "nor a number" "$T_ROWS" '"key":"student_number"'

# --- 3. An administrator's own rows: the type and the ticks ---------------------------
# The mock's administrator login is seated first: a fresh sandbox has no row for it, and the rows under test
# are the ones its seat carries.
curl -s -o /dev/null -X PUT "$B/api/users" -H "$T" -H "$C" \
  -d '{"id":"admin_profile:mock_uuid_admin","first_name":"Sandbox","surname":"Supervisor","passport":"https://example.com/supervisor.jpg","admin_type":"supervisor","permissions":["lessons.manage","assessments.manage"]}'
A_ROWS=$(call mock-admin-token GET /api/me/profile)
has "an administrator's own details answer" "$A_ROWS" '"key":"admin_type"'
has "with the type the school gave them" "$(value_of "$A_ROWS" admin_type)" "supervisor"
has "and the permissions their row carries" "$(value_of "$A_ROWS" permissions)" "lessons.manage"
hasnt "and none of a student's rows" "$A_ROWS" '"key":"student_number"'

# --- 4. Read-only by construction: only GET is a route --------------------------------
has "a POST to it is not a route" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$B/api/me/profile" -H "Authorization: Bearer $S_TOK" -H "$C" -d '{}')" "404"
has "and a PUT is not either" "$(curl -s -o /dev/null -w '%{http_code}' -X PUT "$B/api/me/profile" -H "Authorization: Bearer $S_TOK" -H "$C" -d '{}')" "404"

# --- 5. Cleanup ----------------------------------------------------------------------
has "cleaning up the student answers the hidden row" "$(call dev-skip DELETE /api/users "{\"id\":\"student_profile:${S_PK}\"}")" "\"result\":[{\""
# The seeded teacher's profile is *restored* rather than deleted: the delete would also switch the login off in
# Authentik (that is what the delete does), and the next run needs that login. Activate brings both back, and
# leaves the row the run made — which the next run then patches.
has "and the seeded teacher is restored" "$(call dev-skip POST /api/users/activate "{\"id\":\"teacher_profile:${T_PK}\"}")" "restored"
# The catalog row stays (qualifications are deactivate-only), so it is switched off rather than deleted.
has "and the catalog row is switched off" "$(call dev-skip POST /api/credentials/toggle-active "{\"id\":\"${CRED_ID}\"}")" "OK"

echo ""
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
