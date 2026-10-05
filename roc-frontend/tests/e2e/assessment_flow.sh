#!/bin/sh
# Assessment lifecycle over the API: draft -> publish -> student submit -> grade -> release, plus the
# submit-time rules (MCQ auto-scoring, the deadline and the resubmission limit).
#
# Writes lesson_assessments and submissions rows, so point it at a sandbox backend (see README.md),
# never at prod.
#
#   APP_URL=http://127.0.0.1:8000 LESSON_ID=lessons:test_lesson sh tests/e2e/assessment_flow.sh

B=${APP_URL:-http://127.0.0.1:8000}
T="Authorization: Bearer ${AUTH_TOKEN:-dev-skip}"
C="Content-Type: application/json"
L=${LESSON_ID:-lessons:test_lesson}
# Unique per run: the sandbox may still hold assessments from earlier runs.
TITLE="API flow quiz $(date +%s)"
pass=0; fail=0
check() { # $1 label, $2 actual, $3 expected substring
  case "$2" in *"$3"*) echo "PASS  $1"; pass=$((pass+1));; *) echo "FAIL  $1 — got: $(echo "$2" | head -c 160)"; fail=$((fail+1));; esac
}
stored_mark() { # $1 assessment id, $2 answer position -> that answer's stored allocated_mark
  curl -s "$B/api/teacher/submissions?assessment_id=$1" -H "$T" | python3 -c "
import json,sys
rows = json.load(sys.stdin)[0]['result']
answers = (rows[0].get('answers') if rows else None) or []
print(answers[$2]['allocated_mark'] if len(answers) > $2 else 'no answer')"
}
submit() { # $1 assessment id, $2 answers array (optional)
  body=${2:-"[]"}
  curl -s -X POST "$B/api/student/submit-assessment" -H "$T" -H "$C" -d "{\"assessment_id\":\"$1\",\"answers\":$body}"
}
submit_status() { # $1 assessment id, $2 answers array (optional)
  body=${2:-"[]"}
  curl -s -o /dev/null -w '%{http_code}' -X POST "$B/api/student/submit-assessment" -H "$T" -H "$C" -d "{\"assessment_id\":\"$1\",\"answers\":$body}"
}

AID=$(curl -s -X POST "$B/api/teacher/create-lesson-assessment" -H "$T" -H "$C" -d "{\"lesson_id\":\"$L\",\"title\":\"$TITLE\"}" | python3 -c "
import json,sys
r=json.load(sys.stdin)[0]['result'][0]; print(r['id'])")
check "create returns an id" "$AID" "lesson_assessments:"
check "teacher sees the draft" "$(curl -s "$B/api/teacher/lesson-assessments?lesson_id=$L" -H "$T")" '"active":false'
# Scoped to this run's assessment, so it also holds when the sandbox already has published ones.
DRAFT_VISIBLE=$(curl -s "$B/api/student/assessments?lesson_id=$L" -H "$T" | TITLE="$TITLE" python3 -c "
import json,os,sys
rows=json.load(sys.stdin)[0]['result']
print(sum(1 for r in rows if r.get('title') == os.environ['TITLE']))")
check "student cannot see the draft" "$DRAFT_VISIBLE" "0"
check "publish flips active" "$(curl -s -X POST "$B/api/teacher/toggle-assessment-active" -H "$T" -H "$C" -d "{\"assessment_id\":\"$AID\",\"active\":true}")" '"active":true'
check "student sees it once published" "$(curl -s "$B/api/student/assessments?lesson_id=$L" -H "$T")" "\"title\":\"$TITLE\""
check "first submit is iteration 1" "$(curl -s -X POST "$B/api/student/submit-assessment" -H "$T" -H "$C" -d "{\"assessment_id\":\"$AID\"}")" '"iteration":1'
# This assessment has no max_resubmissions, i.e. 0 = unlimited, so the second submit is a bump.
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

# Questions in the strict shape the schema now enforces
WITH_Q=$(curl -s -X POST "$B/api/teacher/create-lesson-assessment" -H "$T" -H "$C" -d "{\"lesson_id\":\"$L\",\"title\":\"$TITLE with questions\",\"total_mark\":3,\"questions\":[{\"type\":\"mcq\",\"question\":\"Pick one\",\"options\":[\"a\",\"b\"],\"answer\":\"b\",\"marks\":3}]}")
check "questions are stored" "$WITH_Q" '"type":"mcq"'
check "options are stored" "$WITH_Q" '"options":["a","b"]'
check "marks are stored" "$WITH_Q" '"marks":3'
check "total_mark is stored" "$WITH_Q" '"total_mark":3'
check "an unknown question type is rejected" "$(curl -s -X POST "$B/api/teacher/create-lesson-assessment" -H "$T" -H "$C" -d "{\"lesson_id\":\"$L\",\"title\":\"$TITLE bad\",\"questions\":[{\"type\":\"multiple_choice\",\"question\":\"x\",\"answer\":\"a\"}]}")" "must conform"

# --- MCQ auto-scoring: the chosen letter against the question's stored answer ---
MCQ_AID=$(curl -s -X POST "$B/api/teacher/create-lesson-assessment" -H "$T" -H "$C" -d "{\"lesson_id\":\"$L\",\"title\":\"$TITLE scoring\",\"total_mark\":8,\"questions\":[{\"type\":\"mcq\",\"question\":\"Pick one\",\"options\":[\"a\",\"b\"],\"answer\":\"b\",\"marks\":3},{\"type\":\"essay\",\"question\":\"Explain\",\"answer\":\"m\",\"marks\":5}]}" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['result'][0]['id'])")
check "the scoring assessment is created" "$MCQ_AID" "lesson_assessments:"
curl -s -X POST "$B/api/teacher/toggle-assessment-active" -H "$T" -H "$C" -d "{\"assessment_id\":\"$MCQ_AID\",\"active\":true}" > /dev/null
CORRECT='[{"question_index":0,"answer_type":"mcq","answer_text":"b","allocated_mark":3},{"question_index":1,"answer_type":"essay","answer_text":"Because, it protects","allocated_mark":5}]'
WRONG='[{"question_index":0,"answer_type":"mcq","answer_text":"a","allocated_mark":3},{"question_index":1,"answer_type":"essay","answer_text":"Because, it protects","allocated_mark":5}]'
submit "$MCQ_AID" "$CORRECT" > /dev/null
check "a correct MCQ scores the question's marks" "$(stored_mark "$MCQ_AID" 0)" "3"
check "a non-MCQ answer keeps its allocation" "$(stored_mark "$MCQ_AID" 1)" "5"
submit "$MCQ_AID" "$WRONG" > /dev/null
check "a wrong MCQ scores 0" "$(stored_mark "$MCQ_AID" 0)" "0"
check "the theory answer survives the rescore" "$(curl -s "$B/api/teacher/submissions?assessment_id=$MCQ_AID" -H "$T")" "Because, it protects"

# --- deadline: the page disables the button, the backend is authoritative ---
PAST_AID=$(curl -s -X POST "$B/api/teacher/create-lesson-assessment" -H "$T" -H "$C" -d "{\"lesson_id\":\"$L\",\"title\":\"$TITLE closed\",\"deadline\":\"2020-01-01T00:00:00Z\"}" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['result'][0]['id'])")
curl -s -X POST "$B/api/teacher/toggle-assessment-active" -H "$T" -H "$C" -d "{\"assessment_id\":\"$PAST_AID\",\"active\":true}" > /dev/null
check "a submission past the deadline is rejected" "$(submit "$PAST_AID")" "deadline for this assessment has passed"
check "the deadline rejection is a 409" "$(submit_status "$PAST_AID")" "409"
OPEN_AID=$(curl -s -X POST "$B/api/teacher/create-lesson-assessment" -H "$T" -H "$C" -d "{\"lesson_id\":\"$L\",\"title\":\"$TITLE open\",\"deadline\":\"2099-01-01T00:00:00Z\"}" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['result'][0]['id'])")
check "a submission before the deadline is accepted" "$(submit "$OPEN_AID")" '"iteration":1'

# --- max_resubmissions: 0 is unlimited, otherwise the iteration is capped ---
LIMIT_CREATE=$(curl -s -X POST "$B/api/teacher/create-lesson-assessment" -H "$T" -H "$C" -d "{\"lesson_id\":\"$L\",\"title\":\"$TITLE limited\",\"max_resubmissions\":1}")
LIMIT_AID=$(echo "$LIMIT_CREATE" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['result'][0]['id'])")
check "the resubmission limit is stored" "$LIMIT_CREATE" '"max_resubmissions":1'
check "the first submit is within the limit" "$(submit "$LIMIT_AID")" '"iteration":1'
check "a resubmit past max_resubmissions is rejected" "$(submit "$LIMIT_AID")" "Resubmission limit reached"
check "the resubmission rejection is a 409" "$(submit_status "$LIMIT_AID")" "409"

# The stored submission now carries the awarded mark for the MCQ, so grading can show it.
check "the graded view still reports the submission as ungraded" "$(curl -s "$B/api/teacher/submissions?assessment_id=$MCQ_AID" -H "$T")" '"graded":false'

echo ""
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
