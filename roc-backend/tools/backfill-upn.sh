#!/bin/sh
# Give every existing Authentik account the short spelling of its school number, so someone who types
# `JES-123` signs in as well as someone who types `JES-000123`.
#
# Why this exists: the login is the school's number, and the app stores the padded form as the username
# (`JES-000123`) and the short form (`JES-123`) as the account's `upn` attribute — the one other
# identifier Authentik's identification stage can be told to match. Accounts the app has created since
# carry it already; the ones made before do not, and nothing in the app can add it retroactively. The
# school also has to tick **UPN** among that stage's user fields in Authentik for either form to work.
#
# Idempotent: re-running only touches accounts whose `upn` differs.
#
#   AUTHENTIK_API_URL=https://auth.johnethel.school/api/v3/core/users/ \
#   AUTHENTIK_API_TOKEN=<token with user read + write> sh roc-backend/tools/backfill-upn.sh
#
# Add `DRY_RUN=1` to print what it would do without patching anything.
set -e
: "${AUTHENTIK_API_URL:?set AUTHENTIK_API_URL, e.g. https://auth.example/api/v3/core/users/}"
: "${AUTHENTIK_API_TOKEN:?set AUTHENTIK_API_TOKEN}"
export AUTHENTIK_API_URL AUTHENTIK_API_TOKEN DRY_RUN

python3 - <<'PY'
import json, os, re, urllib.request, urllib.error

base = os.environ["AUTHENTIK_API_URL"].rstrip("/")
token = os.environ["AUTHENTIK_API_TOKEN"]
dry = os.environ.get("DRY_RUN", "") not in ("", "0", "false")
pattern = re.compile(r"^([A-Za-z]+)-0*([0-9]+)$")   # EMP-000045 -> EMP-45, jes-000123 -> jes-123

def call(method, url, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token)
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read() or b"{}")

url, checked, patched, skipped = base + "/?page_size=200", 0, 0, 0
while url:
    page = call("GET", url)
    for user in page.get("results", []):
        checked += 1
        username = user.get("username") or ""
        m = pattern.match(username)
        if not m:
            continue                                  # a login that is not a school number
        short = "%s-%s" % (m.group(1), m.group(2))
        if (user.get("attributes") or {}).get("upn") == short:
            skipped += 1
            continue
        if dry:
            print("would set %s -> upn=%s" % (username, short))
        else:
            attrs = dict(user.get("attributes") or {})
            attrs["upn"] = short
            call("PATCH", "%s/%s/" % (base, user["pk"]), {"attributes": attrs})
            print("set %s -> upn=%s" % (username, short))
        patched += 1
    url = page.get("pagination", {}).get("next")
print("checked %d, patched %d, already correct %d%s" % (checked, patched, skipped, " (dry run)" if dry else ""))
PY
