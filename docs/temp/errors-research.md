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
- `errors` — array of messages (mirrors Golem's gateway error convention)
- `debug` — developer-facing, contains raw error details. Logged to console, never shown to user.

## Golem's built-in Result mapping

MoonBit agent methods return `Result<T, AppError>`. Golem maps:

| Return | HTTP Status | Body |
|--------|------------|------|
| `Ok(value)` | 200 OK | JSON-serialized `value` |
| `Err(appError)` | 500 Internal Server Error | JSON-serialized `AppError` (the format above) |

**Not configurable.** All `Err` responses are HTTP 500. Use the `code` field for programmatic differentiation, not the HTTP status.

## Layer responsibilities

```
db_client / authentik_client   →  message = clean summary, debug = raw details
db_*.mbt / validation.mbt       →  propagate, never discard original debug
*_handler.mbt                   →  sole error translator, constructs user-facing messages
*_agent.mbt                     →  pass-through only, zero error handling
```

### Contract

| Layer | Must do | Must NOT do |
|-------|---------|-------------|
| DB/Auth client | Put raw SQL/HTTP response in `debug`, clean summary in `message` | Put raw SQL/HTTP responses or stack traces in `message` |
| DB helpers | Propagate `Err(e)` as-is | Construct new `AppError` that discards `e.debug` |
| Handlers | Translate lower-layer errors to user-facing `message`, preserve `debug` | Swallow errors silently |
| Agents | Return handler result as-is | Add error handling logic |

### Example: DB client

```moonbit
// db_client.mbt — lowest layer
pub fn surreal_error(body : String, sql : String?) -> AppError {
  AppError::{
    code: SurrealDBError,
    message: "Database query failed",                                   // user-facing
    debug: Some("SQL: " + sql + " | Response: " + body)                 // developer-facing
  }
}
```

### Example: Handler (sole error translator)

```moonbit
// student_handler.mbt
pub fn student_fetch_subjects(...) -> Result[Array[SubjectInfo], AppError] {
  let result_arr = match db_student_fetch_subjects(config, cl) {
    Ok(arr) => arr
    Err(e) => Err(e)   // propagate as-is — debug is already populated
  }
  // ...
}

pub fn student_get_class_level(...) -> Result[String, AppError] {
  let arr = match db_student_fetch_profile(config, student_id) {
    Ok(a) => a
    Err(e) => Err(e)   // propagate — do not discard e.debug
  }
  if arr.length() == 0 {
    return Err(AppError::{
      code: NotInitialized,
      message: "Account not initialized. Please contact your school administrator.",
      debug: None     // business error, no raw detail needed
    })
  }
}
```

### Example: Agent (pass-through)

```moonbit
// student_agent.mbt
pub fn StudentAgent::get_subjects(self : Self, incoming_key : String) -> Result[Array[SubjectInfo], String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  let now = @wallClock.now().seconds
  match student_fetch_subjects(self.cache, self.config.value, self.student_id, now) {
    Ok(arr) => Ok(arr)
    Err(e) => Err(e.to_json_string())
  }
}
```

## Frontend proxy contract

The `proxyFetch` function in `golem.ts`:

1. **Checks `!res.ok` first** — any non-2xx response is always an error, regardless of body format
2. **On 2xx** — parses Golem's `{"Ok": ...}` / `{"Err": ...}` envelope
3. **`extractErrorFromBody(raw)`** — single function handles three formats:
   - Golem Err envelope: `{"Err": "<inner_json>"}`
   - Top-level: `{"code":"...","errors":[...]}` (Golem gateway + our AppError)
   - Legacy nested: `{"error":{"code":"..."}}` (defensive, backward-compatible)
4. Returns `{ data }` on success, `{ error: { code, message } }` on failure

```ts
function extractErrorFromBody(raw: string): BackendError | null {
    const parsed = JSON.parse(raw);
    
    // Format 1: Golem Err envelope
    if (parsed.Err && typeof parsed.Err === 'string') {
        const inner = JSON.parse(parsed.Err);
        if (inner.code) return { code: inner.code, message: inner.message || inner.errors?.[0] };
    }
    
    // Format 2: Top-level (Golem gateway + our AppError)
    if (parsed.code) return { code: parsed.code, message: parsed.message || parsed.errors?.[0] };
    
    // Format 3: Legacy nested
    if (parsed.error?.code) return { code: parsed.error.code, message: parsed.error.message };
    
    return null;
}
```

## Error code catalog

| Code | Meaning | Usage |
|------|---------|-------|
| `VALIDATION_ERROR` | Invalid input | DB helpers, auth, validation |
| `AUTH_FAILURE` | Bad auth key | Auth check |
| `NOT_FOUND` | Resource not found | DB helpers, handlers |
| `NOT_INITIALIZED` | User not initialized | Handlers |
| `AUTHENTIK_ERROR` | Authentik API failure | Authentik client |
| `SURREALDB_ERROR` | Database failure | DB client, DB helpers |
| `INTERNAL_ERROR` | Unexpected error | Config resolution, auth |

## Rules that prevent silent error swallowing

1. **No layer returns success without valid data.** An empty DB result is `NotFound`, not `Ok([])`.
2. **`Err(e)` is always propagated as-is from DB helpers.** Never construct a new `AppError` that discards `e.debug`.
3. **The handler is the only layer that constructs user-facing messages.** Lower layers return technical summaries; the handler translates.
4. **The frontend never trusts HTTP status alone.** `!res.ok` is a gate, but `extractErrorFromBody` also runs on 2xx responses as defense-in-depth.
5. **`debug` is never shown to the user.** It's logged to console only. The `message` field is what's displayed in the UI.
