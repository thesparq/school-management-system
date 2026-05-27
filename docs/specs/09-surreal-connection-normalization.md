# Unit 9 — SurrealDB Connection & Schema Normalization

## Goal

Connect to the production SurrealDB instance and normalize the denormalized `lesson_content` table into lookup tables (`subjects`, `class_levels`, `terms`, `class_subjects`) via a SurrealQL migration run through Surrealist. Add Golem secrets for SurrealDB credentials and an HTTP client helper that all agents will use to query SurrealDB in later units.

## Design

### Normalized Schema

**`lesson_content` (existing — stays schemaless)**
The original table is not touched. No `DEFINE TABLE` or schema enforcement is added. Four new optional fields are added via `DEFINE FIELD`:

| New Field | Type | Source |
|---|---|---|
| `class_level_id` | `record<class_levels>` | Extracted from existing `class_level` string |
| `subject_id` | `record<subjects>` | Extracted from existing `subject` string |
| `term_id` | `record<terms>` | Extracted from existing `term` string |
| `week_number` | `int` | Extracted from existing `week` string |

The old `class_level`, `subject`, `term`, `week` string fields are **kept in place** — no data is removed. This is a non-destructive migration: existing code that reads the old string fields continues to work unchanged.

**New lookup tables (all `SCHEMAFULL`):**

**`subjects`** — all subjects in the curriculum
| Field | Type | Notes |
|---|---|---|
| `id` | auto numeric | SurrealDB default |
| `name` | `string` | e.g. "Basic Science", "Mathematics" — unique |
| `code` | `option<string>` | Short code like "BSC" |
| `active` | `bool` | Default `true` |

**`class_levels`** — all class levels (year groups)
| Field | Type | Notes |
|---|---|---|
| `id` | auto numeric | SurrealDB default |
| `name` | `string` | e.g. "Primary 1", "JSS 1" — unique |
| `code` | `option<string>` | |
| `active` | `bool` | Default `true` |

**`terms`** — academic terms (always 3)
| Field | Type | Notes |
|---|---|---|
| `id` | auto numeric | SurrealDB default |
| `name` | `string` | "First Term", "Second Term", "Third Term" — unique |
| `sort_order` | `int` | 1, 2, 3 |
| `active` | `bool` | Default `true` |

**`class_subjects`** — many-to-many mapping answering "what subjects does a class study?"
| Field | Type | Notes |
|---|---|---|
| `id` | auto numeric | SurrealDB default |
| `class_level_id` | `record<class_levels>` | FK to class_levels |
| `subject_id` | `record<subjects>` | FK to subjects |
| `active` | `bool` | Default `true` |

**Why `class_subjects` exists:** It defines the curriculum. Instead of scanning every `lesson_content` row and doing `SELECT DISTINCT subject WHERE class_level = ...`, you query:
```surql
SELECT subject_id.* FROM class_subjects WHERE class_level_id = $cl AND active = true;
```
This is faster and becomes the authoritative source once admins maintain it directly (Unit 22). It's initially populated from distinct `(class_level, subject)` pairs found in existing lesson records.

**New indexes on lesson_content (old indexes kept as-is):**

| Index | Fields | Purpose |
|---|---|---|
| `idx_lesson_cl` | `class_level_id` | Fast lookup by class level (FK) |
| `idx_lesson_subj` | `subject_id` | Fast lookup by subject (FK) |
| `idx_lesson_nav` | `class_level_id, subject_id, term_id, week_number` | Composite index for the common lesson query: "fetch lesson for this class, subject, term, week" |

Existing indexes `idx_class_level`, `idx_class_subject`, and `idx_nav` remain unchanged — they still serve ad-hoc queries on the old string fields.

### Migration Script

A single `.surql` file at `db/normalize-schema.surql`. Run manually via Surrealist's SQL editor. The migration is idempotent — `DEFINE FIELD` on an already-defined field is a no-op, and population queries use `CREATE ... ON DUPLICATE KEY UPDATE`.

### Golem Secrets for SurrealDB

A single shared `SurrealConfig` struct defines all 5 connection parameters as Golem secrets. Every agent that needs SurrealDB access (StudentAgent, TeacherAgent, future AdminAgent methods) gets one `@config.Config[SurrealConfig]` injected via its constructor — no per-agent config duplication.

| Secret | Env Var | Purpose |
|---|---|---|
| `host` | `SURREAL_DB_HOST` | SurrealDB hostname (no scheme) |
| `ns` | `SURREAL_DB_NS` | Namespace — sent as `surreal-ns` header |
| `database` | `SURREAL_DB` | Database name — sent as `surreal-db` header |
| `username` | `SURREAL_DB_USERNAME` | HTTP Basic Auth username |
| `password` | `SURREAL_DB_PASSWORD` | HTTP Basic Auth password |

Auth uses HTTP Basic Auth (`username:password` base64-encoded via `@base64.encode` from `moonbitlang/core/encoding/base64`). This avoids JWT expiry issues and is the standard SurrealDB SDK auth method.

Secrets are set via `secretDefaults` in `golem.yaml` for local dev (with `{{ ENV_VAR }}` template syntax for env var substitution) and via `golem secret create` for production.

### Agent HTTP Client

A shared `surreal_client.mbt` in `agents/app-agents/` provides a `surreal_query(config: Config[SurrealConfig], sql: String) -> Result[String, String]` function that:
1. Takes the agent's injected `@config.Config[SurrealConfig]` directly — no manual secret resolution by the caller
2. Resolves all 5 secrets internally with `catch` — returns `Err(...)` on any missing secret
3. Builds HTTP Basic Auth header via `@base64.encode(Bytes::from_array(str_to_bytes(user + ":" + pass)).view())`
4. Sends a WASI HTTP POST to `https://{host}/sql` with `surreal-ns`, `surreal-db`, `Authorization` headers
5. Uses full `match`-based error handling on every WASI HTTP operation — no `.unwrap()` panics
6. Returns the JSON response body on success (2xx) or `Err("SurrealDB {status}: {body}")` on non-2xx

The `@http`, `@http_types`, `@streams`, `@utf8`, and `@base64` packages are imported in `moon.pkg`.

### Gateway DB-test Endpoint

A single `/gateway/db-test` endpoint on the Gateway Agent verifies connectivity end-to-end:
- No activation check (bootstrap/debug endpoint)
- Auth key check (same as all other endpoints)
- Calls `StudentAgentClient::scoped(fn(student) { student.test_db() })` via typed RPC — Gateway never holds DB credentials
- The StudentAgent's `test_db` calls `surreal_query(self.config, "SELECT 1")`

---

## Implementation

### 1. Create `db/normalize-schema.surql`

Full migration script — run in Surrealist one time.

### 2. Update `golem.yaml` — add SurrealDB secrets

```yaml
secretDefaults:
  local:
    authKey: "dev-auth-key-change-in-production"
    host: "{{ SURREAL_DB_HOST }}"
    ns: "{{ SURREAL_DB_NS }}"
    database: "{{ SURREAL_DB }}"
    username: "{{ SURREAL_DB_USERNAME }}"
    password: "{{ SURREAL_DB_PASSWORD }}"
```

### 3. Update `agents/app-agents/moon.pkg` — add imports

```
  "golemcloud/golem_sdk/http" @http,
  "golemcloud/golem_sdk/interface/wasi/http/types" @http_types,
  "golemcloud/golem_sdk/interface/wasi/io/streams" @streams,
  "moonbitlang/core/encoding/utf8" @utf8,
  "moonbitlang/core/encoding/base64" @base64,
```

Note: `@http_types` avoids alias conflict with existing `golemcloud/golem_sdk/agents/types @types`.

### 4. Create `agents/app-agents/surreal_client.mbt`

Defines the shared `SurrealConfig` struct (all 5 fields as `@config.Secret[String]`) and `surreal_query(config, sql)` function:

- HTTP Basic Auth via `@base64.encode` from `moonbitlang/core/encoding/base64`
- `surreal-ns` / `surreal-db` headers (SurrealDB SDK convention)
- `/sql` path (ns/db in headers, not URL)
- Full `match`-based error handling — returns `Result[String, String]`, never panics

### 5. Scaffold StudentAgent and TeacherAgent with `test_db`

Both agents use the shared `SurrealConfig` (not separate per-agent configs):

```moonbit
#derive.agent
struct StudentAgent {
  config : @config.Config[SurrealConfig]
}

pub fn StudentAgent::test_db(self : Self) -> String {
  match surreal_query(self.config, "SELECT 1") {
    Ok(body) => "OK: " + body
    Err(e) => "ERROR: " + e
  }
}
```

Gateway Agent's `/gateway/db-test` calls `StudentAgentClient::scoped(fn(student) { student.test_db() })` via typed RPC — Gateway never holds SurrealDB credentials.

### 6. Add SvelteKit proxy route for db-test

`frontend/src/routes/api/db-test/+server.ts`:

```typescript
import { proxyToGateway } from '$lib/server/golem';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async (event) => {
	const userId = event.locals.user?.id;
	if (!userId) {
		return new Response(
			JSON.stringify({ error: { code: 'UNAUTHENTICATED', message: 'Not authenticated.' } }),
			{ status: 401, headers: { 'content-type': 'application/json' } }
		);
	}
	const result = await proxyToGateway('/gateway/db-test', userId);
	if (result.error) {
		return new Response(JSON.stringify(result), {
			status: 502,
			headers: { 'content-type': 'application/json' }
		});
	}
	return new Response(JSON.stringify(result), {
		status: 200,
		headers: { 'content-type': 'application/json' }
	});
};
```

### 7. Build and verify

```bash
cd agents
golem build
moon check --target wasm
moon info && moon fmt

cd ../frontend
pnpm build
pnpm check
```

### 8. Run the migration (Surrealist)

Open the Surrealist SQL editor for the production database. Paste `db/normalize-schema.surql` and click Run.

### 9. Verify migration

```surql
SELECT count() FROM subjects;
SELECT count() FROM class_levels;
SELECT count() FROM terms;
SELECT count() FROM class_subjects;
SELECT count() FROM lesson_content WHERE subject_id IS NONE;
SELECT count() FROM lesson_content WHERE week_number IS NONE;
```

### 10. Verify agent connectivity

```bash
curl -H "X-Golem-Auth-Key: dev-auth-key-change-in-production" \
  "http://agents.localhost:9006/gateway/db-test"
# → "OK: [{\"result\":[{\"1\":1}],\"status\":\"OK\"}]"
```

---

## Dependencies

| Item | Action | Purpose |
|---|---|---|
| `@http` | Add to moon.pkg import | WASI HTTP outgoing request |
| `@http_types` | Add to moon.pkg import | HTTP type constructors (aliased to avoid conflict with existing `@types`) |
| `@streams` | Add to moon.pkg import | Stream error types |
| `@utf8` | Add to moon.pkg import | UTF-8 encoding for HTTP |
| `@base64` | Add to moon.pkg import | Base64 encoding for HTTP Basic Auth |
| `surreal` CLI | Install locally | Dev testing and debugging |
| Surrealist | — | Run migration SQL |

## Verification Checklist

### Migration
- [ ] `db/normalize-schema.surql` executes without errors in Surrealist
- [ ] `SELECT count() FROM subjects` > 0 with distinct subject names from lessons
- [ ] `SELECT count() FROM class_levels` > 0 with distinct level names from lessons
- [ ] `SELECT count() FROM terms` = 3 (First, Second, Third Term)
- [ ] `SELECT count() FROM class_subjects` > 0 with distinct (class_level, subject) pairs
- [ ] `SELECT count() FROM lesson_content WHERE subject_id IS NONE` = 0 (all migrated)
- [ ] `SELECT count() FROM lesson_content WHERE week_number IS NONE` = 0
- [ ] Old `class_level`, `subject`, `term`, `week` fields still exist and have original values
- [ ] Re-running migration is a no-op (no errors, no duplicate rows)
- [ ] `idx_lesson_cl`, `idx_lesson_subj`, `idx_lesson_nav` indexes exist
- [ ] Old indexes `idx_class_level`, `idx_class_subject`, `idx_nav` still exist

### Agent Layer
- [ ] `moon check --target wasm` succeeds (zero errors)
- [ ] `golem build` succeeds
- [ ] `moon info && moon fmt` runs clean in `agents/`
- [ ] `SurrealConfig` compiles with `#derive.config` and 5 `@config.Secret[String]` fields
- [ ] `surreal_query` compiles and returns `Result[String, String]`
- [ ] `StudentAgent` and `TeacherAgent` use shared `SurrealConfig` (not per-agent configs)
- [ ] Gateway Agent calls `StudentAgentClient::scoped(fn(student) { student.test_db() })` via typed RPC
- [ ] Gateway `GET /gateway/db-test` with valid auth returns `"OK: ..."` (after setting correct credentials)
- [ ] Gateway `GET /gateway/db-test` with wrong auth returns `"unauthorized"`
- [ ] Gateway `GET /gateway/db-test` with bad SurrealDB credentials returns `"ERROR: SurrealDB 401: ..."`
- [ ] Existing gateway endpoints unchanged (ping, check-activation, admin/activate, etc.)

### Frontend Layer
- [ ] `pnpm build` succeeds (zero errors)
- [ ] `pnpm check` passes (zero errors)
- [ ] `GET /api/db-test` for authenticated user returns `{ data: "OK: ..." }` with 200
- [ ] `GET /api/db-test` for unauthenticated user returns 401

### Documentation
- [ ] `docs/architecture.md` Storage Model section updated with new tables
- [ ] `docs/progress-tracker.md` updated: Unit 9 marked as completed
