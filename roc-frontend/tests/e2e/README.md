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
| `render_lesson_roles_check.cjs` | Which sections each viewer is shown. No browser and no backend: it runs the page's own script against a lesson shaped like the ones prod stores (every section the record can carry) and checks that a pupil gets the lesson and their own work around it — objectives, the body, key points, conclusion, "before you start", "what you'll be able to do", extra practice — while a teacher or admin gets all of that plus the teacher's side (lesson plan as a table, materials, both assessments, remediation, teacher's notes, references, primary sources) and the answer keys behind both question banks; that the pupil's page carries none of those, no tables and no raw JSON; and that a lesson with no content says so rather than rendering an empty page. | Nothing (runs against `www/index.html` alone) |
| `e2e_signout.cjs` | The nav bar's avatar menu and sign-out: the menu starts closed, opens on a click, shows who is signed in and offers Sign Out, closes on a click outside; signing out navigates to Authentik's end-session with this origin's callback as the return and clears the token from storage; and the card the person is left looking at while that navigation is under way is centered in the visible page, evenly padded inside, and (at phone width) no wider than the screen with nothing spilling sideways. | Backend |
| `chat_channels.sh` | The school's chat channel directory over the API: a pupil may read it but not list a channel (403), someone with no token is refused (401), a listing that names no visibility makes a *private* channel (fail closed), a pupil's list carries the public channels but not the private ones while an administrator's carries both with their codes, a code turns its channel up whatever its case (and a code nobody holds is a 404, not an empty list), a code another channel holds is refused (`code_taken`), re-listing a channel replaces its code and leaves one row, and the shapes a listing will not accept (a room id that is not one, no name, no code, a name over 120 bytes) all answer 400. Makes sure the channel table exists and takes its own rows back out. | Sandbox backend + mock Authentik + the sandbox database |
| `e2e_chat_channels.cjs` | The same two kinds of channel as the person meets them, in Chromium: an administrator makes a public one (the create carries `visibility: public`) and hands out the code they are shown; a pupil sees it in *Join*, joining is a real join, and the channel lands in their own list; a private one is made unlisted, is **not** in the pupil's directory, is not opened by a code nobody holds, and **is** opened by its code. Builds the backend, boots it against the sandbox database and a mock Synapse (its own port), installs the channel table if missing, and removes its rows. | Sandbox database + mock Authentik + playwright |
| `e2e_auth_callback.cjs` | The OAuth2 round trip with Authentik's endpoints intercepted: the redirect URI the app sends is `<origin>/auth/callback` on both legs, the code is exchanged on the callback path with the PKCE verifier, the token is stored, the URL is cleaned back to the root, and a bare callback visit starts from the root too. | Backend |
| `auth_config_check.cjs` | An origin's auth wiring against the *real* Authentik, no browser: the advertised userinfo endpoint is the instance-wide one and matches what the backend derives, it answers 401 for a bad token, and the app's redirect URI is registered (with an unregistered one rejected as a control). | Network access to Authentik |
| `e2e_student.cjs` | Student drill-down in Chromium: subject cards from prod, terms, lessons filtered by subject+term, full lesson content, scroll-spy sections, no page errors. | Backend |
| `e2e_admin.cjs` | Admin user management in Chromium: the form creates a user (the number field is read-only and empty until the save, no address is given at all, and a password generated in the form rides the create; the one-time credentials panel hands over the login the school issued — `JES-000123` — with the once-visible password, and its Copy button reaches the clipboard with both), the new account appears in the table under that same number, the row's Edit form shows the number again still read-only, the backdrop closes it, the Reset password modal names the account by its login, and a validation error surfaces in the UI. | Sandbox backend |
| `e2e_user_roles.cjs` | The role-tailored half of user management in Chromium: the modal's fields follow the picked role (a student's date of birth and class level, a teacher's date employed and qualifications picker, a parent's linked-students picker, an administrator's role title) and the other roles' fields are absent, the table's extra column is the tab's own (Class for students, Students for parents, Role title for administrators, none for teachers) beside the school number and status every tab shares, the modal sits over a blurred backdrop, and a click on that backdrop cancels the form without a write. | Sandbox backend |
| `e2e_passport_upload.cjs` | Passport upload from the admin modal in Chromium, with R2's PUT intercepted: the file input signs a URL, PUTs the photo, the public URL lands in the passport field, and the created profile carries it. `503` mode runs the same form against a backend started without the R2 variables and checks the form shows the backend's own message and uploads nothing. | Sandbox backend on the target port, started with the R2 variables (see its header for the values the checks read back) |
| `e2e_users_directory.cjs` | The directory half of user management in Chromium: a login the fixture's Authentik lists for a role with no profile row behind it is a row with the `No profile yet` badge and a Complete profile action, that action loads it into the form above (which switches to `Complete Profile`, a disabled email field holding the login's address, a disabled role picker and a `Complete profile` submit), the submit writes `PUT /api/users` about that login and nothing else, reports `Profile completed`, and the row then renders like any other (no badge, the profile's own name, the login's address, Edit and Deactivate back). Then the row's own actions: the toggle follows the login's true state (Activate while the suite's own delete has left it off, Deactivate once it is back on), and Edit loads the row into the form prefilled, whose Save changes patches it and shows the edited values in the table. Deletes the profile it finds on that login before it starts, so it can be run again and again against one sandbox. | Sandbox backend |
| `e2e_admin_config.cjs` | Admin configuration hub in Chromium: every section (terms, class levels, subjects, session terms, the curriculum edge) lists the fixture's rows, a create through the form appears in the list afterwards, and a refused create shows the backend's own text (400 validation, or the database's statement message). Then managing what exists: a row edited in place and the same rename refused by a unique index, a subject deactivated (off `/api/subjects`, still in the hub with an Inactive badge) and reactivated, a session term created inactive switched on, and a curriculum edge switched off and back on. Re-entering the hub from the dashboard refetches the lists. | Sandbox backend |
| `e2e_boot_and_cache.cjs` | What the page costs to load, in Chromium: the boot screen is in the served HTML with its own inline styles (not a stylesheet), it is what is on screen while the bundle is still coming down and it says so in the school's words after a few seconds; a bundle that never arrives turns it into "the app could not start" with a reload button rather than a blank page; an admin page fetches **no** KaTeX at all; the webfonts arrive beside the page (`media=print` switched to `all`) instead of blocking it; and every static file is served `no-cache` **with** a validator, so the validator the first response carried earns a 304 with no body while one from an older build earns the bundle again. Needs `www/build-id.txt` (written by `build.roc`) for the caching half. | Sandbox backend |
| `e2e_admin_responsive.cjs` | The configuration hub, user management and messaging at the width of a phone (390x844), in Chromium. Every configuration section and every users tab lays its rows out as stacked cards — the header row is dropped, each cell prints the name of the column it sits in, and a user row's tick, avatar and name stay together on its first line — with nothing crossing the right edge of the screen and the tab strip scrolling inside its own box rather than off the edge; the page header's *Add New User* button is whole and on screen, the form modal fits the screen, and the messaging page stacks its channel list over a viewport-tall conversation whose composer stays inside it. Then the same pages at 1280x800, where all of it has to be gone again: table rows are rows, the header row is back, no cell prints a column name, and the messaging panels sit side by side. | Sandbox backend |
| `e2e_keyboard.cjs` | The keyboard, in Chromium, on the admin pages and a teacher's lesson: the sidebar and breadcrumb are real links (Tab reaches them, Enter follows the focused one) and a modal takes the focus when it opens, keeps Tab inside it, hands the focus back to its opener when Escape closes it, and sends its form when Enter is pressed in a field (the same POST the button sends); Space ticks a row's checkbox and switches a configuration tab (with `role`/`aria-checked`/`aria-selected` saying so); Enter in the hub's create form sends it; Escape closes the bell's panel and the page's own assessment modal (Enter sends that one too). Answers the two writes that would leave a row behind with a stub, and clears the teacher's own pair again. | Sandbox backend |
| `e2e_assessments.cjs` | Assessment lifecycle in Chromium: the teacher picks a lesson, creates a draft, publishes it; the student sees it and submits; the teacher's grading list shows the auto-scored MCQ marks; the teacher grades and releases. | Sandbox backend |
| `assessment_flow.sh` | The same lifecycle over the API with curl, including the draft/published rules, MCQ auto-scoring, the deadline and the resubmission limit, and the validation errors. | Sandbox backend |
| `users_api.sh` | User management over the API with curl: the listing's email and enabled state come from Authentik (not from the profile tables), a new email is patched into Authentik and shows up in the listing, an unknown id or a malformed address is still a 400, and a delete soft-deletes the profile row *and* disables the login — a login Authentik cannot disable answers 502 rather than success. Also the directory-driven listing: a login the fixture's Authentik lists alone appears with `has_profile:false` and its own address, the two logins in no role group appear in no tab, `PUT` on that login is a 400 naming the missing field until it carries the student set (then the row lists with the profile's own fields), a second `PUT` is a patch that keeps what it leaves out and does not rewrite `created_at`, and a `DELETE` then `PUT` leaves the login listed as a bare login and then restores the profile with `deleted_at` cleared. | Sandbox backend, mock Authentik and its database. Its school-number checks read the counters out of the database on either side of the writes: a create moves its role's counter exactly once and the row carries the rendered number (`JES-000001`, `EMP-000001`), a refused create and a create the database itself rejects burn no number, a teacher and an admin draw from the one `staff` counter, a pk that is a teacher and is then given an admin profile reuses its number, a number already in use is refused by the column's unique index, a parent is created with none, and a `PUT` carrying either number is a 400 naming the field. Then the login itself, which *is* that number: a pupil with no address at all is created and the write's own answer carries the login (`username`, `JES-…`) that its row lists as both `username` and `school_number` and that the mock's record holds with an empty address; a member of staff is the same on the staff series; a parent without an address is refused with "it is their login" while one made with an address signs in by it; and a create the database rejects leaves a gap in the series (the number was drawn before the login, which was then rolled back) while a refused one burns nothing. The account also carries the number's short form as its `upn` — the one other identifier Authentik's identification stage can match — and the mock's own grant finds the login by either spelling, so both `JES-000123` and `JES-123` are asked for. |
| `authz.sh` | Role-based authorization over the API with curl: `dev-skip` (admin) still reaches a student route, a teacher route and the user/configuration writes; `dev-student` and `dev-teacher` are refused the routes outside their role with a 403 naming the role the route needs; the role of a real-looking token comes from the mock userinfo `groups` claim; and a missing or bogus token is still a 401. | Sandbox backend, mock Authentik with `AUTHENTIK_ISSUER_URL` |
| `token_cache.sh` | The backend's token cache, with the mock's own validation counter as the instrument: three requests carrying one minted (JWT-shaped) token cost exactly one userinfo call; the entry is keyed by the token's SHA-256 and its deadline is the earlier of the TTL and the token's own `exp`; deleting an account drops its entries in the same call, so the still-valid token is a 401 on its next request, and re-enabling drops them too; an entry past its deadline is a miss; a DEV_MODE token and a token with no readable `exp` are never cached; with the table removed every request validates and nothing fails. | Sandbox backend, mock Authentik and its database |
| `math_render_check.cjs` | Maths in a senior lesson renders as maths. It writes its own lesson (week 99 under the fixture edge, so it cannot collide with the seeded week 1) whose body carries LaTeX — `$1011_2 = 11_{10}$`, a `$$...$$` display formula, a formula in an MCQ and one in a model answer — drives Chromium to it through the admin LMS deep link, and checks that KaTeX typeset it: `.katex` nodes exist, the display formula became a display block, no raw `\times` or `$$` is left in the text, and the page threw nothing. Deletes the lesson afterwards. Needs the vendored KaTeX under `www/katex/` to be served, which is why it runs in a real browser. | Sandbox backend and its database |
| `e2e_general_assessments.cjs` | General (term-weighted) assessment lifecycle in Chromium: the teacher creates one with hand-written questions from the Assessments & Grading hub and publishes it; the student sees it under My Assignments, answers it, and a closed one shows its deadline state; the teacher grades and releases it from the hub's Grading tab. | Sandbox backend |
| `e2e_loading.cjs` | Loading states in Chromium, driven by *clicking* — landing on the dashboard and going through the sidebar — because that is the path the suites above never took. The users list shows a skeleton that hands over to its table, no list is left on a loading message, the top border bar shows for a navigation and for a tab switch and goes away once the view has rendered, the nav bar carries the active session term, a tab switch shows that tab's own rows, a list whose payload is empty shows the empty state (faked for one tab through the route interception, because the fixture's directory gives every tab a row), and with `/api/users?role=*` answering 500 the list shows the backend's own message with a retry (and the retry loads the list) instead of a spinner. | Sandbox backend |
| `e2e_notifications_lms.cjs` | The notification bell and the admin LMS drill-down in Chromium. Notifications: a finished write raises a top-right toast carrying its title and message with a countdown bar that shrinks, pauses on hover and resumes when the pointer leaves, dismisses itself at zero, and leaves an entry in the bell's dropdown (badge count) that Clear all empties and a click outside closes. LMS: every drill step puts itself in the URL (`?class=`, `&subject=`, `&term=`, `&lesson=`), each breadcrumb lands on the level it names (the subject crumb on the lessons list reaches the terms step, not the subjects step), browser back/forward walk the drill a level at a time, and a direct load at depth restores that step. | Sandbox backend |
| `general_assessment_flow.sh` | The same general lifecycle over the API, including `assessment_type=general` submissions, the weight budget, the strict question shape and the opens/closes/attempt rules. Creates its own subject per run, so it never spends the fixture's weight budget. | Sandbox backend |
| `smoke_teacher_role.cjs` | The teacher role's own shell in Chromium: My Classes renders, the sidebar offers it and hides the admin entries, and an unassigned teacher sees the empty state rather than a gate failure. | Sandbox backend |
| `e2e_matrix_sso.cjs` | The chat page's own login, in Chromium, against a mock Synapse (`fixtures/mock_synapse.py`): the Messaging tab asks the homeserver which provider it offers and opens its SSO entry point **with the id it was offered** (the mock offers `oidc-authentik` — what Synapse makes of a configured `idp_id: authentik` — and answers 404 `M_NOT_FOUND "Unknown identity provider"` for any other, as the real homeserver does), comes back with a one-time `loginToken`, exchanges it for an access token and connects; the sidebar offers *＋ New channel* to an administrator **and not to a pupil** (driven with a token whose groups map to that role), while *Join* stays both; a reload reuses the stored token (no second login); a replayed token is refused with a **Try again** button rather than a redirect loop; a homeserver offering no provider is reported in the page instead of the browser being sent into a 404; and the mock never receives a `/_synapse/admin/` call — the credential the old proxy needed is gone. Self-contained: builds the backend, boots it **without** `MATRIX_ADMIN_TOKEN` plus the mock — no database, no Authentik, no wasm rebuild. | Roc toolchain + playwright |
| `me_profile.sh` | The Settings page's own details (`GET /api/me/profile`): each role's own rows — a teacher's qualification by name and their class-subject pair matching the assignment given, a student's class and number, an administrator's type and ticks — with one role's rows staying out of another's card, and the route answering 404 to POST and PUT. Drives created logins by JWT, and the *seeded* teacher for the teacher case (a login created through the API has no group in the mock). | Sandbox backend |
| `password_change.sh` | The password-change requirement over the API: a login created with a password (or reset by an admin) is refused everywhere but `/api/me/password-state` and `/api/me/password`, with `code: password_change_required`; setting one's own clears it; an admin's reset puts it back; a login created without a password stays ungated. Sandbox backend + mock Authentik (the login is driven by a JWT whose `sub` names it). | Sandbox backend |
| `e2e_password_change.cjs` | The same requirement as the person meets it, in Chromium: the app moves to Settings on its own, the sidebar offers only that item, the form refuses a short and a mismatched password without a round trip, and the real change — after the app has signed them out: the browser is sent to Authentik's end-session endpoint, its stored token is gone, and entering again with the new password opens the app. Then a change the person *chooses*: the current password is asked, a wrong one is refused, the right one lands and signs them out the same way. Creates its own student row (with a password) and deletes it after. | Sandbox backend |
| `smoke_assignments_lms.cjs` | The teacher-assignment surfaces in Chromium: the admin LMS drill-down renders class → subject → term → lesson → content read-only, the teacher row's Assign dialog searches, badges and saves the whole pair set, the Configuration hub's Qualifications tab creates a catalog row, and the teacher form's picker offers it. Creates its own teacher row (the Assign action needs one with a profile). | Sandbox backend |
| `list_order.sh` | The order every list the pages pull comes back in, over the API: the class lists in the school's own order — the primary years, then the junior school, then the senior school, which is what `class_stage_rank` sorts by — in `/api/class_levels`, `/api/class-subjects`, `/api/curriculum` and a teacher's own pair lists; subject lists alphabetical; and the orders the other lists have (terms by sort order, session terms by name, lessons by week, assessments and submissions newest first). Writes one deliberately unsorted pair set for `teacher_profile:dev_teacher` and clears it again. | Sandbox backend |
| `e2e_list_order.cjs` | The same order as the admin and staff *views* render it, in Chromium: the admin LMS class picker (Year 1-5, JSS 1-3, SSS 1-3), a class's subject cards, the Configuration hub's class level / subject / curriculum tables, and the teacher's My Classes cards. Assigns that teacher's pairs in reverse first and clears them at the end. | Sandbox backend |

```sh
node tests/e2e/render_lesson_check.cjs            # defaults to a known prod lesson
LESSON_ID=lessons:... node tests/e2e/render_lesson_check.cjs
node tests/e2e/render_lesson_roles_check.cjs      # the pupil/staff section split, no backend needed
node tests/e2e/e2e_student.cjs
node tests/e2e/e2e_auth_callback.cjs
node tests/e2e/e2e_signout.cjs
node tests/e2e/auth_config_check.cjs                    # defaults to the deployed origin
node tests/e2e/auth_config_check.cjs http://127.0.0.1:8000
node tests/e2e/e2e_admin.cjs
node tests/e2e/e2e_user_roles.cjs
node tests/e2e/e2e_users_directory.cjs
node tests/e2e/e2e_admin_config.cjs
node tests/e2e/e2e_assessments.cjs
node tests/e2e/e2e_general_assessments.cjs
node tests/e2e/e2e_loading.cjs
node tests/e2e/e2e_notifications_lms.cjs
APP_URL=http://127.0.0.1:8308 node tests/e2e/e2e_passport_upload.cjs   # backend started with the R2 variables
node tests/e2e/e2e_matrix_sso.cjs       # self-boots backend + mock Synapse (see its header)
sh tests/e2e/assessment_flow.sh
sh tests/e2e/users_api.sh
sh tests/e2e/general_assessment_flow.sh
sh tests/e2e/authz.sh
sh tests/e2e/list_order.sh
node tests/e2e/e2e_list_order.cjs
sh tests/e2e/token_cache.sh      # MOCK_AUTHENTIK_URL + SURREAL_URL, like users_api.sh
node tests/e2e/math_render_check.cjs   # SURREAL_URL for the database it writes its lesson to
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
draws the same numbers prod will), the `token_cache` statements from `db/schema-v12-token-cache.surql` (so a sandbox keeps validated tokens like prod, instead of validating every request while the cache looks the same from outside) and `session_term`,
seeds the school's eleven class levels — the primary years, the junior school and the senior school, each with the
stage `db/schema-v13-class-tier.surql` puts on it, which is what the class lists are ordered by — terms, four
subjects with their `has_subject` edges (JSS 1 teaches all four, Year 1 and SSS 1 two each, so a class list has
rows in more than one stage), one lesson, one session term, and a `student_profile:dev_user` so the dev-skip
caller resolves a name. The
lesson's `content.mcq_questions` carry a `correct_answer` letter, which is what the create-assessment modal
stores as the question's `answer` and what submit-time MCQ scoring compares against. The
mock keeps a user table: a fresh `pk` per create, which is what keeps each created account's record id
distinct; GET lists in Authentik's own shape, PATCH updates the fields it is given, DELETE removes one (the
compensation path's call) and an unknown pk answers 404. The repo's `mock_authentik.py` returns a constant
`pk`, so per-role runs would collide on the record id. It also serves the instance-wide userinfo path the
backend validates tokens against: `mock-student-token` (`Students`), `mock-teacher-token` (`Teachers`),
`mock-admin-token` (`Administrators`) and `mock-groupless-token` (a login in no group, i.e. a student) answer
with the `groups` claim a real session would carry, which is where `authz.sh` gets a role without DEV_MODE
(this is why the backend needs `AUTHENTIK_ISSUER_URL` pointing at the mock). A **JWT-shaped** token is answered from its own claims instead — `{"sub": <a pk this directory has>, "exp": <seconds from now>}`, refused once `exp` has passed or that login is switched off — so a suite can mint a token for any login it has, and `GET /userinfo_calls` reports how many validations the endpoint has answered, which is what makes a cache hit observable from outside the backend (`token_cache.sh` is built on both).

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

One more state the suites share: the current session term. A school has one, the database enforces that
(`db/schema-v11`, a partial unique index on the active flag), and switching a term on therefore switches
the current one off — so a suite that activates its own term moves the flag rather than adding to it.
`e2e_admin_config.cjs` switches the seeded term back before it finishes, because the suites that read the
active term by name (`e2e_loading` asserts the nav bar's badge) run after it.

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
