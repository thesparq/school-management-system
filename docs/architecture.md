# Architecture

What runs today, and the rules that keep it coherent. The MoonBit/Golem path this project grew up on is
retired — it is summarised at the end, and its code still lives in `agents/` and `frontend/` — so nothing
here describes it as current. `docs/progress-tracker.md` holds the live state and the open work.

## Stack

| Layer | Technology | Role |
| :--- | :--- | :--- |
| Identity provider | Authentik | OIDC login, JWT issuance, the user directory, and the admin API for user lifecycle. The system of record for identity attributes |
| Frontend | Joy (Roc, WASM) | A single-page app compiled to `app.wasm`, plus the page's own JavaScript in `roc-frontend/www/index.html` |
| Backend | Roc (`basic-webserver` platform) | One process: the HTTP API *and* the static files. `roc-backend/main.roc` holds every route; small pure modules beside it |
| Database | SurrealDB 3.x | The school's data: curriculum, lessons, assessments, submissions, profiles. Prod is `db2.johnethel.school`, ns `main`, db `lessons` |
| Object storage | Cloudflare R2 | Passport photos (public URL on the profile) |
| Deployment | Dokploy + Traefik | `devops/docker-compose.yml`; the app is the `app` service, built by `Dockerfile.app`, published on `app.johnethel.school` |
| Toolchain | Roc nightly | Pinned in `Dockerfile.app` from `roc-lang/nightlies`; the Joy platform is vendored in `roc-frontend/joy/` with a host patch (`roc-frontend/JOY_HOST_PATCH.md`) |

## Repository layout

```
roc-backend/            the API: main.roc (routes), Authentik.roc, SurrealDB.roc, Url.roc, AuthUrls.roc,
                        Base64.roc … and *Test.roc files beside them (roc test)
roc-frontend/           app.roc (the SPA), State.roc (model/messages), *View.roc (views), UI.roc,
                        www/index.html (the page's own JS: routing, forms, chat, assessments),
                        www/app.css → dist.css (Tailwind), joy/ (vendored platform), build.roc
db/schema-v2..v7.surql  the schema lineage. Additive version files; the latest applied to prod is v7
devops/                 the compose file (Dokploy), legacy/docker-compose.golem.yml, .env.example
docs/                   these context files
agents/, frontend/      the retired MoonBit/Golem stack — reference for stored-data conventions, not deployed
Dockerfile.app          the deployment image: frontend bundle + backend binary
```

## System boundaries

- **Browser** — the SPA, its `index.html` logic, and the user's token. It talks to the backend at the same
  origin and to Authentik for login. No database credentials, no R2 secret, no service tokens live here.
- **Backend** — the only thing that talks to SurrealDB, Authentik's admin API and R2. It validates every
  request's bearer token against Authentik before any route does work, and holds all credentials in its
  environment (`SURREAL_*`, `AUTHENTIK_*`, `R2_*`, plus `DEV_MODE`, `BIND_HOST`, `PORT`, `STATIC_DIR`).
- **SurrealDB** — the school's data. Reached only by the backend, over HTTP Basic auth, with a URL that is
  in-cluster in production (`http://surrealdb:8000/sql`) and the public endpoint for clients outside.
- **Authentik** — identity. Login happens in the browser; the backend only validates tokens and performs
  admin user operations (create, update, disable) with a service-account token.

## Auth & access

1. The SPA starts an OAuth2 **PKCE** flow against Authentik and receives a code on
   `<origin>/auth/callback`, which it exchanges for a token and keeps in `localStorage`.
2. Every API call sends that token as a bearer. The backend validates it against Authentik's
   **instance-wide** userinfo endpoint — `/application/o/userinfo/`, *not* `<issuer>userinfo` (that is a
   404 and would reject every real token; `AuthUrls.roc` derives it correctly, and
   `roc-frontend/tests/e2e/auth_config_check.cjs` checks a deployed origin against the real Authentik).
3. The caller's identity comes from the token (`sub`/`uid`, which is the Authentik `pk`), and its role from
   the `groups` claim — the frontend routes by that role. **The backend does not yet enforce it per route:**
   it validates the token and scopes the queries it builds to the caller's own record, but any valid token can
   call any route, teacher and admin endpoints included. The retired agent stack did gate by role, so this is a
   regression to close before production (it is on the leftover list in `docs/progress-tracker.md`).
4. `DEV_MODE=true` accepts a `dev-skip` token so local work and the sandbox suites need no login.
   Production sets `DEV_MODE=false`, which turns that path off entirely — `deploy_check.cjs` asserts it.

## Storage model

**The schema files are the definition.** `db/schema-v*.surql` (v2 … v7) are additive version files applied in
order; the applied result lives in the database and can be read back with `INFO FOR TABLE`. This document
deliberately does not duplicate the field lists — the duplication is what made the previous version of this
file stale. What belongs here is the shape and the rules:

- **Tables**: `subjects`, `class_levels`, `terms`, `session_term`, `lessons`, `lesson_content`, `has_subject`
  (a relation edge class_levels → subjects), `class_terms`, `teacher_assignment`, `student_profile`,
  `teacher_profile`, `parent_profile`, `admin_profile`, `lesson_assessments`, `general_assessments`,
  `compositions`, `submissions`, `credentials`.
- **Two known divergences between the files and prod**, both in the harmless direction (the files declare more
  than prod has, and both concern unused tables): v3 declares a `teaches` edge that was never applied, and v3
  declares `general_assessments.questions.*` sub-fields that prod lacks (that table is empty and the feature is
  unimplemented). A database rebuilt from `db/schema-v*.surql` would therefore be slightly stricter there than
  prod. Nothing else differs: the sandbox fixture and prod match field-for-field on the tables the app uses.
  *(Both were closed on 2026-10-05: the six `general_assessments.questions.*` statements were applied for the
  general-assessment feature, and applying v3 for them also brought in its `teaches` table and
  `teacher_profile.qualifications` — empty and unread by the app. Prod and the files now agree on the tables the
  app uses.)*
- **Profiles are keyed by the Authentik pk** (`student_profile:<pk>`), never by email or username.
- **Relations are edges**, created with `RELATE`; `has_subject` is the curriculum.
- **Record links, not strings**: a filter on a link column must compare against a record literal
  (`record_ref!` / `type::record('<table>','<id>')`). A quoted string never matches — verified: quoted → 0 rows,
  record → 225 rows.
- **Ids are written `table:pk`**, and a pk that looks like a number is still a *string* id part. SurrealDB
  renders such a part back to us quoted (``student_profile:`14``) in a write's own answer, so `bare_id` strips
  the quotes: a write response's id and a listing's id name the same record, and PUT/DELETE accept either
  spelling. The listings normalize what they emit (`student_profile:14`).
- **`SCHEMAFULL` means what it says**: a field (or sub-field, e.g. `answers[*].allocated_mark`) that is not
  declared is rejected, and the statement's error arrives inside an HTTP 200 body.
- **Soft deletes**: `deleted_at`, with listings filtering `deleted_at IS NONE`.
- **Assessment shapes**: `lesson_assessments.questions[*]` and `general_assessments.questions[*]` carry the
  strict question shape (`type` asserted to `mcq|boolean|short_answer|essay`, `question`, `options`, `answer`,
  `explanation`, `marks`); `submissions` holds one row per student and assessment (`iteration` bumps in place,
  `assessment_type` is `lesson` or `general`, `assessment_id` is the bare id), and `answers[*]` carries
  `question_index`, `answer_type`, `answer_text`, `allocated_mark` — where an MCQ's awarded mark is written at
  submit time and the question's own allocation stays in the assessment's `questions[*].marks`.

## Principles

1. **One source of truth per attribute.** Identity attributes (email, display name, enabled/disabled, groups)
   belong to Authentik and are *read from it*, not copied into SurrealDB; school attributes (class level, date
   of birth, passport, role title, enrolment) belong to the profile tables. The two are joined by the Authentik
   pk. Writes act on the owner first — creating a user creates the login, then the profile row.
   The two sides are also *listed* together: the user listing is the union of a role's profile rows and the
   logins the directory puts in that role, so a user an admin created in Authentik appears (marked
   `has_profile:false`, with the login's own name, email and enabled state) before any school data exists, and
   `PUT` attaches the profile row to that login. A login in no role group — an outpost, a service account —
   belongs to no tab and is listed nowhere.
2. **A write must report what the database did.** SurrealDB answers HTTP 200 with `"status":"ERR"` in the body
   when a statement fails, so every write goes through `db_body!` / `db_response!` and a failure answers 500
   with the statement's own message. Trusting the status is how a rejected write gets reported as success.
3. **The server is the authority.** The page disables a submit past a deadline for feedback, but the backend
   decides: deadline, `scheduled_at`, `max_resubmissions`, and whether an assessment is published are all
   checked server-side with a 409. The page's state is cosmetic.
4. **State lives in the database, not in the process.** The backend keeps nothing between requests, so any
   instance can serve any request. Per-request configuration comes from the environment.
5. **Schema changes are additive and versioned.** A new `db/schema-vN.surql` with `DEFINE FIELD IF NOT EXISTS`,
   no `REMOVE`/`DELETE`/rewrite; verified on a sandbox that mirrors prod first, then applied to prod with the
   row counts checked before and after.
6. **No JSON parser in the backend.** Payload shapes are flat and known, read with fixed scanners
   (`extract_field`, `extract_number_field`, `json_array_or_empty!`, `json_bool`, and `split_json_elements` for
   arrays). Anything richer would need a parser this Roc version does not have.
7. **Verify against something that behaves like production.** The e2e suites run against a sandbox built from
   `roc-frontend/tests/e2e/fixtures/sandbox-schema.surql` (which mirrors the prod schema) with a mock Authentik;
   production data is never written to. `roc check main.roc` must end at 0 errors and 3 warnings, and a page
   load belongs to any frontend rebuild — two Roc shapes compile cleanly into a wasm that renders nothing
   (`roc-frontend/JOY_HOST_PATCH.md`).

## Retired: the MoonBit/Golem path

The project began as SvelteKit + MoonBit agents on Golem Cloud, with SurrealDB behind them: a singleton Admin
Agent, one durable Student/Teacher/Parent agent per user, typed RPC between them, agent struct fields as the
durable state, and a SvelteKit server acting as the auth proxy and API gateway. `agents/` and `frontend/` still
hold that code, and `devops/legacy/docker-compose.golem.yml` still describes its runtime (eight services plus
their volumes, out of the deployed stack).

Two things about it are still worth knowing:

- **It is the reference for stored-data conventions.** Where a shape is not obvious from the schema — how a
  submission is stored, what an answer object carries, how a general assessment is created — the old code
  (`agents/app-agents/db_assessment.mbt`, `core_api.mbt`) is what the current implementation mirrors.
- **Its rules that outlived it** are the principles above: identity versus profile, soft deletes, record-link
  filters, and the server as the authority for deadlines.

What is gone: durable per-user agents and their RPC fan-out, the agent memory caches, the Golem gateway and
its firewall rule, and the SvelteKit proxy. The current backend is stateless and the browser talks to it
directly, so the request path is shorter by two hops and the state that used to live in agent struct fields
lives in SurrealDB.
