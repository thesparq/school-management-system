#!/bin/sh
# A term the school switches off is off for the pupils. The switch is the hub's own (`terms.active`, via
# POST /api/terms/toggle-active): once it is off, the term is gone from a pupil's term list, its lessons are
# gone from their lesson list (named term or not), the lesson itself is refused by id rather than served,
# its assessments leave their list, and handing work in for one is refused too. The school's own side is
# untouched — a teacher or an admin still reads the lesson, which is how the term gets switched back on.
#
#   APP_URL=http://127.0.0.1:8000 sh tests/e2e/term_switch.sh
#
# Writes the sandbox's `terms` table (and restores it) and creates one assessment, so point it at a sandbox
# — never at prod. The assessment it makes is left `active` and soft-deleted at the end.

B=${APP_URL:-http://127.0.0.1:8000}
DB=${SURREAL_URL:-http://127.0.0.1:8002/sql}
NS=${SURREAL_NS:-main}
DB_NAME=${SURREAL_DB:-lessons}
DB_USER=${SURREAL_USER:-root}
DB_PASS=${SURREAL_PASS:-root}
A="Authorization: Bearer ${AUTH_TOKEN:-dev-skip}"
S="Authorization: Bearer ${STUDENT_TOKEN:-dev-student}"
C="Content-Type: application/json"
STAMP=$(date +%s)
pass=0; fail=0
check() { # $1 label, $2 actual, $3 expected substring
  case "$2" in *"$3"*) echo "PASS  $1"; pass=$((pass+1));; *) echo "FAIL  $1 — got: $(echo "$2" | head -c 170)"; fail=$((fail+1));; esac
}
status() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
db_query() { curl -s -u "$DB_USER:$DB_PASS" -X POST "$DB" -H "surreal-ns: $NS" -H "surreal-db: $DB_NAME" -H 'Accept: application/json' --data-binary "$1"; }

# The fixture's own term and lesson: `terms:noel_term` holds `lessons:test_lesson` (JSS 1 / Agricultural
# Science), which is what these lists are driven from.
LESSON=lessons:test_lesson
TERM=terms:noel_term
SUBJECT=subjects:agricultural_science

# --- the term is on: the pupil reads its lesson, and an assessment on it ------------------------
check "the term is listed for a pupil" "$(curl -s "$B/api/student/terms" -H "$S")" '"noel_term"'
check "and its lesson is listed" "$(curl -s "$B/api/student/lessons?subject_id=${SUBJECT}&term_id=${TERM}" -H "$S")" '"test_lesson"'
check "and the lesson itself reads" "$(status "$B/api/student/lesson?lesson_id=${LESSON}" -H "$S")" "200"

AID=$(curl -s -X POST "$B/api/teacher/create-lesson-assessment" -H "$A" -H "$C" -d "{\"lesson_id\":\"${LESSON}\",\"title\":\"Term switch ${STAMP}\",\"questions\":[]}" | python3 -c "
import json,sys
try: print(json.load(sys.stdin)[0]['result'][0]['id'])
except Exception: print('')" 2>/dev/null)
check "an assessment on that lesson" "$AID" "lesson_assessments:"
check "published" "$(status -X POST "$B/api/teacher/toggle-assessment-active" -H "$A" -H "$C" -d "{\"assessment_id\":\"${AID}\",\"assessment_type\":\"lesson\",\"active\":true}")" "200"
check "the pupil sees it in the lesson's assessments" "$(curl -s "$B/api/student/assessments?lesson_id=${LESSON}" -H "$S")" "${AID#lesson_assessments:}"

# --- the school switches the term off (the hub's own route) -------------------------------------
check "switching the term off answers 200" "$(status -X POST "$B/api/terms/toggle-active" -H "$A" -H "$C" -d "{\"id\":\"${TERM}\",\"active\":false}")" "200"
check "the row is off in the database" "$(db_query "SELECT active FROM ${TERM};")" '"active":false'

check "the term is gone from a pupil's term list" "$(curl -s "$B/api/student/terms" -H "$S" | grep -c noel_term)" "0"
check "and its lesson is gone from the lesson list" "$(curl -s "$B/api/student/lessons?subject_id=${SUBJECT}&term_id=${TERM}" -H "$S")" '"result":[]'
check "gone even with no term named" "$(curl -s "$B/api/student/lessons?subject_id=${SUBJECT}" -H "$S")" '"result":[]'
check "the lesson by id is refused, not served" "$(curl -s "$B/api/student/lesson?lesson_id=${LESSON}" -H "$S")" "That term is switched off"
check "and the refusal says the school turned it off" "$(curl -s "$B/api/student/lesson?lesson_id=${LESSON}" -H "$S")" "turned this term off"
check "the assessment left the pupil's list" "$(curl -s "$B/api/student/assessments?lesson_id=${LESSON}" -H "$S")" '"result":[]'
check "and handing work in for it is refused" "$(curl -s -X POST "$B/api/student/submit-assessment" -H "$S" -H "$C" -d "{\"assessment_id\":\"${AID}\",\"answers\":[]}")" "That term is switched off"

# The people who would switch it back on still see everything: the admin LMS names the term it drilled to.
check "the school's own side still reads the lesson" "$(status "$B/api/teacher/lessons?lesson_id=${LESSON}" -H "$A")" "200"

# --- back on: the pupil reads it again ----------------------------------------------------------
check "switching the term back on answers 200" "$(status -X POST "$B/api/terms/toggle-active" -H "$A" -H "$C" -d "{\"id\":\"${TERM}\",\"active\":true}")" "200"
check "the lesson is listed again" "$(curl -s "$B/api/student/lessons?subject_id=${SUBJECT}&term_id=${TERM}" -H "$S")" '"test_lesson"'
check "and the lesson reads again" "$(status "$B/api/student/lesson?lesson_id=${LESSON}" -H "$S")" "200"
check "and the assessment is back on the list" "$(curl -s "$B/api/student/assessments?lesson_id=${LESSON}" -H "$S")" "${AID#lesson_assessments:}"

# Clean up: the assessment this suite made is hidden, so the fixture is as it was found.
db_query "UPDATE ${AID} SET deleted_at = time::now();" > /dev/null
check "the suite's assessment is cleared away" "$(curl -s "$B/api/student/assessments?lesson_id=${LESSON}" -H "$S" | grep -c "${AID#lesson_assessments:}")" "0"

echo ""
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
