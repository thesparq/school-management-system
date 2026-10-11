#!/bin/sh
# Apply db/schema-v10-lesson-indexes.surql and report the two things that decide whether it takes.
#
#   SURREAL_URL=... SURREAL_USER=... SURREAL_PASS=... sh db/apply-v10-and-verify.sh
#
# Safe to run against prod as often as you like: `DEFINE INDEX IF NOT EXISTS` is a no-op where the
# index already exists, and the rest is read-only. Nothing here deletes or rewrites anything — a
# refused statement is the worst case, and it names the record that caused it.
#
# The connection comes from the environment; nothing is stored in this file. Prod takes its own values
# the way the backend does (Infisical's prod environment, with SURREAL_URL pointing at the public
# endpoint for clients outside the cluster).
set -eu

url="${SURREAL_URL:-http://127.0.0.1:8002/sql}"
user="${SURREAL_USER:-root}"
pass="${SURREAL_PASS:-root}"
# The app's own names win: prod's environment carries SURREAL_DB_NS/SURREAL_DB, not SURREAL_NS.
ns="${SURREAL_DB_NS:-${SURREAL_NS:-main}}"
db="${SURREAL_DB:-lessons}"
here=$(dirname "$0")

sql() {
    curl -s -u "$user:$pass" -X POST "$url" \
        -H "surreal-ns: $ns" -H "surreal-db: $db" -H 'Accept: application/json' \
        --data-binary "$1"
}

say() { printf '%s\n' "$1"; }

say "== target: $url  (ns=$ns db=$db)"
say ""
say "== 1. the indexes (no-ops where they already exist)"
result=$(sql "$(cat "$here/schema-v10-lesson-indexes.surql")")
case "$result" in
    *ERR*) say "   REFUSED: $result"; say "   => the data does not hold the rule yet; see step 2."; exit 1 ;;
    *) say "   applied" ;;
esac

say ""
say "== 2. lessons sharing an edge, term and week (rows back = the rule could not be added)"
dups=$(sql "SELECT * FROM (SELECT count() AS n, has_subject, term, week FROM lessons GROUP BY has_subject, term, week) WHERE n > 1;")
printf '%s' "$dups" | python3 -c '
import sys, json
try:
    rows = json.load(sys.stdin)[0]["result"]
except Exception as e:
    print("   could not read the answer:", e); sys.exit(0)
if not rows:
    print("   none — one lesson per edge, term and week holds")
else:
    print("   %d group(s) break it:" % len(rows))
    for r in rows:
        print("     ", r["has_subject"], r["term"], "week", r["week"], "->", r["n"], "lessons")
'

say ""
say "== 3. indexes on lessons now"
sql "INFO FOR TABLE lessons;" | python3 -c '
import sys, json
for name, definition in sorted(json.load(sys.stdin)[0]["result"]["indexes"].items()):
    print("  ", name, "-", "UNIQUE" if "UNIQUE" in definition else "plain")
'
