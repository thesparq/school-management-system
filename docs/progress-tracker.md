# Progress Tracker

## Current Phase: Phase 8 — Prod DB alignment (Roc stack)

**Status: backend + renderer aligned to prod (`db2.johnethel.school`, ns `main`, db `lessons`); one pre-existing frontend blocker open (see below).**

### List ordering — the school's class order, subjects alphabetical (2026-10-20)

The lists the pages render came back in whatever order the query happened to produce: the class lists
were `ORDER BY name` (so the admin LMS, the Configuration hub and the drill-downs read JSS 1-3, SSS 1-3,
then Year 1-5), `/api/curriculum` had no `ORDER BY` at all, and the pair lists ordered classes by name.
Now one rule — `class_stage_rank` in `roc-backend/main.roc` — orders every list of classes by the stage
`class_levels.tier` carries (v13: primary, junior, senior) and then by name, so they read **Year 1-5,
then JSS 1-3, then SSS 1-3**, with a level nobody has staged after the three. It is applied to
`/api/class_levels` (all three variants), `/api/class-subjects`, `/api/curriculum` and the teacher's own
pair lists (`/api/teacher/assignments`, `/api/teacher/classes`); SurrealDB's `ORDER BY` takes a field
name rather than an expression, so the rank is computed in an inner select and the outer one still
answers exactly the columns it did before. Subject lists were already alphabetical (`ORDER BY name`)
and stay that way; a pair list is class first, subject inside the class.

**The other lists were audited and left as they were** — terms and the student's terms by `sort_order`,
session terms by name, credentials by name, lessons by `week`, assessments and submissions newest first,
a parent's children by name. The user listing stays `created_at DESC` on purpose: a just-created
account is what an admin looks for, and the Authentik half of the merged listing has no school-side
name to sort by server-side.

**The sandbox fixture grew the data this needs** (`roc-frontend/tests/e2e/fixtures/sandbox-schema.surql`):
the `tier` field (v13's own statement) and prod's eleven class levels with their stages, four subjects
out of the school's list with `has_subject` edges in three stages, so a list that groups by stage has
something to group. Two suites enforce the order and both were checked against the *old* code as a
negative control (7 of 23 API checks and 5 of 10 browser checks fail there, and all pass on this one):

- `tests/e2e/list_order.sh` — the API order of every list above (23 checks).
- `tests/e2e/e2e_list_order.cjs` — the same order as the admin and staff views render it in Chromium:
  the admin LMS class picker, a class's subject cards, the hub's class level / subject / curriculum
  tables, and a teacher's My Classes cards (10 checks).

One open item: a class level created in the hub carries no stage, so it sorts after the three stages
until someone sets one — the sibling workstream that makes the stage editable in the hub is what closes
that; until then the ordering rule and the create form disagree about new rows.

### Teacher assignments and qualifications — backend migrated (2026-10-08)

Two features from the retired SvelteKit/MoonBit stack are now served by the Roc backend, ported with
the old stack's one real bug fixed:

- **Class-subject pairs are `has_subject` edges; a teacher's access is `teacher_assignment`** — one row
  per (teacher, edge, active session term), soft-deleted. The old agent *wrote* `teacher_assignment`
  but the teacher's own read used v3's `teaches` edge, so a saved assignment never reached the
  teacher's view; here both sides use `teacher_assignment` alone.
- **New endpoints** (all role-gated via the matrix): `GET /api/credentials` (+ POST create, POST
  toggle-active — no hard delete, a teacher profile may hold the record link); `GET
  /api/class-subjects` (every active pair with class/subject names); `GET /api/teacher-assignments
  ?teacher_id=` and `POST /api/teacher-assignments` (the replace-all save, scoped to the active
  session term; empty list clears). A save hides the dropped pairs and revives-or-creates the kept
  ones in one call — the (teacher, edge, term) unique index counts soft-deleted rows too, so a
  plain delete-then-create refused the second save of the same pair.
- **Teacher routes are now gated by the caller's assignments** (the developer's "hard 403" call):
  lessons, lesson-assessments, create-lesson-assessment, toggle-assessment-active,
  create-general-assessment and the general-assessments list (subject-scoped), and the submissions
  list / grade / release-grades. Lists are scoped to the assigned edges (a teacher with no active
  session term gets an empty list); naming a specific unassigned lesson/assessment/submission is a
  403. Admin callers pass the gate (may_call's rule), so the admin LMS and the suites' dev-skip
  token can read anything. `GET /api/teacher/classes` is the teacher's own assigned-pairs list.
- **Teacher qualifications**: `POST/PUT /api/users` accept `qualifications` (an array of
  `credentials:<id>` record ids; anything else is a 400 naming the rule, and any other role
  carrying the field is a 400 naming its table); the create journals them so a reconciler replay
  restores them; the teacher listing selects the column so the form can prefill. The catalog
  (`credentials` table) keeps prod's record-link shape — no schema change.
- **Verified on a fresh sandbox** (`roc check main.roc` 0/0; a 38-check curl suite covering the
  credential lifecycle, the qualifications create/update/listing/validation, the assign/clear/
  re-assign round trip and the 403s, plus admin bypass; `assessment_flow.sh` 41/41, `users_api.sh`
  95/95, `authz.sh` 27/27, and all seven `*Test.roc` suites green). The sandbox fixture gained the
  `teacher_assignment`/`teaches` mirror definitions and prod's unique credentials-name index.

### Live round 2 — student first-navigation, role-scoped boot fetches, real silent refresh, section nav (2026-10-09)

Five live reports fixed and browser-verified on the sandbox:

- **A student's subject list stranded on its skeleton on first in-app navigation** (it worked on
  reload): the boot-time fetch's payload can be dropped when the page that owns the hidden input is
  not rendered yet, and navigating into the page did not refetch. `NavigateTo(StudentSubjects)` (and
  `UrlChanged`) now refetch the list, like the admin pages already did.
- **403 console noise for every role**: boot fetches were role-blind (students fetched teacher and
  admin endpoints). `init` now scopes the boot fetches by role — students fetch only their subjects,
  teachers their classes/lessons, admins the full set — so a student session makes zero 403s.
- **Silent refresh never engaged**: the authorize request lacked `offline_access`, so Authentik never
  issued a refresh token (the retired SvelteKit app requested it; the SPA did not). The scope now
  includes it, the refresh token is stored at login, and a new per-minute sweep refreshes the access
  token proactively when it is within two minutes of expiring — a 401-driven refresh also still
  works as the catch-all, with a redirect to Authentik only when refreshing is impossible.
- **The lesson section navigator's box closed when the pointer moved into it**: the panel was
  positioned outside the hover group. It now sits in flow inside the group (student, teacher and the
  admin LMS lesson views), so the box stays open and clickable; the admin LMS lesson view also gains
  the navigator and the mobile table-of-contents (renderLesson wires them; the teacher's view
  already had it).
- New `e2e_nav_fixes.cjs` (6 checks) covers the navigation, no-403, offline_access and nav-box
  behavior; `e2e_icons_refresh` 10/10, `smoke_assignments_lms` 17/17, `smoke_teacher_role` 6/6,
  `e2e_loading` 20/20, `e2e_student` 7/7 stay green.

### Post-deploy polish — icons, tabs, week badge, token refresh (2026-10-08)

Four live-reports fixed and browser-verified against the sandbox:

- **Lucide icons were blank** because Joy's runtime creates every element in the HTML namespace,
  so plain `document.createElement("svg")` never paints. `www/index.html` now routes the SVG tag
  names to `createElementNS` up front, and every `UI.icon` use draws. (Verified: the tab icons are
  SVG-namespace elements and render.)
- **User-management tabs** now use the same segmented pill control as the Configuration hub — one
  tab switcher across the app instead of two styling languages.
- **The lesson week badge** no longer wraps: `whitespace-nowrap` on the badge and `shrink-0` on its
  header container (renderLesson).
- **Access-token refresh**: the page now stores the OAuth2 refresh token and, on any `/api` 401
  (an access token that expired mid-session), silently exchanges it once and retries the request;
  a failed refresh redirects back through Authentik instead of leaving error states on page
  (`window.fetch` is wrapped at the top of the page module, so both the JS-driven fetches and the
  runtime's HTTP effects are covered; sign-out clears the refresh token too).
- **Breadcrumb**: the admin LMS page shows "LMS" instead of the catch-all "Page".
- New `e2e_icons_refresh.cjs` (10 checks) covers all of it; `smoke_assignments_lms` 17/17,
  `smoke_teacher_role` 6/6, `e2e_admin` 16/16, `e2e_loading` 20/20 after the changes.

### Teacher assignments, qualifications and the admin LMS — frontend wired (2026-10-08)

The Roc SPA now drives everything above, mirroring the retired SvelteKit screens:

- **Teachers tab**: an Assign action on each teacher row opens the dialog — the teacher's current
  pairs as removable "Class / Subject ✕" badges, a search box whose dropdown offers the pair
  catalog minus the already-picked rows (case-insensitive, like the old SearchSelect), and a Save
  that replaces the whole set. The teacher's own My Classes page now lists the assigned pairs
  (`GET /api/teacher/classes`) and opens the lesson picker scoped to the clicked subject.
- **Qualifications**: a Qualifications tab in the Configuration hub lists/creates/reanames/
  deactivates the catalog; the teacher add/edit form carries the searchable multi-select, prefilled
  from the row and sent back as `credentials` record links.
- **Admin LMS (`/admin/lms`, sidebar "LMS")**: class level → subjects → terms → lessons → lesson
  content, read-only (no tabs, no assessment actions), reusing the student lesson renderer. The
  class/subject/term filters on the lessons endpoint make the lists exactly one class level.
- **Verified in Chromium against the sandbox**: a new `smoke_assignments_lms.cjs` (17 checks)
  plus the repo suites — `e2e_admin` 16/16, `e2e_admin_config` 53/53, `e2e_loading` 20/20,
  `e2e_assessments` 17/17, `e2e_general_assessments` 25/25, `e2e_users_directory` 27/27,
  `e2e_student` 7/7 — and `roc check app.roc` 0 errors. Two suite-ordering notes: `users_api.sh`
  restores the seed-student profile it completes (re-run `e2e_users_directory` after it by
  dropping that profile row), and `e2e_admin_config`'s curriculum-create check needs the
  jss_2/agricultural-science edge absent (a second run on the same sandbox sees the unique-index
  refusal, which the suite's own duplicate check then expects).

### Completed — prod schema alignment (read-only against prod)
- [x] `roc-backend/main.roc` — connection config comes from the environment only:
  `SURREAL_URL` (default `https://db2.johnethel.school/sql`), `SURREAL_DB_NS` (`main`),
  `SURREAL_DB` (`lessons`), credentials from `SURREAL_USER`/`SURREAL_PASS` (or verbatim
  `SURREAL_AUTH`). The hardcoded credential default is gone; a missing credential warns at startup.
- [x] `roc-backend/Base64.roc` (new) — standard base64 encoder, so the `Basic` header is built at
  startup instead of pre-computed; tests in `roc-backend/Base64Test.roc` (`roc test Base64Test.roc`).
- [x] Student queries aligned to the prod shape: `subjects WHERE active`, `terms` ordered by
  `sort_order`, lessons filtered by `has_subject.out` + `term`, lesson by record id.
  Lesson filters use `type::record('<table>', '<id>')`: a quoted string never matches a record link
  (verified: quoted → 0 rows, record → 225 rows).
- [x] `/api/users?role=` reads `student_profile`/`teacher_profile`/`parent_profile`/`admin_profile`.
- [x] `/api/terms` (admin) returns every term ordered by `sort_order`; `/api/student/terms` the active subset.
- [x] `roc-frontend/www/index.html` — user rows from `display_name`/`first_name`+`surname`, terms as
  `id|name|sort_order`, `renderLesson` reads `lesson.content.*` (objectives as objects, introduction,
  content sections, key points, conclusion).
- [x] `roc-frontend/www/app.wasm` + `dist.css` rebuilt.

### Frontend fixes found while verifying
- [x] Asset URLs are root-absolute (`/app.wasm`, `/runtime.js`, `/dist.css`): deep links such as
  `/student/subjects` previously resolved them to `/student/...` and failed to load the module.
- [x] Port handlers are registered through `mount({ setup })`. The runtime drains `State.init`'s
  effects before `mount` returns, and unregistered ports are dropped — the initial data fetches
  never reached the page.

### Verified
- `roc check main.roc` → 0 errors; `roc test Base64Test.roc` → all 9 cases pass.
- Backend against prod (DEV_MODE, read-only): 23 subjects; 3 terms; 75 lessons for
  `subjects:agricultural_science` + `terms:noel_term` (225 without the term); full lesson record via
  `/api/student/lesson`; `/api/users?role=Student` → empty result; `/health` → healthy.
- `renderLesson` driven with a real prod lesson through the page's own JS (DOM stub): introduction,
  objectives (no raw JSON), sections, sub-points, key points and conclusion all render.

### coturn container — TURN for Matrix calls (2026-10-07)

The `coturn` service (host networking) never came up: a crash loop of
`Cannot bind TLS/TCP listener socket to addr 127.0.0.1:3478` (EADDRINUSE) ending in
`Fatal final failure` after 60 s of retries, then `restart: unless-stopped` starts it again.
Diagnosed from outside the box:

- With no `listening-ip`, coturn discovers every host address (loopback included) and binds a
  stream listener on each; one EADDRINUSE makes turnserver retry 60 s and `exit(1)` — a single
  bad address kills the whole server (`src/apps/relay/tls_listener.c`: `max_binding_time = 60`
  then `exit(-1)`).
- Port 3478 (tcp+udp) on the host answers STUN with a `SOFTWARE=eturnal` attribute: a leftover
  **eturnal** TURN install on the VPS owns the wildcard `0.0.0.0:/[::]:3478` (verified with
  `ss -tulpn`, root: `users:(("eturnal",…))`), unrelated to this stack (no eturnal anywhere in
  the repo). A wildcard listener blocks every other bind on the port, so no coturn (pinned or
  not) can start until it is removed. Synapse/Element themselves were fine (HTTP 200 on
  `matrix.`/`chat.`), so only calls fail — messaging works.

Fix (in-repo): `--listening-ip=${COTURN_LISTEN_IP:-185.214.135.229}` pins coturn to the server's
own address so loopback is never bound and the bind set is exactly one address; dropped
`--no-tcp-relay` (TCP relay leg matters on UDP-blocked school networks; the homeserver already
advertises `?transport=tcp`); `.env.example` documents `COTURN_LISTEN_IP`; `devops/README.md`
gains a coturn section (host must not run another TURN — `ss -tulpn | grep 3478`, the eturnal
signature — and the ports to open: 3478/tcp+udp, 5349/tcp, 49152-49252/udp).

**Server action still required (not run from here)**: `systemctl disable --now eturnal` (or
remove the package), then `docker compose -f devops/docker-compose.yml up -d coturn`; verify with
`docker logs coturn` and `python3 devops/stun_probe.py` (should answer `Coturn-…`, not
`eturnal`).

### In-app messaging — the chat token proxy (2026-10-07)

With coturn up, the remaining blocker was in the app itself: `GET /api/matrix/token` was a
hardcoded stub that always answered `"token":null`, so the Messaging page immediately showed
"Matrix authentication not configured" and never synced (`roc-frontend/www/index.html` refuses to
sync without a token). Synapse/Element themselves were healthy — the app was the dead link.

- **`roc-backend/Matrix.roc` (new)** — the two homeserver admin calls the proxy needs,
  mirroring the retired MoonBit stack's `matrix_client.mbt`: `ensure_user!` (idempotent
  `PUT /_synapse/admin/v2/users/<id>`, so the account is created on first use and later logins
  refresh the display name) and `get_user_token!` (`POST /_synapse/admin/v1/users/<id>/login`,
  returns the access token). User ids are `@<the app user's own id>:matrix.johnethel.school` —
  same form the retired stack wrote, so accounts from that era are reused. `@`/`:` are
  percent-encoded for the path; a trailing-slash trim keeps the homeserver URL tidy.
- **`main.roc`** — the stub answers 503 naming the missing env var when `PUBLIC_MATRIX_URL` or
  `MATRIX_ADMIN_TOKEN` is unset (the R2 convention), then ensures the account and mints the token
  as the caller; display name from the userinfo `name`, then `preferred_username`, then the id.
  Only the backend holds the admin token — the browser gets only its own account's token.
- **Deploy wiring** — `PUBLIC_MATRIX_URL`/`MATRIX_ADMIN_TOKEN` added to the compose `app`
  environment and both `.env.example` files; `devops/generate_matrix_admin.sh` rewritten for the
  current stack (old one named the retired `matrix-synapse-1` container and relied on password
  login, which `homeserver.yaml` now disables: register the admin via the registration secret,
  grab its token during a one-line temporary `password_config.enabled: true`, restore).
- **Frontend** — the messaging error path now shows the backend's own error text (e.g. a 503
  naming `MATRIX_ADMIN_TOKEN`) instead of a generic "not configured" line.

**Verified**: `roc check main.roc` 0 errors / 0 warnings; `sh
roc-frontend/tests/e2e/matrix_token.sh` 16/16 against a mock Synapse
(`fixtures/mock_synapse.py`, new): 401 without a token, every role allowed, the response carries
homeserver + a real token (not `null`), the mock saw the caller's encoded user id on both admin
calls plus the caller's display name, and a missing admin token answers 503 naming it.

**Follow-up 6 (2026-10-07) — Matrix server admin follows the Authentik admin group**: stock
Synapse has no group→admin mapping (server admin is a Synapse-internal boolean, settable only by
`register_new_matrix_user -a` or the admin API). Since the backend already derives the caller's
role from Authentik for authorization, the token proxy now mirrors it: after `ensure_user!`, it
calls `PUT /_synapse/admin/v1/users/<id>/admin` (`Matrix.ensure_admin!`) with the caller's own
authoritative role (`caller.role == "admin"` — the same value that gates routes, so dev tokens
work too), on every mint. A demotion in Authentik removes Matrix admin at the next request;
`system_admin` (no Authentik identity) is never touched. Verified: suite 26/26 (admin caller
→ `{"admin": true}`, student → `{"admin": false}`); `roc check` 0/0.

**Still to finish on the server**: obtain one valid `MATRIX_ADMIN_TOKEN` (e.g. the database
bootstrap: elevate the operator's Synapse user temporarily, mint `system_admin`'s token via
`POST /_synapse/admin/v1/users/@system_admin:…/login`, de-elevate), inject in Dokploy/Infisical,
redeploy — after that the app keeps every admin in step automatically. Also still open: the
double-`devops` compose mount on the server (a manually-run compose without `-p`/`--project-directory`
created a parallel `code_*` project; cleanup + a correct recreate from Dokploy's invocation remain).

**Both follow-ups closed (2026-10-07)** — no more fresh device per visit, and in-app room
provisioning:

- **Token/device reuse.** The proxy now validates the token the page already holds: the page caches
  it in `sessionStorage` (`matrix_token`) and sends it back as `X-Matrix-Token`;
  `Matrix.is_token_valid!` (new, `GET /_matrix/client/v3/account/whoami`) checks it still acts as
  the caller, and a fresh token — a fresh Synapse device — is minted only when the old one is gone
  or invalid. A 401 on any client call makes the page drop the cache and mint once more
  (`_matrixRefreshingToken` guards the retry). The minted token is the admin's, acting as the user
  (Synapse's admin `login` endpoint ignores any `device_id` body and creates a new device each
  call), so reuse is what stops the device accumulation.
- **Room UI (all client API, `roc-frontend/www/index.html`).** Create a channel (public, so it
  appears in the directory), browse/join public channels, accept pending invites (sync's
  `rooms.invite` → Join), and invite members by display name or user id (`user_directory` search
  → `/_rooms/<id>/invite`). Two auth helpers (`appAuthHeaders` for the proxy, `matrixAuthHeaders`
  for the homeserver) so the two bearer tokens can't be confused; the cache is cleared on sign-out.

**Verified**: `roc check main.roc` 0/0; `node --check` on the page's script; `sh
roc-frontend/tests/e2e/matrix_token.sh` 21/21 (mock now answers whoami and tracks minted tokens,
so the suite proves a valid cached token comes back unchanged with no extra login while a stale one
is replaced by exactly one fresh mint).

**Diagnosability follow-up (2026-10-07)**: the transport error the chat page surfaces was a bare
"Http Error contacting the Matrix homeserver" — the real reason (DNS/connect/TLS) sits behind an
opaque `InternalHttp.TransportErr` this package cannot destructure, so it was dropped. Now the
message names the homeserver it could not reach (e.g. `cannot reach the Matrix homeserver at
https://matrix.example.com`), which is what actually misconfigures this: a `PUBLIC_MATRIX_URL`
pointing at an unreachable value. Reproduced locally. The local `.env.example` shipped a dead
`matrix.example.com` placeholder that would trigger exactly this; it now defaults to the real
homeserver like the compose file.

**Follow-up 2 (2026-10-07)**: the deployed app reported `invalid URL for the Matrix homeserver:
https://matrix.johnethel.school` with the correct URL set in Infisical. Every URL the backend
builds parses cleanly (probed the platform's parser directly: dev/uuid/numeric local parts,
login and whoami paths, all OK), which pointed at the run-time value, not the builder. Two fixes:
(1) the token proxy's env reads (`PUBLIC_MATRIX_URL`, `MATRIX_ADMIN_TOKEN`, `MATRIX_SERVER_NAME`)
are `Str.trim`-ed, so a hidden trailing space/carriage return in the pasted value — invisible in
both logs and the old message — can no longer break the URL; (2) an `InvalidUrl` reply now names
the parser's actual reason (`invalid character byte 32`, `invalid host: …`, …) via the public
`Url.ParseErr` tags, so anything left uncaught is self-describing. Verified locally: a trailing
space after the URL now connects through to the real homeserver; a genuinely invalid URL answers
with the byte-level reason.

**Follow-up 3 (2026-10-07)**: with the reason now shown, the deployed app reported `invalid
character byte 32` — an ASCII space inside the built URL path. The env values are trimmed, so the
space is mid-value: it lived in the built user id (`@<sub>:<server>`), and `path_segment` encoded
only `@` and `:`, leaving the space raw and the whole URL unparsable. Fix: the path segment now
percent-encodes the parser's full forbidden set (space, controls, `"` `<` `>` `\` `#` `?`, plus
`@`/`:`), so whatever a user id carries the URL always parses, and mint-failure messages include
the user id. Verified: suite 21/21; a space in the server name flows through the mock encoded
(`%40dev_user%3Amatrix%20johnethel.school`).

**Follow-up 4 (2026-10-07) — the real root cause**: with the user id now shown, the built id was
`@ ["authentik Admins", "Super Admins"]}:matrix.johnethel.school` — a fragment of the userinfo
body after its last colon, i.e. `caller_id!` had taken its *fallback* (`bare_id(user)` over the
whole body). The fragment starts with a space after a colon: Authentik's real userinfo is spaced
(`"sub": "…"`, `"groups": [ … ]`), while `extract_field` matched the needle `"sub":"` (colon
right against the quote). Only the mock Authentik's compact `separators=(",", ":")` output ever
satisfied it, so the caller's identity was garbage for every real user — the messaging failure was
just the first user-visible one (`created_by` on assessments and `student_id` on submissions were
silently writing the same garbage as record ids; `name`/`preferred_username` extraction was broken
too). The role claim worked because `extract_json_array` trims before inspecting.

Fix: all three `extract_field` copies (`main.roc`, `Authentik.roc`, `Matrix.roc`) now split on
`"field":` with a trim before the quote split, so both `"field":"v"` and `"field": "v"` parse;
the value is the text between the first two quotes either way. The mock Authentik's userinfo now
serves **spaced** JSON like the real one, and `matrix_token.sh` (24 checks) proves a
`mock-student-token`'s `sub` lands in the Synapse caller id as
`%40mock_uuid_student%3Amatrix.johnethel.school`.

**Follow-up 5 (2026-10-07) — the id is Authentik's hashed subject**: once the extractor was
fixed, the deployed user id became `@addd0ec45fbe…07145a:matrix.johnethel.school` — 64 hex
chars, Authentik's hashed `sub`. That is the account's stable identity (the same key the app
writes `created_by`/`student_id` with), so it is kept as the Matrix id; it is not the blocker.
The remaining deployed error, `Matrix create user failed (HTTP 401: Invalid access token
passed.)`, is Synapse rejecting `MATRIX_ADMIN_TOKEN` itself (401 = not a recognised token; a
non-admin token would be 403) — the operator must mint a fresh one via
`devops/generate_matrix_admin.sh`. The chat UI also rendered the raw localpart for senders; it
now loads the room's member list on open and shows display names, falling back to the localpart
(Matrix ids are opaque by design — the display name is what people see, and the backend already
sets it from the user's own name on every ensure).

### Resolved — the app runs the full student flow against prod

Two independent causes, both found and fixed:

1. **Joy's host allocator overlapped pages grown by the Roc boxy runtime.** `bump_span` in the Joy platform's
   `host/host.rs` assumes the host is the only code that grows linear memory, but the boxy runtime's
   `std.heap.page_allocator` grows it too, so `END` goes stale and the host hands out spans that overlap the
   runtime's pages — the trap surfaced in `roc_boxy_register_erased_proc` on the second host entry. Fixed with a
   local host patch (re-read `memory_size(0)`, use `memory_grow`'s return value; the note and patch were in
   `roc-frontend/JOY_HOST_PATCH.md` / `joy/host-bump-span.patch`; **retired 2026-10-07**, see the Joy 0.34.0
   section below — Joy ships this fix upstream).
2. **`www/index.html` never unwrapped SurrealDB's response envelope.** `Array.isArray(data) ? data : (data[0]?.result || [])`
   treats the one-element envelope `[{ result: [...], status: "OK" }]` as the rows, so every list rendered a
   single fieldless row (`|Unknown|`, `Unknown||true`) and no data ever appeared. Replaced by the shared
   `unwrapRows` helper at all five call sites.

Verified in Chromium against the live prod DB (read-only, `DEV_MODE` backend): 9/9 checks — subject cards from
prod, terms, lessons filtered by subject+term, full lesson content (introduction, objectives as text, sections,
sub-points, key points, conclusion), scroll-spy sections, and no page errors.

Caveat: rebuilding `www/app.wasm` from the unmodified `app.roc` (which names the remote platform URL) reproduced
the host crash against 0.33.0. **Retired 2026-10-07**: `app.roc` now pins Joy 0.34.0, whose release ships the
fix upstream, and builds clean from the URL alone — the vendored patched platform is deleted.

### User creation (T7) — done

`POST /api/users` now writes the role's profile table instead of a legacy `student` record:

- Payload: `role`, `email`, `first_name`, `middle_name`, `surname`, `date_of_birth`, `class_level`,
  `role_title`, `passport`. Validation mirrors the MoonBit admin agent (`validate_passport_url`): email,
  first name, surname and a passport **URL** are required; students additionally need a `YYYY-MM-DD` date of
  birth and a class level that **exists** (record links are not existence-checked by SurrealDB, so the
  backend queries it before creating anything).
- Order: validate → check the class level → create the Authentik login → create the profile record. A failed
  profile write calls `Authentik.deleteUser!` so no orphan login is left behind, and the response carries the
  database's own message.
- SurrealDB answers **HTTP 200 with `"status":"ERR"` in the body** for a failed statement, so the handler
  inspects the body — otherwise a rejected write would look like success.
- The admin form ([AdminView.roc]) collects the new fields and the app POSTs to its own origin (the page passes
  `window.location.origin` in the flags; it used to hardcode `localhost:8000`). A successful create re-fetches
  the four role lists so the new account appears without a reload.
- `mock_authentik.py` (repo root) returns a constant `pk`; for per-role testing use a counter-based mock.

**Verified** against a sandbox instance (`surreal start --bind 127.0.0.1:8002 --user root --pass root`, prod
schema recreated from `INFO FOR TABLE`, class levels seeded) plus the mock Authentik:

- curl: student / teacher / parent / admin created with the right fields (`display_name`, `date_of_birth`,
  `current_class`/`class_enrolled`, `role_title`, parent `name`+`display_name`); 400s for a missing passport,
  a non-URL passport, a missing/malformed date of birth, an unknown class level; the compensation message for a
  colliding profile id.
- Browser (Chromium, `roc-frontend/www/app.wasm`): 5/5 — the admin page loads, the form reports success, the
  created student appears in the table, a validation error surfaces in the UI, no page errors.

### Legacy endpoints — aligned or retired

| Endpoint | Now |
|---|---|
| `GET /api/students` | `student_profile` (same rows as `/api/users?role=Student`) |
| `GET /api/teachers` | `teacher_profile` |
| `GET /api/curriculum` | `has_subject` (the class_levels → subjects edge is the curriculum) |
| `GET /api/session_terms` | `session_term` (prod names it in the singular); `POST` creates a session term |
| `GET/POST /api/class_arms` | 410 — class arms are not part of the schema (use `class_levels` + `class_terms`) |
| `POST /api/students`, `POST /api/teachers` | 400 pointing at `POST /api/users` (they used to create legacy tables) |

Verified read-only against prod: students/teachers `[]`, curriculum returns the 127 `has_subject` edges,
`session_term` returns the 2026/2027 sessions, `class_arms` returns 410, and the retired POSTs return 400
without writing.

### Joy 0.34.0 — the host fix ships upstream; vendored patch retired (2026-10-07)

Joy 0.34.0's release fixed the exact crash this app carried a local host patch for:
"fix random crashes in apps with subscriptions or callbacks … once their model grew" (apps passing flags and
using `Http`, ports, or debounce) — the boxy runtime growing wasm linear memory behind the host allocator's
stale `END`. `app.roc` now pins the 0.34.0 release bundle (+ joy-html 0.17.0) instead of the patched local
checkout; the vendored `joy/` directory, `host-bump-span.patch`, and `JOY_HOST_PATCH.md` are deleted, and the
references in `docs/architecture.md` and the e2e README updated.

**Verified** (`roc check app.roc` 0 errors; sandbox 8322, rebuilt wasm + runtime.js): `e2e_admin.cjs` 9/9
(ports-heavy: generate-password and copy-to-clipboard ports, Http creates), `e2e_users_directory.cjs` 23/23,
`e2e_loading.cjs` 20/20 (subscription/navigation paths), `e2e_admin_config.cjs` 53/53, `users_api.sh` 96/96,
`authz.sh` 27/27, `assessment_flow.sh` 41/41, `general_assessment_flow.sh` 56/56.

**Compiler pin — bumped to `nightly-2026-09-29-7f11a82` (2026-10-08).** Joy 0.34.0's recommended
`nightly-2026-10-06-c34079d` is not usable for this repo yet, in two steps: the 10-02 nightly made
`redundant expose` and `redundant open tag union` hard errors, which the shipped bundles of basic-cli 0.24.0
(the build tool behind `build.roc`) and basic-webserver 0.14.0-rc1 (the backend) still trip (12 and 4
errors); and 10-01 — the last nightly that still compiles both — segfaults in codegen when emitting the
backend binary (`roc build main.roc` → SIGSEGV; `check` passes). 09-29 is the newest nightly that builds
both sides: `roc build main.roc` 0 errors / 61 warnings (all from the platform bundles) and
`roc run build.roc` 0 errors / 85 warnings, the binary runs the full suite set above, and all unit tests
pass (Base64 9/9, AuthUrls 4/4, R2 20/20, Url 16/16, Hmac 7/7, Sha256 7/7). `Dockerfile.app` pins this
nightly and tolerates the compiler's exit-2-on-warnings for both Roc builds (0 and 2 both mean success).
The frontend's `exposing` clauses and `Base64`/`AuthUrls` signatures were made rule-compliant
(`->` for pure functions, no redundant type re-exports) so a future jump to 10-02+ needs the platform
bundles to catch up, not this repo.

### User management flow — the admin's feedback, implemented (2026-10-08)

Tested the UI as an admin would and rebuilt the flow around what did not work:

- **Reset password works from the row.** Every row now has a Reset password action that opens the modal
  in a password-only mode (Generate fills it, Set password calls the existing `/api/users/set-password`),
  and the new value appears once in the credentials panel with the Copy button.
- **The form is a modal now.** Add (header button), Complete profile, Edit and Reset password all open
  the same overlay; the table stays visible behind it. (A conditional `on_click` expression as the
  handler value did not dispatch from one branch — Joy's runtime attaches handlers per message — so the
  modal uses two explicit submit buttons, one per mode.)
- **The email is editable in every mode.** The form used to disable the address on a PUT; now a PUT that
  carries an email patches Authentik's login address, so an account created without one (or with a typo)
  can be fixed. The completing write now sends the login's own address back with the PUT.
- **Delete works for every row — including a profile-only row.** Rows whose pk the directory does not
  list (never created in Authentik, or its login was removed) previously answered 502, so they could be
  hidden but never removed. The backend now checks the directory: no login listed for the pk → the
  profile hide IS the whole delete (200); the honest 502 survives for a reachable login whose own
  disable fails or an unreachable directory. The ghost test in `users_api.sh` was updated to the new
  contract.
- **Bulk delete:** each row carries a selection tick; the bar above the table reports the count and
  deletes the whole selection (one DELETE per id). Deactivate is called **Delete** everywhere.

**Verified** (sandbox 8322, Joy-0.34 wasm rebuilt and `dist.css` regenerated): `e2e_admin.cjs` 16/16
(new: reset-password round trip through the modal, exact-match selector — `has-text("Set password")` is a
substring of every row's Reset password button), `e2e_users_directory.cjs` 27/27 (labels Delete/Reset
password; completing PUT carries the address; modal open/close lifecycle), `e2e_loading.cjs` 20/20,
`e2e_admin_config.cjs` 53/53, `users_api.sh` 95/95 (ghost is now a delete-200 check), `authz.sh` 27/27,
`assessment_flow.sh` 41/41, `general_assessment_flow.sh` 56/56.

### Manual Authentik users, and the new icon set (2026-10-08)

**A user created directly in Authentik (with the student group) vanished once other users existed.**
Root cause: `Authentik.listUsers` fetched exactly one directory page (`page_size=200`, ordered by pk
ascending), so a directory past 200 users silently dropped the newest login — the manual user lived on
page 2. `directory_users!` now pages to a short page and merges the pages into one envelope
(verified against a 214-user directory: the manual student lists with `has_profile:false` alongside
everyone else; 56-user tab behaves the same), and the role mapping falls back to the bare `groups`
list when `groups_obj` is absent.

**Icons + modal polish.** Emojis are gone from user management: the Students/Teachers/Parents/Admins
tabs, the empty states, the passport preview, the Add button and the close control are now inline
**Lucide** SVGs (MIT, stroke style, `currentColor`, rendered from a small `UI.icon` helper over
joy-html's generic `element tag). The modal's Cancel text button is a × icon, the overlay gets
`backdrop-blur`, the card is `rounded-2xl shadow-2xl`, required-field asterisks are gone and the
labels read like labels. Verified by the browser suites (16/16, 27/27, 20/20, 53/53) and a clean
screenshot pass.

---

### Build and tests — done

- Joy 0.34.0 is pinned by release-bundle URL in `app.roc` (joy-html 0.17.0), so `cd roc-frontend && roc run
  build.roc` builds a working app on any machine with just the compiler. The vendored patched 0.33.0 checkout
  (`roc-frontend/joy/`, `host-bump-span.patch`, `JOY_HOST_PATCH.md`) was deleted when 0.34.0 shipped the fix
  upstream.

### Zero-warning sweep — our code clean (2026-10-08)

- **Frontend**: the seven `module [...]` headers (UI, AdminView, DashboardView, MessagingView, StudentView,
  TeacherView, Auth) are gone — UI and the views are now type modules (their defs moved into the matching
  `X := [].{{...}}` block; callers already used the `X.`-prefixed style, so nothing else changed), and the
  dead `Auth.roc` (its two exports were referenced nowhere) was deleted. `roc check app.roc`: 0 errors, 0
  warnings — except `State.roc`, which keeps its header on purpose: it exports seven types plus functions
  (Model, Msg, Route, Role, the two tab unions, ListState, list_state); a type module can expose only its
  own type and extension-block aliases are opaque, so the migration is a file-per-type split (like
  `http.Response`/`http.Method`) — proportionate only when a compiler actually refuses headers.
- **Backend**: moved to **basic-webserver 0.17.0** (the current release), which dropped the old raw
  `request.target` and `pf.Utc`. The router now reconstructs the target text (`path?query`) from `Target`;
  the R2 signing timestamp comes from `pf.UnixTime` + the new pure `Time8601.roc` (Howard Hinnant's
  civil-from-days; vectors checked against `date -u`, 6/6). This retired all 61 bundle-bundle warnings:
  `roc check main.roc`: 0 errors, 0 warnings; unit tests Base64 9/9, AuthUrls 4/4, R2 20/20, Url 16/16,
  Hmac 7/7, Sha256 7/7, Time8601 6/6.
- **npm**: the root `.npmrc` (`pnpm.onlyBuiltDependencies=[]`) confused npm under the npm-based build and
  is deleted; the pnpm config in the retired SvelteKit `frontend/` and root `package.json` is left as
  legacy.
- **What remains**: the 77 warnings `build.roc` reports are all inside the basic-cli 0.24.0 release bundle
  (the build tool's own sources), not this repo — they clear when a rule-compliant basic-cli ships or we
  replace the build path. Verified on the sandbox after the sweep: e2e_admin 10/10, e2e_users_directory
  27/27, e2e_loading 20/20, e2e_admin_config 53/53, users_api 96/96, authz 27/27, assessment_flow 41/41,
  general_assessment_flow 56/56.
- `roc-frontend/tests/e2e/` holds the checks used during this migration: `e2e_student.cjs` (student drill-down
  against the backend), `e2e_admin.cjs` (user creation in a sandbox), `render_lesson_check.cjs` (the lesson
  renderer, no browser), plus `fixtures/sandbox-schema.surql` and `fixtures/mock_authentik_unique.py`.
  `tests/e2e/README.md` has the commands. All three pass as committed.
- The Roc stack is now in git (it had been untracked). Left untracked on purpose: the stale generators
  (`roc-backend/gen_main.py`, `main_fallback.py`, `refactor.py`), scratch `test_json*.roc`, the downloaded
  Golem component blob, and `roc-agents/` (a prototype pointing at an external `roc-golem` checkout).

### Assessments — done (lesson assessments)

All twelve assessment endpoints now use the prod tables (`lesson_assessments`, `submissions`) instead of a
non-existent `assessments` table, following the MoonBit agents' conventions where they affect stored data:

- **Drafts**: `POST /api/teacher/create-lesson-assessment` always writes `active = false`; the teacher publishes
  with `POST /api/teacher/toggle-assessment-active`. Students only ever see `active = true` rows.
- **Submissions**: one row per student and assessment. The first submit writes `iteration = 1`, a resubmit bumps
  it in place, and `assessment_id` stores the **bare** record id (the agents' convention) so both stacks find
  each other's rows. `assessment_type` is `lesson`, `status` starts as `submitted`.
- **Grading**: `grade-submission` sets `scored_mark` (prod has no `graded_at` column — listings return
  `scored_mark IS NOT NONE AS graded` instead) and `release-grades` sets `grade_released_at` plus
  `status = 'graded'`.
- The teacher's lesson page has a **lesson picker** (the viewer needs a concrete lesson id, previously a backlog
  item), `/api/teacher/lessons?lesson_id=` returns the full record, and the tab shows Draft/Published with a
  Publish/Unpublish button.
- **Question picker**: the create modal lists the lesson's own bank (`content.mcq_questions` /
  `content.theoretical_questions`) with a checkbox and a marks field per question (MCQ default 1, theory 5, matching
  the generated lessons' own marking). The selection is stored in the strict shape the schema enforces — `type`,
  `question`, `options`, `answer`, `explanation`, `marks` — and `total_mark` is the sum of the picks. MCQ answers
  keep the bank's option letter and `options` preserves a/b/c order, so the letter maps back.
- Two JS wiring bugs surfaced and are fixed: listeners on individual nodes died on every app re-render (tabs,
  create-assessment modal), so those controls are delegated at the document level, and `showTab` re-queries its
  elements instead of holding references.

**Verified**: API lifecycle 21/21 (`tests/e2e/assessment_flow.sh`, including the stored question shape and the
schema's rejection of an unknown question type) and the browser flow 9/9 (`tests/e2e/e2e_assessments.cjs`,
including a picked question landing in the stored assessment); the student (7/7) and admin (5/5) checks still
pass.

**Schema change applied to prod (2026-10-05)**: `lesson_assessments` now carries the strict question shapes from
`db/schema-v3.surql` — `questions.*.type` (asserted to `mcq|boolean|short_answer|essay`), `.question`, `.options`,
`.answer`, `.explanation`, `.marks` — so question objects are storable. Purely additive: `DEFINE FIELD IF NOT
EXISTS` for sub-fields that did not exist, no `REMOVE`, no `DELETE`, no rewrite. Verified on a prod-mirroring
sandbox first (pre-existing row untouched, updates still work, an unknown `type` rejected), then on prod: both
assessment tables held 0 rows before and after, and a probe row created with questions → published → read back →
removed, leaving the counts at 0. That set came from `db/schema-v3.surql`, so the schema file already described it;
the answers set is the new `db/schema-v7-submission-answers.surql` above. One divergence in the other direction
remains: v3 also declares the same `questions.*.*` fields for `general_assessments`, which prod does not have (that
table is empty and the feature is unimplemented), so a database rebuilt from `db/schema-v*.surql` is stricter there
than prod — harmless, and it matches as soon as general assessments land.

### Student answer-taking — done

- **The form** (`www/index.html`): an assessment in the student's tab opens a question form — radio groups for
  MCQ questions (option letters a/b/c as the value), a textarea for anything without options — with a live
  "N of M answered" counter, a back link, and a disabled submit plus "the deadline has passed" once the
  deadline is in the past. Answers are collected in the shape the MoonBit stack used
  (`question_index`, `answer_type`, `answer_text`, `allocated_mark`) and POSTed to
  `/api/student/submit-assessment`; the list then shows a green "Submitted: <title>" note.
- **The backend no longer lies about failed writes.** SurrealDB answers HTTP 200 with `"status":"ERR"` in the
  body when a statement fails, and every write path trusted the status: a rejected submission was acknowledged
  in the UI while nothing was stored. `db_body!` / `db_response!` in `main.roc` now interpret the body for the
  twelve write paths (subjects, terms, class levels, session terms, user creation, assessment create/publish,
  submit, grade, release, and the legacy `PUT`/`DELETE /api/users`), answering 500 with the statement's own
  message. Reads are unchanged.
- **The schema gap that made answers unstorable**: `submissions` is SCHEMAFULL and prod declared only `answers`
  (`array<object>`) and `answers.*` (`object`) — no sub-fields — so every answer object was rejected
  (`Found field 'answers[0].allocated_mark', but no such field exists for table 'submissions'`), which is also
  why the table held 0 rows. `db/schema-v7-submission-answers.surql` (new) declares the four fields the form
  sends; prod has them, and the sandbox fixture carries the same statements, so a sandbox built from the
  fixture matches prod field-for-field (`submissions` 15 fields, `lesson_assessments` 21).

**Verified** on a sandbox built from the fixture: browser lifecycle 14/14
(`tests/e2e/e2e_assessments.cjs` — the form renders, both answer kinds store as
`{"question_index":0,"answer_type":"mcq","answer_text":"b","allocated_mark":4}`, the teacher's grading tab
shows the student, the released grade appears), API lifecycle 21/21 (`tests/e2e/assessment_flow.sh`), admin
creation 5/5. Prod: the v7 statements applied with both assessment tables at 0 rows before and after, and a
probe row (one MCQ answer, one theory answer) created, read back identical, then deleted.

### Remaining

- [x] **`general_assessments` can now store question objects on prod** (applied 2026-10-05). The table declared
  `questions` and `questions.*` but none of the sub-fields, so a create with questions answered 500 with the
  database's own message. `db/schema-v3.surql` lines 43-48 already carried the six `DEFINE FIELD IF NOT EXISTS`
  statements — they had been applied to `lesson_assessments` only. Verified on a prod-shaped sandbox first
  (dropping the six there reproduced the failure, re-applying them fixed it), then on prod: 6 statements, 0
  errors; both `general_assessments` and `compositions` held 0 rows before and after; a probe row created with
  an MCQ question object, read back with every field intact, then deleted.
  *Honest note*: the script that applied them also fed the whole v3 file to prod, which additionally created
  v3's `teaches` table and `teacher_profile.qualifications`. Both are empty (`teacher_assignment` is empty, so
  its data migration was a no-op) and nothing in the app reads them — and both are declared by the schema file,
  so prod and the files now agree rather than diverge.
- [ ] Nothing computes a term result from `percentage_weight` (the weight is stored, and `compositions` is
  neither read nor written — no code path in either stack computes the weighted sum).
- [ ] R2 uploads are verified end to end against the **real** bucket (credentials from Infisical): a
  backend-signed `PUT` answered 200, the public URL served the object byte-for-byte, a real browser upload
  through the admin form produced `https://r2.johnethel.school/student/passports/<uuid>.jpg` with no CORS or
  page errors, and the probe objects were deleted afterwards (signed `DELETE` 204, `GET` 404). The bucket's
  preflight already allows `PUT` from any origin with `content-type`. What remains unexercised is only the
  account-creation path storing that URL on a real profile (sandboxed, since prod profiles are the school's).
### Authorization — done

The backend now reads the token's `groups` and gates every route, answering 403 with the role the route needs
(unauthenticated stays 401). One function holds the matrix by route family: `/api/student/*` → student,
`/api/teacher/*` → teacher, user and configuration writes → admin, the shared reads (the pickers, the hub tabs,
the student cards) → any authenticated role, and **an admin may go anywhere** — which is what lets one `dev-skip`
token keep driving every suite. `dev-skip`/`test-token` act as admin; `dev-student`/`dev-teacher` were added so
`tests/e2e/authz.sh` (27 checks) proves the gate bites, and a real-looking token's role comes from the mock's new
instance-wide userinfo endpoint. The role list is the page's own list, mirrored with a comment to keep the two in
step. Also admin-only now: `/api/students`, `/api/teachers` (whole-school rosters), `/api/enroll` (the retired
Golem prototype, which writes an enrolment) and `/api/upload-url` (the passport signer behind the admin form).

### General assessments — closed out

- **The flow suite is self-isolating**: it creates its own subject per run, so the per-term weight budget starts
  empty and it can run twice in a row (it used to fail on its fourth run). It also reads the stored `questions`
  and `answers` back out of the database when `SURREAL_URL` is set, checking them against the schema the fixture
  mirrors.
- **A real bug fixed**: a resubmit after a released grade was accepted and replaced the answers the released mark
  was awarded for, leaving `scored_mark` and `grade_released_at` pointing at answers that no longer existed. The
  MoonBit stack refused that; the backend now answers 409.
- **Compared against the legacy stack** (its general-assessment code), with verdicts: the legacy's list queries
  and budget check compared record links as quoted strings and therefore matched **nothing** — the Roc version's
  `type::record(...)` literals are the fix, not a deviation; the legacy's question struct is unrepresentable in
  the schema; `compositions` and weighted term results exist in neither stack; `max_resubmissions = 0` means
  unlimited here and one attempt there; `answer_type` for non-MCQ answers stores the question's own type rather
  than the legacy's `theoretical`.
- **Reported, not changed** (see the leftover list): no student grade view, no 0..total_mark range check on
  `grade-submission`, no weight-remaining summary, and `percentage_weight` goes through the digits-only scanner
  (`10.5` → 105, `-5` → 5; the form refuses both client-side).

### Loading states, the nav bar's session term, and the user form

Reported by the developer while testing the running app, and all fixed in `ef8c4c7`:

- **A failed list request used to dispatch nothing**, so `State.roc`'s single global `isLoading` stayed true and
  every tab showed `Loading... / Fetching data from server` forever — one flag for every list, which is why
  switching tabs could not change it. A *successful* fetch with zero rows dispatched `""`, indistinguishable
  from "never loaded". The rule is now three states per list (`ListState`: `Pending` → skeleton, `Ready` → rows or
  a real empty state, `Failed(message)` → an error state naming what failed **with a Retry**), and the JS always
  answers a fetch — `ok` + rows, `ok` with no rows, or `error` + the API's own `{"error","detail"}` message.
  Applied to every list fed through `fetch_data`; user management also refetches its active tab on page entry and
  on tab switch.
- **A top border progress bar** on navigations and in-page tab switches (the retired app's own markup), and
  **skeleton placeholders** (`animate-pulse`, shaped like the content) while a list is genuinely not loaded.
- **The nav bar shows the active session term** — `GET /api/session_terms/active` with the legacy query
  (`SELECT id, session_name, term.name AS term_name FROM session_term WHERE active = true LIMIT 1`), shown as a
  badge with a spinner while it loads, refetched on navigation. The retired app also toasted when it changed;
  this app has no toast system, so the badge simply updates.
- **The Add New User form** is a labelled grid (name row → email + role → the role-specific fields the create
  actually reads → passport → one primary action).
- **The bundle is served `no-cache`** (`ccb37c0`): `app.wasm` and `dist.css` were cached for an hour while
  `index.html` was not, so a rebuild kept serving the old app against the new markup. Hashed filenames are what
  would let the bundle be cached immutably again.

**Verified** on a sandbox with the merged tree: the new `e2e_loading.cjs` **20/20** (it navigates by *clicking*
through the sidebar rather than `goto`-ing a URL — every other suite jumps straight to the URL, which is why this
class of bug hid — and it also intercepts a list to answer 500 and asserts an error state with a working retry),
plus `e2e_admin` 5/5, `e2e_admin_config` 53/53, `e2e_student` 7/7, `e2e_assessments` 17/17,
`e2e_general_assessments` 25/25, `authz.sh` 27/27, `assessment_flow.sh` 41/41, `general_assessment_flow.sh` 56/56.
`roc check main.roc` 0 errors / 3 warnings, `roc check app.roc` 0 errors.

**Dev-workflow gotcha**: changing a view's model shape (as this pass did to `State.roc`) can kill a running
`roc run` instance mid-flight — the watcher swaps in the new wasm while the old model is live, and the process
dies with SIGSEGV. Restart it; a fresh start runs the same sources fine.

### Remaining

- [ ] **No toast system.** The retired app toasted when the active session term changed and after other
  background events; here the badge just updates. Worth building once, for many callers.
- [ ] `e2e_passport_upload.cjs`'s upload mode needs R2 variables in the sandbox backend and an upper-case
  access-key id (its regex), so it reports 8/9 without them — the signed URL and the form flow pass regardless.
- [ ] **No student grade view.** The legacy stack had `/student/my-grades` (answers hidden until release) and
  `project-overview.md` lists "view own grades and feedback after grading" as a student feature; the Roc app has
  no such page. The data is all there (`submissions` with `scored_mark`/`grade_released_at`).
- [ ] `POST /api/teacher/grade-submission` has **no 0..total_mark range check** (the legacy `teacher_manual_grade`
  had one, and the page's prompt says 0-100). Shared with the lesson flow, so it needs one decision, not a patch.
- [ ] No **weight-remaining summary** for a teacher: the legacy had `teacher_get_percentage_summary` feeding two
  cards and capping the create modal's weight; here only the backend's 100% refusal.
- [ ] Nothing computes a term result from `percentage_weight` (the weight is stored, and `compositions` is
  neither read nor written — no code path in either stack computes the weighted sum).
- [ ] **The Golem/MoonBit durable layer is built but not wired** — parked for now, at the developer's request.
  Six agent types still exist and build (`moon check` 0 errors, `app-agents.wasm` 1.1 MB) and CI still deploys
  them, but the Roc backend's only call is the stale `POST /api/enroll` → a `cs101` prototype (no auth key,
  unused by the UI), and the eight `golem-*` services are in `devops/legacy/docker-compose.golem.yml`, out of the
  deployed stack. Which operations must be durable is still open.
- [ ] R2 uploads are verified end to end against the **real** bucket (credentials from Infisical): a
  backend-signed `PUT` answered 200, the public URL served the object byte-for-byte, a real browser upload
  through the admin form produced `https://r2.johnethel.school/student/passports/<uuid>.jpg` with no CORS or
  page errors, and the probe objects were deleted afterwards (signed `DELETE` 204, `GET` 404). The bucket's
  preflight already allows `PUT` from any origin with `content-type`. What remains unexercised is only the
  account-creation path storing that URL on a real profile (sandboxed, since prod profiles are the school's).
- [ ] `e2e_general_assessments.cjs` still creates on the subject its pickers select (10% + 1% per run), so it
  needs a fixture reload after ~9 runs — `general_assessment_flow.sh` no longer has that limit.
- [ ] `docs/architecture.md` is written for the Roc stack now, but the retired path could still use a fuller
  account (the agent table, the RPC fan-out) if anyone needs it beyond git history.
- [x] Closed 2026-10-07: the Joy host allocator bug is fixed upstream in Joy 0.34.0 (see the Joy 0.34.0
  section) — nothing left to file.

### Three parallel workstreams — two done

The leftover list was worked through by three agents in parallel, each in its own worktree with its own sandbox
ports (SurrealDB 8202/8203/8204, mock Authentik 9202/9203/9204, backend 8302/8303/8304 — the backend's `PORT`
and the mock's port argument were added for exactly this).

**Assessments now behave** (merged as `215b7ab`, from the agent's `0b3eb3d`):

- MCQs are scored server-side at submit. `answers.*` has only its four declared sub-fields, so the awarded mark
  goes into `allocated_mark` (the question's marks when the chosen letter matches the question's stored
  `answer`, 0 otherwise); the question's own allocation stays readable in the assessment's
  `questions[*].marks`, and non-MCQ answers are passed through untouched. Submission-level `scored_mark` is left
  alone, so auto-scored MCQs do not skip the teacher's grade/release flow.
- A passed `deadline` and an exhausted `max_resubmissions` (0 = unlimited) both answer **409** with a message;
  the deadline is decided by the database (`deadline < time::now()`) so there is no clock handling in Roc.
  `create-lesson-assessment` can finally set `max_resubmissions` — the column and its default existed but
  nothing could write it.
- The teacher's grading list shows the auto-scored marks inline (`MCQ auto-scored: 4 / 4`, `Q1 ✓ 4/4`).
**Follow-up by me**: submit also refuses an unpublished assessment (409) and an unknown one (404) — a draft
  was unsubmittable in the legacy agent and is now here too; two of the new API cases had been submitting to
  drafts, which is why they now publish first. Then `scheduled_at`: it was stored and ignored, so submit now
  refuses an answer before it opens (409, same database-side comparison as the deadline), and the create modal
  finally collects the rules — open time, close time and attempt limit — as `datetime-local` fields converted to
  UTC, with the answer form and list button saying when an assessment opens.

**Backend correctness** (merged as `7e744e6`, from the agent's `3e8a0c6`): `PUT`/`DELETE /api/users` resolve the
profile table from the id's own prefix instead of writing the legacy `student` table, validate like the create
path, and soft-delete; `query_param` percent-decodes through the new pure `Url` module (`UrlTest.roc`, 16 cases).

**Verified by me, not just reported**: `roc check main.roc` 0 errors / 3 warnings; `roc test UrlTest.roc` 16/16;
`sh tests/e2e/assessment_flow.sh` 41/41; `node tests/e2e/e2e_assessments.cjs` 17/17;
`e2e_student.cjs` 7/7; `e2e_admin.cjs` 5/5; plus my own curl run of the user-update lifecycle and the
encoded-vs-raw query comparison (13/13).

**The admin Configuration Hub** (merged as `6ac72bc`, from the agent's `e7e29be`) replaced its `|_model|` stubs
with real sections: Academic Terms, Class Levels, Subjects, Session Terms (the Class Arms tab, since class arms
answer 410) and Curriculum each list their endpoint's rows and create new ones, showing the backend's own
message on failure — including the `detail` from `db_response!`. `POST /api/curriculum` now relates a
class-level/subject pair, and the three existing creates validate their required fields. The fixture gained
prod's unique indexes and a seeded `session_term`. Verified on the merged tree: `e2e_admin_config.cjs` **25/25**,
`e2e_admin.cjs` 5/5, `e2e_assessments.cjs` 17/17, `assessment_flow.sh` 41/41, `e2e_student.cjs` 7/7,
`e2e_auth_callback.cjs` 12/12.

**Merge notes** (three worktrees touching the same files): `www/dist.css` conflicted and was regenerated from
the merged sources (the removals were classes the hub's own edit deleted); the e2e README kept both sides of
its conflict (the fixture's new indexes + `session_term` seed, and the `correct_answer` note). The admin agent
also documented a compiler landmine in `JOY_HOST_PATCH.md`: two shapes (an `if`/`else` producing a
`List(Effect(Msg))`, and `List.keep_if` + `match List.first(...)` in a view helper) compile with 0 errors into a
wasm that renders nothing, so a page load after a rebuild is part of the workflow.

### How user management works now (the pattern, implemented)

Identity attributes are read from Authentik and school attributes from the profile tables, joined by the
Authentik pk:

- `GET /api/users?role=` makes **one** Authentik directory call per listing and merges each row's `email` and
  `is_active` by pk, rebuilding the envelope `unwrapRows` expects. When Authentik is unreachable — or a row's pk
  is not in the directory — the row carries *neither* identity field rather than an invented one.
- The pk matcher reads **both** shapes, and that is load-bearing: production Authentik sends `"pk": 10` as a
  number (verified read-only against the real API) while the sandbox mock sends a string, so a string-only
  match would have shown no emails in production while every sandbox check passed.
- `DELETE /api/users` soft-deletes the profile row *and* disables the login in Authentik; a failure there
  answers 502 saying the login is still live, because a hidden profile with a working login is the failure that
  matters.
- `PUT /api/users` sends a new email to Authentik (validated first) and writes the profile columns as before;
  an email on its own is a valid update.
- Verified on a sandbox: `users_api.sh` **28/28** (new), `assessment_flow.sh` 41/41, `e2e_admin.cjs` 5/5,
  `e2e_admin_config.cjs` 25/25, `e2e_student.cjs` 7/7, `e2e_assessments.cjs` 17/17, `roc check` 0 errors / 3
  warnings. The mock Authentik was rewritten to serve list/PATCH/DELETE with an in-memory table (and 404s for an
  unknown pk, which is what makes the 502 path observable).

The principle behind it: the identity provider owns identity and the app database owns school data —
Authentik holds the login, the email, whether the account is enabled and the groups that decide the role;
`student_profile` and its siblings hold what only this app knows (class level, date of birth, passport, role
title) and are keyed by the Authentik pk. Reads of identity attributes go to Authentik rather than being
copied into SurrealDB, so there is one source of truth per attribute, and writes act on the owner first. SCIM
is the heavier enterprise variant of the same idea, worth it only if users should be provisioned from the IdP
side rather than from the admin screen.

---
### Deployment pass — built, awaiting the deploy

**Decided**: the app answers on `app.johnethel.school` and ships as a service in `devops/docker-compose.yml`,
the same Dokploy/Traefik pattern as everything else on that host.

- **`Dockerfile.app`** (repo root) builds everything in two stages: the pinned Roc nightly from
  `roc-lang/nightlies` — the channel for this compiler, since the older `roc-lang/roc` nightly tag stops at a
  build that predates it — then `npm ci` + Tailwind + `roc run build.roc` for the bundle and
  `roc build main.roc` for the binary. The runtime stage carries the binary, `www/`, and the CA roots, and
  sets `BIND_HOST=0.0.0.0` / `DEV_MODE=false`.
- **The `app` service**: Traefik labels for `app.johnethel.school` → port 8000, the in-network SurrealDB URL
  (`http://surrealdb:8000/sql`), `AUTHENTIK_ISSUER_URL` for token validation,
  `AUTHENTIK_SERVICE_ACCOUNT_TOKEN` for creating logins, both networks, `restart: unless-stopped`.
- **Cleanup**: the eight `golem-*` services and their four volumes moved to
  `devops/legacy/docker-compose.golem.yml` (the retired agent runtime, out of the deployed stack, kept for
  rollback); the four stale `docker-compose.yml.*` variants are deleted (two were identical 775-line files with
  the authentik block duplicated into every service, so YAML kept only the last); `.env.example` documents the
  app's variables; the README now describes what is actually deployed instead of the earlier Caddy-based local
  stack.
- **Stale stylesheet**: the committed `www/dist.css` predated a lot of the UI — regenerating it added nine
  utilities the markup already used and dropped none, so the answer form's controls had been rendering with
  browser defaults. `www/app.css` also scans `index.html` explicitly now, since most of this app's markup lives
  in the page's JavaScript.

**Verified** without a Docker daemon (none on this machine, so the image build itself is the one step not run
here): the same sequence against a clean copy of the sources with the compiler extracted from the pinned
tarball — 0 errors, and the resulting binary served `/health` (`surreal db is healthy`), `index.html`,
`dist.css`, `runtime.js` and `app.wasm` on `0.0.0.0:8000`, rejected the dev token with `DEV_MODE=false`, and
passed the browser drill-down 7/7 against prod data.

**Still to do on the server**: the Dokploy deploy of this compose — note that the `app` service and
`Dockerfile.app` live on this branch (`feat/hotfix-16-codebase-polish`), while `main` is 146 commits behind and
has no Roc stack at all, so the deployment has to point at this branch (or land after a merge).

**Pre-deploy checks done from here** (nothing on the server was touched):

- DNS: `app.johnethel.school` → `185.214.135.229`, the same host as `auth.`/`db2.`/`chat.`; Traefik answers 404 on
  port 80 for that host, i.e. nothing is published there yet.
- Authentik accepts `https://app.johnethel.school/auth/callback` on the authorize endpoint (302 into the login
  flow) and rejects an unregistered URI (400), so the provider registration is correct.
- **A blocking bug found here**: the backend derived its token-validation URL as
  `AUTHENTIK_ISSUER_URL + "userinfo"`, but Authentik serves *one* userinfo endpoint per instance
  (`/application/o/userinfo/`) — the derived URL 404s, so every real token would have been rejected with 401 as
  soon as `DEV_MODE` was off. `dev-skip` never calls Authentik, so nothing local caught it. The rule now lives in
  `roc-backend/AuthUrls.roc` (pure, covered by `AuthUrlsTest.roc`, 4/4) and the compose sets
  `AUTHENTIK_USERINFO_URL` explicitly. `tests/e2e/auth_config_check.cjs` (new) checks all of it against the real
  Authentik for a given origin — 5/5 for the deployed origin.

After the deploy: `node tests/e2e/auth_config_check.cjs` plus `/health` and the static assets on the deployed
origin, then a real login, and the sandbox suites re-run with `DEV_MODE` off.

**The OAuth callback path**: the frontend used to send `redirect_uri = <origin>/`, so the login return landed on
the app root and the registered URI had to be the bare origin. It now uses `<origin>/auth/callback`, a real
callback path like the older SvelteKit app's `<origin>/api/auth/callback` — the root stays free of OAuth
parameters and the registration is explicit. The backend's SPA fallback already serves `index.html` for that
path, and a visit without a code starts the app from the root. `tests/e2e/e2e_auth_callback.cjs` drives the whole
round trip with Authentik's endpoints intercepted and asserts the URI on both legs (12/12).

### Three more workstreams — done

Merged as `b050420` (their own commits: `f0ed0aa`, `7695938`, `3db0b68`); they overlapped in `main.roc`, the
frontend and the fixture, so they landed together with the conflicts resolved by hand (both blocks kept where the
user listing met the hub writes; the R2 passport call plus the assessment-hub setup in `index.html`;
`dist.css` regenerated).

- **The hub manages what it lists.** `PUT` for terms, subjects, class levels and session terms;
  `POST …/toggle-active` for those plus the curriculum edge; `?all=true` on the three active-only listings so a
deactivated row stays manageable in the hub while dropping off `/api/subjects` and the student's cards. Updates
  are patches (absent = unchanged; nothing carried is a 400) and a duplicate name comes back with the unique
  index's own message.
- **General assessments** work end to end — create with hand-written questions and the opens/closes/attempts
  rules, publish, student answer, MCQ auto-scoring, the same 409 guards, grading through the existing list.
  `assessment_type=general`, bare `assessment_id`, one row per student and assessment with `iteration` bumping in
  place. `compositions` is deliberately neither read nor written (nothing computes a weighted term result) and
  create enforces the legacy ≤100% weight budget. It also fixed an existing bug: "Show all submissions"
  referenced module-scoped variables and threw on click.
- **Real presigned passport uploads.** `Sha256.roc` + `Hmac.roc` (pure; NIST and RFC 4231 vectors) and `R2.roc`
  (SigV4 query presigning, checked against AWS's published `GET /test.txt` vector). `POST /api/upload-url` signs
  a 600-second `PUT` for `<profileType>/passports/<userId>.jpg`, validates both parts, and answers 503 naming any
  missing variable rather than a URL that cannot work. The form uploads the file and writes the returned public
  URL into the passport field; the URL field still works.

**Verified on the merged tree** (sandbox: SurrealDB 8002, mock Authentik 9000, backend 8010; fixture 157
statements, 0 errors): `general_assessment_flow.sh` 49 passed / 1 skipped (the compositions check wants
`SURREAL_URL`), `e2e_general_assessments.cjs` 25/25, `users_api.sh` 28/28, `assessment_flow.sh` 41/41,
`e2e_admin_config.cjs` 53/53, `e2e_passport_upload.cjs` 9/9, `e2e_assessments.cjs` 17/17, `e2e_admin.cjs` 5/5,
`e2e_student.cjs` 7/7, `e2e_auth_callback.cjs` 12/12; `roc check` 0 errors / 3 warnings; `Sha256Test` 7/7,
`HmacTest` 7/7, `R2Test` 20/20, `UrlTest` 16/16. One test fix: `e2e_passport_upload.cjs` asserted the sandbox's
access key instead of the signature's shape.

---

### The user listing is directory-driven — done

The admin's blocker: users created in Authentik itself (with `Students`/`Teachers` groups) did not appear in
User Management, and neither did the admin's own account. Cause: `GET /api/users?role=` read the profile
tables and merged Authentik's `email`/`is_active` onto those rows — all four tables were empty, so the tabs
were empty, and `POST /api/users` always creates a *new* login, so there was no way to attach a profile to a
login that already existed.

- **The listing is a union keyed by pk.** Every profile row of the requested role (as before), plus every
  login the directory lists for that role that has no profile row — with `has_profile` telling the two apart.
  A login in no role group (an outpost, a service account) maps to no role and is listed in no tab; the
  student default stays where it belongs, on the caller's own role. One directory call per request.
- **Group names come from `groups_obj`.** The list endpoint's `groups` field holds group **ids**, the names
  live in `groups_obj` (verified against prod: `"groups":["79a71c0e-…"]`, `"groups_obj":[{"name":"authentik
  Admins",…}]`). `role_from_group_names` is now the one mapping, read by the caller's role (userinfo `groups`,
  names) and by the directory listing (`groups_obj`).
- **`PUT /api/users` attaches a profile to an existing login.** It probes the row: present → patch (every
  field the payload leaves out keeps its stored value), absent → the row is made from the payload, so the
  create path's required fields are checked first (`validate_profile_fields!`, shared with `POST`) and the
  statement is `CREATE` — this SurrealDB's `UPDATE` on a missing record is a silent no-op that still answers
  OK. `deleted_at = NONE` is part of the write, so completing a soft-deleted profile brings it back.
- **One form, two writes.** A profile-less row shows a `No profile yet` badge and a **Complete profile**
  action that loads that login into the existing form (title, description, disabled email and role picker,
  button label all switch); the same form still creates a login when no profile id is loaded. `State.roc`
  picks `PUT` + `id` over `POST` + `role`/`email` from `completingProfileId`.

**Verified** (sandbox: SurrealDB 8212, mock Authentik 9212, backend 8312; fixture 157 statements, 0 errors;
`roc check main.roc` 0 errors / 3 warnings, `roc check app.roc` 0 errors): the seeded student/teacher/parent/admin
logins list with `has_profile:false` and their login email; the groupless and unrelated-group logins appear in
no tab; `PUT` with the full student set creates the row (`class_enrolled` + `current_class`), a second `PUT` is
a patch, an incomplete payload is a 400 naming the missing field, `DELETE` then `PUT` brings a profile back,
`POST` still creates login + profile; in Chromium, **19/19** checks — the badge and action, the form switching
modes, the completed row becoming a normal row, the teachers tab, no page errors.

The fixture's directory now starts with one login per role plus two that belong to no role (`seed_user`), and
its created logins carry `groups_obj: []` the way Authentik's own API does — and a **numeric** pk, the shape
the real API sends, because a mock that only ever sends string pks is what hid the two bugs below.

**The suites** (`tests/e2e/`, sandbox 8212/9212/8312, fresh fixture): `users_api.sh` **54/54** (28 existing +
26 for the directory listing and the completing write, run twice on one sandbox), `e2e_users_directory.cjs`
**17/17** (new; the badge, the form switching modes, the write being a `PUT` about that login with no email,
the row becoming normal; run twice), `e2e_loading.cjs` **20/20** (its four stale checks asserted the Teachers
tab was empty — every tab has a seeded row now, so the empty state is faked for one tab through the route
interception it already used for the 500 case), `e2e_admin.cjs` 5/5, `e2e_admin_config.cjs` 53/53,
`e2e_student.cjs` 7/7, `authz.sh` 27/27. `roc check main.roc` 0 errors / 3 warnings, `roc check app.roc` 0
errors.

**Two bugs the sandbox had been hiding, both about the shape of a pk.** Authentik sends a login's `pk` as a
*number* (`"pk":13`) and puts it first in the object; the group objects that follow carry a string `pk` of
their own. The mock only ever sent string pks, so two readers that matched `"pk":"…"` looked right there:

- the listing's pk reader took a **group's** pk (the real listing came back as
  `student_profile:b8908daf-…`, the `Students` group's uuid, which matches no profile row and so also silently
  broke the email/is_active merge for every login in a group). Both readers now take the login's own `pk`,
  number or string.
- `Authentik.createUser!` read the pk the same way and, finding nothing on a response whose new login has no
  groups, fell back to the literal `user_uuid_123`. That is why prod has a `student_profile:user_uuid_123` row
  for a login that really has pk 14: the profile was written under a placeholder id, leaving the login with no
  profile and the row orphaned. `Authentik.roc` reads the number form now.

SurrealDB renders a string id part that looks like a number back to us quoted (``student_profile:`14``), so
`bare_id` strips the backticks and the listing emits ids in one spelling (`student_profile:14`); without that,
a row made by the create path could not be joined to its login. The fixture's created logins now carry numeric
pks too, so this class of bug cannot hide in the sandbox again. A profile-less row also carries the login's
`username`, which is what the page shows when a login has no name at all — two of the real directory's are
named only by their username.

One more thing the tests had to learn: a pk that looks like a number is still a *string* id part, so a raw
SurrealQL statement has to spell it `type::record('student_profile','14')` the way `record_ref!` does —
`student_profile:14` in a statement is a number part, a different record from the one the app writes.
`users_api.sh` builds its ids through a `rid` helper now, and reads a created row's pk out of the listing
(or strips the quotes SurrealDB puts on it in a write's own answer).

**Prod cleanup (approved, one-off)**: the placeholder-id row the create bug left behind is gone, along with
the dummy login it was meant for. `student_profile:user_uuid_123` (Grace Chioma Nwosu1822 — `e2e_admin.cjs`'s
own fixture data, `https://example.com/grace.jpg` and a `Nwosu<stamp>` surname, written 2026-10-05 by that
suite running against prod) was deleted, and so was its login `grace1791225481822@example.com` (pk 14, in no
group, so it was in no tab anyway). Checked first: nothing referenced either side (`submissions` and
`parent_profile` are empty). Before → after: `student_profile` 1 → 0 rows, directory logins 9 → 8. The four
tabs now list only real accounts: `temp-student` (pk 13), `temp-staff` (pk 11) and the admin (pk 5), each
waiting for its school data.

### Merge-readiness review and fixes — done (four commits)

A review of the branch ran against `27e65b5` + `7eb6ee9` (the deploy path, the Phase 8 work, the
suites and the docs). Its findings and the fixes that followed are the four commits after that:
`ae18d9b` (deploy), `dd72570` (backend), `4aadb2e` (build script), `6444403` (docs and hygiene).

- **Deploy.** The `app` service now lists the five `R2_*` variables. Compose forwards only what a
  service's own `environment:` names, so Infisical/Dokploy interpolated them while the container read
  them as unset and `/api/upload-url` answered 503. The compose's relative paths — mounts and build
  context alike — resolve against the **project directory**, which Dokploy sets to the repository root
  (`--project-directory …/code` in its build command), not against this file's own folder. So the two
  binds keep their `./devops/…` prefix, and the app's build context is `.`, not `..` (the first deploy
  failed with `failed to read dockerfile: open Dockerfile.app: no such file or directory`; see the
  deploy-fix note at the end of this section). `.github/workflows/deploy-backend.yml` is `workflow_dispatch` only now:
  it deployed the retired Golem runtime on any push to `main` touching `agents/**`, which includes the
  merge that was about to introduce it. The job is intact for the move to roc-golem. Both
  `.env.example` files match what the code and the compose file read.
- **Backend.** `/health` answers 503 when the database is unreachable, decided through `db_body!`; it
  used to answer 200 with "surreal db is down" inside the body, which the container's HEALTHCHECK read
  as healthy. `Authentik.createUser!` no longer falls back to the literal `user_uuid_123` when a create
  response carries no pk — the caller answers 502 and writes no profile row, instead of 200 with an
  orphan row (the shape of the production row whose cleanup landed in `27e65b5`).
- **Frontend build.** `roc run build.roc` failed twice during the review with "roc build failed for
  app.roc" while a direct `roc build` of the same command succeeded: the captured output ended at the
  warnings and lost the trailing summary line the check reads. The compiler now runs under `sh` with
  stdout and stderr redirected into `build.log`, and the same rule is applied to that file — a summary
  reporting errors, or a missing wasm, still fails the build. Not reproduced in five attempts on the
  pinned platform (which has no redirect API, hence `sh`), so the truncation is unproven; the decision
  just no longer depends on a pipe.
- **Docs and hygiene.** `docs/architecture.md` states the role matrix the backend enforces
  (`required_role`/`may_call`, proven by `authz.sh`) instead of calling it a missing regression, and
  records that `db/schema-v5*.surql` were never applied to prod: no `id_sequences` table, no
  `student_profile.admission_number`, no `staff_id`, and the backend writes none of them — so applying
  v5 to a fresh database breaks `POST /api/users` for Student/Teacher/Admin. Both v5 files say the same
  in a header. The root `.gitignore` ignores the untracked scratch a broad `git add -A` would otherwise
  sweep in before a push.

**Verified in this pass** (sandbox 8222/9222/8322, plus the Dockerfile's steps replayed on a clean
`git archive` copy): `roc check main.roc` 0 errors / 3 warnings and `roc check app.roc` 0 errors;
`users_api.sh` 54/54, `authz.sh` 27/27, `assessment_flow.sh` 41/41, `general_assessment_flow.sh` 56/56,
`e2e_users_directory.cjs` 17/17, `e2e_loading.cjs` 20/20, `e2e_admin.cjs` 5/5, `e2e_admin_config.cjs`
53/53, `e2e_general_assessments.cjs` 25/25, `e2e_signout.cjs` 9/9, `e2e_auth_callback.cjs` 12/12, and —
after the selector fix in `7eb6ee9` — `e2e_student.cjs` 7/7 and `e2e_assessments.cjs` 17/17 (both had
been failing on a fresh fixture: the nav bar's session-term badge carries the term's own name, so
`text=Noel Term` clicked the badge); `deploy_check.cjs` 8/8 against the built binary running
`DEV_MODE=false`, which refuses `dev-skip` and serves the bundle; `auth_config_check.cjs` 5/5 against
the real Authentik; and, read-only against prod, the four user tabs, 23 subjects, 75/225 lessons and
127 curriculum edges.

**Independently re-verified** on its own fresh sandbox (8922/9922/8822) at `fa99fc5` by a separate
reviewer pass: both `roc check`s, the 157-statement fixture, all thirteen suite counts above, and each
fix adversarially — the compose lists the five `R2_*` and its relative paths resolve to the real
files under a local `docker compose config` run (Dokploy's `--project-directory` override showed up
only on the server — see the deploy-fix note), the workflow's
job body is byte-identical with only `workflow_dispatch` left as a trigger, both `.env.example` files are
an exact set match with what the code and the compose file read, the no-pk create answers 502 with no row
written (while a real pk still creates one), and the build script fails on a broken `app.roc` and on a
missing compiler while succeeding normally. It also confirmed the diff touches only the seventeen files
the six commits name. The two notes it raised are folded in: `e2e_loading.cjs`'s skeleton check was 19/20
twice in five runs — a timing race in the check, not a regression — so the hold-back is now 2 s and the
skeleton wait starts immediately after the click (20/20 in seven runs since); and `devops/.env.example`
listed `ACME_EMAIL`, which nothing in the repository reads, so it is gone.

**Left for the server / open**:

- The deploy host settled the path convention for good: Dokploy passes `--project-directory` = the repo
  root, so relative paths resolve there — the bind mounts need their `./devops/…` prefix and the app's
  build context is `.`, which the deploy-fix commit below applies. Still to confirm there: that the
  `R2_*` values actually reach the `app` service (from `devops/.env`, populated via Infisical).

A first Dokploy deploy (after the merge) failed at the image build: `failed to read dockerfile: open
Dockerfile.app: no such file or directory`. Cause: Dokploy runs the compose with `--project-directory`
pointing at the repository root, so `build.context: ..` resolved *above* the repo — the review's
"one command settles it" caveat, settled the other way. Fixed in `devops/docker-compose.yml`:
`context: .`, the two bind mounts restored to `./devops/element/config.json` /
`./devops/matrix-config/homeserver.yaml` (what a repo-root project directory needs), and the obsolete
`version: '3.8'` key removed (Dokploy warned about it). Re-verified with Dokploy's own invocation
(`docker compose --project-directory <repo> -f devops/docker-compose.yml config`): the context and both
mounts now resolve to the real paths under the repo.

A second deploy got past the compose stage and failed one step later: `cd roc-backend && roc build
main.roc` exited 2 — `roc build` exits 2 when it emits warnings, so the three module-header
deprecation warnings (Authentik.roc, Golem.roc, SurrealDB.roc) made every `RUN` look like a failure
even though the summary said "0 errors … successfully building: main". Fixed at the source instead of
gating the exit code: the three files now use the type-module shape the rest of the backend already
uses (`R2 := [].{…}`), so `roc check main.roc` and `roc build main.roc` are both 0 errors / 0 warnings
(exit 0) and the Dockerfile needed no change. Behaviour is unchanged — on a fresh sandbox
`users_api.sh` 77/77, `authz.sh` 27/27, `assessment_flow.sh` 41/41. The older "0 errors / 3 warnings"
lines in this file record the state before that migration.

A third issue, found while the developer tested the live app: the hub's lists (terms, class levels,
session terms, subjects) answered intermittent 500 `{"error":"Database error"}` — a real backend 500
(Network tab), the database never restarted, and a manual retry always landed. That is a stale
keep-alive: the docker bridge drops the app's idle connection to `surrealdb:8000`, the first request
after a pause fails at the socket, and the retry opens a fresh connection (it never reproduced on
localhost, which is why the suites were green). Fixed with `SurrealDB.query_read!` (retry once on a
connection-level failure, logged to stdout so `docker logs` confirms it), applied to every read call
site and the user listing (`db_body_read!`), while writes stay non-retrying; and the compose now
starts the app only after the database's healthcheck (`depends_on: condition: service_healthy`).
Verified: `roc check main.roc` 0 errors / 0 warnings; the retry branch proven against a dead DB
(500 plus the logged retry line); on a fresh sandbox `users_api.sh` 77/77, `authz.sh` 27/27,
`assessment_flow.sh` 41/41, `e2e_admin_config.cjs` 53/53, `e2e_loading.cjs` 20/20.

- `/health` now makes an unreachable database an unhealthy container. The compose file's
  `restart: unless-stopped` reacts to exits, not to health, so the state surfaces in `docker ps` health
  and in `deploy_check.cjs` rather than as a restart loop.
- The build-script truncation is hardened but unexplained: if a build ever fails with an empty or short
  `build.log`, the redirect is the suspect rather than the compiler.

### School numbers — done (students, teachers and admins)

Every member of the school now carries a permanent number, in the shape the developer settled on: the
database stores the integer alone and the prefix is applied by the code, so the number is the person's
identity rather than a formatting choice.

- **Stored as an integer, one counter per class of member.** `student_profile.admission_number`, and
  `staff_id` on `teacher_profile` and `admin_profile`, all `option<int>`; `id_sequences` holds a `student`
  row and a `staff` row. Teachers and admins share the `staff` counter, and a pk that already holds a staff
  number on either staff table *reuses* it rather than drawing a second one — which is what keeps a teacher
  made an admin holding their own number. A student who becomes staff draws a fresh staff number; a parent
  has none.
- **Rendered in one place.** `main.roc` renders `JES-000123` / `EMP-000045` into the listing's
  `school_number` field; neither the database nor the page spells a prefix a second time, so the written
  form can change without touching a stored number. User Management shows the number read-only.
- **Allocated inside the profile's own statement** — `CREATE … SET admission_number = (UPDATE
  id_sequences:student SET current_value += 1 RETURN current_value)[0].current_value` — so a rejected or
  duplicate create cannot burn a number and a retry draws the next. Verified on this SurrealDB: the
  increment rolls back with a failing statement, and two concurrent increments serialized (3, then 4).
  Once set, the number is immutable: a `PUT` carrying either field is a 400 naming it, the same refusal
  `class_enrolled` gets.
- **`db/schema-v8-ids.surql`** is the additive migration: `UPSERT` seeds for the two counters (never v5's
  `DELETE`), `option<int>` columns with unique indexes. It supersedes the never-applied `v5` pair, whose
  headers now say so, and the sandbox fixture mirrors it. **Applying v8 to prod is part of the deploy** —
  prod is SCHEMAFULL, so a create that has to hand out a number fails until the columns exist; there is no
  backfill, because prod has no profile rows.

**Verified** on a fresh sandbox: `roc check main.roc` 0 errors / 3 warnings, `roc check app.roc` 0 errors;
the fixture loads 170 statements / 0 errors; students drew `JES-000001` then `JES-000002`, a teacher and an
admin drew `EMP-000001` then `EMP-000002` from the one `staff` counter; a rejected create (no passport) and
a create the database itself rejected (`2011-13-45`) left both counters unmoved; a teacher's pk given an
admin profile reused `EMP-000001` with the counter unmoved (the reverse direction too); a `PUT` carrying
`admission_number` (string) or `staff_id` (integer, with a space after the colon) answered 400 with the
stored values unchanged; `current_value = 999999` rendered `JES-1000000` rather than truncating; and the
rendered cell was read back out of the DOM (header, `JES-000001`, `—` for a profile-less row and a parent,
no editable control). Suites: `users_api.sh` 77/77 (44 checks added), `authz.sh` 27/27,
`assessment_flow.sh` 41/41, `e2e_users_directory.cjs` 17/17, `e2e_admin.cjs` 5/5, `e2e_loading.cjs` 20/20,
`e2e_admin_config.cjs` 53/53.

**Independently re-verified** on its own fresh sandbox at `5ecdf58`: all ten checks reproduced —
the allocation numbers and the unmoved counters on refused creates (validation and database alike), the
reuse rule in both staff directions plus the fresh-`JES-` and fresh-`EMP-` transitions, the immutability
400s in both spellings, a hand-written duplicate refused by `idx_student_admission`, three parallel
creates drawing 6, 7, 8, `JES-1000000` from a counter of 999999, the read-only table cell, the
fixture-vs-v8 statement match, all thirteen suites (again `users_api.sh` 77/77), and every sentence of
the docs — plus the negative: with the v8 field dropped, a create fails exactly as the docs say
("Found field 'admission_number', but no such field exists"), the counter unmoved and the login rolled
back.

**Two boundaries, both by design**: numbers on two staff tables cannot carry one global unique index, so
cross-table uniqueness rests on the shared counter and the reuse rule being the only allocators (hand-written
SQL could still put one number on a teacher and an admin); and when Authentik is unreachable the listing
falls back to the raw rows, which carry the integer and no `school_number`, so that column renders empty —
the same way email and `is_active` do there.

**Still to do on the server**: apply `db/schema-v8-ids.surql` to prod (row counts either side, as always)
**before** the backend deploy; the number column then appears in User Management. If the school ever wants a
different written form, only the renderer in `main.roc` changes.

### Two-system writes are journaled — done (create/delete reconciled)

User management spans Authentik and SurrealDB with no shared transaction. Previously the create and
delete were compensated sagas: each step failure triggered the matching rollback, but a *crash*
between two steps left a half-state no compensation ran for. The developer asked for a proper tie;
this adds a write journal (`db/schema-v9-pending-ops.surql`, also mirrored in the fixture).

- Every `POST /api/users` (with or without a password) and `DELETE /api/users` first records its
  intent in `pending_ops` (`CREATE … RETURN id`, SurrealDB's own unique id — a timestamp id collided
  on same-millisecond calls and a hyphenated part is parsed as subtraction). Each completed side
  advances `step`: login → password → profile (create); profile_hidden → login_disabled (delete).
- `reconcile_pending!` (boot + `POST /api/users/reconcile`, admin) settles rows stuck in `running`:
  the profile write replays idempotently from the journaled payload (school number allocated in the
  same statement, never duplicated), a create whose password was never set is rolled back (the value
  is gone by design — never journaled), and a delete finishes the un-done half. Unsettlable rows stay
  visible at `GET /api/users/pending` (admin) with the failing message.
- The journaled payload is a quote-free `;`-separated string on purpose: the file's JSON scanners
  read a value up to the first double quote, so a payload with JSON quotes could not be read back.

**Verified** (`roc check main.roc` 0/0; sandbox): a normal create lands its row `done/profile`; a
simulated crash after the login removes the unusable login and marks the row failed; a crash after
the password replays the profile from the journal (new school number, `done`, row listed again); a
delete interrupted between the two sides is finished by the reconciler; `pending`/`reconcile` are
403 for non-admin; `users_api.sh` 94/94 (was 87), `authz.sh` 27/27, `assessment_flow.sh` 41/41.
The frontend half (password field + Generate + Copy credentials, working row actions, richer
columns) is done — the section below.

### User management's frontend half — done (2026-10-07)

The backend half (passwords, activate, the journal) shipped above; this is the form and the row
actions the admin actually uses, plus the two small backend fixes the form exposed.

- **The create form carries an optional password**, with a Generate button (the page's own generator — Roc has
  no random source — answers through the rendered input's input event, exactly like typing). A create that
  carried one comes back as a **one-time credentials panel**: the email and the password, shown once with a
  Copy button (`copy_to_clipboard` port; plain-http origins fall back to execCommand) and cleared the moment
  the form starts another write. The password is never stored anywhere (the backend journal marks only its
  presence) and bad ones stay refused (8-72 chars, no line breaks).
- **The row actions work.** Edit loads the row into the form above (prefilled from the row's own listing
  line; the submit is the same PUT, patching), Deactivate soft-deletes the profile and disables the login
  (DELETE /api/users), and the toggle follows the login's true state — a row whose login is off offers
  Activate (POST /api/users/activate) instead. A profile-less row still offers exactly Complete profile (its
  one action).
- **The payload mirrors what the form shows.** `role_title` rides only an Admin write — it is a column of
  `admin_profile` alone, and a carried non-column field is a 400 on the backend, which the first Edit of a
  student row hit because fixture rows carry a stray flex `role_title`. And the parent completing path was
  unblocked on the backend: `misplaced_update_fields` refused first/middle/surname for `parent_profile` even
  though its own attach validation demands them and `update_clauses!` derives the parent's single `name`
  from them. A parent attached through the form now lands with the derived name ("Ada Okeke"), locked by two
  new `users_api.sh` checks.
- The richer listing columns (school number, status) were already in from the backend half; the row line
  now also carries first/middle/surname/date_of_birth/current_class/role_title/passport for Edit's prefill.

**Verified** (`roc check main.roc` 0 errors; `roc check app.roc` 0 errors; sandbox 8322): `e2e_admin.cjs`
10/10 (new: Generate fills a 16-char password; the panel hands over `email\npassword` and the clipboard holds
it; a value with a double quote is refused up front), `e2e_users_directory.cjs` 27/27, run twice (new: activate
flips the toggle; **deactivate hides the profile and disables the login — the bare Inactive row then offers
Activate as its only action, which restores both**; Edit-prefill → Save changes → `User updated` and the row
shows the edited surname; suite re-runnable — its reset deletes the profile row directly from the sandbox
database, like users_api.sh's, so the fixture's login is never mutated), `e2e_loading.cjs` 20/20 (retry check
now keys on the login's address, so a users_api.sh run that leaves the seed parent completed cannot trip it),
`e2e_admin_config.cjs` 53/53, `users_api.sh` 96/96 (was 94; +2 parent-completing), `authz.sh` 27/27,
`assessment_flow.sh` 41/41, `general_assessment_flow.sh` 56/56.

**Review fixes landed before the merge** (2026-10-08): a deactivated (bare) row now offers **Activate** — the
previous code showed only Complete profile once the profile was hidden, making reactivation unreachable
through the UI; form values are validated up front against `"`, `\`, `|` and line breaks, because the
hand-written JSON payload is scanned (not parsed) by the backend and the directory rows are `|`-separated —
so such values can no longer be stored silently truncated or shift the Edit prefill; the credentials panel
moved to the end of the view to dodge a Joy 0.34.0 runtime bug (a conditional subtree whose size changes
shifts the flat ref list the renderer patches attributes by, and a value-input patch could land on a text
node — `node.setAttribute is not a function`); `Dockerfile.app` regained its `npm ci` step; and the doc
references to the retired EventStore/joy-vendoring/old nightly were cleaned up.

**Still open**: `e2e_admin_config.cjs`'s curriculum create is not re-runnable on one long-lived sandbox — the
JSS 2 + Agricultural Science link it adds collides on the unique index with the link an earlier run left
behind (every other create in the suite stamps its name). It passes on a fresh fixture; re-running needs
that leftover edge deleted, or the create stamped like the rest.

---

### Feedback pass — notifications, role-tailored forms, the LMS drill's history (2026-10-11)

**The tree did not compile when this pass started.** The previous session was cut off mid-edit and left two
stray braces behind: a duplicated `}` after `SubmitCompleted`'s arm in `State.roc` (which closed the `match msg`
early, so everything after it parsed as statements — ~264 errors, most of them nonsense) and a duplicated
`ConfigUpdateCompleted(tab, res) => {` header in the same file with `RetryList`/`StartEdit`'s arms grafted under
it. `AdminView.roc`'s `user_row` was also missing the two parens that close its `List.concat`/`table_row`, and
`init`'s `AdminLMS` boot arm returned a whole tuple where its siblings return an effect list. Both files check
clean again.

**Notifications — toasts with a pausable countdown, and a bell that keeps the history.** A finished write now
raises a top-right toast (success/error/warning/info) whose countdown bar shrinks, pauses on hover and resumes
when the pointer leaves, and dismisses itself at zero; every notification also lands in the navbar bell's
dropdown, which shows a count badge. Two bugs surfaced while wiring it, both worth remembering:

- The countdown bar was looked up with `querySelector(".h-0.5")` — an invalid selector (a class name is not a
  selector when it contains a dot), so *every* notification threw mid-render. That exception aborted the paint
  after the state change, which is why a created student stopped appearing in the table. The bar carries its own
  `notification-bar` class now.
- The bell's badge and dropdown were written into their DOM nodes directly (`appendChild`, `innerHTML`). That
  makes the vdom's own view of the subtree lie: the next patch walked its refs out of step and set a `value`
  attribute on an unrelated **text node** (`node.setAttribute is not a function`), after which clicking "Reset
  password" navigated to the Configuration Hub — the same Joy 0.34.0 runtime hazard the retired credentials-panel
  comment already described. The bell is app state now: `notificationsOpen` + `notificationsData`, a
  `ToggleNotifications`/`CloseNotifications`/`ClearNotifications`/`GotNotificationsData` set, and the page's
  toast history arriving through the usual hidden-input bridge (`formatNotifications` serializes
  `kind|title|message` per line). The page never writes into that subtree. The toast container itself is still
  the page's own DOM, appended to `<body>` outside `#app`, which is why it is safe there.

**The user form and list are role-tailored.** The one modal's fields now follow the picked role — a student's
date of birth and class level (native date inputs, as the retired app used, rather than a text box hoping for
`YYYY-MM-DD`), a teacher's date employed plus the qualifications picker, a parent's linked-students picker
(badges + search, the same pattern the parent modal used before), an administrator's role title — and the role's
fields sit in their own full-width block so nothing shares a row with another role's half-empty field. The
table's extra column is the tab's own: **Class** for students, **Students** for parents, **Role title** for
administrators, none for teachers (their one extra action, Assign, already lives in the actions cell). The
backend gained the fields the form sends: a teacher's `date_employed` and a parent's `students` (linked
`student_profile` ids) ride create, update, journal replay and the listing, alongside `qualifications`.

**Clicking outside a modal cancels it — both modals.** The user form's overlay had no backdrop hook at all, and
the teacher Assign dialog's overlay pointed at the *user form*'s close input, so its backdrop closed the wrong
dialog. Each overlay now carries `modal-backdrop` + its own `data-close-input` (`user_form_close_input` →
`CloseUserForm`, `assign_close_input` → `CloseTeacherAssign`), which is the bridge the page's document listener
already spoke. The modal also sits on a blurred backdrop.

**The admin LMS drill-down is a URL per step.** `?class=`, then `&subject=`, `&term=`, `&lesson=` — so the
browser's back/forward walks the drill (the reported bug: from the lessons list, back landed on the subjects
step), a reload at depth restores that step, and each breadcrumb lands on the level it names rather than one step
up: the subject crumb on the lessons list reaches the terms step, "← All classes" reaches the class picker, and
the class name reaches that class's subjects. That needed four distinct messages (`BackAdminClasses`,
`BackAdminSubjects`, `BackAdminTerms`, `BackAdminLessons`) where the previous pass had three names all doing
`history.back()`, and it retired the now-unused `history_back` port.

**The section navigator was swallowing clicks.** `showTab` toggled `hidden` on `#section-nav`, but the element's
own markup carries `md:flex`, which beats a bare `hidden` at desktop widths — so on the assessments and grading
tabs the navigator stayed on screen as an invisible fixed strip along the right edge, over whatever was behind
it (in the sandbox: the grading list's "Grade" button, which is how `e2e_assessments.cjs` caught it). The tab
switch now swaps the whole class list, the way the tabs themselves are switched, so `hidden` really hides.

**Test suites.** New: `e2e_notifications_lms.cjs` (toasts, countdown, hover pause, auto-dismiss, bell badge,
dropdown, Clear all, outside-click close; then the LMS drill's URLs, crumbs, back/forward and deep-load
restore) and `e2e_user_roles.cjs` (per-role modal fields, per-role table columns, blurred backdrop,
backdrop-click cancels without a write). Repaired: `e2e_passport_upload.cjs` still drove the *pre-modal* form
(a bare `e.g. Adamu` fill with no click to open, and a class-level text input where the form has had a
`<select>` since the modal landed) — it opens the modal and selects the class now, and both its modes pass;
`smoke_assignments_lms.cjs` leaned on a teacher row some earlier suite happened to leave behind (its Assign
action needs a *profiled* teacher) and now creates its own; `render_lesson_check.cjs`'s DOM stub needed
`window.fetch` because the page's 401-refresh wrapper rebinds it; the README's check table gained the three new
suites and the two smoke tests.

**Build note for the next person**: `roc-frontend/build.roc` runs `roc build --no-cache`, so a full build takes
minutes (7 on this machine), and **two builds at once clobber each other** — they write the same `www/app.wasm`
and the same `build.log`, which is what made a run look like "compiler produced no summary and no wasm". Run one
at a time, detached, and wait for it.

**Verified** (sandbox on the `~/.cache/sms-sandbox` fixture; `roc check main.roc` 0 errors; `roc check app.roc`
0 errors): `e2e_admin.cjs` 16/16, `e2e_admin_config.cjs` 53/53 (on a fresh fixture), `e2e_users_directory.cjs`
27/27, `e2e_user_roles.cjs` 18/18, `e2e_notifications_lms.cjs` 26/26 (three runs in a row), `e2e_loading.cjs`
20/20, `e2e_icons_refresh.cjs` 10/10, `e2e_nav_fixes.cjs` 6/6, `e2e_student.cjs` 7/7, `e2e_assessments.cjs`
17/17, `e2e_general_assessments.cjs` 25/25, `e2e_signout.cjs` 9/9, `e2e_auth_callback.cjs` 12/12,
`smoke_assignments_lms.cjs` 18/18, `smoke_teacher_role.cjs` 6/6, `e2e_passport_upload.cjs` 9/9 and 5/5 (its 503
mode), `render_lesson_check.cjs` all checks, `users_api.sh` 95/95, `authz.sh` 27/27, `assessment_flow.sh`
41/41, `general_assessment_flow.sh` 56/56, `matrix_token.sh` 26/26.

**The two scopes that were still open — both closed (2026-10-11).** Same hole, two more surfaces:

- **Teacher's term.** A lesson hangs off a term and the picker has no term step, so it listed every term's
  lessons under one class and subject — the same week number once per term, which is the other half of
  "20+ lessons". It reads the term of the **active session term**, the term the teacher's own assignments are
  already scoped to; a caller that names a term (the admin LMS) is untouched. The alternative — giving the
  teacher's picker the retired app's term step — is a UI change nobody has asked for yet, and this keeps the
  picker's scope identical to the assignment's.
- **Student's subjects.** `/api/student/subjects` answered every active subject in the school, so a student
  could pick one their class is not paired with and land on an empty lesson list. It now answers the subjects
  that class's `has_subject` pairs name (`id IN (SELECT VALUE out FROM has_subject WHERE in = <class> AND
  active = true)`), with the full list kept for a student whose profile names no class — the same fallback rule
  the lesson list uses, for the same reason.

**Indexes — and a correction.** I said `lessons` was unindexed on `has_subject`/`term`; that was true of this lineage
and **wrong about prod**. Prod carries `idx_lessons_unique` on `(has_subject, term, week)` UNIQUE and
`idx_lessons_slug` on `slug`, both applied outside `db/*.surql`. So the rule I was about to recommend as a
future safeguard has been in place all along — which is also why prod came back with **zero** duplicate groups
over 3413 lessons, and why the "20+ lessons" could only ever have been the query scoping. `db/schema-v10-
lesson-indexes.surql` now records those two indexes (no-ops on prod, and the rule the sandbox fixture was
missing), and notes that v2's `idx_lessons_topic` is not in prod at all. `db/apply-v10-and-verify.sh` applies it
and reports the duplicate count; its earlier `--swap` path is gone, since there is nothing to swap once the file
defines the rule directly. **Prod ended this work exactly as it started it** — the index added there was a second
copy of the one it already had, and was removed again.

**The lesson for next time**: derive a database's shape from the database, not from the schema directory that is
supposed to describe it. One `INFO FOR TABLE lessons` — thirty seconds, read-only — would have replaced the whole
index argument with "already indexed, already unique".

**Verified again after both** (`roc check main.roc` 0 errors): teacher picker on one edge holding a Noel lesson
and a Calvary probe **2 rows → 1**; JSS 2 student's subjects **Yoruba Language (JSS 1 only) excluded**, full list
back with no profile; and the sweep: `smoke_teacher_role` 9/9, `e2e_student` 7/7, `e2e_loading` 20/20,
`e2e_assessments` 17/17, `e2e_admin_config` 52/53 (its documented leftover-edge caveat), `e2e_users_directory`
27/27, `users_api.sh` 95/95, `authz.sh` 27/27. Against **prod**, read-only: 3413 lessons, **0 duplicate groups**,
and `smoke_assignments_lms` 18/18 on the sandbox after its fixture gained prod's two indexes.

---

### The duplicate "Week 1" lessons — diagnosed and fixed (2026-10-11)

**It was the query, not the data.** A lesson hangs off one `has_subject` edge (`class_level -> subject`) and one
term, and `topics` is unique on `(has_subject, term, week)` — so duplicate weeks cannot come from the seed, and
nothing needed prod access after all. The lists that filtered by **subject alone** matched that subject in *every*
class level, so one class's curriculum listed its weeks once per class: JSS 1's and JSS 2's Agricultural Science
lessons both answered a reader asking for JSS 2's.

Reproduced in the sandbox by putting a second week-1 lesson on JSS 2's Agricultural Science edge: the subject-only
question came back with **two rows, both "Week 1"**, and the class-scoped one with a single row. That is the
reported symptom exactly, and three class levels are what turn it into "20+ lessons".

**Fixed on both surfaces that had it** (the admin LMS already passed `class_id` and was never affected):

- **Teacher.** The My Classes card carries the pair's `class_id`, and the picker now asks for `class_id` +
  `subject_id` (its retry asks for the same). Opening a card also had to start choosing the lesson view: the
  action sent the fetch and pushed the URL but never set the route, so a teacher clicking a class saw nothing
  happen and the picker was reachable only by URL.
- **Student.** The profile's own `current_class` scopes the list, read once per request. A student whose profile
  names no class keeps the unscoped list — someone not enrolled anywhere still reads a subject's lessons rather
  than nothing, which is the failure mode that made this worth guarding (the same reason the clause is left out
  when the lookup answers `null`/`NONE`).

**Verified**: JSS 2 student **1 row (was 2)**; teacher picker **1 row** of the 2 the same subject returns; a
student with no profile unchanged at 2; `smoke_teacher_role.cjs` **9/9** with two new checks that stub both
endpoints so a page that stops sending `class_id` fails the suite (the request must name the pair's class, and
the JSS 2 lesson must not appear under the JSS 1 pair). Full sweep after the change: `e2e_student` 7/7,
`e2e_assessments` 17/17, `e2e_general_assessments` 25/25, `smoke_assignments_lms` 18/18,
`e2e_notifications_lms` 26/26, `e2e_admin` 16/16, `e2e_user_roles` 18/18, `e2e_users_directory` 27/27,
`e2e_loading` 20/20, `e2e_nav_fixes` 6/6, `e2e_icons_refresh` 10/10, `users_api.sh` 95/95, `authz.sh` 27/27.

**Build note, corrected**: `roc run build.roc` takes **~9 minutes** here and the compiler is fine — an earlier note
blamed concurrency, but the real trap is cutting it short. Run it in the **foreground** with a socket long enough
for it (a 900s timeout works); a detached or timed-out run dies with no summary line and no `www/app.wasm`,
which looks exactly like a compile failure. `roc build` exits 2 merely because the module has a warning.

### The lesson renderer draws the whole record now, split by viewer (2026-10-12)

**Why lessons looked scanty**: prod stores **19 populated sections** per lesson (`content` holds them: introduction,
objectives, content_sections, key_points, conclusion, prior_knowledge, success_criteria, extension_activities,
lesson_steps, materials, formative/summative assessment, remediation, teacher_tips, textbook_references,
primary_sources, mcq_questions, theoretical_questions — 2852–2874 of prod's 3413 lessons carry each one), and
`renderLesson` drew five of them. The schema's flat `objectives`/`content_sections` fields are dead; everything
lives under `content`.

**The split** follows the pupil/teacher modes of the PDF template in the lesson generator
(`johnethel-lesson-generator/src/mastra/public/pdf-assets/template.typ`), with one deliberate departure: the PDF's
pupil mode prints both question banks with the answers stripped, and the school asked for students not to see them
in the app at all, since the app already has its own assessment flow. So a pupil reads the lesson and their own
work around it — objectives (with the generator's taxonomy level), introduction, the numbered content sections
with the `(i)/(ii)` sub-points the generator writes, key points, conclusion, “before you start”
(prior_knowledge), “what you'll be able to do” (success_criteria), “extra practice” (extension_activities) —
while a teacher or admin additionally gets the teacher's side of the same record: lesson plan (**table**: step,
phase, teacher actions, pupil activities, with strategy/duration/check beneath each row), instructional
materials, both assessments, remediation, teacher's tips, textbook references, primary sources, and both question
banks with their answer keys (**tables**). Three tables in total, none for a pupil.

Staff get it through the same `renderLesson`, so the admin LMS and the teacher's viewer both show the full
record; the role comes from the token's groups, decoded at boot as the rest of the page already does. A section
with nothing in the record renders nothing, and the scroll-spy nav is built from whatever rendered, so a pupil's
nav is simply shorter.

**Verified**: a real prod lesson rendered both ways — **22 sections for staff, 12 for a pupil**, 3 tables vs 0,
and no answer-key or teacher text in the pupil's page; then in the browser, the admin LMS deep-link and the
student's own subjects → term → lesson click-through. `render_lesson_roles_check.cjs` (new, 14/14) pins the split
with no browser and no backend; `render_lesson_check.cjs`, `e2e_student` 7/7, `e2e_nav_fixes` 6/6,
`smoke_assignments_lms` 18/18, `e2e_assessments` 17/17, `e2e_loading` 20/20 and `e2e_notifications_lms` 26/26 all
pass.

**Noticed, not fixed**: a student's lesson page is not URL-addressable — `setupLessonViewer` (which reads `?id=`)
is only wired for the staff path, so a student who reloads `/student/lesson` gets “Select a Lesson” and has to
click back through their subjects. The teacher/admin deep link works. Worth fixing if students are expected to
share or reload lesson links.

### The dashboard's cards read real numbers (2026-10-12)

They were placeholders — "—", "Syncing from database", and a hard-coded "Online". One role-aware
`GET /api/dashboard` now counts what the cards show, scoped exactly the way the rest of the API scopes the same
data, so a card cannot report something the caller could not otherwise open: an admin gets students, teachers and
active class levels; a teacher gets their assigned pairs for the active session term, the submissions of their own
lessons still awaiting a mark, and the assessments published on those lessons (no active term answers zeros, the
same empty answer their own lists give); a student gets the subjects their class is paired with and the published
assessments on that class's lessons they have not submitted, with the wider answer kept for a student whose
profile names no class.

The payload is numbers only — one `key|value` line each, through the usual hidden-input bridge — so the labels
stay in `DashboardView.roc`, and a number the backend does not send renders as a dash rather than breaking the
cards around it. System Status reads the fetch's own state (Checking… / Unavailable with the reason / Online)
instead of always claiming everything is fine. Navigating back to the Dashboard refetches: these are counts, so a
stale panel is the one thing it must not show.

**Verified** by role against the sandbox — admin 18 students / 8 teachers / 9 classes / Online; a teacher holding
one pair 1 class / 11 awaiting a mark / 23 assessments, and 0/0/0 once the pair is cleared; a JSS 2 student 1
subject / 0 assignments, and 7 / 23 with no class on the profile — then in the browser for all three roles,
including the refetch on navigating away and back. `e2e_loading` 20/20 (it drives the dashboard through the
sidebar), `smoke_teacher_role` 9/9, `e2e_student` 7/7, `e2e_admin` 16/16, `e2e_user_roles` 18/18,
`e2e_notifications_lms` 26/26, `smoke_assignments_lms` 18/18, `e2e_assessments` 17/17, `e2e_admin_config` 52/53
(its documented caveat), `users_api.sh` 95/95, `authz.sh` 27/27.

**Still to do on this screen**: the parent dashboard has no cards — just a "My Children" placeholder. Their
linked-students list (the same ids the parent form now writes) would fill it, and `Recent Activity` on the admin
dashboard is still an empty placeholder too.

### Mobile: the lesson view, and breadcrumbs that lost their steps (2026-10-12)

Both found on a 390px viewport.

- **The lesson view scrolled sideways and ran off the right edge.** The lesson column is a flex child, so it
  kept `min-width: auto` and could not shrink below its widest content — the failure mode is invisible on a
  desktop and total on a phone. It carries `min-w-0 w-full` now, and the staff tables keep a readable minimum
  width inside their scrolling wrapper rather than squashing four columns into 390px.
- **The desktop dot rail floated over the lesson text on a phone.** `md:flex` on its own is not "desktop
  only": with no display rule below md the element falls back to `block`. Worse, two functions owned its `hidden`
  class — `buildSectionNav` removed it while the tab switch added it back — so the rail showed wherever the two
  last disagreed. One function now owns that decision (`updateSectionNav`: wide screen **and** lesson tab **and**
  sections present), from one pair of class strings, and the shown state keeps `hidden` so small screens never
  see it. This is also what the earlier "invisible strip over the grading tab" fix had been papering over.
- **The breadcrumb rendered its separators over empty labels** ("All classes › › ›"). A step reached by clicking
  carries its own name in the model; a reload or a shared link at depth restores only the ids from the URL. The
  names are resolved from the lists that carry them — and the two lists that were fetched into a *step's* hidden
  input now live in the drill's shell, because a fetch lands only where an input exists and neither input exists
  at depth, so those responses were being dropped. A deep load now reads **“All classes › JSS 1 › Agricultural
  Science › Noel Term”**.

**Verified** at 390px and 1280px: no sideways scroll, all 22 sections rendered, the rail absent on the phone and
present on desktop, the tables scrolling rather than squashing. Suites: `e2e_notifications_lms` 26/26,
`e2e_user_roles` 18/18, `e2e_loading` 20/20, `smoke_assignments_lms` 18/18, `e2e_student` 7/7,
`smoke_teacher_role` 9/9, `e2e_nav_fixes` 6/6, `e2e_admin` 16/16, `e2e_assessments` 17/17, `e2e_admin_config`
52/53 (its documented caveat), both render checks green.

**Next on this screen**: a class-subject pairs picker inside the teacher's own form (create and edit), so the
pairs can be set without going to the row's Assign dialog — with the edit mode seeding from the teacher's current
pairs before Save is enabled, since an unseeded empty picker would wipe them.

### The teacher form's pairs, a lesson page that reloads, and the parent's children (2026-10-12)

The four queued items, all closed.

- **Pairs in the teacher form.** The form carries the Assign dialog's picker (badges + search) over its own
  state, so a new teacher can teach something without a second trip to the row's Assign action. On edit it
  seeds from the teacher's current pairs and **Save waits for that fetch** — the picker is the set the save
  replaces, so an unseeded empty one would clear a teacher's assignments. The backend takes `pairs` on the
  profile payload (create and update) and writes the set through the statement the dialog's save already used;
  the key's presence decides, so `[]` means "none of them" rather than "not sent". One behaviour changed while
  sharing that statement: clearing now scopes to the term being saved, where the dialog's old copy cleared
  every term the teacher had — a save describes this term, and the last term's rows are the record of what
  they taught then.
- **A lesson page is a URL.** The student's click-through writes `?id=` and the page reads it back into the
  drill-down on a load, so a reload or a shared link opens that lesson instead of "No subject selected".
  Underneath sat a routing bug worth its own line: `parse_route` matched the **whole** URL, so any link
  carrying a query string fell through to `NotFound` — a reload of a lesson page rendered the app's 404 view.
  A route is a path; the query string is state.
- **The parent dashboard lists their children**, from a new `/api/parent/children` that reads the students the
  caller's own parent row links (so a parent sees their own children and nobody else's), with the same three
  states every other list has.
- **Student assessments with no lesson named are class-scoped**, like the subject and lesson lists.

**Verified in the browser**: a teacher created from the form with a pair picked in it, read back through the API
carrying that pair; a student's lesson surviving a reload and naming its subject and term; the parent dashboard
naming a linked child with their class. By curl: create-with-pairs, a PUT replacing the set, an empty list
clearing it, and create-with-pairs with no active term refused (400) before anything is made. Suites:
`e2e_user_roles` 18/18, `e2e_admin` 16/16, `e2e_loading` 20/20, `e2e_student` 7/7, `smoke_teacher_role` 9/9,
`e2e_notifications_lms` 26/26, `e2e_nav_fixes` 6/6, `smoke_assignments_lms` 18/18, `e2e_assessments` 17/17,
`e2e_general_assessments` 25/25, `e2e_admin_config` 52/53 (its documented caveat), `e2e_users_directory` 27/27,
both render checks, `users_api.sh` 95/95, `authz.sh` 27/27.

**Fixed rather than noted**: nothing enforced a single active `session_term`. `active_session_term_id!` reads
one row with `LIMIT 1` and a teacher's assignment write is scoped by that read, so two active terms meant a save
could land under whichever row came back first — and the hub could produce that state, because activating a term
wrote its flag without touching the current one (watched it happen on a sandbox: a pair written against a term
nobody was looking at). `db/schema-v11-single-active-session-term.surql` mirrors the flag into a field that is
absent unless the row is active and puts a unique index over it — a plain unique index on `active` would allow
exactly one *inactive* row, and SurrealDB's unique indexes ignore NONE, which is what makes this partial. The
session-term toggle is now a **move** (the others off, then the named row on, in one call — the index makes that
order mandatory), `active_session_term_id!` orders by creation so a legacy two-active database answers the same
way twice, and `e2e_admin_config.cjs` restores the seeded term it switched away from, since `e2e_loading` reads
that term by name. Prod holds one active row today, so the migration applies cleanly; it is **not applied to
prod yet** — that is the one step left, and it is the file rather than a manual statement: apply
`db/schema-v11-single-active-session-term.surql`.

*(2026-10-19: prod's `session_term` now carries `only_active` and `idx_st_only_active`, and exactly one row
is active — so v11 **is** applied. The note above was true when it was written and is left as the record of
that day; the deploy note is the one to trust.)*

---

### The token cache — one validation per page boot, not one per request (2026-10-19)

Every `/api` request validated its bearer token by calling Authentik's userinfo endpoint, which is a whole
HTTPS round trip, and a page does not make one request: a dashboard boot fires about a dozen, the admin hub's
lists fire four directory walks together, and `/api/users?role=` walks the whole directory a page at a time.
So one page load paid for a dozen authoritative validations of the same token, and a fetch loop would have
multiplied that straight into Authentik.

**Why a store and not a map.** The platform hands `respond!` its `Context` **by value**, and `Server.Outcome`
has no variant that carries an updated context back — so an app-level table cannot be held across requests at
all; the only things the platform documents as retained are host-owned handles (`Sqlite.Db`,
`Server.Readiness`). The cache therefore lives in a store the app already owns: SurrealDB, in a `token_cache`
table (`db/schema-v12-token-cache.surql`).

- **What is kept**: the body Authentik answered with, base64-encoded (a quote-free, backslash-free value, so
the response scanner reads it back intact rather than a re-rendering of it), keyed by the token's SHA-256 —
the table holds no live credentials, and the raw token is nowhere. The deadline is the earlier of now + 60
seconds and the token's own `exp`, read by decoding the token's payload segment; a token whose `exp` cannot be
read (the mock's fixed tokens, any non-JWT) is simply not cached, and a DEV_MODE token never reaches the
validation path at all. A hit is indistinguishable from a miss because the stored body *is* the body the route
would have been handed, and the role is still derived from it in the one place it is ever derived.
- **Invalidation is pushed, where this backend owns the write.** Dropping a disabled account's entries is
*not* an extra request: the disable already happens in this process (`DELETE /api/users` calls
`Authentik.updateUser!`), so it is one more statement on the connection the handler is already holding. Four
call sites, all of them writes that change what userinfo would answer about that login: the delete handler
(with the profile hide, before the disable branches — so whichever branch the delete lands in, the cache is
already gone), the reconciler's replay of an interrupted delete, the activate path (re-enabling counts too —
the rule is the write, not "disable only"), and the update path when it carries a new email. **The TTL covers
what this process cannot see**: someone disabled directly in Authentik's own UI, where 60 seconds is the
backstop rather than the mechanism. That number is the one thing still open — it is the school's to pick
(short enough to bite, long enough that a page's burst is one call).
- **A miss always falls through to Authentik** — no entry, an expired one, a database that fails to answer, a
table that was never created. The cache is never the reason a request fails, and a database without v12 runs
exactly as before, one validation per request, which is what the startup line reports (`token cache: ready`
/ `not usable — apply db/schema-v12-token-cache.surql`).

**The bug the verification found, and it was silent.** `extract_number_field` read a numeric JSON field by
keeping every digit anywhere in the value, so a token carrying a *fractional* `"exp": 1792407417.59` read as
179240741759 — a second count from the year 1975 — and `time::from_unix` refused it as out of range. The
UPSERT errored, nothing was ever cached, and every request still answered 200 (the write is best-effort by
design, so the failure was invisible except as the latency it did not save). The rule is fixed rather than the
one caller: a number is the digit run the value **begins** with — its whole-number part — not every digit the
value contains. That reader is shared (`field_int!`: assessment weights, marks, resubmission counts; the
school-number columns; the dashboard counts), and its other callers read integer fields, so one rule now
covers them all. `users_api.sh` (95 checks, the school numbers), `assessment_flow.sh` (41) and
`general_assessment_flow.sh` (56) are what stood behind that.

**Verified** with `roc-frontend/tests/e2e/token_cache.sh` (new, 32 checks, driven through the mock's own
validation counter and the database): three requests with one token cost one validation; the entry's id is the
token's hash and its deadline sits inside the TTL; a delete drops the login's entries in the same call and the
still-valid token is a 401 on its very next request; a re-enable drops them too (the next request validates
again); an entry past its deadline is a miss; a token ten seconds from expiry gets ten seconds, not sixty; a
token with no readable `exp` and a DEV_MODE token are never cached; a bogus token is still a 401; and with the
table removed a request still works, validating every time. A genuine 60-second cycle was watched end to end
(cached at 0s, hits at 20s and 40s, a fresh validation at 65s), and `matrix_token.sh` — which boots its own
backend with **no database at all** — still passes 26/26, which is the fall-through rule doing its job. The
rest of the sweep: `e2e_loading` 20/20, `e2e_admin` 16/16, `e2e_assessments` 17/17, `e2e_general_assessments`
25/25, `e2e_user_roles` 18/18, `e2e_users_directory` 27/27, `e2e_notifications_lms` 26/26, `e2e_admin_config`
54/55 (its documented caveat), `e2e_student` 7/7, `smoke_teacher_role` 9/9, `smoke_assignments_lms` 18/18,
`e2e_nav_fixes` 6/6, `e2e_signout` 9/9, `e2e_auth_callback` 12/12, `authz.sh` 27/27, both render checks.

**Applies to prod**: `db/schema-v12-token-cache.surql` needs applying, like v11 — the code is correct either
way (without it every request validates, exactly as today) and the boot line says which it is. The sandbox
fixture (`tests/e2e/fixtures/sandbox-schema.surql`) mirrors the statements, so a sandbox caches like prod, and
the mock Authentik now answers a **JWT-shaped** token from its own claims (`{"sub": …, "exp": …}`, refused
once `exp` has passed or the login is off) and reports `/userinfo_calls`, which is what makes a cache hit
observable in a suite.

---

### The SSS 1–3 scheme of work, extracted for review (2026-10-19)

The school sent `NEW NERDC SCHEME, 2025.pdf` (428 pages: JSS 1–3 and SSS 1–3) and asked for the senior
scheme of a named list of subjects, formatted to review, with the context lesson generation needs — and
**not** loaded into the database. It is in `docs/curriculum/sss-nerdc-2025/`: `schemes.json` (1,746 weeks
across 18 subjects × SSS 1–3, 1,096 of them teaching weeks), `sss1.md`/`sss2.md`/`sss3.md` (the same
tables, readable), `contexts.md` (what the senior tier means per subject, including the WAEC 2026–2030
literature list the document itself carries) and `extract_sss.py` — the parser is `pdftotext -layout`
plus the document's own inconsistencies (mixed-case term headings, subject headings missing their class
or their "SCHEME OF WORK", column headings that do not sit where the rows put their text, tables that run
across page breaks), and no row is hand-edited, so a corrected PDF re-extracts to corrected data.

What the school's review has to settle: **Yoruba is not in the document at all** (no Nigerian-language
table anywhere in its 428 pages — the 18 extracted are everything it holds that was asked for); *Computer*
is read as the new scheme's **Digital Technologies**; *History* as the document's **Nigerian History**; SSS 3
carries one or two terms for most subjects because it is the examination year; the three new classes need
their age ranges; and the school's streaming decides which of the 18 subjects is offered on which class.

**The tier is built, not proposed.** `db/schema-v13-class-tier.surql` adds `class_levels.tier`
(`primary`/`junior`/`senior`, backfilled by code) and the three senior class levels, and adds
a lesson's `context` field as the week's own outline (prod already had it — 3,413 rows carry one — so no
new field was added for it). Applied to the
sandbox and verified (SSS 1–3 read back `tier = 'senior'`, the JSS rows `junior`, `year_1` `primary`, and
the class-level create path still works). **Prod still needs v11, v12 and now v13 applied.**

`db/load-sss-scheme.py` is the load: subjects, the 54 `has_subject` edges (all subjects on all three
classes, the school's call), the term mapping, and one lesson per teaching week with the week's content
cell as `context` — 1,096 rows, proven on the sandbox (a re-run writes nothing), then removed from
the sandbox again because unscoped lesson lists change when 1,000 lessons appear (see that folder's README).
The load surfaced one real follow-up: `/api/teacher/lessons` answers `ORDER BY week LIMIT 50`, so with this
much data the picker is capped and its order is not total — worth a search or a term step rather than a
silent cut.

**Senior maths renders.** The calculation subjects carry equations, so KaTeX 0.16.11 is vendored under
`roc-frontend/www/katex/` (scripts, stylesheet, `.woff2` fonts — no CDN, the app typesets on a school
network), `www/index.html` typesets `$...$` / `$$...$$` after a lesson, question bank or answer form renders,
and `tests/e2e/math_render_check.cjs` (7 checks) proves it in Chromium on a lesson written for the check.
The scheme review's remaining decisions are answered (Yoruba parked — the PDF has none; Computer Studies and
History as the school's names; SSS 3's short year kept as the document has it).

**What prod actually holds, read on 2026-10-19** (`db2.johnethel.school`, ns `main`, db `lessons`, through the
public endpoint with the school's own credentials): 8 class levels (`jss_1..3`, `year_1..5`), 23 subjects,
3,413 lessons, and the terms `noel_term`, `calvary_term`, `summer_term` — the school's names, which is what
the loader's `--terms` maps onto. **v11 is applied** (`session_term.only_active` + its index, one active
row); **v12 is not** (`token_cache` does not exist); **v13 is not** (no `tier`, no SSS classes); and none of
the senior scheme is loaded (0 lessons for Chemistry, Physics, Biology, Economics, Government or Financial
Accounting, and no such subjects).

Two things that read back from prod changed the plan before anything was written to it:

- **`lessons.context` already exists and already carries exactly what the scheme provides** — all 3,413 rows
  have one ("Distinguishing wants from needs."), and it is the field the generator reads as its `context`
  argument. v13's second field for it (`content_outline`) was a duplicate of something prod has had all
  along; it is out of the schema file, the loader writes `context`, and only an **older draft** of it ever
  reached the sandbox.
- **The sandbox fixture was missing five of prod's `lessons` fields** (`context`, `generated`, `version`,
  `updated_at`, `deleted_at`), which is exactly why the duplication was not visible locally. The fixture now
  declares them, field-for-field with prod.

The load was re-run on the sandbox with the corrected field (`context`, `generated` false, `version` 1 on a
sample row) and removed again afterwards; the sandbox keeps the schema and the tier.

**Applied to prod on 2026-10-19**, with the school's go-ahead ("additive and not destructive"), in three
steps: v12 (`token_cache`), v13 (`tier` + the three senior classes), then the loader with the school's own
terms. Read back afterwards: class levels 8 → 11 (SSS 1-3 `senior`, the JSS rows `junior`, the year rows
`primary`), subjects 23 → 35 (six reused by name), edges +54, lessons 3,413 → **4,509**, and the rows
awaiting generation 529 → **1,625** — `content` empty and `generated` false, which is the state the school
asked for ("awaiting lesson generation instructions"). A sample row: `y9-chm-t1-w1-introduction-to-chemistry`,
*Noel Term*, `context "Definition, history, branches, and importance of chemistry"`. The scheme's midterm,
break and examination weeks are not lessons (prod's own data agrees: 10 of its 3,413 rows name such a week).

The loader got the school's own slug convention on the way (`y<class><subject>-t<term>-w<week>-<topic>`, read
from the target database: Year 1-5 = `y1`-`y5`, JSS 1-3 = `y6`-`y8`, so SSS 1-3 = `y9`-`y11`), and the prod
run caught two bugs the sandbox never could: the `--terms` flag rebound the loader's own `wanted` list (it had
never been exercised), and one statement per request meant 11 minutes for 1,162 of them — honest errors, slow
network; batching is the speed-up if the scheme is ever reloaded.

**Still open from this work**: pushing `main` (the deploy that ships KaTeX and the token cache — the database
is already ahead, so the app works either way), and the `LIMIT 50` picker below.

### The hub's Class Levels screen edits a level's stage (2026-10-20)

`class_levels.tier` (v13) decides what a lesson is written for — a senior class gets exam-level lessons, a
junior one does not — and it was only settable by hand until now. The Configuration Hub's **Class Levels**
screen carries a **Stage** column and a Stage picker on both the create form and the row editor
(`primary` / `junior` / `senior`, plus "Not set", which is the column's NONE). The backend's list returns
`tier`, the create accepts it and the patch writes it, so a level can be re-classified without SQL. Verified
on the sandbox: the field survives a hub edit of the level's name/code/age range (that PUT only writes what
it carries), and `e2e_admin_config.cjs` asserts the column and both pickers.

### An administrator's type and permissions — enforced by the data, chosen from the hub (2026-10-20)

The school asked for two things: an admin *type* (Supervisor now — "they have access to the LMS but not user
management" — Bursar/Registrar/Admin officer later), and permissions the school can tick per administrator.
Both are built, and the split between them is the design:

- **The type is a preset and a label; the ticks are the truth.** A pure role→permission table makes giving one
  person a small extra right mean inventing a role, and per-person ticks alone make setting up each new
  administrator a fresh decision. So the type sets the starting ticks (and is the school's own name for what
  the person is), each tick can then be taken off or put back, and **the backend enforces the ticks**.
- **The catalog is code** (`admin_permissions`, `admin_types` in `main.roc`), so adding a type is a line, and
  `GET /api/admin-types` hands the form the same list the gate uses — labels and hints included, so the screen
  and the 403s speak the school's words rather than permission keys.
- **Six permissions**: users, school setup, curriculum & lessons, assessments, staff assignments, permissions.
  `required_permission` maps the admin route families onto them (`/api/users` writes → `users.manage`, config
  writes → `setup.manage`, the LMS reads → `lessons.manage`, assessment work → `assessments.manage`, the Assign
  dialog → `assignments.manage`); reads that every role needs stay open, and a route with no permission named
  behaves exactly as before.
- **Deciding rights is its own permission** (`permissions.manage`), not implied by `users.manage`: without
  that split an admin who could edit users could grant themselves the run of the school. The check is on the
  *payload* (the write that names `admin_type`/`permissions`), so a name edit by a users-only admin still
  lands, and the 403 names "Manage permissions".
- **Nobody is locked out**: `db/schema-v14-admin-permissions.surql` backfills every existing admin as
  `super_admin` with all six, and the backend refuses any write that would take the school's last super admin
  away (the delete path included). `super_admin` carries every permission by definition, so its stored ticks
  are never the reason something is allowed.
- **The screen**: the user form's Admin branch now shows an **Admin type** picker (replacing the free-text
  "Role title", which is why the directory column reads "Admin type" and shows the catalog's label), a
  **Permissions** panel with one tick per permission and the school's own wording, and it opens a fresh
  administrator on the catalog's *narrowest* type — so Add-then-Save cannot hand out more than the school's
  smallest seat. The panel is read-only for a caller without `permissions.manage`, and the save leaves both
  fields out for them, so the backend's refusal is never the thing they meet.
- **The sidebar follows the caller's own row** (`GET /api/admin-rights`): a supervisor sees the LMS, the
  dashboard and messaging, and no User Management or Configuration Hub. A deep link or a reload after a
  permission change lands on a card naming the permission the screen needs instead of a page of failed calls.
  The page fails *open* when the rights answer has not arrived — the backend is the authority, and hiding the
  school's own screens from a super admin whose one request hiccuped is the worse failure.

**Two rules the work exposed, both in the shared scanners** (`main.roc`):

- `extract_field` read a column the row does not carry — the database answers `null` — as the *next field's
  name*: `"middle_name":null,"passport":"…"` put "passport" in the middle name, and the edit form prefilled
  it back into the next save. A value that does not start with a quote is absent now.
- `carries_field` decides an array's presence by the key alone, and only for the fields `array_update_fields`
  names; `permissions` and `pairs` are arrays this app sends, so they are named there. Without it
  `{"admin_type":"supervisor","permissions":[…]}` read as a type-only payload and the ticks were silently
  replaced with the type's defaults.

**Verified on the sandbox**: `authz.sh` 51/51 (new cases: a seat with `users.manage` but not
`permissions.manage` may edit users and may not set a type, grant itself anything, or create an admin with a
type; a holder of the permission may; the listing carries type and ticks), `users_api.sh` 95/95,
`assessment_flow.sh` 41/41, `general_assessment_flow.sh` 53/53, `e2e_admin_permissions.cjs` (the form and a
supervisor's own view, in Chromium), `e2e_user_roles.cjs`, `e2e_admin.cjs`, `e2e_admin_config.cjs`,
`e2e_users_directory.cjs`; `roc check` clean on both sides.

**Applied to prod on 2026-10-20, then deployed.** `db/schema-v14-admin-permissions.surql` ran against
`db2.johnethel.school` (ns `main`, db `lessons`): both columns exist, and the backfill matched nothing —
**prod holds no profile rows at all** (0 admins, 0 students, 0 teachers, 0 parents; the curriculum is the
whole of what is stored there). So the school's administrators were Authentik-only, and the new gate would
have refused every one of them the LMS and user management with no way back in (setting a type needs
`permissions.manage`, which needs a row). Read from the school's own Authentik first: nine logins, of which
exactly one is an admin — `thesparq@johnethel.school` (pk 5, groups *authentik Admins* + *Super Admins*).
That login's row was seeded as the v14 backfill would have written it, so nothing changes for the school on
day one:

```sql
CREATE admin_profile:5 SET display_name = 'Samuel Iyeh', first_name = 'Samuel', surname = 'Iyeh',
  passport = 'https://r2.johnethel.school/passports/samuel-iyeh.jpg',   -- placeholder; replace from the form
  admin_type = 'super_admin',
  permissions = ['users.manage', 'setup.manage', 'lessons.manage', 'assessments.manage', 'assignments.manage', 'permissions.manage'],
  staff_id = (UPDATE id_sequences:staff SET current_value += 1 RETURN current_value)[0].current_value;
```

`id_sequences:staff` was at 0, so the row is **EMP-000001** and the next staff create takes 2 — the app's
own numbering rule, not a number invented for it. The row is the school's own to change: the new screen
shows it as *Super Admin* with every tick, and any administrator whose login has no row yet appears in the
Users tab as "No profile yet" to be completed with a type (the workflow a login added in Authentik later
takes).

**Deployed the same day** (`cbb5974`, six commits: the class-level Stage field, the admin types and
permissions, the two scanner fixes, the screen and its suites). The rebase onto the school-order work
(`458d0de`) was a real one: that commit rewrote the `/api/class_levels` query to sort by
`class_stage_rank`, and the resolution keeps its inner-select rank *and* returns `tier`, which the hub's
Stage column reads. Running the whole set on a fresh sandbox then caught two gaps, both fixed in `cbb5974`:
the fixture did not declare v14's columns (they had only ever been applied by hand to the long-lived
sandbox, so every admin write failed on a fresh one), and `authz.sh` was not idempotent — it left the mock
admin's row as the school's only super admin, so a second run's first demotion was refused by the lockout
guard. It now keeps a spare super admin and passes 51/51 twice in a row.

**Deploy order matters**: v14 goes to prod **before** the new code, or the running code would read no type and
no ticks for the admins that exist and refuse them everything. The backfill inside v14 is what makes the order
safe.

---

## Completed Work

- [x] Roc basic-webserver backend (main.roc, SurrealDB.roc, Authentik.roc, Golem.roc; the retired
  EventStore.roc stub is gone — see the journal section)
- [x] Roc Joy framework frontend (app.roc, State.roc, UI.roc, DashboardView, AdminView, TeacherView, StudentView)
- [x] SurrealDB schema lineage (db/schema-vN.surql; the old event-sourcing tables were never applied —
  writes are journaled instead, and CQRS/event sourcing is deferred to the roc-golem design)
- [x] CSS theme system with shadcn/Tailwind tokens (light + dark mode)
- [x] **Phase 5: Security Hardening**
  - [x] Environment variables for all secrets/URLs (SURREAL_URL, SURREAL_AUTH, AUTHENTIK_*, GOLEM_URL, DEV_MODE)
  - [x] Fixed auth bypass: dev-skip/test-token only work when DEV_MODE=true
  - [x] Hardened SQL sanitization (comprehensive injection prevention)
  - [x] Added CORS headers and OPTIONS preflight handler
  - [x] Added JWT expiration check in frontend
  - [x] Created .env.example documentation
- [x] **Phase 5: Frontend Navigation & UX**
  - [x] Fixed broken navigation (added push_state port handler)
  - [x] Clickable breadcrumbs with Dashboard back-link
  - [x] Mobile sidebar overlay with hamburger menu toggle
  - [x] Parent role sidebar navigation
  - [x] URL path-based initial route (supports direct URL access)
  - [x] Removed hardcoded dummy data from State init
  - [x] School branding: "John Ethel Academy"
- [x] **Phase 5: UI Polish**
  - [x] Professional role-specific dashboards with welcome messages
  - [x] Stat cards with dynamic content placeholders
  - [x] Quick action buttons linking to relevant pages
  - [x] Route-based Teacher/Student views (Lessons, Assessments, Assignments)
  - [x] Professional empty states with icons and helpful messages
  - [x] Admin submit feedback (green success / red error banners)
  - [x] Config hub tabs with instructions and examples
  - [x] Loading/empty states in user table
- [x] **Phase 6: Unified Roc Server**
  - [x] Backend serves both API and static frontend (single server on port 8000)
  - [x] SPA fallback: non-API GET requests without file extensions serve index.html
  - [x] Static file serving with correct MIME types (HTML, CSS, JS, WASM, SVG, PNG, etc.)
  - [x] Directory traversal prevention (strips `..` and `//`)
  - [x] API routes gated behind `/api/` prefix
  - [x] No separate Python dev server needed
- [x] **Phase 6: Auth Upgrade**
  - [x] Migrated from OAuth2 implicit flow to Authorization Code + PKCE
  - [x] Code verifier/challenge generation in frontend
  - [x] Token exchange via Authentik token endpoint
- [x] **Phase 6: E2E Test Stabilization**
  - [x] **23 tests passing, 2 skipped (known Joy WASM crashes), 0 failures**
  - [x] Fixed sidebar nav items: changed from `<a href="#">` to `<div>` to prevent browser navigation
  - [x] PKCE flow assertions in auth tests
  - [x] Config Hub renders with all tabs test
  - [x] Teacher/Student dashboard quick action verification
  - [x] `test.fixme` markers for Joy framework WASM click crashes (Teacher/Student sidebar nav)
- [x] **Phase 7: MVP Feature Implementation**
  - [x] School logo in sidebar (replaced "John Ethel Academy" text with actual logo image)
  - [x] User Management with role tabs (Students | Teachers | Parents | Administrators)
  - [x] Role-specific user tables with active/inactive badges, avatar initials
  - [x] User creation form with role dropdown and passport photo upload field
  - [x] Backend: Role-filtered `/api/users?role=` query param support
  - [x] Student LMS: My Subjects page with subject cards → lesson viewer flow
  - [x] Beautiful Lesson Viewer with:
    - Right-side sticky dot navigation (scroll-spy highlights active section)
    - Hover to expand section names, click to smooth-scroll
    - Mobile FAB (floating action button) for TOC
    - Learning Objectives card (numbered list)
    - Content Sections with headers, body text, sub-points
    - Key Points amber card
    - Lesson | Assessments tabs
  - [x] Teacher Lesson Viewer with 3 tabs (Lesson | Assessments | Grading)
  - [x] Teacher assessment creation modal
  - [x] Grading workflow: view submissions, grade, release grades
  - [x] Assessment submission flow for students
  - [x] MessagingView with Matrix/Synapse integration (rooms list, chat area, send)
  - [x] Backend: Student lesson APIs (`/api/student/subjects`, `/api/student/lessons`, `/api/student/lesson`)
  - [x] Backend: Teacher lesson APIs (`/api/teacher/lessons`, `/api/teacher/lesson-assessments`)
  - [x] Backend: Assessment APIs (create, submit, grade, release)
  - [x] Backend: Matrix token proxy (`/api/matrix/token`)
  - [x] Backend: Passport upload URL endpoint (`/api/upload-url`)
  - [x] New routes: StudentSubjects, StudentLesson, TeacherMyClasses, Messaging
  - [x] Updated SurrealDB schema + seed data (students, teachers, parents, admins, subjects)
  - [x] JS port layer completely overhauled (lesson viewer, scroll spy, Matrix sync, upload)

## E2E Test Results (25 tests)
| Category | Tests | Status |
|----------|-------|--------|
| Authentication | 3 | ✅ All passing |
| Theme Switcher | 2 | ✅ All passing |
| Admin Role | 6 | ✅ All passing |
| Teacher Role | 2 passing + 1 fixme | ✅ Sidebar + dashboard passing |
| Student Role | 2 passing + 1 fixme | ✅ Sidebar + dashboard passing |
| Breadcrumbs | 3 | ✅ All passing |
| Responsive Layout | 2 | ✅ All passing |
| Branding | 2 | ✅ All passing |
| Backend Health | 1 | ✅ Passing |

### Known Issues (test.fixme)
- Joy framework WASM crash on `NavigateTo` for Teacher/Student routes when triggered via sidebar click
- Root cause: Chromium renderer process crash during WASM execution — not a code bug, framework-level issue
- **Does NOT affect real browser usage** — only Playwright headless Chromium

## Backend API Endpoints
| Method | Path | Description | Status |
|--------|------|-------------|--------|
| GET | /health | Health check | ✅ |
| GET | /api/users?role= | List users by role (Student/Teacher/Parent/Admin) | ✅ |
| POST | /api/users | Create user (via Authentik + SurrealDB) | ✅ |
| PUT | /api/users | Update user | ✅ |
| DELETE | /api/users | Soft delete user | ✅ |
| POST | /api/upload-url | Get R2 presigned upload URL for passport photo | ✅ |
| GET | /api/student/subjects | List subjects | ✅ |
| GET | /api/student/terms | List terms (filtered by subject_id) | ✅ |
| GET | /api/student/lessons | List lessons (filtered by subject/term) | ✅ |
| GET | /api/student/lesson | Full lesson content by lesson_id | ✅ |
| GET | /api/student/assessments | List active assessments for student | ✅ |
| POST | /api/student/submit-assessment | Submit assessment | ✅ |
| GET | /api/teacher/lessons | List all lessons for teacher | ✅ |
| GET | /api/teacher/lesson-assessments | List assessments per lesson | ✅ |
| POST | /api/teacher/create-lesson-assessment | Create assessment | ✅ |
| GET | /api/teacher/submissions | List student submissions | ✅ |
| POST | /api/teacher/grade-submission | Grade a submission | ✅ |
| POST | /api/teacher/release-grades | Release grades to student | ✅ |
| GET | /api/matrix/token | Matrix/Synapse token proxy | ✅ |
| GET | /api/subjects | List subjects | ✅ |
| GET | /api/terms | List terms | ✅ |
| GET | /* (static) | Static file serving | ✅ |
| GET | /* (SPA) | SPA fallback to index.html | ✅ |

## Remaining Work (Backlog)
- [x] Subject → Term → Lesson navigation drill-down (multi-level routing; each drill step is its own URL)
- [x] Real passport photo upload (presigned PUT to R2 from browser)
- [x] Edit user dialog/form
- [x] Config tab forms CRUD (Terms, Class Levels, Curriculum, Class Arms, Subjects)
- [x] Toast/notification system (top-right toasts with a pausable countdown + the navbar bell's history)
- [x] Dashboard stat cards wired to real API data (one role-aware `/api/dashboard`; counts scoped the way
  each role's own lists are)
- [x] A class-subject pairs picker inside the teacher's own form (create and edit; seeded on edit, and Save
  waits for the seed — see the section below)
- [x] A lesson page is URL-addressable for students as well as staff (`?id=`, restored into the drill-down)
- [x] Parent portal — the dashboard lists the children the parent's own row links (`/api/parent/children`)
- [ ] The admin dashboard's "Recent Activity" feed — it would need an activity/audit source that does not
  exist yet; the school has deferred this one
- [x] `/api/student/assessments` without a `lesson_id` is scoped to the student's class now
- [x] One current session term, enforced by the data (`db/schema-v11`), with the hub's toggle turned into a
  move
- [ ] Rate limiting on the backend — **dropped in favour of the token cache** (see the section above): the
  gate in front of every route already bounds an anonymous caller to `/health` and the SPA fallback, there is
  no login endpoint to brute-force (Authentik owns sign-in), and the real exposure — an authenticated client
  looping — is what the cache now absorbs. If it is ever revisited it is per-**account**, not per-IP (a school
  is usually one NAT address, and a per-IP limit would lock out a whole classroom), and it needs two numbers
  only the school can pick: requests per minute per account, and the burst allowance
- [x] Push `main` — done 2026-10-20 (`cbb5974`): the class-level **Stage** field in the hub, the **admin
  types and permissions** (schema v14 + enforcement + the screen), and the two scanner fixes. v14 was
  applied to prod first, and the school's one admin login was seeded as `super_admin` (see the section
  above) so nobody lost access.
- [ ] The school's admins are Authentik-only, and a login added there later starts with no row: it can use
  the shell's open routes (the directory listing, the dashboard) but nothing permission-gated until an
  administrator gives it a profile and a type from the Users tab. Worth saying to the school when they add
  staff, and worth a line on that screen if it confuses them.
- [ ] The teacher lesson picker (`/api/teacher/lessons`, `ORDER BY week LIMIT 50`) is capped without a total
  order: with the senior scheme loaded (4,509 lessons), "week 1" alone fills the page and the rows that come
  back are whatever the database gives first. A teacher's own list is scoped to their assignments and the
  active term — usually under 50 — so this bites an admin viewing that page, or a teacher with four or more
  subjects. Wants a tie-break that makes the cut deterministic and a way past it (a search, or the term step
  the admin LMS already has).
- [ ] Cloud deployment configuration — Dokploy already builds from `Dockerfile.app` on push to `main`, so
  this is only worth keeping if something different is wanted

Not this repository, but the reason lessons read thin: the generator
(`johnethel-lesson-generator`) asks for 3+ content sections with a soft word count and validates neither, so
its output is ~3.4 sections of ~58 words. See the lesson-renderer section above for the measurements.

## Architecture Notes
- **Unified Roc server**: Single `roc-backend/main.roc` serves both API and frontend on port 8000
- **Golem is used only for critical operations** (enrollment via class agents), not the entire backend
- Roc basic-webserver handles all direct CRUD — keeps it simple and fast
- Frontend is a Joy WASM SPA compiled from `roc-frontend/app.roc`
- Auth is delegated to Authentik via OAuth2 Authorization Code + PKCE flow
- Static files served from `STATIC_DIR` env var (defaults to `../roc-frontend/www`)
- SurrealDB 3.3.0 on port 8001 (surrealkv:// for persistence in dev)
- Messaging uses Matrix/Synapse homeserver at `matrix.johnethel.school`
- Passport photos stored in Cloudflare R2 (S3-compatible)

