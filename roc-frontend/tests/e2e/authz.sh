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
check "an administrator's token may call a teacher route" "$(call mock-admin-token GET /api/teacher/lessons)" " HTTP 200"
check "an administrator's token may write configuration" "$(call mock-admin-token POST /api/terms "{\"name\":\"Authz admin term ${STAMP}\",\"sort_order\":95}")" " HTTP 200"
check "a token with no groups is a student" "$(call mock-groupless-token GET /api/student/subjects)" " HTTP 200"
check "and is refused a teacher route (403)" "$(call mock-groupless-token GET /api/teacher/lessons)" " HTTP 403"

echo ""
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
