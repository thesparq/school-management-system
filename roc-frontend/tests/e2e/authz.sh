#!/bin/sh
# Role-based authorization over the API: the caller's role comes from the userinfo `groups` claim
# (or from a DEV_MODE token's own name), and each route family answers only the roles allowed to
# use it.
#
# Writes a user row through the mock Authentik, so point it at a sandbox backend (see README.md),
# never at prod. The `mock-*-token` cases need the backend started with AUTHENTIK_ISSUER_URL
# pointing at the mock, or every one of them is a 401.
#
#   APP_URL=http://127.0.0.1:8000 sh tests/e2e/authz.sh

B=${APP_URL:-http://127.0.0.1:8000}
C="Content-Type: application/json"
STAMP=$(date +%s)
pass=0; fail=0
check() { # $1 label, $2 actual, $3 expected substring
  case "$2" in *"$3"*) echo "PASS  $1"; pass=$((pass+1));; *) echo "FAIL  $1 — got: $(echo "$2" | head -c 160)"; fail=$((fail+1));; esac
}
call() { # $1 token, $2 method, $3 path, $4 body (optional) -> "<body> HTTP <status>"
  if [ -n "$4" ]; then
    curl -s -w ' HTTP %{http_code}' -X "$2" "$B$3" -H "Authorization: Bearer $1" -H "$C" -d "$4"
  else
    curl -s -w ' HTTP %{http_code}' -X "$2" "$B$3" -H "Authorization: Bearer $1"
  fi
}

# --- 1. dev-skip is the admin: every route the suites drive still answers ---
check "dev-skip reaches a student route" "$(call dev-skip GET /api/student/subjects)" " HTTP 200"
check "dev-skip reaches a teacher route" "$(call dev-skip GET '/api/teacher/lesson-assessments?lesson_id=lessons:test_lesson')" " HTTP 200"
CREATE=$(curl -s -X POST "$B/api/users" -H 'Authorization: Bearer dev-skip' -H "$C" \
  -d "{\"role\":\"Parent\",\"email\":\"authz_${STAMP}@example.com\",\"first_name\":\"Role\",\"surname\":\"Check\",\"passport\":\"https://example.com/authz.jpg\"}")
CREATED_ID=$(echo "$CREATE" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['result'][0]['id'])" 2>/dev/null)
check "dev-skip can create a user" "$CREATED_ID" "parent_profile:"
check "dev-skip can delete one" "$(call dev-skip DELETE /api/users "{\"id\":\"$CREATED_ID\"}")" " HTTP 200"
check "dev-skip reaches an admin config write" "$(call dev-skip POST /api/terms "{\"name\":\"Authz term ${STAMP}\",\"sort_order\":99}")" " HTTP 200"

# --- 2. dev-student: the student API, nothing else ---
check "dev-student is allowed a student route" "$(call dev-student GET /api/student/subjects)" " HTTP 200"
check "dev-student is refused a teacher route (403)" "$(call dev-student GET /api/teacher/lessons)" " HTTP 403"
check "and the refusal names the teacher role" "$(call dev-student GET /api/teacher/lessons)" "requires the teacher role"
check "dev-student is refused an admin write (403)" "$(call dev-student POST /api/terms "{\"name\":\"Authz denied ${STAMP}\",\"sort_order\":98}")" " HTTP 403"
check "dev-student is refused a user write (403)" "$(call dev-student DELETE /api/users '{"id":"parent_profile:nobody"}')" " HTTP 403"

# --- 3. dev-teacher: the teacher API, not the admin's ---
check "dev-teacher is allowed a teacher route" "$(call dev-teacher GET /api/teacher/lessons)" " HTTP 200"
check "dev-teacher is refused an admin write (403)" "$(call dev-teacher POST /api/terms "{\"name\":\"Authz denied2 ${STAMP}\",\"sort_order\":97}")" " HTTP 403"
check "and the refusal names the admin role" "$(call dev-teacher POST /api/terms '{"name":"x","sort_order":1}')" "requires the admin role"
check "dev-teacher is refused a student route (403)" "$(call dev-teacher GET /api/student/subjects)" " HTTP 403"
check "a teacher may still read the configuration" "$(call dev-teacher GET /api/terms)" " HTTP 200"

# --- 4. no token at all is an authentication failure, not an authorization one ---
check "no token is a 401" "$(curl -s -o /dev/null -w ' HTTP %{http_code}' "$B/api/student/subjects")" " HTTP 401"
check "a bogus token is a 401" "$(curl -s -o /dev/null -w ' HTTP %{http_code}' "$B/api/student/subjects" -H 'Authorization: Bearer not-a-real-token')" " HTTP 401"
check "and an admin route without a token is a 401 too" "$(curl -s -o /dev/null -w ' HTTP %{http_code}' -X POST "$B/api/terms" -H "$C" -d '{"name":"x","sort_order":1}')" " HTTP 401"

# --- 5. a real-looking token: the role comes from the userinfo `groups` claim ---
check "a student's token is allowed a student route" "$(call mock-student-token GET /api/student/subjects)" " HTTP 200"
check "a student's token is refused a teacher route (403)" "$(call mock-student-token GET /api/teacher/lessons)" " HTTP 403"
check "a student's token may read the directory listing" "$(call mock-student-token GET '/api/users?role=Student')" " HTTP 200"
check "a teacher's token is allowed a teacher route" "$(call mock-teacher-token GET /api/teacher/lessons)" " HTTP 200"
check "a teacher's token is refused an admin write (403)" "$(call mock-teacher-token POST /api/terms "{\"name\":\"Authz denied3 ${STAMP}\",\"sort_order\":96}")" " HTTP 403"
# The cases below demote and promote this login's row, and the school keeps one super admin: a spare is
# kept in the sandbox (created once, never deleted) so the file can run again against the same sandbox.
# Without one, a second run's first demotion is refused by the lockout guard — the guard working, not a
# failed check — and every later case would then be read against the wrong seat.
SPARES=$(curl -s "$B/api/users?role=Admin" -H 'Authorization: Bearer dev-skip')
case "$SPARES" in
  *"Authz Spare"*) ;;
  *)
    curl -s -o /dev/null -X POST "$B/api/users" -H 'Authorization: Bearer dev-skip' -H "$C" \
      -d "{\"role\":\"Admin\",\"email\":\"authz_spare_${STAMP}@example.com\",\"first_name\":\"Authz\",\"surname\":\"Spare\",\"passport\":\"https://example.com/spare.jpg\",\"admin_type\":\"super_admin\"}"
    ;;
esac
# The admin role comes from the group; what the admin may *do* comes from their school-side profile
# (`admin_type` + `permissions`, db/schema-v14). The mock's admin login has no profile, so it starts with
# no permissions at all — which is the point: an Authentik admin nobody has set up in the school can see
# the shell and nothing else.
curl -s -o /dev/null -X DELETE "$B/api/users" -H "Authorization: Bearer dev-skip" -H "$C" -d '{"id":"admin_profile:mock_uuid_admin"}'
check "an admin login with no school profile may not use the LMS (403)" "$(call mock-admin-token GET /api/teacher/lessons)" " HTTP 403"
check "and the refusal names the permission it needs" "$(call mock-admin-token GET /api/teacher/lessons)" "View and manage lessons"
check "attaching a supervisor profile to that login is accepted" "$(curl -s -o /dev/null -w '%{http_code}' -X PUT "$B/api/users" -H "Authorization: Bearer dev-skip" -H "$C" -d '{"id":"admin_profile:mock_uuid_admin","first_name":"Sandbox","surname":"Supervisor","passport":"https://example.com/supervisor.jpg","admin_type":"supervisor"}')" "200"
check "a supervisor may call a teacher route" "$(call mock-admin-token GET /api/teacher/lessons)" " HTTP 200"
check "a supervisor may not create a user (403)" "$(call mock-admin-token POST /api/users '{"role":"Parent","email":"authz_sup@example.com","first_name":"Authz","surname":"Sup","passport":"https://example.com/a.jpg"}')" " HTTP 403"
check "and the refusal names Manage users" "$(call mock-admin-token POST /api/users '{}')" "Manage users"
check "a supervisor may not write configuration (403)" "$(call mock-admin-token POST /api/terms "{\"name\":\"Authz sup ${STAMP}\",\"sort_order\":94}")" " HTTP 403"
check "and the refusal names Manage school setup" "$(call mock-admin-token POST /api/terms '{}')" "Manage school setup"
check "promoting that login to super admin is accepted" "$(curl -s -o /dev/null -w '%{http_code}' -X PUT "$B/api/users" -H "Authorization: Bearer dev-skip" -H "$C" -d '{"id":"admin_profile:mock_uuid_admin","admin_type":"super_admin"}')" "200"
check "a super admin may write configuration" "$(call mock-admin-token POST /api/terms "{\"name\":\"Authz admin term ${STAMP}\",\"sort_order\":95}")" " HTTP 200"
check "a token with no groups is a student" "$(call mock-groupless-token GET /api/student/subjects)" " HTTP 200"
check "and is refused a teacher route (403)" "$(call mock-groupless-token GET /api/teacher/lessons)" " HTTP 403"

# --- 6. `permissions.manage` decides rights; `users.manage` does not imply it ------------
# A seat that manages users but may not decide permissions is a type from the catalog with its own
# ticks (the ticks are what the backend enforces, so this is exactly that seat). Without this rule an
# admin who could edit users could grant themselves the run of the school.
curl -s -o /dev/null -X PUT "$B/api/users" -H "Authorization: Bearer dev-skip" -H "$C" \
  -d '{"id":"admin_profile:mock_uuid_admin","admin_type":"supervisor","permissions":["users.manage"]}'
check "an admin with users.manage may edit a user's own fields" "$(call mock-admin-token PUT /api/users '{"id":"admin_profile:mock_uuid_admin","first_name":"Sandbox"}')" " HTTP 200"
check "and may create a user" "$(curl -s -o /dev/null -w ' HTTP %{http_code}' -X POST "$B/api/users" -H "Authorization: Bearer mock-admin-token" -H "$C" -d "{\"role\":\"Parent\",\"email\":\"authz_rights_${STAMP}@example.com\",\"first_name\":\"Authz\",\"surname\":\"Rights\",\"passport\":\"https://example.com/a.jpg\"}")" " HTTP 200"
check "but may not change an admin's type (403)" "$(call mock-admin-token PUT /api/users '{"id":"admin_profile:mock_uuid_admin","admin_type":"super_admin"}')" " HTTP 403"
check "and the refusal names Manage permissions" "$(call mock-admin-token PUT /api/users '{"id":"admin_profile:mock_uuid_admin","admin_type":"super_admin"}')" "Manage permissions"
check "nor grant itself permissions (403)" "$(call mock-admin-token PUT /api/users '{"id":"admin_profile:mock_uuid_admin","permissions":["permissions.manage"]}')" " HTTP 403"
check "nor create an admin with a type (403)" "$(call mock-admin-token POST /api/users '{"role":"Admin","email":"authz_type@example.com","first_name":"Authz","surname":"Type","passport":"https://example.com/a.jpg","admin_type":"supervisor"}')" " HTTP 403"
# A seat that holds the permission may decide rights — this is the one the school's own screen uses.
check "a seat with permissions.manage may decide rights" "$(curl -s -o /dev/null -w '%{http_code}' -X PUT "$B/api/users" -H "Authorization: Bearer dev-skip" -H "$C" -d '{"id":"admin_profile:mock_uuid_admin","permissions":["users.manage","permissions.manage"]}')" "200"
check "and that seat may then set a type" "$(call mock-admin-token PUT /api/users '{"id":"admin_profile:mock_uuid_admin","admin_type":"supervisor"}')" " HTTP 200"
# A payload that names only a type asks for that type's own ticks (its defaults); the screen always sends
# both, so what it saves is exactly what its checkboxes showed.
check "naming only a type asks for its default ticks" "$(curl -s -o /dev/null -w '%{http_code}' -X PUT "$B/api/users" -H "Authorization: Bearer dev-skip" -H "$C" -d '{"id":"admin_profile:mock_uuid_admin","admin_type":"supervisor","permissions":["users.manage","permissions.manage"]}')" "200"
# What the screen reads a row back from: the listing carries the type and the ticks it was given.
check "the admin listing carries the type" "$(call dev-skip GET '/api/users?role=Admin')" '"admin_type":"supervisor"'
check "and the ticks" "$(call dev-skip GET '/api/users?role=Admin')" '"permissions":["users.manage","permissions.manage"]'
# Leave the seeded seat as the file found it.
curl -s -o /dev/null -X PUT "$B/api/users" -H "Authorization: Bearer dev-skip" -H "$C" \
  -d '{"id":"admin_profile:mock_uuid_admin","admin_type":"supervisor","permissions":["lessons.manage","assessments.manage"]}'

# --- 7. a row's absent columns read as absent, not as the next field's name ----------------
# The database answers a selected column the row does not carry as `null`; the listing scans text, so
# `"middle_name":null,"passport":"…"` used to read "passport" as the middle name and the edit form
# prefilled it back into the next save.
CREATED_ADMIN=$(curl -s -X POST "$B/api/users" -H 'Authorization: Bearer dev-skip' -H "$C" \
  -d "{\"role\":\"Admin\",\"email\":\"authz_null_${STAMP}@example.com\",\"first_name\":\"No\",\"surname\":\"Middle${STAMP}\",\"passport\":\"https://example.com/a.jpg\",\"admin_type\":\"supervisor\"}")
CREATED_ADMIN_ID=$(echo "$CREATED_ADMIN" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['result'][0]['id'])" 2>/dev/null)
ADMIN_ROW=$(call dev-skip GET '/api/users?role=Admin')
check "a row with no middle name answers with none" "$ADMIN_ROW" '"middle_name":"","surname":"Middle'
check "and no date of birth" "$ADMIN_ROW" '"date_of_birth":""'
check "and no class" "$ADMIN_ROW" '"class_name":""'
check "and the created admin carries the type it was made with" "$ADMIN_ROW" "\"admin_type\":\"supervisor\""
check "cleaning up that admin answers 200" "$(call dev-skip DELETE /api/users "{\"id\":\"$CREATED_ADMIN_ID\"}")" " HTTP 200"

echo ""
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
