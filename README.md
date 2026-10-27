# School Management System

A school management platform and LMS running in production at **Johnethel Heights**, a
primary and secondary school in Ogbomoso, Nigeria.

Teachers curate assessments from AI-generated lesson content and grade submissions.
Students work through lessons and assignments. Administrators manage users, classes,
terms and enrolment. Parents see the students linked to them. More than **1,000 lesson
records** are in production.

---

## Stack

| Layer | Technology | Role |
|:--|:--|:--|
| Frontend | Roc (Joy) → WebAssembly | A single-page app compiled to `app.wasm` |
| Backend | Roc on `basic-webserver` | One process serving the JSON API *and* the static bundle |
| Database | SurrealDB 3.x | Curriculum, lessons, assessments, submissions, profiles |
| Identity | Authentik | OIDC login, JWT issuance, user directory, admin API |
| Storage | Cloudflare R2 | Presigned uploads for passport photos |
| Deployment | Dokploy + Traefik | One image built by `Dockerfile.app` |

The frontend has no database credentials and no service tokens. The backend is the only
process that talks to SurrealDB, Authentik's admin API and R2, and it decides who the
caller is before any route does work.

**Why Roc:** it is pre-1.0 and the compiler is pinned to a nightly, which is a deliberate
trade. The client is one WebAssembly binary and the server is one static binary serving
both the API and the app — no framework between the request and the route. It is also the
only production codebase I know of that runs the same language on both sides.

## What it does

**Students** see the subjects, terms and lessons for their own class, read lesson content,
submit assignments before the deadline (resubmission allowed), and read grades and
feedback once a teacher has marked them.

**Teachers** see the classes they teach, curate assessments from each lesson's question
bank — multiple-choice and theoretical — set deadlines, and grade submissions from an
inbox. A grade and its feedback are pushed back to the student's own durable record.

**Administrators** manage users by role, initialise accounts, activate and deactivate
logins in Authentik, reset passwords, assign teachers to classes and subjects, create and
activate session terms, upload passport photos to R2, and manage the school's chat
channel directory.

**Parents** see the students linked to their profile and can follow each child's subjects,
terms and lessons.

## Engineering notes

- **Auth** is OAuth2 PKCE against Authentik. The backend validates each bearer token
  against the instance-wide userinfo endpoint and caches the answer for at most 60
  seconds, so a page that fires a dozen calls costs one validation. Every miss — no
  entry, expired entry, unreachable database, missing table — falls through to Authentik,
  so the cache is never the reason a request fails.
- **Authorisation** is enforced server-side from a single route table in
  `roc-backend/main.roc`: `/api/student/*` requires a student, `/api/teacher/*` a teacher,
  account and configuration writes an admin, shared reads any authenticated role. Admins
  may call anything.
- **Passwords belong to Authentik.** The app never stores one. A password change proves
  the current password through the provider's own password grant, discards the answer, and
  ends the session that set it.
- **Schema is versioned** in `db/schema-v*.surql`. The files are lineage, not a rebuild
  recipe — the applied definition is the database and can be read back with
  `INFO FOR TABLE`.
- **Crypto is implemented and tested against published vectors:** RFC 4231 cases for
  HMAC-SHA256 and AWS's worked SigV4 presign example for R2 uploads.

## Repository layout

```
roc-backend/     the API — main.roc holds every route; Authentik, SurrealDB, R2, Base64,
                 HMAC, SHA-256 and SigV4 helpers beside it, each with a *Test.roc file
roc-frontend/    the SPA — app.roc, State.roc and the views, plus the page's own JS/CSS
db/              versioned SurrealDB schema (v2 → v16) and migration helpers
devops/          compose files for Dokploy, Authentik and Matrix
docs/            architecture, standards, specs and the live progress tracker
agents/          retired MoonBit + Golem Cloud stack — reference only, not deployed
frontend/        retired SvelteKit frontend — reference only, not deployed
```

## Tests

Three layers, run separately:

```sh
bash scripts/test-unit.sh      # Roc unit tests, one *Test.roc file at a time
bash scripts/test-api.sh       # API behaviour against a sandbox schema
bash scripts/test-smoke.sh     # end-to-end against a running deployment
```

`roc-frontend/tests/e2e/` holds the browser suites, including an authorisation check that
a student's token is refused a teacher route.

## Running it

Roc is pinned to a nightly (`nightly-2026-09-29-7f11a82`, see `Dockerfile.app`); a
compiler from another channel may disagree with the platform URLs in the file headers.

```sh
roc check roc-backend/main.roc     # 0 errors expected
roc build roc-backend/main.roc     # writes ./main
```

Configuration comes entirely from the environment — `SURREAL_*`, `AUTHENTIK_*`, `R2_*`,
`DEV_MODE`, `BIND_HOST`, `PORT`, `STATIC_DIR`. See `devops/.env.example`.
`DEV_MODE=true` accepts stand-in tokens for local work and the sandbox suites; production
sets it to `false`.

## History

This started in 2022 as a static school website. It became a Python results system, then a
SvelteKit frontend with a MoonBit and Golem Cloud durable-agent backend. That stack is
retired: the platform now runs on Roc on both sides. The old code remains in `agents/` and
`frontend/` because the stored-data conventions still apply, but it is not deployed.

`docs/progress-tracker.md` holds the current state and the open work.
