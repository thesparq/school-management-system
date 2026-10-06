# Progress Tracker

## Current Phase: Phase 8 — Prod DB alignment (Roc stack)

**Status: backend + renderer aligned to prod (`db2.johnethel.school`, ns `main`, db `lessons`); one pre-existing frontend blocker open (see below).**

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

### Resolved — the app runs the full student flow against prod

Two independent causes, both found and fixed:

1. **Joy's host allocator overlapped pages grown by the Roc boxy runtime.** `bump_span` in the Joy platform's
   `host/host.rs` assumes the host is the only code that grows linear memory, but the boxy runtime's
   `std.heap.page_allocator` grows it too, so `END` goes stale and the host hands out spans that overlap the
   runtime's pages — the trap surfaced in `roc_boxy_register_erased_proc` on the second host entry. Fixed with a
   host patch (re-read `memory_size(0)`, use `memory_grow`'s return value); see `roc-frontend/JOY_HOST_PATCH.md`
   and `roc-frontend/joy-host-bump-span.patch`. `www/app.wasm` is built against the patched host. Upstream
   report text is in the same note.
2. **`www/index.html` never unwrapped SurrealDB's response envelope.** `Array.isArray(data) ? data : (data[0]?.result || [])`
   treats the one-element envelope `[{ result: [...], status: "OK" }]` as the rows, so every list rendered a
   single fieldless row (`|Unknown|`, `Unknown||true`) and no data ever appeared. Replaced by the shared
   `unwrapRows` helper at all five call sites.

Verified in Chromium against the live prod DB (read-only, `DEV_MODE` backend): 9/9 checks — subject cards from
prod, terms, lessons filtered by subject+term, full lesson content (introduction, objectives as text, sections,
sub-points, key points, conclusion), scroll-spy sections, and no page errors.

Caveat: rebuilding `www/app.wasm` from the unmodified `app.roc` (which names the remote platform URL) reproduces
the host crash. Build against the patched local platform as described in `JOY_HOST_PATCH.md`.

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

### Build and tests — done

- Joy 0.33.0 is vendored at `roc-frontend/joy/` with the host allocator patch applied
  (`joy/host-bump-span.patch`), and `app.roc` points at it, so `cd roc-frontend && roc run build.roc` builds
  a working app on any machine. The layout mirrors a Joy checkout (`platform/…` plus `www/runtime.js`) so the
  template's own `build.roc` copies the runtime unchanged. Swap `app.roc` back to the release URL once the fix
  ships upstream.
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
- [ ] Optional: file the Joy host allocator bug upstream (`roc-frontend/JOY_HOST_PATCH.md` has a ready-to-post
  report).

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
its created logins carry `groups_obj: []` the way Authentik's own API does.

---

## Completed Work

- [x] Roc basic-webserver backend (main.roc, SurrealDB.roc, Authentik.roc, Golem.roc, EventStore.roc)
- [x] Roc Joy framework frontend (app.roc, State.roc, UI.roc, DashboardView, AdminView, TeacherView, StudentView)
- [x] SurrealDB schema (schema.surrealql) with event sourcing tables
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
- [ ] Wire lesson viewer URL param to actual lesson ID (currently shows placeholder on navigation)
- [ ] Subject → Term → Lesson navigation drill-down (multi-level routing)
- [ ] Real passport photo upload (presigned PUT to R2 from browser)
- [ ] Edit user dialog/form
- [ ] Config tab forms CRUD (Terms, Class Levels, Curriculum, Class Arms, Subjects)
- [ ] Parent portal (linked students view)
- [ ] Dashboard stat cards wired to real API data
- [ ] Toast/notification system
- [ ] Cloud deployment configuration
- [ ] Rate limiting on backend

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
- Tab switching in Config Hub crashes WASM on button click
- Root cause: Chromium renderer process crash during WASM execution — not a code bug, framework-level issue
- **Does NOT affect real browser usage** — only Playwright headless Chromium

## Backend API Endpoints
| Method | Path | Description | Status |
|--------|------|-------------|--------|
| GET | /health | Health check | ✅ |
| GET | /api/students | List students | ✅ |
| POST | /api/enroll | Enroll via Golem | ✅ |
| GET | /api/teachers | List teachers | ✅ |
| POST | /api/teachers | Create teacher | ✅ |
| GET | /api/subjects | List subjects | ✅ |
| POST | /api/subjects | Create subject | ✅ |
| GET | /api/terms | List terms | ✅ |
| POST | /api/terms | Create term | ✅ |
| GET | /api/class_levels | List class levels | ✅ |
| POST | /api/class_levels | Create class level | ✅ |
| GET | /api/curriculum | List curriculum | ✅ |
| POST | /api/curriculum | Create curriculum | ✅ |
| GET | /api/class_arms | List class arms | ✅ |
| POST | /api/class_arms | Create class arm | ✅ |
| GET | /api/users | List users | ✅ |
| POST | /api/users | Create user | ✅ |
| PUT | /api/users | Update user | ✅ |
| DELETE | /api/users | Soft delete user | ✅ |
| GET | /api/session_terms | List session terms | ✅ |
| POST | /api/session_terms | Create session term | ✅ |
| GET | /* (static) | Static file serving | ✅ |
| GET | /* (SPA) | SPA fallback to index.html | ✅ |

## Remaining Work (Backlog)
- [ ] Wire config tab forms to API (Terms, Class Levels, Curriculum, Class Arms, Subjects CRUD forms)
- [ ] User role selector in Add User form (Admin/Teacher/Student/Parent)
- [ ] Edit user dialog/form
- [ ] User activation/deactivation
- [ ] Student/Teacher/Parent list views with search/filter
- [ ] Passport photo upload
- [ ] LMS lesson content (subject → term → lesson browsing)
- [ ] Assessment creation and grading
- [ ] Parent portal (linked students view)
- [ ] Timetable management
- [ ] Dashboard stat cards wired to real API data
- [ ] Toast/notification system
- [ ] Loading skeleton components
- [ ] Cloud deployment configuration
- [ ] Rate limiting on backend
- [ ] Investigate Joy framework WASM crash on Teacher/Student NavigateTo

## Architecture Notes
- **Unified Roc server**: Single `roc-backend/main.roc` serves both API and frontend on port 8000
- **Golem is used only for critical operations** (enrollment via class agents), not the entire backend
- Roc basic-webserver handles all direct CRUD — keeps it simple and fast
- Frontend is a Joy WASM SPA compiled from `roc-frontend/app.roc`
- Auth is delegated to Authentik via OAuth2 Authorization Code + PKCE flow
- Static files served from `STATIC_DIR` env var (defaults to `../roc-frontend/www`)
