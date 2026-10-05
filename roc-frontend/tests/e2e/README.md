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
| `e2e_student.cjs` | Student drill-down in Chromium: subject cards from prod, terms, lessons filtered by subject+term, full lesson content, scroll-spy sections, no page errors. | Backend |
| `e2e_admin.cjs` | Admin user management in Chromium: the form creates a user, the new account appears in the table, and a validation error surfaces in the UI. | Sandbox backend |
| `e2e_assessments.cjs` | Assessment lifecycle in Chromium: the teacher picks a lesson, creates a draft, publishes it; the student sees it and submits; the teacher grades and releases. | Sandbox backend |
| `assessment_flow.sh` | The same lifecycle over the API with curl, including the draft/published rules and the validation errors. | Sandbox backend |

```sh
node tests/e2e/render_lesson_check.cjs            # defaults to a known prod lesson
LESSON_ID=lessons:... node tests/e2e/render_lesson_check.cjs
node tests/e2e/e2e_student.cjs
node tests/e2e/e2e_auth_callback.cjs
node tests/e2e/e2e_admin.cjs
node tests/e2e/e2e_assessments.cjs
sh tests/e2e/assessment_flow.sh
```

## Sandbox for the admin and assessment checks

`e2e_admin.cjs`, `e2e_assessments.cjs` and `assessment_flow.sh` write rows, so they must not run against
prod. Start a throwaway SurrealDB, load the schema fixture, and point a backend at it plus the mock
Authentik:

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
`passport`, `display_name` and `questions` fields), seeds the class levels, terms, one subject with its
`has_subject` edge, one lesson, and a `student_profile:dev_user` so the dev-skip caller resolves a name. The
mock hands out a fresh `pk` per create and accepts `DELETE`, which is what the compensation path calls; the
repo's `mock_authentik.py` returns a constant `pk`, so per-role runs would collide on the record id.

Two schema notes learned from the prod tables: relations are created with `RELATE` (`CREATE` on a relation
table is rejected), and `questions` / `answers` are `array<object>`, which implies their `.*` sub-field.
