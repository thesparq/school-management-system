#!/bin/sh
# General assessment lifecycle over the API: create (draft) -> publish -> student submit -> grade ->
# release, plus the submit-time rules (MCQ auto-scoring, the deadline, the opens-at time and the
# resubmission limit) and the create-time validation (required fields, the term weight budget, the
# strict question shape).
#
# Writes general_assessments and submissions rows, so point it at a sandbox backend (see README.md),
# never at prod.
#
# Self-isolating: the create-time weight budget is 100% per session term and subject, and one run
# spends 30% of it, so a fixed subject would refuse the fourth run's creates. A run therefore
# creates its own subject through the API first (the sandbox accepts the suite's teacher token) and
# the budget starts empty, which is what lets the same sandbox run this twice in a row.
#
#   APP_URL=http://127.0.0.1:8000 sh tests/e2e/general_assessment_flow.sh
#   SUBJECT_ID=subjects:agricultural_science SESSION_TERM_ID=session_term:session_2026_2027 \
#     sh tests/e2e/general_assessment_flow.sh
#
# SUBJECT_ID skips the create; that pair's budget is then the caller's to keep under 100%.

B=${APP_URL:-http://127.0.0.1:8000}
T="Authorization: Bearer ${AUTH_TOKEN:-dev-skip}"
C="Content-Type: application/json"
ST=${SESSION_TERM_ID:-session_term:session_2026_2027}
# Unique per run (seconds + pid), so two runs in the same second still get their own subject and
# their own list rows.
RUN_TAG="$(date +%s)-$$"
TITLE="General assessment $RUN_TAG"
pass=0; fail=0
check() { # $1 label, $2 actual, $3 expected substring
  case "$2" in *"$3"*) echo "PASS  $1"; pass=$((pass+1));; *) echo "FAIL  $1 — got: $(echo "$2" | head -c 200)"; fail=$((fail+1));; esac
}
create() { # $1 extra JSON fields (optional); empty means just the required ones
  extra=${1:-}
  curl -s -X POST "$B/api/teacher/create-general-assessment" -H "$T" -H "$C" \
    -d "{\"subject_id\":\"$SUBJ\",\"session_term_id\":\"$ST\",\"title\":\"$TITLE\"${extra}"
}
id_of() { python3 -c "import json,sys; r=json.load(sys.stdin)[0]; print(r['result'][0]['id'] if r['status']=='OK' and r['result'] else 'create failed: '+str(r.get('result'))[:120])"; }
publish() { curl -s -X POST "$B/api/teacher/toggle-assessment-active" -H "$T" -H "$C" -d "{\"assessment_id\":\"$1\",\"assessment_type\":\"general\",\"active\":true}"; }
submit() { # $1 assessment id, $2 answers array (optional)
  body=${2:-"[]"}
  curl -s -X POST "$B/api/student/submit-assessment" -H "$T" -H "$C" -d "{\"assessment_id\":\"$1\",\"assessment_type\":\"general\",\"answers\":$body}"
}
submit_status() { # $1 assessment id
  curl -s -o /dev/null -w '%{http_code}' -X POST "$B/api/student/submit-assessment" -H "$T" -H "$C" -d "{\"assessment_id\":\"$1\",\"assessment_type\":\"general\",\"answers\":[]}"
}
stored_mark() { # $1 assessment id, $2 answer position -> that answer's stored allocated_mark
  curl -s "$B/api/teacher/submissions?assessment_id=$1" -H "$T" | python3 -c "
import json,sys
rows = json.load(sys.stdin)[0]['result']
answers = (rows[0].get('answers') if rows else None) or []
print(answers[$2]['allocated_mark'] if len(answers) > $2 else 'no answer')"
}
db_query() { # $1 SurrealQL, read straight from the sandbox database; needs SURREAL_URL
  curl -s -u "${SURREAL_USER:-root}:${SURREAL_PASS:-root}" -X POST "$SURREAL_URL" \
    -H "surreal-ns: ${SURREAL_DB_NS:-main}" -H "surreal-db: ${SURREAL_DB:-lessons}" -H 'Accept: application/json' \
    --data-binary "$1"
}

# This run's own subject, so the (session term, subject) weight budget starts at 0% every time.
SUBJ=${SUBJECT_ID:-}
if [ -z "$SUBJ" ]; then
  SUBJ=$(curl -s -X POST "$B/api/subjects" -H "$T" -H "$C" -d "{\"name\":\"General flow $RUN_TAG\",\"code\":\"GF-$RUN_TAG\"}" | id_of)
  check "the run creates its own subject" "$SUBJ" "subjects:"
fi

# --- create: a draft, with the questions in the strict stored shape ---
QUESTIONS='[{"type":"mcq","question":"Pick one","options":["a","b"],"answer":"b","marks":3},{"type":"essay","question":"Explain","answer":"","marks":5}]'
CREATED=$(create ",\"description\":\"Term test\",\"percentage_weight\":10,\"total_mark\":8,\"questions\":$QUESTIONS")
AID=$(echo "$CREATED" | id_of)
check "create returns a general_assessments id" "$AID" "general_assessments:"
check "questions are stored" "$CREATED" '"type":"mcq"'
check "options are stored" "$CREATED" '"options":["a","b"]'
check "the answer letter is stored" "$CREATED" '"answer":"b"'
check "marks are stored" "$CREATED" '"marks":5'
check "the percentage weight is stored" "$CREATED" '"percentage_weight":10'
check "total_mark is stored" "$CREATED" '"total_mark":8'
check "it starts as a draft" "$CREATED" '"active":false'
check "teacher sees the draft" "$(curl -s "$B/api/teacher/general-assessments?subject_id=$SUBJ&session_term_id=$ST" -H "$T")" "\"title\":\"$TITLE\""
# Scoped to this run's assessment, so it also holds when the sandbox already has published ones.
DRAFT_VISIBLE=$(curl -s "$B/api/student/general-assessments" -H "$T" | TITLE="$TITLE" python3 -c "
import json,os,sys
rows=json.load(sys.stdin)[0]['result']
print(sum(1 for r in rows if r.get('title') == os.environ['TITLE']))")
check "student cannot see the draft" "$DRAFT_VISIBLE" "0"
# A draft is unsubmittable, not just invisible: a stale tab or a hand-made request naming one is refused.
check "a submission to the draft is refused" "$(submit "$AID")" "not published"
check "and it is a 409" "$(submit_status "$AID")" "409"
check "a submission to an unknown general assessment is refused" "$(submit "general_assessments:nope_$(date +%s)")" "No such assessment"

# --- publish: students see it, and the student list carries the names for the pickers ---
check "publish flips active" "$(publish "$AID")" '"active":true'
STUDENT_LIST=$(curl -s "$B/api/student/general-assessments?subject_id=$SUBJ&session_term_id=$ST" -H "$T")
check "student sees it once published" "$STUDENT_LIST" "\"title\":\"$TITLE\""
check "the list names the subject" "$STUDENT_LIST" '"subject_name":'
check "the list names the session term" "$STUDENT_LIST" '"session_term_name":'

# --- submit: one row per student, iteration bumps in place, MCQs auto-scored ---
FIRST_SUBMIT=$(submit "$AID" '[{"question_index":0,"answer_type":"mcq","answer_text":"b","allocated_mark":3},{"question_index":1,"answer_type":"essay","answer_text":"Because it protects","allocated_mark":5}]')
check "first submit is iteration 1" "$FIRST_SUBMIT" '"iteration":1'
check "the submission is stored as general" "$FIRST_SUBMIT" '"assessment_type":"general"'
check "the assessment_id is the bare id" "$FIRST_SUBMIT" "\"assessment_id\":\"$(echo "$AID" | cut -d: -f2)\""
check "an MCQ matching the stored answer is scored" "$(stored_mark "$AID" 0)" "3"
check "a non-MCQ answer keeps its allocation" "$(stored_mark "$AID" 1)" "5"
SUBS=$(curl -s "$B/api/teacher/submissions?assessment_id=$AID" -H "$T")
SID=$(echo "$SUBS" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['result'][0]['id'])")
check "submissions carry a student name" "$SUBS" '"student_name":"'
check "one row per student and assessment" "$(echo "$SUBS" | python3 -c "import json,sys; print(len(json.load(sys.stdin)[0]['result']))")" "1"

# What the database holds, not what the API echoed: the fixture carries prod's field definitions for
# both tables, so a row this suite wrote and read back here is the shape the schema enforces. Needs
# SURREAL_URL, like the compositions check at the end.
if [ -n "$SURREAL_URL" ]; then
  STORED_QUESTIONS=$(db_query "SELECT questions FROM $AID;" | python3 -c "
import json,sys
declared = {'type','question','options','answer','explanation','marks'}
allowed = {'mcq','boolean','short_answer','essay'}
rows = json.load(sys.stdin)[0]['result']
qs = rows[0]['questions'] if rows else []
problems = []
if len(qs) != 2: problems.append(str(len(qs)) + ' stored')
for q in qs:
    extra = set(q) - declared
    if extra: problems.append('undeclared ' + ','.join(sorted(extra)))
    if q.get('type') not in allowed: problems.append('type ' + str(q.get('type')))
    if not isinstance(q.get('question'), str): problems.append('question is not a string')
    if not isinstance(q.get('answer'), str): problems.append('answer is not a string')
    if 'options' in q and not (isinstance(q['options'], list) and all(isinstance(o, str) for o in q['options'])): problems.append('options are not strings')
    if 'marks' in q and not isinstance(q['marks'], (int, float)): problems.append('marks is not a number')
if len(qs) == 2:
    if qs[0] != {'type':'mcq','question':'Pick one','options':['a','b'],'answer':'b','marks':3}: problems.append('the MCQ is not what was sent')
    if qs[1] != {'type':'essay','question':'Explain','answer':'','marks':5}: problems.append('the essay is not what was sent')
print('ok' if not problems else '; '.join(problems))")
  check "the stored questions carry the schema's six question fields" "$STORED_QUESTIONS" "ok"
  STORED_ANSWERS=$(db_query "SELECT answers FROM $SID;" | python3 -c "
import json,sys
declared = {'question_index','answer_type','answer_text','allocated_mark'}
rows = json.load(sys.stdin)[0]['result']
ans = rows[0]['answers'] if rows else []
problems = []
if len(ans) != 2: problems.append(str(len(ans)) + ' stored')
for a in ans:
    extra = set(a) - declared
    if extra: problems.append('undeclared ' + ','.join(sorted(extra)))
    if not isinstance(a.get('question_index'), int): problems.append('question_index is not an int')
    if not isinstance(a.get('answer_type'), str): problems.append('answer_type is not a string')
    if not isinstance(a.get('answer_text'), str): problems.append('answer_text is not a string')
    if not isinstance(a.get('allocated_mark'), int): problems.append('allocated_mark is not an int')
if len(ans) == 2:
    if ans[0] != {'question_index':0,'answer_type':'mcq','answer_text':'b','allocated_mark':3}: problems.append('the auto-scored MCQ is not what was sent')
    if ans[1] != {'question_index':1,'answer_type':'essay','answer_text':'Because it protects','allocated_mark':5}: problems.append('the typed answer is not what was sent')
print('ok' if not problems else '; '.join(problems))")
  check "the stored answers are the schema's four declared sub-fields" "$STORED_ANSWERS" "ok"
else
  echo "SKIP  the stored questions and answers shapes (set SURREAL_URL to read them back)"
fi

# This assessment has no max_resubmissions, i.e. 0 = unlimited, so the second submit is a bump.
check "resubmit bumps the iteration" "$(submit "$AID")" '"iteration":2'
check "still one row after the resubmit" "$(curl -s "$B/api/teacher/submissions?assessment_id=$AID" -H "$T" | python3 -c "import json,sys; print(len(json.load(sys.stdin)[0]['result']))")" "1"
check "a wrong MCQ is rescored to 0" "$(submit "$AID" '[{"question_index":0,"answer_type":"mcq","answer_text":"a","allocated_mark":3}]' > /dev/null; stored_mark "$AID" 0)" "0"

# --- grading: the teacher's list is keyed off assessment_id, so the row shows there ---
check "not graded yet" "$SUBS" '"graded":false'
check "grade records a mark" "$(curl -s -X POST "$B/api/teacher/grade-submission" -H "$T" -H "$C" -d "{\"submission_id\":\"$SID\",\"scored_mark\":7}")" '"scored_mark":7'
check "graded now reads true" "$(curl -s "$B/api/teacher/submissions?assessment_id=$AID" -H "$T")" '"graded":true'
check "release stamps status" "$(curl -s -X POST "$B/api/teacher/release-grades" -H "$T" -H "$C" -d "{\"submission_id\":\"$SID\"}")" '"status":"graded"'
check "grade_released_at is set" "$(curl -s "$B/api/teacher/submissions?assessment_id=$AID" -H "$T")" '"grade_released_at":"'

# --- a released grade is final: the answers behind it cannot be replaced ---
# The MoonBit stack refused a resubmit once grade_released_at was set (student_handler_assessment.mbt).
# The refused attempt below carries the correct answer, so it would re-score the row to 3 if the
# guard let it through.
check "a resubmit after the grade is released is refused" "$(submit "$AID" '[{"question_index":0,"answer_type":"mcq","answer_text":"b","allocated_mark":3}]')" "has been released"
check "the released-grade rejection is a 409" "$(submit_status "$AID")" "409"
check "the graded answers are untouched" "$(stored_mark "$AID" 0)" "0"

# --- the deadline: the page disables the button, the backend is authoritative ---
PAST_AID=$(create ",\"percentage_weight\":5,\"deadline\":\"2020-01-01T00:00:00Z\"" | id_of)
publish "$PAST_AID" > /dev/null
check "a submission past the deadline is rejected" "$(submit "$PAST_AID")" "deadline for this assessment has passed"
check "the deadline rejection is a 409" "$(submit_status "$PAST_AID")" "409"

# --- scheduled_at: not open yet, refused until it passes ---
LATER_CREATE=$(create ",\"percentage_weight\":5,\"scheduled_at\":\"2099-01-01T00:00:00Z\"")
LATER_AID=$(echo "$LATER_CREATE" | id_of)
check "scheduled_at is stored" "$LATER_CREATE" '"scheduled_at":'
publish "$LATER_AID" > /dev/null
check "a submission before scheduled_at is rejected" "$(submit "$LATER_AID")" "not open yet"
check "the not-open rejection is a 409" "$(submit_status "$LATER_AID")" "409"
EARLIER_AID=$(create ",\"percentage_weight\":5,\"scheduled_at\":\"2020-01-01T00:00:00Z\"" | id_of)
publish "$EARLIER_AID" > /dev/null
check "a submission after scheduled_at is accepted" "$(submit "$EARLIER_AID")" '"iteration":1'

# --- max_resubmissions: 0 is unlimited, otherwise the iteration is capped ---
LIMIT_CREATE=$(create ",\"percentage_weight\":5,\"max_resubmissions\":1")
LIMIT_AID=$(echo "$LIMIT_CREATE" | id_of)
publish "$LIMIT_AID" > /dev/null
check "the resubmission limit is stored" "$LIMIT_CREATE" '"max_resubmissions":1'
check "the first submit is within the limit" "$(submit "$LIMIT_AID")" '"iteration":1'
check "a resubmit past max_resubmissions is rejected" "$(submit "$LIMIT_AID")" "Resubmission limit reached"
check "the resubmission rejection is a 409" "$(submit_status "$LIMIT_AID")" "409"

# --- create-time validation ---
check "a title is required" "$(curl -s -X POST "$B/api/teacher/create-general-assessment" -H "$T" -H "$C" -d "{\"subject_id\":\"$SUBJ\",\"session_term_id\":\"$ST\",\"percentage_weight\":1}")" "title is required"
check "a subject is required" "$(curl -s -X POST "$B/api/teacher/create-general-assessment" -H "$T" -H "$C" -d "{\"session_term_id\":\"$ST\",\"title\":\"x\"}")" "subject_id is required"
check "a session term is required" "$(curl -s -X POST "$B/api/teacher/create-general-assessment" -H "$T" -H "$C" -d "{\"subject_id\":\"$SUBJ\",\"title\":\"x\"}")" "session_term_id is required"
check "a percentage weight is required" "$(curl -s -X POST "$B/api/teacher/create-general-assessment" -H "$T" -H "$C" -d "{\"subject_id\":\"$SUBJ\",\"session_term_id\":\"$ST\",\"title\":\"x\"}")" "percentage_weight must be a whole number"
check "an unknown question type is rejected" "$(create ",\"percentage_weight\":1,\"questions\":[{\"type\":\"multiple_choice\",\"question\":\"x\",\"answer\":\"a\"}]")" "must conform"
# The weight budget is the rule the MoonBit stack enforced; this run has spent 30% of the term.
check "weights that would pass 100% are refused" "$(create ",\"percentage_weight\":80")" "exceeds 100%"

# --- the lesson flow is untouched: a lesson submission is still assessment_type lesson ---
LESSON_AID=$(curl -s -X POST "$B/api/teacher/create-lesson-assessment" -H "$T" -H "$C" -d "{\"lesson_id\":\"lessons:test_lesson\",\"title\":\"$TITLE lesson\"}" | id_of)
curl -s -X POST "$B/api/teacher/toggle-assessment-active" -H "$T" -H "$C" -d "{\"assessment_id\":\"$LESSON_AID\",\"active\":true}" > /dev/null
check "a lesson submission is still assessment_type lesson" "$(curl -s -X POST "$B/api/student/submit-assessment" -H "$T" -H "$C" -d "{\"assessment_id\":\"$LESSON_AID\"}")" '"assessment_type":"lesson"'

# --- compositions: the implementation neither reads nor writes the join table ---
if [ -n "$SURREAL_URL" ]; then
  COMPOSITIONS=$(db_query 'SELECT count() AS c FROM compositions GROUP ALL;' | python3 -c "
import json,sys
try: print(json.load(sys.stdin)[0]['result'][0]['c'])
except Exception: print('unknown')")
  check "the general flow writes no compositions rows" "$COMPOSITIONS" "0"
else
  echo "SKIP  the general flow writes no compositions rows (set SURREAL_URL to check the join table)"
fi

echo ""
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
