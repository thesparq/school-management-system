# HF-08 — Error Handling Unification

## Goal

Unify all error responses across the system into a single format matching Golem's gateway error convention (`{"code":"...","message":"...","errors":["..."]}`), eliminate lossy error propagation in DB helpers by renaming `detail`→`debug` and enforcing a user-facing vs developer-facing message contract, and fix the frontend proxy to recognize all Golem response formats via a single `extractErrorFromBody` function — preventing silent success on gateway errors.

## Design

### Structural decisions

- **`AppError` field rename:** `detail` → `debug` across all MoonBit source files. `message` = always user-facing (clean, no raw SQL/HTTP). `debug` = always developer-facing (raw SQL, response bodies).

- **New `AppError::to_json_string()` format** — top-level `code`/`message`/`errors` fields matching Golem's gateway error shape, plus a non-standard `debug` field for developer diagnostics:

  ```json
  {"code":"SURREALDB_ERROR","message":"Database query failed","errors":["Database query failed"],"debug":"SQL: SELECT ... | Response: ..."}
  ```

  The `errors` array mirrors Golem's built-in format. The `debug` field is additive (Golem doesn't have it) — never shown to users, only logged to console.

- **Frontend `extractErrorFromBody(raw)`** — single function handles three formats:
  1. Golem agent `Err` envelope: `{"Err": "<inner_json>"}`
  2. Golem gateway error + our new `AppError`: `{"code":"...","errors":[...]}`
  3. Legacy nested format (defensive): `{"error":{"code":"...","message":"..."}}`

- **`proxyFetch` adds `!res.ok` gate** — any non-2xx response is treated as error before body format inspection. No more silent fallthrough to `{ data: raw }`.

- **Layer contract enforced:** 
  - DB client / Authentik client: `message` = clean, `debug` = raw detail
  - DB helpers: propagate, never discard original `debug`
  - Handlers: sole error translator, constructs user-facing `message`
  - Agents: pass-through only

### No new dependencies

All changes within existing files. No new packages.

---

## Implementation

### 1. Backend: `errors.mbt` — `detail` → `debug` + new JSON format

**File:** `agents/app-agents/errors.mbt`

Struct change:
```moonbit
pub struct AppError {
  code : ErrorCode
  message : String   // always user-facing, clean
  debug : String?    // developer-facing, contains raw SQL/HTTP responses
}
```

Updated `to_json_string()`:
```moonbit
pub fn AppError::to_json_string(self : AppError) -> String {
  let debug_json = match self.debug {
    Some(d) => "\"" + escape_json_string(d) + "\""
    None => "null"
  }
  "{\"code\":\"" +
  self.to_code_string() +
  "\",\"message\":\"" +
  escape_json_string(self.message) +
  "\",\"errors\":[\"" +
  escape_json_string(self.message) +
  "\"],\"debug\":" +
  debug_json +
  "}"
}
```

Updated `surreal_error()`:
```moonbit
pub fn surreal_error(body : String, sql : String?) -> AppError {
  AppError::{
    code: SurrealDBError,
    message: "Database query failed",
    debug: Some(match sql {
      Some(s) => "SQL: " + s + " | Response: " + body
      None => "Response: " + body
    })
  }
}
```

Updated `not_found_error()`:
```moonbit
pub fn not_found_error(resource : String) -> AppError {
  AppError::{ code: NotFound, message: resource + " not found", debug: None }
}
```

Updated `validation_error()`:
```moonbit
pub fn validation_error(msg : String) -> AppError {
  AppError::{ code: ValidationError, message: msg, debug: None }
}
```

Updated `escape_json_string()` — no changes needed (already handles `\`, `"`, `\n`, `\r`, `\t`).

### 2. Backend: `db_client.mbt` — `surreal_error()` debug update

**File:** `agents/app-agents/db_client.mbt`

All calls to `surreal_error(body, sql?)` already use the helper — no structural changes needed since the helper itself is updated in Section 1. The `parse_result_array()` function already delegates to `surreal_error()`.

Verify no manual `AppError::{ code: SurrealDBError, message: ... }` constructions exist outside `surreal_error()`.

### 3. Backend: `authentik_client.mbt` — `detail` → `debug`

**File:** `agents/app-agents/authentik_client.mbt`

All `AppError::{}` constructions use `detail:`. Replace every `detail:` → `debug:`.

Functions affected (grep for `AppError`):
- `authentik_request()` — HTTP transport errors
- `check_authentik_status()` — status code errors
- `authentik_create_user()` — parse failures
- `authentik_get_group_pk_by_name()` — parse failures, not found

Pattern (example):
```moonbit
// Before:
Err(e) => return Err(AppError::{ code: AuthentikError, message: e, detail: None })

// After:
Err(e) => return Err(AppError::{ code: AuthentikError, message: e, debug: None })
```

### 4. Backend: `db_admin.mbt` — non-lossy error propagation + `detail` → `debug`

**File:** `agents/app-agents/db_admin.mbt`

**4a. `db_admin_save_profile` (line 8-9):**

```moonbit
// Before:
Err(_) => return Err(AppError::{ code: SurrealDBError, message: "Failed to resolve class level", detail: None })

// After:
Err(e) => return Err(AppError::{ code: SurrealDBError, message: "Failed to resolve class level", debug: e.debug })
```

This preserves the original error's `debug` field (which contains the raw SurrealDB response/query) instead of discarding it.

**4b. Grep for all remaining `detail:` → `debug:`**

Search for `detail:` in the file and replace with `debug:`. Only one occurrence expected (the one fixed above in 4a).

### 5. Backend: `admin_handler.mbt` — `detail:` → `debug:` sweep

**File:** `agents/app-agents/admin_handler.mbt`

Grep for all `detail:` occurrences in `AppError` constructions:
```moonbit
// Before:
detail: None
detail: Some(...)

// After:
debug: None
debug: Some(...)
```

Expected occurrences: `validation_error()` calls use `detail:` internally. Since `validation_error` is a helper in `errors.mbt`, update its construction there (done in Section 1). All call sites pass only `msg` — no changes needed at call sites.

Verify no raw `AppError::{ ... detail: ... }` constructions remain in the file.

### 6. Backend: `student_handler.mbt` + `teacher_handler.mbt` — verify clean

**Files:** `agents/app-agents/student_handler.mbt`, `agents/app-agents/teacher_handler.mbt`

Grep for `detail:` and `AppError::`. Expected findings:
- `student_handler.mbt`: One `AppError` construction at line 23 (`NotInitialized`), already uses no `detail` field — safe.
- `teacher_handler.mbt`: Uses `not_found_error()` and `AppError` only through helpers — safe.

If any raw `AppError::{ ... }` with `detail:` found, replace with `debug:`.

### 7. Backend: `auth.mbt` + `validation.mbt` + `config.mbt` — verify

**Files:** `agents/app-agents/auth.mbt`, `agents/app-agents/validation.mbt`, `agents/app-agents/config.mbt`

- `auth.mbt`: `AppError::{ code: ..., message: ..., detail: None }` → `debug: None`
- `validation.mbt`: Uses `AppError::{ code: ..., message: ..., detail: ... }` → `debug:` for all occurrences
- `config.mbt`: `AppError::{ code: ..., message: ..., detail: None }` → `debug: None`

### 8. Frontend: `golem.ts` — `extractErrorFromBody()` + `!res.ok` gate

**File:** `frontend/src/lib/server/golem.ts`

**8a. Remove `parseStructuredError`** — subsumed by `extractErrorFromBody`.

**8b. New function `extractErrorFromBody(raw: string)`:**
```ts
function extractErrorFromBody(raw: string): BackendError | null {
    try {
        const parsed = JSON.parse(raw);

        // Format 1: Golem Err envelope {"Err": "<inner_json>"}
        if (parsed.Err && typeof parsed.Err === 'string') {
            try {
                const inner = JSON.parse(parsed.Err);
                if (inner.code) {
                    return {
                        code: inner.code,
                        message: inner.message || inner.errors?.[0] || 'Unknown error',
                        detail: inner.debug ?? null
                    };
                }
            } catch {}
            return { code: 'AGENT_ERROR', message: parsed.Err };
        }

        // Format 2: Top-level {"code":"...","errors":[...]}
        //           (Golem gateway errors + our new AppError format)
        if (parsed.code) {
            return {
                code: parsed.code,
                message: parsed.message || parsed.errors?.[0] || 'Unknown error',
                detail: parsed.debug ?? null
            };
        }

        // Format 3: Legacy nested {"error":{"code":"...","message":"..."}}
        if (parsed.error?.code) {
            return {
                code: parsed.error.code,
                message: parsed.error.message,
                detail: parsed.error.debug || parsed.error.detail || null
            };
        }
    } catch {}
    return null;
}
```

**8c. Updated `proxyFetch` — add `!res.ok` gate:**
```ts
async function proxyFetch(url: string, method: string = 'GET', body?: Record<string, unknown>): Promise<ProxyResult> {
    try {
        const fetchInit: RequestInit = {
            method,
            headers: { 'X-Golem-Auth-Key': getAuthKey() }
        };
        if (body) {
            fetchInit.headers = { ...fetchInit.headers, 'Content-Type': 'application/json' };
            fetchInit.body = JSON.stringify(body);
        }
        const res = await fetch(url, fetchInit);
        const raw = await res.text();

        // Gate 1: Any non-2xx response is always an error
        if (!res.ok) {
            const extracted = extractErrorFromBody(raw);
            if (extracted) return errorResult(extracted.code, extracted.message);
            return errorResult('GATEWAY_ERROR', raw);
        }

        // Gate 2: 2xx — parse Golem envelope
        try {
            const parsed = JSON.parse(raw);

            if (typeof parsed === 'string') {
                const extracted = extractErrorFromBody(parsed);
                if (extracted) return errorResult(extracted.code, extracted.message);
                return { data: parsed };
            }

            if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
                if ('Ok' in parsed) {
                    const okValue = parsed.Ok;
                    const data = typeof okValue === 'string' ? okValue : JSON.stringify(okValue);
                    return { data };
                }
                if ('Err' in parsed) {
                    const errValue = parsed.Err;
                    const errText = typeof errValue === 'string' ? errValue : JSON.stringify(errValue);
                    const extracted = extractErrorFromBody(errText);
                    if (extracted) return errorResult(extracted.code, extracted.message);
                    return errorResult('AGENT_ERROR', errText);
                }
            }
        } catch {
            // Not valid JSON — check as raw text
        }

        // Gate 3: Defensive — 200 with error body (shouldn't happen but safe)
        const extracted = extractErrorFromBody(raw);
        if (extracted) return errorResult(extracted.code, extracted.message);

        return { data: raw };
    } catch (err) {
        return {
            error: {
                code: 'PROXY_ERROR',
                message: err instanceof Error ? err.message : 'Failed to reach backend service.'
            }
        };
    }
}
```

**8d. Remove unused `parseStructuredError`** — function is superseded by `extractErrorFromBody`. Remove entirely.

**8e. `mapErrorCodeToHttpStatus`** — no changes. Still used by SvelteKit proxy routes to map error codes to browser-facing HTTP statuses.

### 9. Documentation: `errors-research.md`

**File:** `docs/temp/errors-research.md` — full rewrite:

```markdown
# Golem-Idiomatic Error Handling Convention

## Response format

All errors returned by Golem agents use this shape:

```json
{
  "code": "SURREALDB_ERROR",
  "message": "Database query failed",
  "errors": ["Database query failed"],
  "debug": "SQL: SELECT * FROM ... | Response: connection refused"
}
```

Fields:
- `code` — machine-readable, stable, for programmatic switching
- `message` — user-facing, never contains raw SQL or HTTP responses
- `errors` — array of messages (matches Golem's gateway error convention)
- `debug` — developer-facing, contains raw error details. Logged to console, never shown to user.

## Golem's built-in Result mapping

MoonBit agent methods return `Result<T, AppError>`. Golem maps:

| Return | HTTP Status | Body |
|--------|------------|------|
| `Ok(value)` | 200 | JSON-serialized `value` |
| `Err(appError)` | 500 | JSON-serialized `AppError` (the format above) |

**Not configurable.** All `Err` responses are HTTP 500. Use `code` for differentiation.

## Layer responsibilities

```
db_client / authentik_client   →  message=clean, debug=raw details
db_*.mbt / validation.mbt       →  propagate, never discard original debug
*_handler.mbt                   →  sole error translator, constructs user-facing messages
*_agent.mbt                     →  pass-through only, zero error handling
```

### Contract

| Layer | Must do | Must NOT do |
|-------|---------|-------------|
| DB/Auth client | Put raw SQL/HTTP response in `debug`, clean summary in `message` | Put raw data in `message` |
| DB helpers | Propagate `Err(e)` as-is | Construct new `AppError` that discards `e.debug` |
| Handlers | Translate to user-facing `message`, preserve `debug` | Swallow errors silently |
| Agents | Return handler result as-is | Add error handling logic |

## Frontend proxy contract

The `proxyFetch` function:
1. Checks `res.ok` first — any non-2xx is an error regardless of body format
2. On 2xx, parses Golem's `{"Ok": ...}` / `{"Err": ...}` envelope
3. `extractErrorFromBody()` handles three formats:
   - Golem Err envelope: `{"Err": "<inner>"}`
   - Top-level: `{"code":"...","errors":[...]}`
   - Legacy nested: `{"error":{"code":"..."}}`
4. Returns `{ data }` on success, `{ error: { code, message } }` on failure

## Error code catalog

| Code | Meaning | HTTP (proxy) |
|------|---------|-------------|
| `VALIDATION_ERROR` | Invalid input | 400 |
| `AUTH_FAILURE` | Bad auth key | 401 |
| `NOT_FOUND` | Resource not found | 404 |
| `NOT_INITIALIZED` | User not initialized | 403 |
| `AUTHENTIK_ERROR` | Authentik API failure | 502 |
| `SURREALDB_ERROR` | Database failure | 502 |
| `INTERNAL_ERROR` | Unexpected error | 500 |
```

---

## Files Changed (summary)

| File | Section | Change |
|------|---------|--------|
| `errors.mbt` | 1 | `detail` → `debug`, new `to_json_string()` format, updated helpers |
| `db_client.mbt` | 2 | Verify `surreal_error()` usage, no structural changes needed |
| `authentik_client.mbt` | 3 | `detail:` → `debug:` in all `AppError` constructions |
| `db_admin.mbt` | 4 | `db_admin_save_profile` preserves `e.debug`; `detail:` → `debug:` |
| `admin_handler.mbt` | 5 | `detail:` → `debug:` sweep |
| `student_handler.mbt` | 6 | Verify clean (should be zero occurrences) |
| `teacher_handler.mbt` | 6 | Verify clean (should be zero occurrences) |
| `auth.mbt` | 7 | `detail:` → `debug:` |
| `validation.mbt` | 7 | `detail:` → `debug:` in all `AppError` constructions |
| `config.mbt` | 7 | `detail:` → `debug:` in all `AppError` constructions |
| `golem.ts` | 8 | Add `extractErrorFromBody()`, add `!res.ok` gate, remove `parseStructuredError` |
| `docs/temp/errors-research.md` | 9 | Full rewrite for Golem-idiomatic conventions |

---

## Dependencies

None. All changes within existing files. No new packages.

---

## Verification Checklist

### Build
- [ ] `moon check --target wasm` — 0 errors
- [ ] `golem build` — 0 errors
- [ ] `pnpm build` — passes
- [ ] Warnings unchanged or decreased

### Backend — `detail` → `debug`
- [ ] No `detail` field in `AppError` struct definition
- [ ] No `detail:` in any `AppError::{}` construction across all `.mbt` files
- [ ] All `AppError` constructions use `debug:` field
- [ ] `surreal_error()` puts raw info in `debug`, clean message in `message`

### Backend — `to_json_string()` format
- [ ] Produces `{"code":"...","message":"...","errors":["..."],"debug":"..."}` shape
- [ ] `code` is top-level (not nested under `error`)
- [ ] `errors` is an array of strings
- [ ] `debug` is `null` when no debug info available

### Backend — non-lossy propagation
- [ ] `db_admin_save_profile` preserves `e.debug` from original error
- [ ] No `Err(_)` → `Err(AppError::{...})` that discards the original error in handler/DB files

### Frontend
- [ ] `extractErrorFromBody` handles all three formats:
  - [ ] Golem Err envelope: `{"Err": "..."}`
  - [ ] Top-level: `{"code":"...","errors":[...]}`
  - [ ] Legacy nested: `{"error":{"code":"..."}}` (defensive)
- [ ] `proxyFetch` checks `!res.ok` before body format parsing
- [ ] `parseStructuredError` removed (superseded)
- [ ] Non-envelope error responses never fall through to `{ data: raw }`

### Manual smoke
- [ ] Trigger validation error (missing field) → frontend shows error, no toast saying success
- [ ] Trigger DB error (bad query/connection) → frontend shows "Database query failed", console shows `debug` field
- [ ] Send malformed body to Golem (missing `body_json` key) → gateway error caught, frontend shows error
- [ ] Successful request → frontend shows data normally
- [ ] Edit user with `class_level` → profile record created with class_level field populated
- [ ] Golem returns `REQUEST_JSON_BODY_PARSING_FAILED` → no longer silently treated as success
