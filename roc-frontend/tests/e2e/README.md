# End-to-end checks for the school app

These verify the Joy/WASM app against a running backend. Run them after changing `www/index.html`,
`State.roc`, the views, or the backend handlers.

(The `*_test.roc` files one level up are the Joy TodoMVC template's own suite — they test the template, not
this app.)

## Prerequisites

- A build: `cd ../.. && roc run build.roc` (the Joy platform is pinned by release-bundle URL in
  `app.roc`'s header, so Roc downloads it on the first build — nothing to vendor).
- A running backend serving that build:
  `cd ../../../roc-backend && DEV_MODE=true infisical run --env=dev -- roc run main.roc`.
  `DEV_MODE` is what lets these scripts use the `dev-skip` bearer token instead of a real Authentik login.
- Playwright for the browser checks: `npm i -D playwright && npx playwright install chromium` at the repo
  root, or point `NODE_PATH` at an existing install.

`APP_URL` overrides the target (default `http://127.0.0.1:8000`).

`DEV_MODE=true` exposes the tokens that stand in for a login: each names the role it acts as, so a
suite can drive a role without an Authentik session. `dev-skip` is the all-access admin the scripts
here use, `dev-student` and `dev-teacher` are the same idea for the other roles, and `test-token` is
`dev-skip`'s older alias (also an admin). The role of a real token comes from its userinfo `groups`
claim instead; `authz.sh` is the check that the gate bites either way.

## The checks

| Script | What it proves | Needs |
|---|---|---|
| `render_lesson_check.cjs` | The page's own `renderLesson` turns a real lesson into the expected sections (introduction, objectives as text, content sections, sub-points, key points, conclusion) and leaks no raw JSON. No browser: it stubs the DOM and runs the page's JavaScript. | Backend + a lesson id |
| `e2e_signout.cjs` | The nav bar's avatar menu and sign-out: the menu starts closed, opens on a click, shows who is signed in and offers Sign Out, closes on a click outside; signing out navigates to Authentik's end-session with this origin's callback as the return and clears the token from storage. | Backend |
| `e2e_auth_callback.cjs` | The OAuth2 round trip with Authentik's endpoints intercepted: the redirect URI the app sends is `<origin>/auth/callback` on both legs, the code is exchanged on the callback path with the PKCE verifier, the token is stored, the URL is cleaned back to the root, and a bare callback visit starts from the root too. | Backend |
| `auth_config_check.cjs` | An origin's auth wiring against the *real* Authentik, no browser: the advertised userinfo endpoint is the instance-wide one and matches what the backend derives, it answers 401 for a bad token, and the app's redirect URI is registered (with an unregistered one rejected as a control). | Network access to Authentik |
| `e2e_student.cjs` | Student drill-down in Chromium: subject cards from prod, terms, lessons filtered by subject+term, full lesson content, scroll-spy sections, no page errors. | Backend |
| `e2e_admin.cjs` | Admin user management in Chromium: the form creates a user (a password generated in the form rides the create; the one-time credentials panel hands the address and the once-visible password over with a Copy button that reaches the clipboard), the new account appears in the table, and a validation error surfaces in the UI. | Sandbox backend |
| `e2e_users_directory.cjs` | The directory half of user management in Chromium: a login the fixture's Authentik lists for a role with no profile row behind it is a row with the `No profile yet` badge and a Complete profile action, that action loads it into the form above (which switches to `Complete Profile`, a disabled email field holding the login's address, a disabled role picker and a `Complete profile` submit), the submit writes `PUT /api/users` about that login and nothing else, reports `Profile completed`, and the row then renders like any other (no badge, the profile's own name, the login's address, Edit and Deactivate back). Then the row's own actions: the toggle follows the login's true state (Activate while the suite's own delete has left it off, Deactivate once it is back on), and Edit loads the row into the form prefilled, whose Save changes patches it and shows the edited values in the table. Deletes the profile it finds on that login before it starts, so it can be run again and again against one sandbox. | Sandbox backend |
| `e2e_admin_config.cjs` | Admin configuration hub in Chromium: every section (terms, class levels, subjects, session terms, the curriculum edge) lists the fixture's rows, a create through the form appears in the list afterwards, and a refused create shows the backend's own text (400 validation, or the database's statement message). Then managing what exists: a row edited in place and the same rename refused by a unique index, a subject deactivated (off `/api/subjects`, still in the hub with an Inactive badge) and reactivated, a session term created inactive switched on, and a curriculum edge switched off and back on. Re-entering the hub from the dashboard refetches the lists. | Sandbox backend |
| `e2e_assessments.cjs` | Assessment lifecycle in Chromium: the teacher picks a lesson, creates a draft, publishes it; the student sees it and submits; the teacher's grading list shows the auto-scored MCQ marks; the teacher grades and releases. | Sandbox backend |
| `assessment_flow.sh` | The same lifecycle over the API with curl, including the draft/published rules, MCQ auto-scoring, the deadline and the resubmission limit, and the validation errors. | Sandbox backend |
| `users_api.sh` | User management over the API with curl: the listing's email and enabled state come from Authentik (not from the profile tables), a new email is patched into Authentik and shows up in the listing, an unknown id or a malformed address is still a 400, and a delete soft-deletes the profile row *and* disables the login — a login Authentik cannot disable answers 502 rather than success. Also the directory-driven listing: a login the fixture's Authentik lists alone appears with `has_profile:false` and its own address, the two logins in no role group appear in no tab, `PUT` on that login is a 400 naming the missing field until it carries the student set (then the row lists with the profile's own fields), a second `PUT` is a patch that keeps what it leaves out and does not rewrite `created_at`, and a `DELETE` then `PUT` leaves the login listed as a bare login and then restores the profile with `deleted_at` cleared. | Sandbox backend, mock Authentik and its database. Its school-number checks read the counters out of the database on either side of the writes: a create moves its role's counter exactly once and the row carries the rendered number (`JES-000001`, `EMP-000001`), a refused create and a create the database itself rejects burn no number, a teacher and an admin draw from the one `staff` counter, a pk that is a teacher and is then given an admin profile reuses its number, a number already in use is refused by the column's unique index, a parent is created with none, and a `PUT` carrying either number is a 400 naming the field. |
| `authz.sh` | Role-based authorization over the API with curl: `dev-skip` (admin) still reaches a student route, a teacher route and the user/configuration writes; `dev-student` and `dev-teacher` are refused the routes outside their role with a 403 naming the role the route needs; the role of a real-looking token comes from the mock userinfo `groups` claim; and a missing or bogus token is still a 401. | Sandbox backend, mock Authentik with `AUTHENTIK_ISSUER_URL` |
| `e2e_general_assessments.cjs` | General (term-weighted) assessment lifecycle in Chromium: the teacher creates one with hand-written questions from the Assessments & Grading hub and publishes it; the student sees it under My Assignments, answers it, and a closed one shows its deadline state; the teacher grades and releases it from the hub's Grading tab. | Sandbox backend |
| `e2e_loading.cjs` | Loading states in Chromium, driven by *clicking* — landing on the dashboard and going through the sidebar — because that is the path the suites above never took. The users list shows a skeleton that hands over to its table, no list is left on a loading message, the top border bar shows for a navigation and for a tab switch and goes away once the view has rendered, the nav bar carries the active session term, a tab switch shows that tab's own rows, a list whose payload is empty shows the empty state (faked for one tab through the route interception, because the fixture's directory gives every tab a row), and with `/api/users?role=*` answering 500 the list shows the backend's own message with a retry (and the retry loads the list) instead of a spinner. | Sandbox backend |
| `general_assessment_flow.sh` | The same general lifecycle over the API, including `assessment_type=general` submissions, the weight budget, the strict question shape and the opens/closes/attempt rules. Creates its own subject per run, so it never spends the fixture's weight budget. | Sandbox backend |
| `matrix_token.sh` | The chat proxy (`GET /api/matrix/token`) against a mock Synapse (`fixtures/mock_synapse.py`): no/bogus token is a 401; every role is allowed and receives a homeserver plus a real token (not the old `null` stub); the backend upserts and logs in **the caller's own** encoded user id with the caller's display name; a valid cached token is reused (validated via whoami, no new device minted) while a stale one is replaced; a missing `MATRIX_ADMIN_TOKEN` answers 503 naming it. Self-contained: builds the backend and boots it twice plus the mock — no database or Authentik needed. | Roc toolchain |

```sh
node tests/e2e/render_lesson_check.cjs            # defaults to a known prod lesson
LESSON_ID=lessons:... node tests/e2e/render_lesson_check.cjs
node tests/e2e/e2e_student.cjs
node tests/e2e/e2e_auth_callback.cjs
node tests/e2e/e2e_signout.cjs
node tests/e2e/auth_config_check.cjs                    # defaults to the deployed origin
node tests/e2e/auth_config_check.cjs http://127.0.0.1:8000
node tests/e2e/e2e_admin.cjs
node tests/e2e/e2e_users_directory.cjs
node tests/e2e/e2e_admin_config.cjs
node tests/e2e/e2e_assessments.cjs
node tests/e2e/e2e_general_assessments.cjs
node tests/e2e/e2e_loading.cjs
sh tests/e2e/matrix_token.sh          # self-boots backend + mock Synapse (see its header)
sh tests/e2e/assessment_flow.sh
sh tests/e2e/users_api.sh
sh tests/e2e/general_assessment_flow.sh
sh tests/e2e/authz.sh
```

## Sandbox for the admin and assessment checks

`e2e_admin.cjs`, `e2e_users_directory.cjs`, `e2e_admin_config.cjs`, `e2e_assessments.cjs`, `e2e_general_assessments.cjs`,
`assessment_flow.sh`, `general_assessment_flow.sh`, `users_api.sh` and `authz.sh` write rows, so they must not run against
prod. Start a throwaway SurrealDB, load the schema fixture, and point a backend at it plus the mock Authentik:

```sh
surreal start --bind 127.0.0.1:8002 --user root --pass root surrealkv:///tmp/school-sandbox/db &
curl -s -u root:root -X POST http://127.0.0.1:8002/sql \
  -H 'surreal-ns: main' -H 'surreal-db: lessons' -H 'Accept: application/json' \
  --data-binary @tests/e2e/fixtures/sandbox-schema.surql
python3 tests/e2e/fixtures/mock_authentik_unique.py &

cd ../../../roc-backend && DEV_MODE=true \
  SURREAL_URL=http://127.0.0.1:8002/sql SURREAL_USER=root SURREAL_PASS=root \
  AUTHENTIK_API_URL=http://127.0.0.1:9000/api/v3/core/users/ AUTHENTIK_API_TOKEN=mock \
  AUTHENTIK_ISSUER_URL=http://127.0.0.1:9000/application/o/school/ \
  roc run main.roc
```

`AUTHENTIK_ISSUER_URL` is what makes the backend validate real-looking tokens against the mock's
userinfo endpoint (`AuthUrls` derives `/application/o/userinfo/` from it); without it those tokens
would be validated against `localhost:9000` regardless of the mock's port, and every `mock-*-token`
case in `authz.sh` would be a 401.

The fixture schema mirrors the prod profile, lesson and assessment tables (SCHEMAFULL, including the required
`passport`, `display_name` and `questions` fields) plus the lookup tables' unique indexes, the school-number
statements from `db/schema-v8-ids.surql` (`id_sequences` and the `option<int>` number columns, so the sandbox
draws the same numbers prod will) and `session_term`,
seeds the class levels, terms, one subject with its `has_subject` edge, one lesson, one session term, and a
`student_profile:dev_user` so the dev-skip caller resolves a name. The
lesson's `content.mcq_questions` carry a `correct_answer` letter, which is what the create-assessment modal
stores as the question's `answer` and what submit-time MCQ scoring compares against. The
mock keeps a user table: a fresh `pk` per create, which is what keeps each created account's record id
distinct; GET lists in Authentik's own shape, PATCH updates the fields it is given, DELETE removes one (the
compensation path's call) and an unknown pk answers 404. The repo's `mock_authentik.py` returns a constant
`pk`, so per-role runs would collide on the record id. It also serves the instance-wide userinfo path the
backend validates tokens against: `mock-student-token` (`Students`), `mock-teacher-token` (`Teachers`),
`mock-admin-token` (`Administrators`) and `mock-groupless-token` (a login in no group, i.e. a student) answer
with the `groups` claim a real session would carry, which is where `authz.sh` gets a role without DEV_MODE
(this is why the backend needs `AUTHENTIK_ISSUER_URL` pointing at the mock).

That user table also **starts seeded**, with the logins an admin creates in Authentik itself, because the
listing has to show them: `seed-student` (Students), `seed-teacher` (Teachers), `seed-parent` (Parents),
`seed-admin` (Super Admins) and `seed-inactive` (Students, switched off in Authentik), plus two that belong
to no role — `seed-service-account` (no group at all) and `seed-outpost` (group `sms-service-account`) — which
must appear in no tab. The sandbox database seeds **no** profile row for any of them, which is the state the
directory-driven listing is about. A seeded pk carries the mock's pid like a created one does, so a suite
reads its id out of the listing rather than hard-coding it. `users_api.sh` completes such a login, and both
`e2e_loading.cjs` (the teachers tab's row) and `e2e_users_directory.cjs` (the row it completes) read them.

`users_api.sh` and `e2e_users_directory.cjs` both attach a profile to the seeded student login, so each
restores the state it starts from: `users_api.sh` drops any profile row left on it before its directory checks
(a hard delete, so nothing stays hidden behind `deleted_at`), and `e2e_users_directory.cjs` deletes the profile
it finds through the API, which lists the login as a bare login again — that delete switches the mock login
off, as a delete does, so neither suite reads its enabled state. Both can therefore be run again and again
against one sandbox, in either order.

`users_api.sh` needs the mock and the database it points at, not just the backend, because it checks both
sides of a delete. Run it with the sandbox's own addresses:

```sh
APP_URL=http://127.0.0.1:8000 MOCK_AUTHENTIK_URL=http://127.0.0.1:9000 \
  SURREAL_URL=http://127.0.0.1:8002/sql sh tests/e2e/users_api.sh
```

Two schema notes learned from the prod tables: relations are created with `RELATE` (`CREATE` on a relation
table is rejected), and `questions` / `answers` are `array<object>`, which implies their `.*` sub-field.

`general_assessments` and `compositions` are in the fixture too (prod's field definitions). The fixture
carries the six `questions.*` sub-field statements from `db/schema-v3.surql` that prod has not had applied
to `general_assessments`: without them this SurrealDB generation rejects every question object, so a
sandbox could not store what the implementation writes. Apply those statements to prod before general
assessments with questions can be created there. `general_assessment_flow.sh` reads its own rows back out
of the database when `SURREAL_URL` is set (the same address the backend uses, e.g.
`SURREAL_URL=http://127.0.0.1:8002/sql`), which is how it checks the stored questions and answers against
those field definitions.

`e2e_loading.cjs` writes nothing, but it reads the fixture: it asserts the nav bar's badge against the
seeded `session_term` ("2026/2027 — Noel Term"), so it wants that sandbox too. It also reads the seeded
directory, because every tab of it has a row now: the tab it switches to has to list its own seeded login, so
it wants the mock's seeded logins as well. Its empty state is faked for one tab through the route
interception, which is what keeps that state observable whatever the fixture seeds.

The general-assessment checks consume the term/subject weight budget (100%). `general_assessment_flow.sh`
creates its own subject through the API on every run, so it starts from an empty budget and can be run
again on the same sandbox. `e2e_general_assessments.cjs` still creates on the subject its pickers select
(the fixture's `subjects:agricultural_science`, 10% + 1% per run), so reload the fixture once a few runs
have spent that subject's budget, or point `E2E_SUBJECT_ID` at one with room left.
