# Unit 16 — Student Agent: Term & Lesson Lists

**Note:** This specification documents the original Unit 16 design targeting the `lesson_content` table with `class_subject_id` FK. Hotfix 01 (`hotfix-01-surrealdb-schema-v2.md`) supersedes this schema design — queries now target the `lessons` table via `has_subject TYPE RELATION` edges. The `class_subjects` junction table is replaced by graph traversal. Core agent method signatures (`get_terms`, `get_lessons`) remain the same; only the underlying SQL changed.

## Goal

Add `getTerms(classSubjectId)` and `getLessons(classSubjectId, termId)` methods to the Student Agent, querying SurrealDB's normalised `terms` and `lesson_content` tables via the new `class_subject_id` FK. Simultaneously migrate the existing `getSubjects()` to typed returns with TTL caching. All three methods use `#derive.golem_schema` typed returns with `Result[T, String]` Gateway envelopes — no manual JSON serialization. Surface through Gateway endpoints and SvelteKit proxy routes.

## Design

### Data Model Change: `class_subject_id` on `lesson_content`

Replace the two separate `class_level_id` + `subject_id` fields on `lesson_content` with a single `class_subject_id` FK to `class_subjects`. Keep the old fields as deprecated (for backward-compatible queries during migration).

**Normalization migration (`db/normalize-schema.surql`) — add Step 7b after Step 7:**

```surql
-- Step 7b: Add class_subject_id FK, populate from existing pairs
DEFINE FIELD class_subject_id ON lesson_content TYPE option<record<class_subjects>>;
DEFINE INDEX idx_lesson_cs ON lesson_content COLUMNS class_subject_id;
UPDATE lesson_content SET
  class_subject_id = (
    SELECT VALUE id FROM class_subjects
    WHERE class_level_id = $parent.class_level_id
      AND subject_id = $parent.subject_id
    LIMIT 1
  );
```

Also update the navigation index `idx_lesson_nav` to use `class_subject_id, term_id, week_number` instead of `class_level_id, subject_id, term_id, week_number`, and remove `idx_lesson_cl`, `idx_lesson_subj` (no longer needed for query paths).

**Queries in this unit use `class_subject_id` exclusively.** The deprecated `class_level_id`/`subject_id` fields are ignored in new code.

### Data Flow

```
Dashboard load
  → +page.server.ts → GET /api/student/subjects
  → proxyToGateway('/gateway/student/subjects', userId)
  → Gateway → StudentAgent.getSubjects()
    → subject_cache hit + fresh (< 600s) → return Array[SubjectInfo]
    → miss/stale → SurrealDB query via class_subjects
    → cache → return Array[SubjectInfo]
  → Gateway wraps in Result::Ok → {"Ok":[...]}
  → proxyToGateway strips Ok → { data: Subject[] }

Subject card click
  → +page.server.ts → GET /api/student/terms?class_subject_id={csid}
  → proxyToGateway('/gateway/student/terms', userId, { class_subject_id })
  → Gateway → StudentAgent.getTerms(classSubjectId)
    → terms_cache hit + fresh → return Array[TermInfo]
    → miss/stale → SurrealDB: terms with lessons for this class_subject
    → cache → return Array[TermInfo]

Term button click
  → GET /api/student/lessons?class_subject_id={csid}&term_id={tid}
  → same pattern → Gateway → StudentAgent.getLessons(csid, termId)
```

### Typed Returns (No Manual JSON)

All three Student Agent methods return typed arrays. All three Gateway endpoints return `Result[Array[T], String]`.

| Method | StudentAgent Return | Gateway Return |
|---|---|---|
| `get_subjects()` | `Array[SubjectInfo]` | `Result[Array[SubjectInfo], String]` |
| `get_terms(class_subject_id)` | `Array[TermInfo]` | `Result[Array[TermInfo], String]` |
| `get_lessons(class_subject_id, term_id)` | `Array[LessonInfo]` | `Result[Array[LessonInfo], String]` |

Golem's HTTP gateway serializes `Ok([...])` → `{"Ok":[...]}`, `Err("msg")` → `{"Err":"msg"}`. Existing endpoints (`ping`, `check-initialization`, etc.) continue returning `String` — not refactored here.

### TTL Caching (600 seconds for all lists)

Every cache entry stores data + UTC timestamp. Check on every request: if `now - fetched_at < 600`, return cached. Otherwise, re-query SurrealDB. Empty results cached as empty arrays (prevents repeated empty queries).

```moonbit
#derive.golem_schema
struct SubjectCache {
  subjects : Array[SubjectInfo]
  fetched_at : UInt64
}

#derive.golem_schema
struct TermCacheEntry {
  data : Array[TermInfo]
  fetched_at : UInt64
}

#derive.golem_schema
struct LessonCacheEntry {
  data : Array[LessonInfo]
  fetched_at : UInt64
}

let CACHE_TTL : UInt64 = 600
```

**Student Agent struct becomes:**

```moonbit
#derive.agent
struct StudentAgent {
  config : @config.Config[SurrealConfig]
  student_id : String
  mut profile : StudentProfile?
  mut subject_cache : SubjectCache?
  mut terms_cache : Map[String, TermCacheEntry]
  mut lessons_cache : Map[String, LessonCacheEntry]
}
```

The old `subjects: Map[String, SubjectInfo]` field is removed. **This is a breaking state change** — existing student agents have `subjects` in their durable state and will fail to deserialize. Existing agents must be deleted and re-created (via admin re-initialization) post-deploy.

### SurrealDB Queries

**`getSubjects` (updated):**

```sql
SELECT class_subject_id.id AS id,
       class_subject_id.name AS name,
       class_subject_id.code AS code
FROM class_subjects
WHERE class_level_id = $class_level_id AND active = true
ORDER BY class_subject_id.name ASC
```

Returns subject info by resolving the `class_subject_id` record linkage.

**`getTerms`:**

```sql
SELECT id, name, sort_order, active
FROM terms
WHERE active = true
  AND id IN (
    SELECT VALUE term_id FROM lesson_content
    WHERE class_subject_id = $class_subject_id AND term_id != NONE
  )
ORDER BY sort_order ASC
```

**`getLessons`:**

```sql
SELECT id, topic_title, week_number
FROM lesson_content
WHERE class_subject_id = $class_subject_id AND term_id = $term_id
ORDER BY week_number ASC
```

### Response Types (frontend)

```typescript
export interface Subject {
  id: string;
  name: string;
  code: string | null;
}

export interface Term {
  id: string;
  name: string;
  sort_order: number;
  active: boolean;
}

export interface Lesson {
  id: string;
  topic_title: string | null;
  week_number: number | null;
}
```

### proxyToGateway Update

Extend `frontend/src/lib/server/golem.ts` to handle the `Ok`/`Err` Result envelope alongside legacy `String` returns:

```typescript
const raw = await res.text();
let parsed: unknown;
try {
  parsed = JSON.parse(raw);
} catch {
  return { error: { code: 'PROXY_ERROR', message: 'Invalid response from gateway.' } };
}

// Handle Result envelope (Ok/Err) — new pattern
if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
  if ('Err' in parsed) return handleGatewayError(String((parsed as any).Err));
  if ('Ok' in parsed) return { data: JSON.stringify((parsed as any).Ok) };
}

// Legacy string response — existing pattern (ping, check-init, etc.)
if (typeof parsed === 'string') return handleGatewayError(parsed);

return { error: { code: 'UNKNOWN_RESPONSE', message: 'Unexpected response format.' } };
```

Extract `handleGatewayError(msg: string): ProxyResult` that checks for known error strings and returns structured errors.

### Error States

| Condition | Gateway Returns | Proxy Returns |
|---|---|---|
| Auth key mismatch | `Err("unauthorized")` | `403 UNAUTHORIZED` |
| Auth config error | `Err("auth error")` | `502 AUTH_ERROR` |
| Uninitialized user | `Err("NOT_INITIALIZED")` | `403 NOT_INITIALIZED` |
| Agent unreachable | `Err("admin unreachable")` | `502 PROXY_ERROR` |
| SurrealDB error | `Err("ERROR: ...")` | `502 GATEWAY_ERROR` |
| Success (empty) | `Ok([])` | `200 { data: [] }` |
| Success (data) | `Ok([...])` | `200 { data: [...] }` |

## Pre-Implementation: Regenerate SvelteKit Types

Several files in the workspace show LSP errors (`PageData`/`LayoutData` not exported from `./$types`, `$env/dynamic/private` or `$lib/...` import failures) due to the editor's language server using a stale type index. The `.svelte-kit/` generated files exist and are correct — the LSP simply needs to re-index them.

**Before writing any code, run:**

```bash
cd frontend && npx svelte-kit sync
```

This regenerates all route types, env declarations, and path alias configurations in `.svelte-kit/`. After syncing, restart the editor's TypeScript/Svelte language server (in VS Code: `Ctrl+Shift+P` → "TypeScript: Restart TS Server").

If errors persist after restart, verify the generated files exist:
- `.svelte-kit/types/src/routes/$types.d.ts` — exports `PageData` and `LayoutData`
- `.svelte-kit/ambient.d.ts` — declares `$env/dynamic/private` (line 223)
- `.svelte-kit/tsconfig.json` — defines `$lib` path alias

No code changes are needed to fix these LSP errors — they are a tooling cache issue, not a code defect.

## Implementation

### 1. Normalization migration (`db/normalize-schema.surql`)

Add Step 7b (DEFINE FIELD + populate `class_subject_id`). Update `idx_lesson_nav` to `(class_subject_id, term_id, week_number)`. Drop `idx_lesson_cl` and `idx_lesson_subj`. Idempotent — safe to re-run.

### 2. Student Agent — Types & cache fields

**`agents/app-agents/student_agent.mbt`**

Replace `subjects : Map[String, SubjectInfo]` with `mut subject_cache : SubjectCache?`. Add `TermCacheEntry`, `LessonCacheEntry` structs, `CACHE_TTL` constant, `mut terms_cache`, `mut lessons_cache` maps. Update `new()`.

### 3. Student Agent — `get_subjects()` (rebuilt)

```
pub fn get_subjects(self : Self) -> Array[SubjectInfo]
```

1. Check `subject_cache`: if `Some(cache)` and `now - cache.fetched_at < CACHE_TTL`, return `cache.subjects`
2. Get the student's `class_level` from `self.profile`; if `None`, return `[]`
3. Query SurrealDB using the updated SQL (joins through `class_subject_id`)
4. Parse JSON, extract `id, name, code` into `Array[SubjectInfo]`
5. Store in `self.subject_cache = Some(SubjectCache { subjects, fetched_at: now })`, return

### 4. Student Agent — `initialize()` (updated)

Instead of `self.subjects.set(...)` for each subject, after the SurrealDB query populates the subjects list, store in `self.subject_cache = Some(SubjectCache { subjects, fetched_at: now })`. Remove all `self.subjects` references.

### 5. Student Agent — `get_terms()` (new)

```
pub fn get_terms(self : Self, class_subject_id : String) -> Array[TermInfo]
```

1. Check `terms_cache[class_subject_id]`: if `Some(entry)` and fresh, return `entry.data`
2. Query SurrealDB for terms with lessons for this `class_subject_id`
3. Parse JSON response, extract `id, name, sort_order, active` into `Array[TermInfo]`
4. Wrap in `TermCacheEntry`, store in `terms_cache`, return

### 6. Student Agent — `get_lessons()` (new)

```
pub fn get_lessons(self : Self, class_subject_id : String, term_id : String) -> Array[LessonInfo]
```

Same pattern as `get_terms`. Cache key: `"{class_subject_id}|{term_id}"`. Use `topic_title` and `week_number` fields. No manual JSON anywhere.

### 7. Gateway Agent — Three endpoints

**Update `student_subjects` to return `Result[Array[SubjectInfo], String]`:**

```moonbit
#derive.endpoint(get="/student/subjects?user_id={user_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::student_subjects(
  self : Self,
  incoming_key : String,
  user_id : String,
) -> Result[Array[SubjectInfo], String> {
  // 1. Auth check → Err
  // 2. Init check → Err
  // 3. RPC to StudentAgent → Ok(result) or Err("student agent unreachable")
}
```

**Add `student_terms` → `Result[Array[TermInfo], String]`:**

`GET /gateway/student/terms?user_id={user_id}&class_subject_id={class_subject_id}`

Same pattern: auth → init → RPC to `student.get_terms(class_subject_id)` → `Ok(...)` / `Err(...)`.

**Add `student_lessons` → `Result[Array[LessonInfo], String]`:**

`GET /gateway/student/lessons?user_id={user_id}&class_subject_id={class_subject_id}&term_id={term_id}`

Same pattern: auth → init → RPC to `student.get_lessons(class_subject_id, term_id)` → `Ok(...)` / `Err(...)`.

### 8. SvelteKit — Proxy routes

**Update `frontend/src/routes/api/student/subjects/+server.ts`:**

The response from `proxyToGateway` now comes as `{ data: string }` where the string is a re-serialized JSON array (from the `Ok` envelope handling). The existing proxy already does `JSON.parse(result.data)` and wraps in `{ data: [...] }`, so **no code changes needed** — the flow is transparent.

**New: `frontend/src/routes/api/student/terms/+server.ts`:**

```
GET /api/student/terms?class_subject_id={csid}
→ validate auth (401 if no user)
→ validate class_subject_id param (400 if missing)
→ proxyToGateway('/gateway/student/terms', userId, { class_subject_id })
→ parse response JSON → wrap in { data: [...] }
→ return 200
```

**New: `frontend/src/routes/api/student/lessons/+server.ts`:**

```
GET /api/student/lessons?class_subject_id={csid}&term_id={tid}
→ validate auth
→ validate both params (400 if missing)
→ proxyToGateway('/gateway/student/lessons', userId, { class_subject_id, term_id })
→ parse → wrap → return 200
```

### 9. proxyToGateway update (`frontend/src/lib/server/golem.ts`)

As described in Design section above. Consolidate all known error-string checks (`unauthorized`, `auth error`, `NOT_INITIALIZED`, `admin unreachable`) into a single `handleGatewayError(msg: string): ProxyResult` helper function. Insert the `Ok`/`Err` envelope check before the legacy string check.

### 10. Frontend types

Add `Term` and `Lesson` interfaces to `frontend/src/lib/types.ts`.

## Files Changed

| File | Change |
|---|---|
| `db/normalize-schema.surql` | Add Step 7b (`class_subject_id`), update nav index, drop deprecated indexes |
| `agents/app-agents/student_agent.mbt` | Replace `subjects` with `subject_cache`; add `TermCacheEntry`, `LessonCacheEntry`, cache maps, TTL constant; rebuild `get_subjects()`; add `get_terms()`, `get_lessons()`; update `initialize()` and `new()` |
| `agents/app-agents/gateway_agent.mbt` | Update `student_subjects` return type to `Result[Array[SubjectInfo], String]`; add `student_terms`, `student_lessons` endpoints |
| `frontend/src/lib/server/golem.ts` | Extend response parser for `Ok`/`Err` envelope; extract `handleGatewayError` helper |
| `frontend/src/lib/types.ts` | Add `Term`, `Lesson` interfaces |
| `frontend/src/routes/api/student/terms/+server.ts` | **New** — proxy to `/gateway/student/terms` |
| `frontend/src/routes/api/student/lessons/+server.ts` | **New** — proxy to `/gateway/student/lessons` |
| `docs/architecture.md` | Update storage model: `lesson_content` now has `class_subject_id` FK, deprecate `class_level_id`/`subject_id` |
| `docs/progress-tracker.md` | Mark Unit 16 complete |

## Dependencies

None. All MoonBit imports and SvelteKit infrastructure are in place. No new npm packages.

## Verification Checklist

### Pre-Implementation
- [ ] `cd frontend && npx svelte-kit sync` runs without errors
- [ ] Restart TypeScript language server in editor
- [ ] LSP errors in `+page.svelte` (`PageData`), `+layout.svelte` (`LayoutData`), `authentik.ts` (`$env/dynamic/private`), and `UserTable.svelte` (`$lib/...`) are all resolved
- [ ] If any error persists, verify `.svelte-kit/types/src/routes/$types.d.ts` exports `PageData`/`LayoutData`, and `.svelte-kit/ambient.d.ts` declares `$env/dynamic/private`

### Build & Typecheck
- [ ] `golem build` succeeds with zero errors
- [ ] `pnpm build` succeeds with zero errors
- [ ] `pnpm check` passes with zero errors
- [ ] `moon info && moon fmt` run on `agents/app-agents/`

### Normalization Migration
- [ ] Step 7b: `class_subject_id` field added to `lesson_content`
- [ ] All existing `lesson_content` records have `class_subject_id` populated
- [ ] Navigation index updated: `(class_subject_id, term_id, week_number)`
- [ ] Deprecated indexes `idx_lesson_cl`, `idx_lesson_subj` removed
- [ ] No errors on re-run (idempotent)

### Gateway endpoints (via curl)
- [ ] `GET /gateway/student/subjects?...` → `{"Ok":[{"id":"...","name":"...","code":null}]}`
- [ ] `GET /gateway/student/terms?class_subject_id={csid}...` → `{"Ok":[{"id":"...","name":"First Term","sort_order":1,"active":true}]}`
- [ ] `GET /gateway/student/lessons?class_subject_id={csid}&term_id={tid}...` → `{"Ok":[{"id":"...","topic_title":"...","week_number":1}]}`
- [ ] Terms ordered by `sort_order`; lessons ordered by `week_number`
- [ ] `active=false` terms excluded
- [ ] Terms with no lessons for `class_subject_id` excluded
- [ ] Wrong auth → `{"Err":"unauthorized"}`
- [ ] Uninitialized user → `{"Err":"NOT_INITIALIZED"}`
- [ ] SurrealDB error → `{"Err":"ERROR: ..."}` or `{"Err":"student agent unreachable"}`

### TTL Caching
- [ ] First call (any method) queries SurrealDB; second call within 600s skips DB
- [ ] Empty results cached as `[]` (no repeated empty queries)
- [ ] Different `class_subject_id` values produce independent cache entries
- [ ] `initialize()` populates `subject_cache` (no separate query on first subjects call)
- [ ] Agent post-restart (after 600s) → SurrealDB re-queried on next request

### proxyToGateway
- [ ] `{"Ok":[...]}` → `{ data: "[...]" }` (re-serialized array)
- [ ] `{"Err":"unauthorized"}` → `{ error: { code: "UNAUTHORIZED" } }`
- [ ] `{"Err":"NOT_INITIALIZED"}` → `{ error: { code: "NOT_INITIALIZED" } }`
- [ ] `{"Err":"admin unreachable"}` → `{ error: { code: "PROXY_ERROR" } }`
- [ ] Legacy `"admin online"` → `{ data: "admin online" }` (unchanged)
- [ ] Legacy `"unauthorized"` → `{ error: { code: "UNAUTHORIZED" } }` (unchanged)
- [ ] Legacy `"NOT_INITIALIZED"` → `{ error: { code: "NOT_INITIALIZED" } }` (unchanged)

### SvelteKit proxy routes
- [ ] `GET /api/student/subjects` still works (transparent — proxyToGateway handles Ok envelope)
- [ ] `GET /api/student/terms?class_subject_id={csid}` → `200 { data: Term[] }`
- [ ] `GET /api/student/lessons?class_subject_id={csid}&term_id={tid}` → `200 { data: Lesson[] }`
- [ ] Missing `class_subject_id` → `400 MISSING_PARAM`
- [ ] Missing `term_id` (lessons) → `400 MISSING_PARAM`
- [ ] Unauthenticated → `401 UNAUTHENTICATED`
- [ ] Uninitialized → `403 NOT_INITIALIZED`

### Regression
- [ ] Student dashboard subject cards still load
- [ ] Admin dashboard unchanged
- [ ] `pnpm build` zero errors, `pnpm check` zero errors
- [ ] `docs/architecture.md` updated with new FK and deprecated fields
- [ ] `docs/progress-tracker.md` updated
