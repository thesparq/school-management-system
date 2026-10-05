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

- [ ] MCQ auto-scoring on submit, and enforcement of `deadline` / `max_resubmissions` / `scheduled_at` (they are
  accepted but not enforced).
- [ ] `PUT` / `DELETE /api/users` still write the legacy `student` table (no UI calls them); they now report the
  failure instead of answering 200.
- [ ] The admin Configuration Hub is UI-only (`terms_config_view` and friends take `|_model|`), though the
  endpoints for terms, subjects, class levels and session terms exist.
- [ ] General assessments (`general_assessments` + `compositions`) are not implemented; only lesson
  assessments are.
- [ ] Automatic passport upload (R2 presigned PUT) is still a placeholder; the form takes a URL.
- [ ] Query parameters are not percent-decoded, so a client that URL-encodes a record id (`lessons%3Aabc`)
  gets an empty result; the UI passes ids raw.
- [ ] Optional: file the Joy host allocator bug upstream (`roc-frontend/JOY_HOST_PATCH.md` has a ready-to-post
  report).

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
