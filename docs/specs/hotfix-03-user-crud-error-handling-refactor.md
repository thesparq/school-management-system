# HF-03 — User CRUD: Error Handling, Saga Pattern & Config Refactor

## Goal

Rewrite the entire user CRUD layer (create, edit, delete, activate/deactivate) with structured error types, saga-pattern compensation for multi-step operations, split config structs, a shared HTTP client, and proper JSON handling using MoonBit's built-in `Json` type. Eliminate vague `"{}"` fallbacks, silently-swallowed errors, and inconsistent state across Authentik + SurrealDB.

## Motivation

### Problem 1: All errors become `"{}"` or `"ERROR: ..."` strings

The admin agent's `get_profile` returns `"{}"` on auth failure, DB error, parse failure, and empty result — the frontend can never distinguish them. `get_class_levels` returns `"ERROR: parse class_levels response failed"` as a plain string success. Other methods return `Result[String, String]` with vague prefixes like `"Authentik create: HTTP 400 ..."` leaked to the UI.

### Problem 2: No atomicity — inconsistent state across Authentik + SurrealDB

- **Create user**: If `authentik_set_password` fails after `authentik_create_user` succeeds, the Authentik user exists with no password. Ghost user.
- **Delete user**: If `surreal_soft_delete` fails after `authentik_delete_user` succeeds, the Authentik user is gone but the profile is still in SurrealDB.
- **Edit user**: Errors from `authentik_remove_from_group` are silently swallowed — a user can end up in two groups simultaneously.

### Problem 3: Monolithic config + duplicated HTTP code

`SharedConfig` bundles SurrealDB creds (5 fields), Authentik creds (2 fields), and an auth key into one struct. Both `surreal_client.mbt` and `authentik_client.mbt` contain near-identical HTTP request/response logic (~150 lines each, ~60% duplication). Manual JSON string building with concatenation everywhere.

### Problem 4: Golem anti-patterns

`surreal_query_retry` has a manual one-retry workaround for a WASM parse bug — Golem's platform provides 3-retry exponential backoff automatically. Auth key check boilerplate appears in every endpoint verbatim.

## Design

### Structured Error Type

```moonbit
enum ErrorCode {
  ValidationError   // 400 — bad input
  AuthFailure       // 401 — auth key mismatch
  NotFound          // 404 — resource missing
  AlreadyExists     // 409 — username/email taken
  AuthentikError    // 502 — upstream Authentik failure
  SurrealDBError    // 502 — upstream SurrealDB failure
  InternalError     // 500 — unexpected
}

struct AppError {
  code : ErrorCode
  message : String
  detail : String?
}
```

All functions return `Result[T, AppError]`. Endpoints serialize errors to JSON:

```json
{"error":{"code":"VALIDATION_ERROR","message":"Email is invalid","detail":null}}
```

The frontend maps `code` → HTTP status and `message` → user-facing text. No more string matching.

### Config Split

Three `#derive.config` structs, nested:

```moonbit
// config.mbt
#derive.config
pub(all) struct SurrealConfig {
  host : @config.Secret[String]
  ns : @config.Secret[String]
  database : @config.Secret[String]
  username : @config.Secret[String]
  password : @config.Secret[String]
}

#derive.config
pub(all) struct AuthentikConfig {
  host : @config.Secret[String]
  api_token : @config.Secret[String]
}

#derive.config
pub(all) struct SharedConfig {
  surreal : SurrealConfig
  authentik : AuthentikConfig
  auth_key : @config.Secret[String]
}
```

The agent holds one `@config.Config[SharedConfig]`. Client functions receive the sub-config they need: `surreal_query(surreal_config, sql)` and `authentik_create_user(authentik_config, ...)`. This follows the Golem SDK's documented nested config pattern (see `golem-add-config-moonbit` skill — nesting of `#derive.config` structs is explicitly supported).

**Implementation note:** golem-sdk-tools 0.5.2 does not generate `ConfigField::Override` implementations for nested `#derive.config` structs, causing build errors with nested types. The actual implementation uses a flat `SharedConfig` with prefixed fields (`surreal_host`, `surreal_ns`, `authentik_host`, etc.) and resolved-value helper structs (`SurrealCfg`, `AuthentikCfg`) passed to client modules. 

### File Restructuring

MoonBit allows multiple `.mbt` files in the same package directory with a shared namespace — splitting is purely organizational, no import changes:

```
agents/app-agents/
├── errors.mbt              # NEW — AppError, ErrorCode, Result alias
├── config.mbt              # NEW — SurrealConfig, AuthentikConfig, SharedConfig
├── http_client.mbt         # NEW — Shared WASI HTTP request/response
├── surreal_client.mbt      # REFACTORED — takes SurrealConfig, uses http_client
├── authentik_client.mbt    # REFACTORED — takes AuthentikConfig, uses http_client
├── auth.mbt                # NEW — require_auth() helper
├── validation.mbt          # NEW — input validation functions
├── admin_agent.mbt         # REFACTORED — saga-based user CRUD
├── student_agent.mbt       # MINIMAL — update config refs + auth helper
├── teacher_agent.mbt       # MINIMAL — update config refs + auth helper
├── cache_types.mbt         # KEPT (simplified later)
├── main.mbt                # Entry point (unchanged)
└── golem_*.mbt             # Generated (untouched)
```

### Shared HTTP Client

Extract the ~150 lines duplicated in `surreal_client.mbt` and `authentik_client.mbt`:

```moonbit
fn http_request(
  host : String,
  method : @http_types.Method,
  scheme : @http_types.Scheme,
  path : String,
  headers : @http_types.Fields,
  body : Bytes?,
  timeout_ns : UInt64,
) -> Result[(UInt, String)]
```

Handles: header building fallback, body writing, 15s timeout via `@poll.poll`, response stream chunking → byte assembly, status code check. Returns `(status, body_string)` or `AppError`.

Both clients become thin wrappers (~40 lines each) around `http_request`.

### Saga Pattern for Multi-Step Writes

**Create user**: 3 steps with compensation

| Step | Action | On Failure |
|------|--------|-----------|
| 1 | Authentik: Create user | Stop. Nothing to clean up. |
| 2 | Authentik: Set password | **Compensate**: DELETE the user created in step 1. Stop. |
| 3 | SurrealDB: Save profile | **Compensate**: DELETE the user created in step 1. Stop. |

**Delete user**: 2 steps, reverse order

| Step | Action | On Failure |
|------|--------|-----------|
| 1 | SurrealDB: Soft-delete profile | Stop. Nothing was deleted yet. |
| 2 | Authentik: Delete user | **Compensate**: Undo soft-delete (`UPDATE SET deleted_at = NONE`). Stop. |

During the narrow window between steps 1 and 2 (milliseconds in the same agent invocation), the profile appears soft-deleted but the user still exists in Authentik. This is safe — the agent's auth check on every request prevents the deleted user from taking any action, and the compensation path on Authentik failure restores the profile.

**Edit user**: Ordered, critical vs non-critical

| Step | Action | On Failure |
|------|--------|-----------|
| 1 | Validate all inputs | Stop. |
| 2 | Resolve group PK from name (backend, not frontend) | Stop. |
| 3 | Authentik: Update profile (name, email) | Stop (partial state acceptable). |
| 4 | Authentik: Set password (optional) | Stop (ancillary operation). |
| 5 | Authentik: Remove from old groups | Log but continue (non-critical). |
| 6 | Authentik: Add to target group | Stop (critical — user would be group-less). |
| 7 | SurrealDB: Save profile | Stop. |
| 8 | Invalidate caches | Best-effort. |

### Group PK Resolution Moves to Backend

Previously: `edit-profile/+server.ts` calls `getGroupPkByName()` from the TypeScript Authentik client, resolves group names → PKs, passes PKs to the agent.

After: SvelteKit sends the role name. The backend resolves the group PK via `authentik_get_group_pk_by_name()` at write time. This keeps every Authentik write operation in one place (the Golem agent) and eliminates stale-PK bugs.

```moonbit
pub fn authentik_get_group_pk_by_name(
  config : AuthentikConfig,
  name : String,
) -> Result[String]
```

Paginates through `/api/v3/core/groups/?page_size=100&search=<name>`, matches by case-insensitive name, returns the PK.

### User Listing Stays on SvelteKit (Read-Only)

The TypeScript `fetchAllUsers()` + `fetchAllGroups()` in `frontend/src/lib/server/authentik.ts` remain. They handle paginated read-only listing efficiently without a Golem hop. The separation: **reads on SvelteKit, writes through Golem agents**.

### schema-v2.surql Fix: `class_level` → `record<class_levels>`

The `user_profile.class_level` field is currently `TYPE option<string>` but should be a proper record link:

```diff
- DEFINE FIELD IF NOT EXISTS class_level ON user_profile TYPE option<string>;
+ DEFINE FIELD IF NOT EXISTS class_level ON user_profile TYPE option<record<class_levels>>;
```

The `surreal_save_profile` function resolves the class level name to its record ID before inserting (via a SurrealDB subquery). The frontend continues to send names. Also remove the `ASSERT $value IN [...]` on the `role` field — validation moves to the code layer for better error messages.

### MoonBit Json Type

All JSON construction uses MoonBit's built-in `Json` enum + `@json.to_string()`. No more manual string concatenation for JSON. Example:

```moonbit
let response_body = @json.to_string(Json::Object(Map::from_array([
  ("ok", Json::Object(Map::from_array([
    ("pk", Json::Number(Number::from_int(pk))),
    ("uuid", Json::String(uuid)),
  ]))),
])))
```

This eliminates the `escape_json_string` workaround and guarantees valid JSON.

## Implementation

### Phase 1: Structured Errors (`errors.mbt`)

New file. Define `ErrorCode`, `AppError`, `type Result[T] = Result[T, AppError]`, and serialization helpers (`to_json_string`, `to_http_status`).

No existing code changes — only additions.

### Phase 2: Config Split (`config.mbt`)

New file. Move `SharedConfig` and define `SurrealConfig` + `AuthentikConfig`. The `SharedConfig` struct in `surreal_client.mbt` (line 46-56) is removed and replaced with the new nested version.

Update `surreal_client.mbt`:
- Remove `SharedConfig` struct definition
- Remove `check_auth_key` — moved to `auth.mbt`
- Remove `authentik_host` and `authentik_api_token` fields
- All functions that took `@config.Config[SharedConfig]` now take the appropriate sub-config value directly

### Phase 3: Shared HTTP Client (`http_client.mbt`)

New file. Extract the common HTTP logic from both clients. The body-writing, timeout, polling, chunked reading, and byte assembly code is unified.

### Phase 4: SurrealDB Client Refactor (`surreal_client.mbt`)

- Takes `SurrealConfig` directly (resolved values, secrets resolved with `.get()`)
- `surreal_query` now returns `Result[Array[Json]]` — parses and status-checks in one call
- Remove `surreal_query_retry` — Golem's 3-retry default handles failures
- Remove `surreal_query_checked` and `parse_result_array` — merged into `surreal_query`
- `surreal_save_profile`: resolves class_level name → record ID before insert, validates role
- Add `surreal_undo_soft_delete` for delete compensation
- Use `$param` bindings via URL query params for user-provided values (SurrealDB's `/sql` endpoint supports `?key=value` as `$key` bindings)

### Phase 5: Authentik Client Refactor (`authentik_client.mbt`)

- Takes `AuthentikConfig` directly
- All functions return `Result[T]` with `AppError`
- Uses `http_client` internally (drops ~150 lines)
- Add `authentik_get_group_pk_by_name`
- All JSON bodies built with MoonBit `Json` type + `@json.to_string()`

### Phase 6: Auth Helper (`auth.mbt`)

```moonbit
pub fn require_auth(config : SharedConfig, incoming_key : String) -> Result[Unit]
```

Replaces the 4-line boilerplate in every endpoint. Returns `AppError::AuthFailure` or `Ok(())`.

### Phase 7: Validation (`validation.mbt`)

```moonbit
pub fn validate_email(email : String) -> Result[Unit]
pub fn validate_password(password : String) -> Result[Unit]
pub fn validate_username(username : String) -> Result[Unit]
pub fn validate_role(role : String) -> Result[Unit]
pub fn validate_class_level_exists(config : SurrealConfig, class_level : String) -> Result[Unit]
```

Simple regex for email. Password ≥ 8 chars. Username alphanumeric ≥ 3 chars. Role ∈ `["admin", "teacher", "student"]`. Class level queries SurrealDB to confirm existence.

### Phase 8: Admin Agent User CRUD Refactor (`admin_agent.mbt`)

Replace the body of `create_user_in_authentik`, `edit_user_in_authentik`, `delete_user_in_authentik`, `set_user_active_status`, and `get_profile` with the saga-based implementations described above. All endpoints now return consistent JSON error envelopes.

Non-CRUD endpoints (`get_class_levels`, `get_available_class_subjects`, `get_teacher_subjects`, `set_teacher_subjects`, `invalidate_cache`, `ping`) are updated to:
- Use `require_auth()` helper
- Access config via `self.config.value.surreal` / `self.config.value.authentik`
- Return structured errors on failure
- Build response JSON with the `Json` type (not string concatenation)

### Phase 9: Student & Teacher Agent Config Updates

Minimal changes — only update `SharedConfig` → new nested access pattern and use `require_auth()`. No CRUD logic changes.

### Phase 10: golem.yaml

```yaml
secretDefaults:
  local:
    surreal:
      host: "{{ SURREAL_DB_HOST }}"
      ns: "{{ SURREAL_DB_NS }}"
      database: "{{ SURREAL_DB }}"
      username: "{{ SURREAL_DB_USERNAME }}"
      password: "{{ SURREAL_DB_PASSWORD }}"
    authentik:
      host: "{{ AUTHENTIK_HOST }}"
      apiToken: "{{ AUTHENTIK_SERVICE_ACCOUNT_TOKEN }}"
    authKey: "dev-auth-key-change-in-production"
```

### Phase 11: db/schema-v2.surql

```diff
- DEFINE FIELD IF NOT EXISTS class_level ON user_profile TYPE option<string>;
+ DEFINE FIELD IF NOT EXISTS class_level ON user_profile TYPE option<record<class_levels>>;
```

Remove the `ASSERT` clause from the `role` field definition.

### Phase 12: Frontend Changes

**`frontend/src/lib/server/golem.ts`:**
- Remove `isErrMsg()` string matching (`"unauthorized"`, `"auth error"`)
- Parse `{ error: { code, message, detail } }` JSON from agents
- Return `error: { code, message }` from the parsed structure — no re-wrapping
- Map `code` → HTTP status codes in the proxy routes (not in golem.ts)

**`frontend/src/routes/api/admin/users/[pk]/edit-profile/+server.ts`:**
- Remove `getGroupPkByName()` calls
- Send role name + class level name to the agent
- Map error codes to proper HTTP status codes (400 for validation, 502 for upstream)

**`frontend/src/routes/api/admin/users/+server.ts`** (create):
- Map error codes to proper HTTP status codes

**`frontend/src/routes/api/admin/users/[pk]/+server.ts`** (delete):
- Map error codes to proper HTTP status codes

**`frontend/src/routes/api/admin/users/[pk]/activate-authentik/+server.ts`**:
- Map error codes to proper HTTP status codes

**`frontend/src/routes/api/admin/users/[pk]/deactivate-authentik/+server.ts`**:
- Map error codes to proper HTTP status codes

**`frontend/src/routes/api/admin/users/[pk]/profile/+server.ts`**:
- Map error codes to proper HTTP status codes

**`frontend/src/routes/admin/users/UserTable.svelte`:**
- No functional changes needed — already handles `{ error: { code, message } }` responses

## Dependencies

- Golem 1.5.3+ with nested config support (verified in `golem-add-config-moonbit` skill)
- No new packages to install
- Build tools: `moon info`, `moon fmt`, `golem app build`
- SurrealDB schema update (user applies manually)

## Verification Checklist

1. **Build**: `moon build --target wasm` — 0 errors
2. **Build**: `pnpm build` — 0 errors
3. **Type check**: `pnpm check` — 0 errors
4. **Config loads**: `golem build` succeeds — nested secrets resolve correctly
5. **Create user — success**: POST `/api/admin/users` → user in Authentik + profile in SurrealDB
6. **Create user — password fails**: Authentik user is cleaned up (compensation triggered)
7. **Create user — profile save fails**: Authentik user is cleaned up (compensation triggered)
8. **Create user — validation**: Invalid email returns `{ error: { code: "VALIDATION_ERROR", message: "Email is invalid" } }` with HTTP 400
9. **Edit user — success**: All fields update in Authentik + SurrealDB
10. **Edit user — group removal fails**: User still added to target group, error logged but not propagated
11. **Edit user — group add fails**: Structured error returned with HTTP 502
12. **Delete user — success**: Soft-deleted in SurrealDB, deleted in Authentik
13. **Delete user — Authentik fails**: Soft-delete is undone (compensation triggered)
14. **Delete user — SurrealDB fails first**: Stop before Authentik delete, nothing damaged
15. **Activate/deactivate**: Authentik `is_active` toggles correctly
16. **Get profile — not found**: Structured `NotFound` error, not `"{}"`
17. **Get profile — DB error**: Structured `SurrealDBError` with detail, not `"{}"`
18. **Auth key mismatch**: Structured `AuthFailure` error from `require_auth()`, not raw `"unauthorized"`
19. **Group PK resolution**: Edit user works without frontend passing PKs
20. **Class level stored as record link**: User profile shows `class_levels:jss_1` format
21. **No manual retries**: `surreal_query_retry` removed, Golem handles retries
22. **No string-matched errors**: `golem.ts` no longer checks for `"unauthorized"` / `"auth error"`
23. **Proper HTTP statuses**: 400 for validation, 401 for auth, 404 for not found, 409 for already exists, 502 for upstream
