#!/bin/sh
# Assessment lifecycle over the API: draft -> publish -> student submit -> grade -> release.
#
# Writes lesson_assessments and submissions rows, so point it at a sandbox backend (see README.md),
# never at prod.
#
#   APP_URL=http://127.0.0.1:8000 LESSON_ID=lessons:test_lesson sh tests/e2e/assessment_flow.sh

B=${APP_URL:-http://127.0.0.1:8000}
T="Authorization: Bearer ${AUTH_TOKEN:-dev-skip}"
C="Content-Type: application/json"
L=${LESSON_ID:-lessons:test_lesson}
pass=0; fail=0
check() { # $1 label, $2 actual, $3 expected substring
  case "$2" in *"$3"*) echo "PASS  $1"; pass=$((pass+1));; *) echo "FAIL  $1 — got: $(echo "$2" | head -c 160)"; fail=$((fail+1));; esac
}

AID=$(curl -s -X POST "$B/api/teacher/create-lesson-assessment" -H "$T" -H "$C" -d "{\"lesson_id\":\"$L\",\"title\":\"API flow quiz\"}" | python3 -c "
import json,sys
r=json.load(sys.stdin)[0]['result'][0]; print(r['id'])")
check "create returns an id" "$AID" "lesson_assessments:"
check "teacher sees the draft" "$(curl -s "$B/api/teacher/lesson-assessments?lesson_id=$L" -H "$T")" '"active":false'
check "student cannot see a draft" "$(curl -s "$B/api/student/assessments?lesson_id=$L" -H "$T")" '"result":[]'
check "publish flips active" "$(curl -s -X POST "$B/api/teacher/toggle-assessment-active" -H "$T" -H "$C" -d "{\"assessment_id\":\"$AID\",\"active\":true}")" '"active":true'
check "student sees it once published" "$(curl -s "$B/api/student/assessments?lesson_id=$L" -H "$T")" '"title":"API flow quiz"'
check "first submit is iteration 1" "$(curl -s -X POST "$B/api/student/submit-assessment" -H "$T" -H "$C" -d "{\"assessment_id\":\"$AID\"}")" '"iteration":1'
check "resubmit bumps the iteration" "$(curl -s -X POST "$B/api/student/submit-assessment" -H "$T" -H "$C" -d "{\"assessment_id\":\"$AID\"}")" '"iteration":2'
SUBS=$(curl -s "$B/api/teacher/submissions?assessment_id=$AID" -H "$T")
check "submissions carry a student name" "$SUBS" '"student_name":"'
check "not graded yet" "$SUBS" '"graded":false'
check "one row per student and assessment" "$(echo "$SUBS" | python3 -c "import json,sys; print(len(json.load(sys.stdin)[0]['result']))")" "1"
SID=$(echo "$SUBS" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['result'][0]['id'])")
check "grade records a mark" "$(curl -s -X POST "$B/api/teacher/grade-submission" -H "$T" -H "$C" -d "{\"submission_id\":\"$SID\",\"scored_mark\":7}")" '"scored_mark":7'
check "graded now reads true" "$(curl -s "$B/api/teacher/submissions?assessment_id=$AID" -H "$T")" '"graded":true'
check "release stamps status" "$(curl -s -X POST "$B/api/teacher/release-grades" -H "$T" -H "$C" -d "{\"submission_id\":\"$SID\"}")" '"status":"graded"'
check "grade_released_at is set" "$(curl -s "$B/api/teacher/submissions?assessment_id=$AID" -H "$T")" '"grade_released_at":"'
check "a title is required" "$(curl -s -X POST "$B/api/teacher/create-lesson-assessment" -H "$T" -H "$C" -d "{\"lesson_id\":\"$L\"}")" "title is required"
check "a lesson is required" "$(curl -s -X POST "$B/api/teacher/create-lesson-assessment" -H "$T" -H "$C" -d '{"title":"x"}')" "lesson_id is required"

echo ""
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
