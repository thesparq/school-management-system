#!/bin/sh
# The order every list the pages pull comes back in, over the API:
#
#   - the class lists in the school's own order — the primary years (Year 1-5), then the junior school
#     (JSS 1-3), then the senior school (SSS 1-3), which is what `class_stage_rank` in main.roc sorts
#     by — in `/api/class_levels` (all three variants), `/api/class-subjects`, `/api/curriculum` and a
#     teacher's own pair lists;
#   - subject lists alphabetical wherever subjects are listed on their own;
#   - the orders the other lists already had: terms by `sort_order`, session terms by name, lessons by
#     week, credentials by name, assessments and submissions newest first.
#
# Reads only, except a teacher's own pair list: the checks that a teacher's classes come back in that
# order write a deliberately unsorted set for `teacher_profile:dev_teacher` — the identity the
# DEV_MODE `dev-teacher` token stands for — and clear it again, so the sandbox is left as it was
# found (smoke_teacher_role.cjs reads that teacher's empty state). Point it at a sandbox backend
# (see README.md), never at prod.
#
#   APP_URL=http://127.0.0.1:8000 sh tests/e2e/list_order.sh

B=${APP_URL:-http://127.0.0.1:8000}
C="Content-Type: application/json"
ADMIN="Bearer ${AUTH_TOKEN:-dev-skip}"
TEACHER="Bearer dev-teacher"
STUDENT="Bearer dev-student"
pass=0; fail=0
check() { # $1 label, $2 actual, $3 expected substring
  case "$2" in *"$3"*) echo "PASS  $1"; pass=$((pass+1));; *) echo "FAIL  $1 — got: $(echo "$2" | head -c 200)"; fail=$((fail+1));; esac
}
api() { # $1 path, $2 bearer header (optional, defaults to the admin)
  curl -s "$B$1" -H "Authorization: ${2:-$ADMIN}"
}

# --- The order checks: small python3 reads of an answer's rows, because a list's order is not
# something a substring can see. Each prints `ok`, or what it saw instead. ---

# The school's class order, read off the rows' own `name`: the canonical levels that are in the list
# must appear in exactly that order. A sandbox other suites have already written to carries extra
# levels, which this is not about — but a list ordered by name alone (JSS 1 … before Year 1) fails it.
canonical_classes() {
  python3 -c '
import json, sys
canon = ["Year 1", "Year 2", "Year 3", "Year 4", "Year 5", "JSS 1", "JSS 2", "JSS 3", "SSS 1", "SSS 2", "SSS 3"]
names = [r["name"] for r in json.load(sys.stdin)[0]["result"]]
seen = [n for n in names if n in canon]
if not names:
    print("no rows")
elif not seen:
    print("no canonical levels: " + ",".join(names[:5]))
else:
    print("ok" if seen == [n for n in canon if n in names] else "out of order: " + ",".join(seen))
'
}

# A class-subject pair list (one row per pair, named): the classes must follow the school's order and
# each class's subjects must be alphabetical. Rows of a class the school's list does not name (a
# suite's own row) are left out — the check is about the canonical ones.
canonical_pairs() {
  python3 -c '
import json, sys
canon = ["Year 1", "Year 2", "Year 3", "Year 4", "Year 5", "JSS 1", "JSS 2", "JSS 3", "SSS 1", "SSS 2", "SSS 3"]
rank = {name: i for i, name in enumerate(canon)}
rows = json.load(sys.stdin)[0]["result"]
prev, bad, seen = None, [], 0
for r in rows:
    cls = r["class_level_name"]
    if cls not in rank:
        continue
    seen += 1
    key = (rank[cls], r["subject_name"])
    if prev is not None and key < prev:
        bad.append(cls + " / " + r["subject_name"])
    prev = key
if not seen:
    print("no canonical pairs")
else:
    print("ok" if not bad else "out of order at: " + "; ".join(bad))
'
}

# A curriculum list (`in`/`out` record ids): the classes must follow the school's order. Only the
# canonical ids are read, so a suite's own classes are left out.
canonical_curriculum() {
  python3 -c '
import json, sys
canon = ["class_levels:year_%d" % n for n in range(1, 6)] + ["class_levels:jss_%d" % n for n in range(1, 4)] + ["class_levels:sss_%d" % n for n in range(1, 4)]
rank = {name: i for i, name in enumerate(canon)}
rows = json.load(sys.stdin)[0]["result"]
prev, bad, seen = None, [], 0
for r in rows:
    cls = str(r["in"])
    if cls not in rank:
        continue
    seen += 1
    if prev is not None and rank[cls] < prev:
        bad.append(cls)
    prev = rank[cls]
if not seen:
    print("no canonical links")
else:
    print("ok" if not bad else "out of order at: " + "; ".join(bad))
'
}

# The rows' own `name` field, which must be alphabetical.
names_ascending() {
  python3 -c '
import json, sys
names = [r["name"] for r in json.load(sys.stdin)[0]["result"]]
print("ok" if names == sorted(names) else "not alphabetical: " + ",".join(names))
'
}

# A list ordered by one of its own fields: `asc` must not decrease, `desc` must not increase. The
# timestamps are ISO-8601 text, which compares in time order as it stands.
ordered_by() { # $1 field, $2 asc|desc
  python3 -c '
import json, sys
field, direction = sys.argv[1], sys.argv[2]
values = [r[field] for r in json.load(sys.stdin)[0]["result"] if r.get(field) is not None]
want = sorted(values, reverse=(direction == "desc"))
print("ok" if values == want else "not " + direction + ": " + str(values))
' "$1" "$2"
}

# Whether a list is empty (the cleanup check below).
emptiness() {
  python3 -c '
import json, sys
rows = json.load(sys.stdin)[0]["result"]
print("empty" if not rows else "still lists " + str(len(rows)) + " rows")
'
}

# --- 1. The class levels: the primary years first, then the junior school, then the senior school ---
check "the class list reads Year 1-5, JSS 1-3, SSS 1-3" "$(api /api/class_levels | canonical_classes)" "ok"
check "the picker's active-only list reads the same" "$(api '/api/class_levels?admin_lms=1' | canonical_classes)" "ok"
check "the hub's list (every level, active or not) reads the same" "$(api '/api/class_levels?all=true' | canonical_classes)" "ok"

# --- 2. The subject lists, alphabetical ---
check "the student's subject cards are alphabetical" "$(api /api/student/subjects "$STUDENT" | names_ascending)" "ok"
check "the active subject list is alphabetical" "$(api /api/subjects | names_ascending)" "ok"
check "the hub's subject list is alphabetical" "$(api '/api/subjects?all=true' | names_ascending)" "ok"

# --- 3. The class-subject pairs: class order first, then the subject's name inside the class ---
check "the pair list groups by class in the school's order, subjects alphabetical" "$(api /api/class-subjects | canonical_pairs)" "ok"
check "the curriculum list follows the same class order" "$(api '/api/curriculum?all=true' | canonical_curriculum)" "ok"

# --- 4. A teacher's own pair lists: the same order, whatever order the save wrote ---
# One pair of every canonical class the sandbox has (so the set spans the stages), sent in reverse: a
# list that echoed the write would fail. The set is cleared again at the end of the suite, so the
# sandbox is left as it was found.
PAIRS=$(api /api/class-subjects | python3 -c '
import json, sys
canon = ["Year 1", "Year 2", "Year 3", "Year 4", "Year 5", "JSS 1", "JSS 2", "JSS 3", "SSS 1", "SSS 2", "SSS 3"]
rows = [r for r in json.load(sys.stdin)[0]["result"] if r["class_level_name"] in canon]
per_class = []
for r in rows:
    if not per_class or per_class[-1]["class_level_name"] != r["class_level_name"]:
        per_class.append(r)
picked = per_class[::max(1, len(per_class) // 5)][:5]
print(",".join("{\"edge_id\":\"" + r["edge_id"] + "\"}" for r in reversed(picked)))
')
check "the suite found canonical pairs to assign" "$PAIRS" "edge_id"
SAVED=$(curl -s -X POST "$B/api/teacher-assignments" -H "Authorization: $ADMIN" -H "$C" \
  -d "{\"teacher_id\":\"teacher_profile:dev_teacher\",\"pairs\":[$PAIRS]}")
check "the deliberately unsorted pair set saved" "$SAVED" '"status":"OK"'
check "the teacher's own class list comes back in the school's order" "$(api /api/teacher/classes "$TEACHER" | canonical_pairs)" "ok"
check "the dialog's read of the same set does too" "$(api '/api/teacher-assignments?teacher_id=teacher_profile:dev_teacher' | canonical_pairs)" "ok"
curl -s -X POST "$B/api/teacher-assignments" -H "Authorization: $ADMIN" -H "$C" \
  -d '{"teacher_id":"teacher_profile:dev_teacher","pairs":[]}' > /dev/null
check "the suite's own assignment is cleared again" "$(api /api/teacher/classes "$TEACHER" | emptiness)" "empty"

# --- 5. The lists whose order was already right, kept that way ---
check "terms read in their sort order" "$(api /api/terms | ordered_by sort_order asc)" "ok"
check "the student's terms read in their sort order" "$(api /api/student/terms | ordered_by sort_order asc)" "ok"
check "session terms read by session name" "$(api /api/session_terms | ordered_by session_name asc)" "ok"
check "the qualifications catalog is alphabetical" "$(api /api/credentials | names_ascending)" "ok"
check "lessons read by week (the admin LMS drill's list)" "$(api '/api/teacher/lessons?class_id=class_levels:jss_1&subject_id=subjects:agricultural_science&term_id=terms:noel_term' | ordered_by week asc)" "ok"
check "the student's lessons read by week" "$(api '/api/student/lessons?subject_id=subjects:agricultural_science&term_id=terms:noel_term' "$STUDENT" | ordered_by week asc)" "ok"
check "lesson assessments are newest first" "$(api /api/teacher/lesson-assessments | ordered_by created_at desc)" "ok"
check "general assessments are newest first" "$(api /api/teacher/general-assessments | ordered_by created_at desc)" "ok"
check "the grading inbox is newest first" "$(api /api/teacher/submissions | ordered_by submitted_at desc)" "ok"
# The user listing is deliberately newest first (a just-created account is at the top); the logins the
# directory adds to it carry no `created_at`, which is why the check reads only the rows that have one.
check "the user listing is newest first" "$(api '/api/users?role=Student' | ordered_by created_at desc)" "ok"

echo ""
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
