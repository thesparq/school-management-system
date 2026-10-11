#!/bin/sh
# Apply db/schema-v10-lesson-indexes.surql and report what the lesson-list scopes need to know.
#
#   SURREAL_URL=... SURREAL_USER=... SURREAL_PASS=... sh db/apply-v10-and-verify.sh
#   SURREAL_URL=... SURREAL_USER=... SURREAL_PASS=... sh db/apply-v10-and-verify.sh --swap
#
# Without --swap it only runs the additive index and the checks, so it is safe to run against prod as
# often as you like: one `DEFINE INDEX IF NOT EXISTS`, one read-only duplicate count, and a throwaway
# probe index that is dropped again in the same call. --swap is the only thing that changes an index
# that already exists, and it is opt-in so nobody does it by accident on dirty data.
#
# The connection comes from the environment — nothing is stored in this file. Against prod, the
# values the backend itself runs with are the ones to use (Infisical's prod environment).
set -eu

url="${SURREAL_URL:-http://127.0.0.1:8002/sql}"
user="${SURREAL_USER:-root}"
pass="${SURREAL_PASS:-root}"
ns="${SURREAL_NS:-main}"
db="${SURREAL_DB:-lessons}"
mode="${1:-}"
here=$(dirname "$0")

sql() {
    curl -s -u "$user:$pass" -X POST "$url" \
        -H "surreal-ns: $ns" -H "surreal-db: $db" -H 'Accept: application/json' \
        --data-binary "$1"
}

say() { printf '%s\n' "$1"; }

say "== target: $url  (ns=$ns db=$db)"
say ""
say "== 1. the additive index (a no-op when it is already there)"
result=$(sql "$(cat "$here/schema-v10-lesson-indexes.surql")")
case "$result" in
    *ERR*) say "   REFUSED: $result" ; exit 1 ;;
    *) say "   applied" ;;
esac

say ""
say "== 2. lessons sharing an edge, term and week (rows back = real duplicates)"
dups=$(sql "SELECT * FROM (SELECT count() AS n, has_subject, term, week FROM lessons GROUP BY has_subject, term, week) WHERE n > 1;")
printf '%s' "$dups" | python3 -c '
import sys, json
try:
    rows = json.load(sys.stdin)[0]["result"]
except Exception as e:
    print("   could not read the answer:", e); sys.exit(0)
if not rows:
    print("   none — the data is clean")
else:
    print("   %d duplicate group(s):" % len(rows))
    for r in rows:
        print("     ", r["has_subject"], r["term"], "week", r["week"], "->", r["n"], "lessons")
'

say ""
say "== 3. can the UNIQUE rule be added? (probe under a throwaway name, dropped again)"
probe="idx_unique_dryrun_$$"
dry=$(sql "DEFINE INDEX $probe ON lessons COLUMNS has_subject, term, week UNIQUE; REMOVE INDEX IF EXISTS $probe ON lessons;")
case "$dry" in
    *ERR*)
        say "   NO — refused, and nothing was changed:"
        printf '%s' "$dry" | sed 's/^/   /'
        say "   => de-duplicate first; the working index is still in place."
        ;;
    *)
        say "   yes — the data holds the rule today"
        ;;
esac

if [ "$mode" = "--swap" ]; then
    say ""
    say "== 4. swapping the index for its UNIQUE form (--swap was given)"
    case "$dry" in
        *ERR*)
            say "   skipped: the probe above was refused, so the swap would lose the index and change nothing."
            exit 1
            ;;
    esac
    swap_result=$(sql "REMOVE INDEX idx_lessons_edge_term_week ON lessons; DEFINE INDEX idx_lessons_edge_term_week ON lessons COLUMNS has_subject, term, week UNIQUE;")
    case "$swap_result" in
        *ERR*) say "   REFUSED: $swap_result" ; exit 1 ;;
        *) say "   done - one lesson per edge, term and week is now a database rule" ;;
    esac
else
    say ""
    say "== 4. skipped: pass --swap to make the rule a database rule once step 2 is clean"
fi

say ""
say "== indexes on lessons now"
sql "INFO FOR TABLE lessons;" | python3 -c '
import sys, json
print("  ", json.load(sys.stdin)[0]["result"]["indexes"])
'
