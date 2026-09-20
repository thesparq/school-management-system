# Testing System

## Quick Start

```bash
pnpm test          # Compile checks + read-only API smoke (always safe)
pnpm test:unit     # Compile checks only
pnpm test:smoke    # API health checks (needs TEST_JWT)
pnpm test:api      # Full CRUD integration (needs TEST_JWT + Authentik creds)
pnpm test:all      # All three layers
```

## Architecture

Three layers, each one layer deeper into the stack:

```
┌─────────────────────────────────────────────────────┐
│ Layer 1: Compile Checks (test-unit.sh)              │
│   moon check agents/  ·  moon check shared/         │
│   pnpm check frontend/                              │
│   Always runs · 0 external deps · <2 seconds        │
├─────────────────────────────────────────────────────┤
│ Layer 2: Smoke Tests (test-smoke.sh)                │
│   curl → SvelteKit proxy → Golem agent → SurrealDB  │
│   9 read-only endpoints · needs TEST_JWT · <2 secs  │
├─────────────────────────────────────────────────────┤
│ Layer 3: API Integration (test-api.sh)              │
│   Full CRUD per role · Create → Edit → Delete       │
│   Needs TEST_JWT + AUTHENTIK_* env vars             │
│   Auto-cleanup on exit (trap EXIT)                  │
└─────────────────────────────────────────────────────┘
```

## Layer 1: Compile Checks

**Script:** `scripts/test-unit.sh`  
**When:** After every code change  
**Deps:** None  

Verifies the entire monorepo compiles without errors:

| Check | Command | What it validates |
|-------|---------|-------------------|
| MoonBit agents | `moon check --target wasm` in `agents/` | All `.mbt` files in `agents/app-agents/` compile to WASM |
| MoonBit shared | `moon check` in `shared/` | Shared library compiles |
| Frontend TypeScript | `pnpm check` in `frontend/` | All `.svelte` and `.ts` files type-check |

If any of these fail, something is broken at the syntax/type level.  
Fix it before proceeding to Layer 2.

## Layer 2: Smoke Tests

**Script:** `scripts/test-smoke.sh`  
**When:** After deploying changes to a dev environment  
**Deps:** `TEST_JWT` env var  

Sends curl requests to the running SvelteKit development server.  
All endpoints are **read-only** — zero side effects, safe to run repeatedly.

```bash
export TEST_JWT='<your-session-jwt-value>'
pnpm test:smoke
```

### Endpoints tested

| # | Path | What it proves |
|---|------|----------------|
| 1 | `GET /api/ping` | SvelteKit → Golem proxy working |
| 2 | `GET /api/admin/class-levels` | Admin agent → SurrealDB query working |
| 3 | `GET /api/admin/credentials` | Credentials table accessible |
| 4 | `GET /api/admin/session-terms` | Session terms query + caching |
| 5 | `GET /api/admin/active-session-term` | Active session lookup |
| 6 | `GET /api/admin/terms` | Terms table accessible |
| 7 | `GET /api/admin/students/list` | Student profile list (class_name populated) |
| 8 | `GET /api/admin/parents/list` | Parent profile list (students linked) |
| 9 | `GET /api/admin/class-subjects` | Class-subject graph edges |

Each endpoint is called with the admin JWT. A **200 response** means:
- Auth is working (JWT accepted by SvelteKit → forwarded to Golem)
- Golem agent is running and responding
- SurrealDB is connected and returning data
- No schema mismatches, no broken record links, no HTTP-layer errors

### Getting a TEST_JWT

1. Open the app in your browser
2. Log in as admin
3. Open DevTools → Application → Cookies
4. Copy the value of `session_jwt`
5. `export TEST_JWT='<paste-here>'`

## Layer 3: API Integration Tests

**Script:** `scripts/test-api.sh`  
**When:** Before merging PRs, after major refactors  
**Deps:** `TEST_JWT` + `AUTHENTIK_HOST` + `AUTHENTIK_SERVICE_ACCOUNT_TOKEN`  

Full end-to-end CRUD across all four user roles:

```
For each role (student, teacher, admin, parent):
  1. POST /api/admin/users          → create user (201)
  2. GET  /api/admin/users/{uuid}/profile → verify fields
  3. POST /api/admin/users/{uuid}/edit-profile → edit
  4. POST /api/admin/users/{pk}/activate-authentik → activate
  5. POST /api/admin/users/{pk}/deactivate-authentik → deactivate
  6. DELETE /api/admin/users/{pk}   → delete user (200)

Credentials:
  7. POST   /api/admin/credentials  → create credential (201)
  8. DELETE /api/admin/credentials/{id} → delete
```

### Env vars

```bash
export TEST_JWT='<jwt-value>'                    # from browser cookies
export AUTHENTIK_HOST='your-auth.example.com'    # Authentik server host
export AUTHENTIK_SERVICE_ACCOUNT_TOKEN='<token>' # Admin API token
export FRONTEND_URL='http://localhost:5173'       # optional, default
```

### Cleanup

A `trap EXIT` handler runs cleanup on any exit (success, failure, Ctrl+C).  
All created users and credentials are deleted. Nothing persists past the test run.

### Failure modes

| Symptom | Likely cause |
|---------|-------------|
| 401 on create | TEST_JWT expired — get a fresh one |
| 400 "Passport is required" | Backend validation rejecting empty URL |
| 409 or group error | Authentik group missing — create groups first |
| 502 on proxy routes | Golem agents not deployed — run `pnpm run deploy:agents` |
| jq not found | Install jq: `sudo apt install jq` |
| No class levels | DB not seeded — run `schema-v2.surql` |

## Usage Flow

```bash
# 1. Code change
vim agents/app-agents/validation.mbt

# 2. Verify compilation (always works)
pnpm test:unit

# 3. Deploy to dev
pnpm run deploy:agents

# 4. Get fresh JWT from browser, then:
export TEST_JWT='<jwt>'
pnpm test:smoke           # quick health check

# 5. Before merging:
export AUTHENTIK_HOST='...'
export AUTHENTIK_SERVICE_ACCOUNT_TOKEN='...'
pnpm test:api              # full integration

# Or all at once:
pnpm test:all
```

## Files

```
scripts/
├── test-unit.sh       Layer 1 — compile checks (always safe)
├── test-smoke.sh      Layer 2 — read-only API health (needs JWT)
└── test-api.sh        Layer 3 — full CRUD integration (needs JWT + Authentik)

package.json           Test scripts under "test:*" keys
```
