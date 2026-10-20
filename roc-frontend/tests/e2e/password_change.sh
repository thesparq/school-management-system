#!/bin/sh
# The password-change requirement over the API: a login whose password was chosen by an administrator —
# the account was created with one, or an admin reset it — is refused everywhere except the two routes
# that answer that state, until the person sets a password of their own. That is the point of the rule:
# a password somebody else knows is not one to read the school's data with.
#
#   APP_URL=http://127.0.0.1:8000 sh tests/e2e/password_change.sh
#
# Sandbox backend with the mock Authentik (see README.md). The created login is driven by a JWT whose
# `sub` names it, which is how the mock's userinfo answers for a login it has.

B=${APP_URL:-http://127.0.0.1:8000}
C="Content-Type: application/json"
T="Authorization: Bearer ${AUTH_TOKEN:-dev-skip}"
STAMP=$(date +%s)
pass=0; fail=0
check() { # $1 label, $2 actual, $3 expected substring
  case "$2" in *"$3"*) echo "PASS  $1"; pass=$((pass+1));; *) echo "FAIL  $1 — got: $(echo "$2" | head -c 200)"; fail=$((fail+1));; esac
}
call() { # $1 token, $2 method, $3 path, $4 body (optional) -> "<body> HTTP <status>"
  if [ -n "$4" ]; then
    curl -s -w ' HTTP %{http_code}' -X "$2" "$B$3" -H "Authorization: Bearer $1" -H "$C" -d "$4"
  else
    curl -s -w ' HTTP %{http_code}' -X "$2" "$B$3" -H "Authorization: Bearer $1"
  fi
}
# A token the mock's userinfo honours for one login: `sub` names it, `groups` gives its role.
jwt() { # $1 sub, $2 group
  python3 - "$1" "$2" <<'PY'
import base64, json, sys, time
sub, group = sys.argv[1], sys.argv[2]
def b64u(o):
    return base64.urlsafe_b64encode(json.dumps(o).encode()).decode().rstrip('=')
claims = {'iss': 'https://auth.johnethel.school/application/o/school-management-system/',
          'sub': sub, 'exp': int(time.time()) + 3600, 'email': f'{sub}@example.com',
          'name': 'Password Check', 'groups': [group]}
print(b64u({'alg': 'RS256', 'typ': 'JWT'}) + '.' + b64u(claims) + '.sig')
PY
}

# --- 1. An account created with a password is gated until it is replaced ----------------
CREATE=$(curl -s -X POST "$B/api/users" -H "$T" -H "$C" \
  -d "{\"role\":\"Student\",\"email\":\"pw_${STAMP}@example.com\",\"first_name\":\"Pw\",\"surname\":\"Check${STAMP}\",\"date_of_birth\":\"2011-03-04\",\"class_level\":\"class_levels:jss_1\",\"passport\":\"https://example.com/pw.jpg\",\"password\":\"Admin-Chosen-${STAMP}!\"}")
PK=$(echo "$CREATE" | python3 -c "import json,sys; print(str(json.load(sys.stdin)[0]['result'][0]['id']).split(':')[1].strip(chr(96)))" 2>/dev/null)
check "a create with a password answers with a row" "$CREATE" "student_profile:"
TOK=$(jwt "$PK" "Students")

check "the login is told a change is owed" "$(call "$TOK" GET /api/me/password-state)" '"required":true'
check "and why: an account that was just made" "$(call "$TOK" GET /api/me/password-state)" '"reason":"created"'
check "the school's data is refused (403)" "$(call "$TOK" GET /api/student/subjects)" " HTTP 403"
check "with a code the page routes on" "$(call "$TOK" GET /api/student/subjects)" '"code":"password_change_required"'
check "and the refusal says what to do" "$(call "$TOK" GET /api/student/subjects)" "Choose your own password"
check "a write is refused too" "$(call "$TOK" POST /api/me/password '{"password":"short"}')" " HTTP 400"
check "and the reason names the length rule" "$(call "$TOK" POST /api/me/password '{"password":"short"}')" "8-72 characters"

# --- 2. Setting one's own password clears it -----------------------------------------
check "setting a password of one's own is accepted" "$(call "$TOK" POST /api/me/password "{\"password\":\"My-Own-Password-${STAMP}!\"}")" " HTTP 200"
check "the state now says nothing is owed" "$(call "$TOK" GET /api/me/password-state)" '"required":false'
check "and the data is open" "$(call "$TOK" GET /api/student/subjects)" " HTTP 200"

# --- 3. An admin's reset puts the requirement back ------------------------------------
check "an admin may reset it" "$(call dev-skip POST /api/users/set-password "{\"id\":\"student_profile:${PK}\",\"password\":\"Reset-By-Admin-${STAMP}!\"}")" " HTTP 200"
check "the login is gated again" "$(call "$TOK" GET /api/student/subjects)" " HTTP 403"
check "and the reason is the reset" "$(call "$TOK" GET /api/me/password-state)" '"reason":"reset"'

# --- 4. An account created without a password is not gated ----------------------------
# Nothing chose a password for it here (the admin sets one in Authentik), so there is nothing this app
# knows to ask about.
NO_PW=$(curl -s -X POST "$B/api/users" -H "$T" -H "$C" \
  -d "{\"role\":\"Student\",\"email\":\"pw_none_${STAMP}@example.com\",\"first_name\":\"No\",\"surname\":\"Pw${STAMP}\",\"date_of_birth\":\"2011-03-04\",\"class_level\":\"class_levels:jss_1\",\"passport\":\"https://example.com/np.jpg\"}")
NP_PK=$(echo "$NO_PW" | python3 -c "import json,sys; print(str(json.load(sys.stdin)[0]['result'][0]['id']).split(':')[1].strip(chr(96)))" 2>/dev/null)
NP_TOK=$(jwt "$NP_PK" "Students")
check "a login made without a password owes nothing" "$(call "$NP_TOK" GET /api/me/password-state)" '"required":false'
check "and reaches its own data" "$(call "$NP_TOK" GET /api/student/subjects)" " HTTP 200"

# --- 5. A change nothing owed has to prove the current password -------------------------
# The check is Authentik's own password grant (the mock accepts `mock-current-password` for any login it
# knows), and it is what closes the hole a stolen session would otherwise have: without it, anyone holding
# a live session could set a new password and lock the owner out.
check "a chosen change without the current password is refused" "$(call "$NP_TOK" POST /api/me/password "{\"password\":\"Chosen-${STAMP}!\"}" )" " HTTP 400"
check "and says what is missing" "$(call "$NP_TOK" POST /api/me/password "{\"password\":\"Chosen-${STAMP}!\"}")" "Enter your current password"
check "a wrong current password is refused" "$(call "$NP_TOK" POST /api/me/password "{\"password\":\"Chosen-${STAMP}!\",\"current\":\"not-it\"}")" " HTTP 400"
check "and says which one is wrong" "$(call "$NP_TOK" POST /api/me/password "{\"password\":\"Chosen-${STAMP}!\",\"current\":\"not-it\"}")" "not your current password"
check "the right current password is accepted" "$(call "$NP_TOK" POST /api/me/password "{\"password\":\"Chosen-${STAMP}!\",\"current\":\"mock-current-password\"}")" " HTTP 200"
check "and the login still works with its own data" "$(call "$NP_TOK" GET /api/student/subjects)" " HTTP 200"
# A change that *is* owed may send the current password too — and then it has to be right.
check "a wrong current password is refused even when one is owed" "$(call "$TOK" POST /api/me/password "{\"password\":\"Owed-${STAMP}!\",\"current\":\"not-it\"}")" " HTTP 400"

# --- 5. The developer's key is never gated, and cleanup ---------------------------------
check "the developer's own key is unaffected" "$(call dev-skip GET /api/me/password-state)" '"required":false'
check "cleaning up the first login answers 200" "$(call dev-skip DELETE /api/users "{\"id\":\"student_profile:${PK}\"}")" " HTTP 200"
check "and the second" "$(call dev-skip DELETE /api/users "{\"id\":\"student_profile:${NP_PK}\"}")" " HTTP 200"

echo ""
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
