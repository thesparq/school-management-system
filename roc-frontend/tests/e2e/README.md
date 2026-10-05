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
| `e2e_student.cjs` | Student drill-down in Chromium: subject cards from prod, terms, lessons filtered by subject+term, full lesson content, scroll-spy sections, no page errors. | Backend |
| `e2e_admin.cjs` | Admin user management in Chromium: the form creates a user, the new account appears in the table, and a validation error surfaces in the UI. | Backend pointed at the sandbox (below) |

```sh
node tests/e2e/render_lesson_check.cjs            # defaults to a known prod lesson
LESSON_ID=lessons:... node tests/e2e/render_lesson_check.cjs
node tests/e2e/e2e_student.cjs
node tests/e2e/e2e_admin.cjs
```

## Sandbox for the admin check

`e2e_admin.cjs` writes a profile record, so it must not run against prod. Start a throwaway SurrealDB, load
the schema fixture, and point a backend at it plus the mock Authentik:

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

The fixture schema mirrors the prod profile tables (SCHEMAFULL, including the required `passport` and
`display_name` fields) and seeds the class levels. The mock hands out a fresh `pk` per create and accepts
`DELETE`, which is what the compensation path calls; the repo's `mock_authentik.py` returns a constant `pk`,
so per-role runs would collide on the record id.
