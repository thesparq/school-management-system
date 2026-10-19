#!/bin/sh
# The token cache: a validated bearer token is kept for a short while, so a page's burst of API calls
# costs one Authentik validation instead of one per request — and the keeping stops the moment this
# backend changes what Authentik would answer about that account.
#
# What this drives, over the API and the mock's own counters:
#   * repeated requests with one token cost exactly one userinfo call;
#   * a delete and a re-enable each drop what was cached, so the very next request validates again;
#   * an entry never outlives its token, and its deadline is the earlier of the TTL and the token's
#     own `exp`;
#   * a token with no readable `exp`, and a DEV_MODE token, are not cached at all (they validate
#     every time), and a bogus token is still a 401.
#
# Needs the sandbox backend with the mock Authentik (the counter is the mock's, and a token it answers
# about has to be one it can look up) and the sandbox database, which is where a deadline is read.
# It creates one teacher of its own and removes that login and its row again at the end.
#
#   APP_URL=http://127.0.0.1:8000 MOCK_AUTHENTIK_URL=http://127.0.0.1:9000 \
#   SURREAL_URL=http://127.0.0.1:8002/sql sh tests/e2e/token_cache.sh

B=${APP_URL:-http://127.0.0.1:8000}
MOCK=${MOCK_AUTHENTIK_URL:-http://127.0.0.1:9000}
DB=${SURREAL_URL:-http://127.0.0.1:8002/sql}
NS=${SURREAL_NS:-main}
DB_NAME=${SURREAL_DB:-lessons}
DB_USER=${SURREAL_USER:-root}
DB_PASS=${SURREAL_PASS:-root}
T="Authorization: Bearer ${AUTH_TOKEN:-dev-skip}"
C="Content-Type: application/json"
STAMP=$(date +%s)
pass=0; fail=0
check() { # $1 label, $2 actual, $3 expected substring
  case "$2" in *"$3"*) echo "PASS  $1"; pass=$((pass+1));; *) echo "FAIL  $1 — got: $(echo "$2" | head -c 160)"; fail=$((fail+1));; esac
}
count() { # $1 label, $2 a number difference, $3 what it should be
  if [ "$2" = "$3" ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1 — the count moved by $2, wanted $3"; fail=$((fail+1)); fi
}
range() { # $1 label, $2 a number, $3 low, $4 high
  if [ "$2" -ge "$3" ] && [ "$2" -le "$4" ]; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1 — $2 is not between $3 and $4"; fail=$((fail+1)); fi
}
db_query() { # $1 SurrealQL
  curl -s -u "$DB_USER:$DB_PASS" -X POST "$DB" -H "surreal-ns: $NS" -H "surreal-db: $DB_NAME" -H 'Accept: application/json' --data-binary "$1"
}
mint() { # $1 the login's pk, $2 seconds from now -> a JWT-shaped token that names it
  python3 -c '
import base64, json, sys, time
def seg(b): return base64.urlsafe_b64encode(b).decode().rstrip("=")
exp = int(time.time() + float(sys.argv[2]))
print(seg(json.dumps({"alg": "RS256", "typ": "JWT"}).encode()) + "." + seg(json.dumps({"sub": sys.argv[1], "exp": exp}).encode()) + ".not-a-real-signature")
' "$1" "$2"
}
calls() { # how many validations the mock's userinfo endpoint has answered
  curl -s "$MOCK/userinfo_calls" | python3 -c 'import json,sys; print(json.load(sys.stdin)["count"])'
}
hit() { # $1 a bearer token -> the status of one authenticated request
  curl -s -o /dev/null -w '%{http_code}' "$B/api/session_terms" -H "Authorization: Bearer $1"
}
token_key() { # $1 a bearer token -> the record id the cache keeps it under
  python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.argv[1].encode()).hexdigest())' "$1"
}
seconds_left() { # $1 a bearer token -> whole seconds until that token's own entry expires, "none" if it has none
  db_query "SELECT time::unix(expires_at) AS expires_at, time::unix(time::now()) AS now FROM type::record('token_cache', '$(token_key "$1")');" \
    | python3 -c 'import json,sys; rows = json.load(sys.stdin)[0]["result"]; print(round(rows[0]["expires_at"] - rows[0]["now"]) if rows else "none")'
}
entries_for() { # $1 a login's pk -> how many entries that login has cached
  db_query "SELECT count() FROM token_cache WHERE subject = '$1' GROUP ALL;" \
    | python3 -c 'import json,sys; rows = json.load(sys.stdin)[0]["result"]; print(rows[0]["count"] if rows else 0)'
}
pk_of() { # $1 a created row's id as the API answers it (backticked when it looks numeric)
  echo "${1#*:}" | tr -d '`'
}

# --- 1. repeated requests with one token cost one validation ---
SEED_PK=$(curl -s "$MOCK/api/v3/core/users/?page_size=200" | python3 -c '
import json,sys
print(next(u["pk"] for u in json.load(sys.stdin)["results"] if u["username"] == "seed-teacher"))
')
TOKEN=$(mint "$SEED_PK" 3600)
BEFORE=$(calls)
check "a minted token reaches an authenticated route" "$(hit "$TOKEN")" "200"
check "and again" "$(hit "$TOKEN")" "200"
check "and once more" "$(hit "$TOKEN")" "200"
count "three requests, one validation" "$(( $(calls) - BEFORE ))" 1
check "the entry is keyed by the token's hash, not the token" "$(db_query "SELECT subject FROM type::record('token_cache', '$(token_key "$TOKEN")');")" "\"subject\":\"$SEED_PK\""
range "and its deadline is inside the TTL" "$(seconds_left "$TOKEN")" 50 61

# --- 2. DEV_MODE tokens never reach the cache, and a token with no readable exp is never kept ---
BEFORE=$(calls)
hit dev-skip > /dev/null
count "a dev-skip request validates nothing" "$(( $(calls) - BEFORE ))" 0
BEFORE=$(calls)
hit mock-teacher-token > /dev/null
hit mock-teacher-token > /dev/null
count "a token with no exp validates every time" "$(( $(calls) - BEFORE ))" 2
check "a token nobody issued is still a 401" "$(hit not-a-real-token)" "401"

# --- 3. the cache stops serving an account the moment this backend disables it ---
EMAIL="token_cache_${STAMP}@example.com"
CREATE=$(curl -s -X POST "$B/api/users" -H "$T" -H "$C" \
  -d "{\"role\":\"Teacher\",\"email\":\"$EMAIL\",\"first_name\":\"Cache\",\"surname\":\"Check${STAMP}\",\"passport\":\"https://example.com/cache-check.jpg\"}")
RID=$(echo "$CREATE" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['result'][0]['id'])" 2>/dev/null)
PK=$(pk_of "$RID")
ROW="teacher_profile:${PK}"
MINE=$(mint "$PK" 3600)
BEFORE=$(calls)
check "the new account's own token works" "$(hit "$MINE")" "200"
check "and its second request is served from the cache" "$(hit "$MINE")" "200"
count "one validation for the two" "$(( $(calls) - BEFORE ))" 1
check "the login has a cached entry" "$(entries_for "$PK")" 1
check "deleting the account is accepted" "$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "$B/api/users" -H "$T" -H "$C" -d "{\"id\":\"$ROW\"}")" "200"
check "and takes its cached validations with it" "$(entries_for "$PK")" 0
check "so the same token is refused at once" "$(hit "$MINE")" "401"

# --- 4. re-enabling drops it too (the rule is every write that changes what userinfo answers) ---
check "re-enabling the account is accepted" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$B/api/users/activate" -H "$T" -H "$C" -d "{\"id\":\"$ROW\"}")" "200"
BEFORE=$(calls)
check "the token works again" "$(hit "$MINE")" "200"
count "and validated afresh: nothing was kept for it" "$(( $(calls) - BEFORE ))" 1
BEFORE=$(calls)
check "its next request is a hit" "$(hit "$MINE")" "200"
count "with no new validation" "$(( $(calls) - BEFORE ))" 0
curl -s -X POST "$B/api/users/activate" -H "$T" -H "$C" -d "{\"id\":\"$ROW\"}" > /dev/null
BEFORE=$(calls)
check "after a second re-enable the same request still works" "$(hit "$MINE")" "200"
count "but had to validate again" "$(( $(calls) - BEFORE ))" 1

# --- 5. a deadline that has passed is a miss, and the token's own exp can be the sooner one ---
db_query "UPDATE token_cache SET expires_at = time::now() - 1s WHERE subject = '$PK';" > /dev/null
BEFORE=$(calls)
check "an entry past its deadline is not served" "$(hit "$MINE")" "200"
count "the request validated instead" "$(( $(calls) - BEFORE ))" 1
SOON=$(mint "$PK" 10)
hit "$SOON" > /dev/null
range "a token expiring in 10s is not kept for the TTL" "$(seconds_left "$SOON")" 5 11

# --- cleanup: the login and the row leave the sandbox as it was ---
curl -s -X DELETE "$MOCK/api/v3/core/users/$PK/" > /dev/null
curl -s -o /dev/null -X DELETE "$B/api/users" -H "$T" -H "$C" -d "{\"id\":\"$ROW\"}"
db_query "DELETE type::record('teacher_profile', '$PK'); DELETE FROM token_cache WHERE subject = '$PK';" > /dev/null
check "the suite's own login is gone from the directory" "$(curl -s "$MOCK/api/v3/core/users/$PK/" -o /dev/null -w '%{http_code}')" "404"

# --- 6. the cache is off, not broken, when its table is not there ---
# The startup line says which of the two it is (`token cache: ready` / `not usable`); the table is
# only ever written by this backend, so a database without it validates every request instead of
# failing one. Checked last, because it takes the table away from the checks above — and the entry
# it leaves behind is a *new* token's, because a removed table that is defined again can come back
# with the rows it held (SurrealDB defers the removal), which no check here depends on either way.
db_query "REMOVE TABLE token_cache;" > /dev/null
BEFORE=$(calls)
check "with no cache table a request still works" "$(hit "$TOKEN")" "200"
count "and validates every time" "$(( $(calls) - BEFORE ))" 1

# Put the table back the way db/schema-v12-token-cache.surql defines it, so the sandbox is left
# usable for the next run without reloading the fixture.
db_query "
DEFINE TABLE IF NOT EXISTS token_cache SCHEMAFULL PERMISSIONS NONE;
DEFINE FIELD IF NOT EXISTS subject ON token_cache TYPE string;
DEFINE FIELD IF NOT EXISTS identity ON token_cache TYPE string;
DEFINE FIELD IF NOT EXISTS expires_at ON token_cache TYPE datetime;
DEFINE FIELD IF NOT EXISTS created_at ON token_cache TYPE datetime DEFAULT time::now();
DEFINE INDEX IF NOT EXISTS idx_token_cache_subject ON token_cache COLUMNS subject;
DEFINE INDEX IF NOT EXISTS idx_token_cache_expiry ON token_cache COLUMNS expires_at;
" > /dev/null
BACK=$(mint "$SEED_PK" 3600)
BEFORE=$(calls)
check "and the cache answers again once it is back" "$(hit "$BACK")" "200"
check "its next request is a hit" "$(hit "$BACK")" "200"
count "one validation for the pair" "$(( $(calls) - BEFORE ))" 1

echo ""
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
