# End-to-end checks for the school app

These verify the Joy/WASM app against a running backend. Run them after changing `www/index.html`,
`State.roc`, the views, or the backend handlers.

(The `*_test.roc` files one level up are the Joy TodoMVC template's own suite — they test the template, not
this app.)

## Prerequisites

- A build: `cd ../.. && roc run build.roc` (uses the vendored platform in `../../joy`; see
  `../../JOY_HOST_PATCH.md`).
- A running backend serving that build:
  `cd ../../../roc-backend && DEV_MODE=true infisical run --env=dev -- roc run main.roc`.
  `DEV_MODE` is what lets these scripts use the `dev-skip` bearer token instead of a real Authentik login.
- Playwright for the browser checks: `npm i -D playwright && npx playwright install chromium` at the repo
  root, or point `NODE_PATH` at an existing install.

`APP_URL` overrides the target (default `http://127.0.0.1:8000`).

## The checks

| Script | What it proves | Needs |
|---|---|---|
| `render_lesson_check.cjs` | The page's own `renderLesson` turns a real lesson into the expected sections (introduction, objectives as text, content sections, sub-points, key points, conclusion) and leaks no raw JSON. No browser: it stubs the DOM and runs the page's JavaScript. | Backend + a lesson id |
| `e2e_auth_callback.cjs` | The OAuth2 round trip with Authentik's endpoints intercepted: the redirect URI the app sends is `<origin>/auth/callback` on both legs, the code is exchanged on the callback path with the PKCE verifier, the token is stored, the URL is cleaned back to the root, and a bare callback visit starts from the root too. | Backend |
| `auth_config_check.cjs` | An origin's auth wiring against the *real* Authentik, no browser: the advertised userinfo endpoint is the instance-wide one and matches what the backend derives, it answers 401 for a bad token, and the app's redirect URI is registered (with an unregistered one rejected as a control). | Network access to Authentik |
| `e2e_student.cjs` | Student drill-down in Chromium: subject cards from prod, terms, lessons filtered by subject+term, full lesson content, scroll-spy sections, no page errors. | Backend |
| `e2e_admin.cjs` | Admin user management in Chromium: the form creates a user, the new account appears in the table, and a validation error surfaces in the UI. | Sandbox backend |
| `e2e_admin_config.cjs` | Admin configuration hub in Chromium: every section (terms, class levels, subjects, session terms, the curriculum edge) lists the fixture's rows, a create through the form appears in the list afterwards, and a refused create shows the backend's own text (400 validation, or the database's statement message). Re-entering the hub from the dashboard refetches the lists. | Sandbox backend |
| `e2e_assessments.cjs` | Assessment lifecycle in Chromium: the teacher picks a lesson, creates a draft, publishes it; the student sees it and submits; the teacher's grading list shows the auto-scored MCQ marks; the teacher grades and releases. | Sandbox backend |
| `assessment_flow.sh` | The same lifecycle over the API with curl, including the draft/published rules, MCQ auto-scoring, the deadline and the resubmission limit, and the validation errors. | Sandbox backend |
| `e2e_general_assessments.cjs` | General (term-weighted) assessment lifecycle in Chromium: the teacher creates one with hand-written questions from the Assessments & Grading hub and publishes it; the student sees it under My Assignments, answers it, and a closed one shows its deadline state; the teacher grades and releases it from the hub's Grading tab. | Sandbox backend |
| `general_assessment_flow.sh` | The same general lifecycle over the API, including `assessment_type=general` submissions, the weight budget, the strict question shape and the opens/closes/attempt rules. | Sandbox backend |

```sh
node tests/e2e/render_lesson_check.cjs            # defaults to a known prod lesson
LESSON_ID=lessons:... node tests/e2e/render_lesson_check.cjs
node tests/e2e/e2e_student.cjs
node tests/e2e/e2e_auth_callback.cjs
node tests/e2e/auth_config_check.cjs                    # defaults to the deployed origin
node tests/e2e/auth_config_check.cjs http://127.0.0.1:8000
node tests/e2e/e2e_admin.cjs
node tests/e2e/e2e_admin_config.cjs
node tests/e2e/e2e_assessments.cjs
node tests/e2e/e2e_general_assessments.cjs
sh tests/e2e/assessment_flow.sh
sh tests/e2e/general_assessment_flow.sh
```

## Sandbox for the admin and assessment checks

`e2e_admin.cjs`, `e2e_admin_config.cjs`, `e2e_assessments.cjs`, `e2e_general_assessments.cjs`, `assessment_flow.sh` and
`general_assessment_flow.sh` write rows, so they
must not run against prod. Start a throwaway SurrealDB, load the schema fixture, and point a backend at it
plus the mock Authentik:

```sh
surreal start --bind 127.0.0.1:8002 --user root --pass root surrealkv:///tmp/school-sandbox/db &
curl -s -u root:root -X POST http://127.0.0.1:8002/sql \
  -H 'surreal-ns: main' -H 'surreal-db: lessons' -H 'Accept: application/json' \
  --data-binary @tests/e2e/fixtures/sandbox-schema.surql
python3 tests/e2e/fixtures/mock_authentik_unique.py &

cd ../../../roc-backend && DEV_MODE=true \
  SURREAL_URL=http://127.0.0.1:8002/sql SURREAL_USER=root SURREAL_PASS=root \
  AUTHENTIK_API_URL=http://127.0.0.1:9000/api/v3/core/users/ AUTHENTIK_API_TOKEN=mock \
  roc run main.roc
```

The fixture schema mirrors the prod profile, lesson and assessment tables (SCHEMAFULL, including the required
`passport`, `display_name` and `questions` fields) plus the lookup tables' unique indexes and `session_term`,
seeds the class levels, terms, one subject with its `has_subject` edge, one lesson, one session term, and a
`student_profile:dev_user` so the dev-skip caller resolves a name. The
lesson's `content.mcq_questions` carry a `correct_answer` letter, which is what the create-assessment modal
stores as the question's `answer` and what submit-time MCQ scoring compares against. The
mock hands out a fresh `pk` per create and accepts `DELETE`, which is what the compensation path calls; the
repo's `mock_authentik.py` returns a constant `pk`, so per-role runs would collide on the record id.

Two schema notes learned from the prod tables: relations are created with `RELATE` (`CREATE` on a relation
table is rejected), and `questions` / `answers` are `array<object>`, which implies their `.*` sub-field.

`general_assessments` and `compositions` are in the fixture too (prod's field definitions). The fixture
carries the six `questions.*` sub-field statements from `db/schema-v3.surql` that prod has not had applied
to `general_assessments`: without them this SurrealDB generation rejects every question object, so a
sandbox could not store what the implementation writes. Apply those statements to prod before general
assessments with questions can be created there.

The general-assessment checks consume the term/subject weight budget (100%), so reload the fixture (or
point them at another `SESSION_TERM_ID`) once a few runs have spent it.
