#!/bin/sh
# The school's chat channel directory over the API: only an administrator may list a channel, everyone may
# read the public ones, a private channel is listed to administrators alone and opened by whoever holds its
# code — and that code is unique, case-folded, and retired by re-listing the channel.
#
#   APP_URL=http://127.0.0.1:8127 sh tests/e2e/chat_channels.sh
#
# Sandbox backend with the mock Authentik (see README.md): the student is the mock's own student token, so
# the backend sees a real pupil rather than a developer token. The suite makes sure the channel table exists
# (db/schema-v16-chat-channels.surql) so a fresh sandbox works, and deletes the rows it made when done.

B=${APP_URL:-http://127.0.0.1:8000}
C="Content-Type: application/json"
ADMIN="Authorization: Bearer ${AUTH_TOKEN:-dev-skip}"
STUDENT="Authorization: Bearer mock-student-token"
SURREAL=${SURREAL_URL:-http://127.0.0.1:8002/sql}
STAMP=$(date +%s)
ROOM_PUB="!suite${STAMP}pub:matrix.johnethel.school"
ROOM_PRIV="!suite${STAMP}priv:matrix.johnethel.school"
pass=0; fail=0
check() { # $1 label, $2 actual, $3 expected substring
  case "$2" in *"$3"*) echo "PASS  $1"; pass=$((pass+1));; *) echo "FAIL  $1 — got: $(echo "$2" | head -c 200)"; fail=$((fail+1));; esac
}
absent() { # $1 label, $2 actual, $3 substring that must not be there
  case "$2" in *"$3"*) echo "FAIL  $1 — it is there: $(echo "$2" | head -c 200)"; fail=$((fail+1));; *) echo "PASS  $1"; pass=$((pass+1));; esac
}
call() { # $1 auth header, $2 method, $3 path, $4 body (optional) -> "<body> HTTP <status>"
  if [ -n "$4" ]; then
    curl -s -w ' HTTP %{http_code}' -X "$2" "$B$3" -H "$1" -H "$C" -d "$4"
  else
    curl -s -w ' HTTP %{http_code}' -X "$2" "$B$3" -H "$1"
  fi
}
sql() { # $1 statement — the sandbox database itself, for what the API has no route for
  curl -s -u "${SURREAL_USER:-root}:${SURREAL_PASS:-root}" -X POST "$SURREAL" \
    -H 'surreal-ns: main' -H 'surreal-db: lessons' -H 'Accept: application/json' --data-binary "$1"
}

# The table this suite is about, and a clean slate for its own rooms.
sql "$(cat "$(dirname "$0")/../../../db/schema-v16-chat-channels.surql")" > /dev/null 2>&1
sql "DELETE chat_channel WHERE room_id CONTAINS 'suite${STAMP}';" > /dev/null 2>&1

# --- 1. Who may do what ---------------------------------------------------------
check "a pupil may read the directory" "$(call "$STUDENT" GET /api/chat/channels)" "HTTP 200"
check "a pupil may not list a channel" \
  "$(call "$STUDENT" POST /api/chat/channels "{\"room_id\":\"$ROOM_PUB\",\"name\":\"Pupil Made\",\"code\":\"AAAAAA\",\"visibility\":\"public\"}")" "HTTP 403"
check "and nothing was listed by that attempt" "$(sql "SELECT id FROM chat_channel WHERE room_id = '$ROOM_PUB';")" "\"result\":[]"
check "someone with no token is refused" "$(curl -s -w ' HTTP %{http_code}' -X GET "$B/api/chat/channels")" "HTTP 401"

# --- 2. Listing the two kinds ---------------------------------------------------
PUB=$(call "$ADMIN" POST /api/chat/channels "{\"room_id\":\"$ROOM_PUB\",\"name\":\"Suite Public $STAMP\",\"code\":\"PUB${STAMP}\",\"visibility\":\"public\"}")
check "an administrator lists a public channel" "$PUB" '"ok":true'
check "and it comes back as public" "$PUB" '"visibility":"public"'
check "the code is echoed, uppercased by the database" "$PUB" "PUB${STAMP}"
PRIV=$(call "$ADMIN" POST /api/chat/channels "{\"room_id\":\"$ROOM_PRIV\",\"name\":\"Suite Private $STAMP\",\"code\":\"prv${STAMP}\",\"visibility\":\"private\"}")
check "an administrator lists a private channel" "$PRIV" '"ok":true'
check "a payload that names no visibility makes it private" \
  "$(call "$ADMIN" POST /api/chat/channels "{\"room_id\":\"!suite${STAMP}unset:matrix.johnethel.school\",\"name\":\"Suite Unset $STAMP\",\"code\":\"uns${STAMP}\"}")" '"visibility":"private"'

# --- 3. What each role sees -----------------------------------------------------
STUDENT_LIST=$(call "$STUDENT" GET /api/chat/channels)
check "a pupil sees the public channel" "$STUDENT_LIST" "Suite Public $STAMP"
absent "a pupil does not see the private one" "$STUDENT_LIST" "Suite Private $STAMP"
ADMIN_LIST=$(call "$ADMIN" GET /api/chat/channels)
check "an administrator sees the private one" "$ADMIN_LIST" "Suite Private $STAMP"
check "with the code that opens it" "$ADMIN_LIST" "PRV${STAMP}"

# --- 4. The code is what opens a private channel --------------------------------
check "the code turns the channel up" "$(call "$STUDENT" GET "/api/chat/channels/lookup?code=PRV${STAMP}")" "$ROOM_PRIV"
check "lower case is the same code" "$(call "$STUDENT" GET "/api/chat/channels/lookup?code=prv${STAMP}")" "HTTP 200"
check "a code nobody holds is a 404, not an empty list" "$(call "$STUDENT" GET "/api/chat/channels/lookup?code=NOSUCH")" "HTTP 404"
check "and asking with no code at all is a 400" "$(call "$STUDENT" GET "/api/chat/channels/lookup")" "HTTP 400"

# --- 5. Codes are unique, and can be retired ------------------------------------
check "a code another channel holds is refused" \
  "$(call "$ADMIN" POST /api/chat/channels "{\"room_id\":\"!suite${STAMP}dup:matrix.johnethel.school\",\"name\":\"Suite Dup $STAMP\",\"code\":\"PRV${STAMP}\"}")" '"error":"code_taken"'
check "re-listing a channel answers again" \
  "$(call "$ADMIN" POST /api/chat/channels "{\"room_id\":\"$ROOM_PRIV\",\"name\":\"Suite Private $STAMP\",\"code\":\"NEW${STAMP}\",\"visibility\":\"private\"}")" '"ok":true'
check "the retired code opens nothing" "$(call "$STUDENT" GET "/api/chat/channels/lookup?code=PRV${STAMP}")" "HTTP 404"
check "and the new one opens the channel" "$(call "$STUDENT" GET "/api/chat/channels/lookup?code=NEW${STAMP}")" "$ROOM_PRIV"
check "the room is listed once, not twice" "$(sql "SELECT count() FROM chat_channel WHERE room_id = '$ROOM_PRIV' GROUP ALL;")" '"count":1'

# --- 6. What a listing will not accept ------------------------------------------
check "a room id that is not one" "$(call "$ADMIN" POST /api/chat/channels "{\"room_id\":\"suite-nonsense\",\"name\":\"X\",\"code\":\"BAD${STAMP}\"}")" "HTTP 400"
check "a channel with no name" "$(call "$ADMIN" POST /api/chat/channels "{\"room_id\":\"!suite${STAMP}noname:matrix.johnethel.school\",\"name\":\"\",\"code\":\"NAM${STAMP}\"}")" "HTTP 400"
check "a channel with no code" "$(call "$ADMIN" POST /api/chat/channels "{\"room_id\":\"!suite${STAMP}nocode:matrix.johnethel.school\",\"name\":\"Suite No Code $STAMP\",\"code\":\"\"}")" "HTTP 400"
LONGNAME=$(python3 -c "print('N' * 121)")
check "a name longer than a channel name" \
  "$(call "$ADMIN" POST /api/chat/channels "{\"room_id\":\"!suite${STAMP}long:matrix.johnethel.school\",\"name\":\"$LONGNAME\",\"code\":\"LNG${STAMP}\"}")" "HTTP 400"

# --- Done: take the suite's own rooms back out ---------------------------------
sql "DELETE chat_channel WHERE room_id CONTAINS 'suite${STAMP}';" > /dev/null 2>&1

printf '\n%s/%s checks passed\n' "$pass" "$((pass+fail))"
[ "$fail" -eq 0 ]
