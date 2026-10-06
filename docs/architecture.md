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
db/schema-v2..v8.surql  the schema lineage. Versioned files, meant to be additive; v5 was never applied to
                        prod and is superseded by v8 (not replayable as it stands, see Storage model),
                        and v7 is the latest applied
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
   the `groups` claim — the frontend routes by that role, and **the backend enforces the same role per route**
   from one matrix in `roc-backend/main.roc`: `required_role` names what each route family needs —
   `/api/student/*` a student, `/api/teacher/*` a teacher, the account and configuration writes an admin, the
   shared reads any authenticated role — and `may_call` then lets an admin call anything. No token or a bad one
   is a 401; the wrong role is a 403 naming the role the route needs. `roc-frontend/tests/e2e/authz.sh` is the
   check that the gate bites (27 checks, a student's token refused a teacher route with that 403).
4. `DEV_MODE=true` accepts the tokens that stand in for a login — `dev-skip` and its older `test-token` alias
   (admin), plus `dev-student` and `dev-teacher` — so local work and the sandbox suites need no login.
   Production sets `DEV_MODE=false`, which turns that path off entirely — `deploy_check.cjs` asserts it.

## Storage model

**The database is the definition; the files are its lineage.** `db/schema-v*.surql` (v2 … v7) are versioned
files meant to be applied in order — the applied result lives in the database and can be read back with
`INFO FOR TABLE`. They are not a rebuild recipe: v5 was never applied to prod, and replaying the lineage
against a fresh database does not produce a working one (the divergences below say why). This document
deliberately does not duplicate the field lists — the duplication is what made the previous version of this
file stale. What belongs here is the shape and the rules:

- **Tables**: `subjects`, `class_levels`, `terms`, `session_term`, `lessons`, `lesson_content`, `has_subject`
  (a relation edge class_levels → subjects), `class_terms`, `teacher_assignment`, `student_profile`,
  `teacher_profile`, `parent_profile`, `admin_profile`, `lesson_assessments`, `general_assessments`,
  `compositions`, `submissions`, `credentials`.
- **Two divergences between the files and prod were harmless, and both are closed** (the files had declared
  more than prod, on unused tables): v3's `teaches` edge, and its `general_assessments.questions.*` sub-fields.
  *(Both were closed on 2026-10-05: the six `general_assessments.questions.*` statements were applied for the
  general-assessment feature, and applying v3 for them also brought in its `teaches` table and
  `teacher_profile.qualifications` — empty and unread by the app.)*
- **The third divergence is the one that is not harmless, and it is why the lineage is not a rebuild recipe.**
  v5 was never applied to prod: prod's `student_profile` has eleven fields and no `admission_number`, its
  `teacher_profile` and `admin_profile` have no `staff_id`, and there is no `id_sequences` table. The file
  declares all three as required non-empty strings, and the backend used to write none of them — so a fresh
  database with v5 applied broke user creation: `POST /api/users` for a Student answered `Couldn't coerce value
  for field 'admission_number' of 'student_profile:…': Expected 'string' but found 'NONE'`, and the login was
  rolled back so it could be retried. `db/schema-v5-init.surql` also opens with `DELETE id_sequences`, against
  the additive-only rule below. **v8 settles it by superseding both v5 files** (`db/schema-v8-ids.surql`
  declares the numbers as `option<int>`, seeds the two counters with `UPSERT`, and both files say so in their
  own headers): that is the shape the backend writes and the sandbox fixture mirrors, so the numbers work once
  v8 is applied to prod — and until it is, a create that has to hand one out fails with the statement's own
  error (the login is rolled back, so the admin can retry after the schema lands). Nothing else differs: apart
  from the v8 fields, the sandbox fixture and prod match field-for-field on the tables the app uses.
- **School numbers are the person's school identity, and what is stored is the integer alone.**
  `student_profile.admission_number` and `staff_id` on `teacher_profile` and `admin_profile` hold an
  `option<int>` — no prefix, no padding — drawn from one counter per class of member in `id_sequences`
  (`student`, `staff`). Teachers and admins share the `staff` counter, and a pk that already holds a staff
  number on either staff table *reuses* it rather than allocating a second one, which is what keeps a teacher
  made an admin holding their own number (a student who becomes staff is given a fresh staff number). The row
  gets its number in the write that makes it — the counter is bumped and read inside the profile statement
  itself, so a rejected or duplicate create cannot burn one and a retry allocates the next — and the written
  form (`JES-000123`, `EMP-000045`) is rendered by the backend in one place, into the listing's
  `school_number` field: the prefix is in no stored row and in no page. Once set it is immutable — a `PUT`
  payload carrying either field is a 400 naming it, the same refusal `class_enrolled` gets.
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
