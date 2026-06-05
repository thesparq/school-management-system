# HF-07 — Backend Audit Fixes

## Goal

Fix 19 categorized issues from the backend audit — error swallowing, SQL safety via `$bindings`, saga crash-recovery atomicity via `@api.with_atomic_operation`, corrupt-cache self-healing, layer boundary violations, dead code, return-type inconsistency across 4 outlier endpoints, missing teacher caching, and cache-key naming standardization — bringing all endpoints into a consistent `endpoint → handler → cache/db helper → db client` flow fully aligned with `docs/temp/cache-system-research.md` and `docs/code-standards.md`.

## Design

### Structural changes

- **`@api.with_atomic_operation`** wraps all 6 multi-step sagas so external calls replay as one unit on Golem crash recovery. Cache-invalidation RPCs remain outside (fire-and-forget, `catch { _ => () }`).
- **New DB helpers in `db_admin.mbt`:** `db_admin_create_teacher_assignments` (absorbs manual SQL building from `admin_set_teacher_subjects`), `db_admin_fetch_class_level_by_name` (absorbs raw `surreal_query` from `validation.mbt`).
- **New typed structs in `types_admin.mbt`:** `SessionTermDetail`, `SessionTermInfo`, `TermSimple` with `derive(ToJson, FromJson, golem_schema)`. Removes all manual JSON string-building.
- **`CACHE_TTL` constant** in `cache_system.mbt` (`pub let CACHE_TTL : UInt64 = 600UL`). Replaces all raw `600UL` occurrences.
- **4 outlier Admin endpoints** converted from `Result[String, String]` (raw JSON) to typed struct returns, matching the rest of the codebase.
- **Corrupt cache → fallthrough** in all 5 cache-hit paths — corrupt entries silently re-fetch from DB instead of returning `InternalError`.
- **Dead code removed:** `db_teacher_update_lesson_active`.
- **Function rename:** `admin_fetch_active_session_term` → `admin_fetch_active_session_term_id`.
- **Teacher caching added:** `teacher_fetch_terms` and `teacher_fetch_lessons` get cache-first reads with invalidation from toggle endpoints.
- **Cache keys standardized** to `entity[:scope[:subscope]]` format. Per-agent scoping comment added to `cache_system.mbt`.

### No new dependencies

All changes in existing MoonBit source files. `@api` already imported in `moon.pkg`.

---

## Implementation

### 1. Saga Crash-Recovery — `@api.with_atomic_operation`

Six functions need wrapping. The pattern is identical in each: wrap the critical external calls, leave compensation logic working, keep cache-invalidation RPCs outside the atomic block.

#### 1a. `admin_create_user` (`admin_handler.mbt:584-630`)

**External calls:** `authentik_create_user` → `authentik_set_password` → `db_admin_save_profile`

**Crash risk:** User created in Authentik but not in SurrealDB → orphaned account, can auth but agent initialization fails.

**Fix:**
```moonbit
let (pk, uuid) = match @api.with_atomic_operation(fn() -> Result[(Int, String), AppError] {
  let (pk, uuid) = match authentik_create_user(config, username, name, email, password, is_active, group_pk) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  match authentik_set_password(config, pk, password) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  match db_admin_save_profile(config, uuid, role, class_level) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  Ok((pk, uuid))
}) {
  Ok(r) => r
  Err(e) => {
    let _ = authentik_delete_user(config, pk) // compensation: clean up partial Authentik state
    return Err(e) // pk may not be bound if create failed — handle with flag or let-binding
  }
}
```

Compensation note: if `authentik_create_user` itself fails inside the block, `pk` is not bound. Use a `mut pk_created : Int = 0` flag or a `match` that tracks whether the create step completed. On Err exit, only compensate if `pk_created != 0`.

#### 1b. `admin_edit_user` (`admin_handler.mbt:633-771`)

**External calls:** `authentik_update_profile` → (optionally `authentik_set_password`) → `authentik_remove_from_group` (loop) → `authentik_add_to_group` → `db_admin_save_profile`

**Crash risk:** Authentik profile/group changes committed but SurrealDB role/class_level stale — user sees wrong data on next login.

**Fix:** Wrap `authentik_update_profile` + (conditional `set_password`) + `authentik_remove_from_group` + `authentik_add_to_group` + `db_admin_save_profile` in one `@api.with_atomic_operation`. The optional password step means the closure must handle the `None` case inline.

#### 1c. `admin_delete_user` (`admin_handler.mbt:774-804`)

**External calls:** `db_admin_soft_delete_user` → `authentik_delete_user` (with `db_admin_undo_soft_delete` compensation)

**Crash risk:** Soft-deleted in SurrealDB but not deleted in Authentik → account still usable but appears deleted in admin UI.

**Fix:** Wrap `db_admin_soft_delete_user` + `authentik_delete_user` in `@api.with_atomic_operation`. If the block fails, run `db_admin_undo_soft_delete` as compensation. Move the existing compensation logic outside the block:

```moonbit
let deleted = @api.with_atomic_operation(fn() -> Result[Unit, AppError] {
  match db_admin_soft_delete_user(config, target_user_id) { Ok(_) => (); Err(e) => return Err(e) }
  match authentik_delete_user(config, authentik_pk) { Ok(_) => (); Err(e) => return Err(e) }
  Ok(())
})
match deleted {
  Ok(_) => ()
  Err(e) => {
    let _ = db_admin_undo_soft_delete(config, target_user_id)
    return Err(e)
  }
}
```

#### 1d. `admin_set_teacher_subjects` (`admin_handler.mbt:430-511`)

**External calls:** `db_admin_soft_delete_teacher_assignments` → multiple `CREATE teacher_assignment` (loop of `surreal_query` calls)

**Crash risk:** Old assignments deleted, new ones never created → teacher loses all subjects.

**Fix:** First refactor the SQL construction out to `db_admin_create_teacher_assignments` (see Section 2). Then wrap the soft_delete + create_assignments in atomic:

```moonbit
@api.with_atomic_operation(fn() -> Result[Unit, AppError] {
  match db_admin_soft_delete_teacher_assignments(config, target_teacher_id) { Ok(_) => (); Err(e) => return Err(e) }
  match db_admin_create_teacher_assignments(config, teacher_id, pairs, active_st) { Ok(_) => (); Err(e) => return Err(e) }
  Ok(())
})
// TeacherAgent cache invalidation stays outside (fire-and-forget)
```

#### 1e. `admin_create_session_term` (`admin_handler.mbt:353-412`, when `active=true`)

**External calls:** `db_admin_deactivate_all_session_terms` → `db_admin_create_session_term`

**Crash risk:** All session terms deactivated, none created → system has zero active terms, all role-scoped queries fail.

**Fix:** Wrap only when `active` is true (the deactivate step only runs when `active=true`):

```moonbit
if active {
  match @api.with_atomic_operation(fn() -> Result[Unit, AppError] {
    match db_admin_deactivate_all_session_terms(config) { Ok(_) => (); Err(e) => return Err(e) }
    match db_admin_create_session_term(config, session, term_id, active) { Ok(_) => (); Err(e) => return Err(e) }
    Ok(())
  }) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  // fetch the created record to return it...
} else {
  // no atomic block needed — single create call
  match db_admin_create_session_term(config, session, term_id, false) { ... }
}
```

#### 1f. `admin_activate_session_term` (`admin_handler.mbt:415-427`)

**External calls:** `db_admin_deactivate_all_session_terms` → `db_admin_activate_session_term`

**Crash risk:** Same as 1e — all deactivated, none activated.

**Fix:**
```moonbit
match @api.with_atomic_operation(fn() -> Result[Unit, AppError] {
  match db_admin_deactivate_all_session_terms(config) { Ok(_) => (); Err(e) => return Err(e) }
  match db_admin_activate_session_term(config, session_term_id) { Ok(_) => (); Err(e) => return Err(e) }
  Ok(())
}) {
  Ok(_) => Ok(())
  Err(e) => Err(e)
}
```

#### Exclusions

These functions are **not** wrapped because they have only one critical external call or handle errors gracefully:

| Function | Reason |
|----------|--------|
| `teacher_toggle_term` | Single critical DB write. Student lookups + fire-and-forget RPCs are best-effort. |
| `teacher_toggle_lesson` | Same as above. |
| `admin_set_user_active` | Single Authentik call. |
| `admin_soft_delete_profile` | Single DB call. Cache invalidation (H3) is best-effort, outside critical path. |

---

### 2. SQL Safety — Remove Manual Escaping

#### 2a. New `db_admin_create_teacher_assignments` helper (`db_admin.mbt`)

Absorbs the inlined SQL construction from `admin_handler.mbt:488-497`. Uses `$bindings` for every value:

```moonbit
pub fn db_admin_create_teacher_assignments(
  config : SharedConfig,
  teacher_id : String,
  pairs : Array[TeacherSubjectPair],
  active_st : String
) -> Result[Unit, AppError] {
  for pair in pairs {
    let sql = if active_st != "" {
      "CREATE teacher_assignment SET teacher_id = $teacher_id, has_subject = $edge_id, session_term = $active_st, assigned_at = time::now()"
    } else {
      "CREATE teacher_assignment SET teacher_id = $teacher_id, has_subject = $edge_id, assigned_at = time::now()"
    }
    let b = if active_st != "" {
      { "teacher_id": teacher_id, "edge_id": pair.edge_id, "active_st": active_st }
    } else {
      { "teacher_id": teacher_id, "edge_id": pair.edge_id }
    }
    match surreal_query(config, sql, bindings=b) {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
  }
  Ok(())
}
```

Remove `use` of `StringBuilder` and `escape_surreal_string` from `admin_handler.mbt` `admin_set_teacher_subjects`. Handler now calls the new helper instead of raw `surreal_query`.

#### 2b. `db_admin_fetch_students_by_class_levels` (`db_admin.mbt:66-69`)

Replace `escape_surreal_string`-based IN clause with SurrealDB array parameterization. If SurrealDB's `$bindings` does not support array parameters for the IN clause, wrap with a `///|` comment explaining the exception:

```moonbit
///|
/// NOTE: SurrealDB $bindings do not support array parameters for IN clauses.
/// class_level_ids are pre-validated slugs from the DB, not user input.
/// escape_surreal_string is retained here as the only exception in the DB layer.
pub fn db_admin_fetch_students_by_class_levels(...)
```

#### 2c. Audit

- Verify no other `escape_surreal_string` usage in handler files — should be zero.
- Verify `admin_set_teacher_subjects` no longer calls `surreal_query` directly.

---

### 3. Error Propagation Fix (C1)

`student_handler.mbt:12-14` — the only place in all handlers that discards the original error:

```moonbit
// Before (discards error detail):
Err(_) => return Err(AppError::{ code: InternalError, message: "Database unavailable", detail: None })

// After (propagates full error):
Err(e) => return Err(e)
```

Full-audit grep for any other `Err(_) => return Err(AppError::` in handler files. Should find zero after fix.

---

### 4. Cache Self-Healing (H1)

Five cache-hit paths return `InternalError` on corrupt JSON instead of falling through to DB re-fetch. The next `cache.set()` call will naturally overwrite the corrupt entry.

Files and lines to change:

| File | Line(s) | Change |
|------|---------|--------|
| `student_handler.mbt` | 30-32 | `catch { _ => return Err(...) }` → `catch { _ => () }` |
| `student_handler.mbt` | 66-68 | Same |
| `student_handler.mbt` | 102-104 | Same |
| `student_handler.mbt` | 143-145 | Same |
| `teacher_handler.mbt` | 4-6 | Same |

Pattern: the `@json.parse(json_str) catch { _ => return Err(...) }` block becomes `@json.parse(json_str) catch { _ => () }` — then the surrounding `match val { ...; _ => () }` naturally falls through to the `None => ()` arm and proceeds to the DB fetch.

---

### 5. Toggle Invocation Reliability (H2)

`teacher_handler.mbt:53-55` and `:58-59` silently swallow prerequisite lookup failures:

```moonbit
// Before:
let active_st = match admin_fetch_active_session_term(...) { Ok(id) => id; Err(_) => return Ok(()) }
let up_arr = match db_admin_fetch_students_by_class_levels(...) { Ok(arr) => arr; Err(_) => return Ok(()) }

// After:
let active_st = match admin_fetch_active_session_term(...) { Ok(id) => id; Err(e) => return Err(e) }
let up_arr = match db_admin_fetch_students_by_class_levels(...) { Ok(arr) => arr; Err(e) => return Err(e) }
```

The fire-and-forget RPC at line 65 and lines 82-83 stays as `catch { _ => () }` — those are intentionally best-effort.

Variable name consistency: `auth_key_val` at `teacher_handler.mbt:60` → `ak` to match the naming in `admin_handler.mbt`.

---

### 6. Missing Cache Invalidation + CACHE_TTL Constant + Map Init (H3, H4, M7)

#### 6a. `admin_soft_delete_profile` (H3)

Add role query + cache invalidation after the soft-delete:

```moonbit
pub fn admin_soft_delete_profile(
  config : SharedConfig,
  target_user_id : String,
) -> Result[Unit, AppError] {
  // Query role before deleting so we know which agent type to invalidate
  let role = match db_admin_fetch_profile(config, target_user_id) {
    Ok(arr) if arr.length() > 0 => match arr[0] {
      Object(obj) => match obj.get("role") { Some(String(r)) => r; _ => "" }
      _ => ""
    }
    _ => ""
  }
  match db_admin_soft_delete_user(config, target_user_id) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let ak = config.auth_key.get() catch { _ => "" }
  if ak != "" && role != "" {
    if role == "student" {
      let _ = StudentAgentClient::scoped(target_user_id, fn(c) raise @common.AgentError {
        c.trigger_invalidate_cache(ak, "profile")
      }) catch { _ => () }
    }
    if role == "teacher" {
      let _ = TeacherAgentClient::scoped(target_user_id, fn(c) raise @common.AgentError {
        c.trigger_invalidate_cache(ak, "class_groups")
      }) catch { _ => () }
    }
  }
  Ok(())
}
```

#### 6b. `admin_delete_user` (H3)

Add same cache invalidation logic after the soft-delete + Authentik delete succeed. The role can be extracted from the body_json (already parsed) or queried before the delete:

```moonbit
// After successful saga completion in admin_delete_user:
let ak = config.auth_key.get() catch { _ => "" }
if ak != "" {
  let role = match obj.get("role") { Some(String(r)) => r; _ => "" }
  if role == "student" {
    let _ = StudentAgentClient::scoped(target_user_id, fn(c) raise @common.AgentError {
      c.trigger_invalidate_cache(ak, "profile")
    }) catch { _ => () }
  }
  if role == "teacher" {
    let _ = TeacherAgentClient::scoped(target_user_id, fn(c) raise @common.AgentError {
      c.trigger_invalidate_cache(ak, "class_groups")
    }) catch { _ => () }
  }
}
```

If role is not in the body, default to querying it from the profile before the delete (similar to 6a). Prefer using the body value to avoid an extra query.

#### 6c. `CACHE_TTL` constant (H4)

Add to `cache_system.mbt`:
```moonbit
///|
pub let CACHE_TTL : UInt64 = 600UL
```

Replace all raw `600UL` occurrences in:
- `cache_system.mbt` (if any use internally — currently none, `set` receives `ttl_seconds` as a param)
- `student_handler.mbt` lines: 19, 57, 94, 135, 163
- `teacher_handler.mbt` line: 35
- `admin_handler.mbt` lines: 197, 346

Each becomes `CACHE_TTL` (qualified as needed, or import with `use`).

#### 6d. Map initialization consistency (M7)

`teacher_handler.mbt:24`:
```moonbit
// Before:
let groups_map : Map[String, TeacherClassGroup] = Map::new()

// After:
let groups_map : Map[String, TeacherClassGroup] = Map([], capacity=0)
```

---

### 7. Layer Boundary Cleanup (M2, M8)

#### 7a. `validate_class_level_exists` (M2)

New helper in `db_admin.mbt`:
```moonbit
pub fn db_admin_fetch_class_level_by_name(
  config : SharedConfig,
  class_level : String
) -> Result[Array[Json], AppError] {
  surreal_query(config, "SELECT id FROM class_levels WHERE name = $name LIMIT 1", bindings={ "name": class_level })
}
```

`validation.mbt:22-27` changes from:
```moonbit
pub fn validate_class_level_exists(config : SharedConfig, class_level : String) -> Result[Unit, AppError] {
  match surreal_query(config, "SELECT id FROM class_levels WHERE name = $name LIMIT 1", bindings={ "name": class_level }) {
```

To:
```moonbit
pub fn validate_class_level_exists(config : SharedConfig, class_level : String) -> Result[Unit, AppError] {
  match db_admin_fetch_class_level_by_name(config, class_level) {
```

#### 7b. `admin_fetch_active_session_term_detail` (M8)

Currently returns `Ok("{}")` on empty (sentinel value). Change to return typed struct with proper error on empty:

```moonbit
pub fn admin_fetch_active_session_term_detail(
  config : SharedConfig
) -> Result[SessionTermDetail, AppError] {
  let arr = match db_admin_fetch_active_session_term_detail(config) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  if arr.length() > 0 {
    match arr[0] {
      Object(obj) => Ok(SessionTermDetail::{
        id: match obj.get("id") { Some(String(s)) => s; _ => "" },
        session: match obj.get("session") { Some(String(s)) => s; _ => "" },
        term_name: match obj.get("term_name") { Some(String(s)) => s; _ => "" },
      })
      _ => Err(not_found_error("Active session term"))
    }
  } else {
    Err(not_found_error("Active session term"))
  }
}
```

Remove all JSON string-building on lines 220-243.

---

### 8. Type Consistency — 4 Outlier Endpoints (M4)

New typed structs in `types_admin.mbt`:

```moonbit
///|
#derive.golem_schema
struct SessionTermDetail {
  id : String
  session : String
  term_name : String
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct SessionTermInfo {
  id : String
  session : String
  term_name : String
  active : Bool
  created_at : String
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct TermSimple {
  id : String
  name : String
} derive(ToJson, FromJson)
```

Endpoint conversions:

| Endpoint | Old handler | Old return | New return |
|----------|------------|------------|------------|
| `GET /admin/{id}/active-session-term` | `admin_fetch_active_session_term_detail` | `Result[String, String]` | `Result[SessionTermDetail, String]` |
| `GET /admin/{id}/terms` | `admin_fetch_terms` | `Result[String, String]` | `Result[Array[TermSimple], String]` |
| `GET /admin/{id}/session-terms` | `admin_fetch_session_terms` | `Result[String, String]` | `Result[Array[SessionTermInfo], String]` |
| `POST /admin/{id}/create-session-term` | `admin_create_session_term` | `Result[String, String]` | `Result[SessionTermInfo, String]` |

For each handler function:
1. Change return type from `Result[String, AppError]` to `Result[<NewType>, AppError]`
2. Replace JSON string-building with typed struct construction + `Ok(struct)`
3. Update agent endpoint signature to match

**Frontend proxy routes updated:**

| Proxy route | File to update |
|-------------|---------------|
| `GET /api/admin/active-session-term` | `frontend/src/routes/api/admin/active-session-term/+server.ts` |
| `GET /api/admin/terms` | `frontend/src/routes/api/admin/terms/+server.ts` |
| `GET /api/admin/session-terms` | `frontend/src/routes/api/admin/session-terms/+server.ts` |
| `POST /api/admin/session-terms/create` | `frontend/src/routes/api/admin/session-terms/create/+server.ts` |

Frontend changes: the proxy routes currently receive raw JSON strings and pass them through. After the change, Golem serializes typed structs to JSON automatically. The response shape is equivalent (same JSON keys). Update TypeScript types to match the new struct fields if needed.

---

### 9. Code Quality — Dead Code, Duplication, Teacher Caching (M5, M6, L1, L2, L3)

#### 9a. Dead code removal (M5)

Remove `db_teacher_update_lesson_active` from `db_teacher.mbt:20-23`. Verify no callers exist:
- `teacher_toggle_lesson` already uses `db_teacher_update_record_active`
- No other caller found

#### 9b. Code deduplication (M6)

`teacher_handler.mbt:73-75` destructures `meta_arr[0]` three times. Change to:

```moonbit
let meta_obj = match meta_arr[0] {
  Object(obj) => obj
  _ => return Err(not_found_error("Lesson"))
}
let class_level_id = match meta_obj.get("class_level_id") { Some(String(s)) => s; _ => return Err(not_found_error("Lesson class level")) }
let subject_id = match meta_obj.get("subject_id") { Some(String(s)) => s; _ => return Err(not_found_error("Lesson subject")) }
let term_id_val = match meta_obj.get("term_id") { Some(String(s)) => s; _ => return Err(not_found_error("Lesson term")) }
```

#### 9c. Teacher terms caching (L1)

`teacher_fetch_terms` and `teacher_fetch_lessons` currently have zero caching. Add cache-first reads:

**`teacher_fetch_terms`:**
```moonbit
pub fn teacher_fetch_terms(cache : CacheSystem, config : SharedConfig, now : UInt64) -> Result[Array[TermInfo], AppError] {
  let cache_key = "terms:all"
  match cache.get(cache_key, now) {
    Some(json_str) => {
      let val = @json.parse(json_str) catch { _ => () }
      match val {
        Array(arr) => {
          let items : Array[TermInfo] = []
          for i in arr { match i { Object(obj) => { items.push(TermInfo::{...}) }; _ => () } }
          if items.length() > 0 { return Ok(items) }
        }
        _ => ()
      }
    }
    None => ()
  }
  let result_arr = match db_teacher_fetch_terms(config) { Ok(arr) => arr; Err(e) => return Err(e) }
  let terms : Array[TermInfo] = []
  for item in result_arr { match item { Object(obj) => { terms.push(...) }; _ => () } }
  if terms.length() == 0 { return Err(not_found_error("Terms")) }
  cache.set(cache_key, terms.to_json().stringify(), CACHE_TTL, [], now)
  Ok(terms)
}
```

Update `teacher_agent.mbt:22-25` signature to pass `cache` and `now`:
```moonbit
pub fn TeacherAgent::get_terms(self : Self, incoming_key : String) -> Result[Array[TermInfo], String] {
  match require_auth(self.config.value, incoming_key) { Err(e) => return Err(e.to_json_string()); Ok(_) => () }
  let now = @wallClock.now().seconds
  match teacher_fetch_terms(self.cache, self.config.value, now) { Ok(arr) => Ok(arr); Err(e) => Err(e.to_json_string()) }
}
```

**`teacher_fetch_lessons`:**
```moonbit
pub fn teacher_fetch_lessons(cache : CacheSystem, config : SharedConfig, class_level_id : String, subject_id : String, term_id : String, now : UInt64) -> Result[Array[LessonInfo], AppError] {
  let cache_key = "lessons:" + class_level_id + "|" + subject_id + "|" + term_id
  // cache-first pattern identical to student_fetch_lessons...
  cache.set(cache_key, lessons.to_json().stringify(), CACHE_TTL, ["terms:all"], now)
}
```

Update `teacher_agent.mbt:28-32` signature to pass `cache` and `now`.

**Teacher cache invalidation:** Add self-invalidation to `teacher_toggle_term` and `teacher_toggle_lesson`:

In `teacher_toggle_term`, after the DB update succeeds:
```moonbit
cache.invalidate("terms:all")  // invalidate teacher's own terms cache
```

In `teacher_toggle_lesson`, after the DB update succeeds:
```moonbit
cache.invalidate("terms:all")  // lessons depend on terms
```

#### 9d. Function rename (L2)

`admin_fetch_active_session_term` → `admin_fetch_active_session_term_id` in `admin_handler.mbt`. The `_detail` variant now returns a typed struct (see Section 8), making the distinction clearer.

Update the 3 call sites:
- `teacher_handler.mbt:22` — `admin_fetch_active_session_term` → `admin_fetch_active_session_term_id`
- `teacher_handler.mbt:54` — same
- `admin_handler.mbt:483` — same (in `admin_set_teacher_subjects`)

#### 9e. Cache key standardization (L3)

All cache keys are per-agent (each agent has its own `CacheSystem`), so agent-scoped keys are sufficient. Add header comment to `cache_system.mbt`:

```
///|
/// Key naming convention: entity[:scope[:subscope]]
/// Keys are scoped per-agent (each agent owns its own CacheSystem).
///
/// Examples:
///   "profile"           — student profile data
///   "subjects"          — student's subjects list
///   "terms:JSS1"        — terms for a specific class level
///   "lessons:subj|term" — lessons for subject+term combination
///   "lesson:{id}"       — individual lesson content
///   "class_groups"      — teacher's class assignments
///   "terms:all"         — global terms list (teacher/admin)
///   "active_session_term_id"  — cached active session term ID
///   "session_terms"     — admin session term list
```

No functional changes needed — keys already follow a consistent pattern within their agent scope.

---

## Files Changed (summary)

| File | Sections |
|------|----------|
| `cache_system.mbt` | 6c (CACHE_TTL), 9e (key comment) |
| `student_handler.mbt` | 3 (C1), 4 (H1), 6c (CACHE_TTL) |
| `teacher_handler.mbt` | 5 (H2), 4 (H1), 6c (CACHE_TTL), 6d (M7), 9b (M6), 9c (L1), 9d (L2 rename) |
| `admin_handler.mbt` | 1a-1f (6 sagas), 2a (SQL extraction), 6a-6b (H3), 6c (CACHE_TTL), 8 (M4 types), 9d (L2 rename) |
| `admin_agent.mbt` | 8 (M4 return types), 9d (L2 rename) |
| `teacher_agent.mbt` | 9c (L1 cache passthrough) |
| `db_admin.mbt` | 2a (new helper), 2b (IN clause fix), 7a (new helper) |
| `db_teacher.mbt` | 9a (M5 dead code) |
| `validation.mbt` | 7a (M2 delegate) |
| `types_admin.mbt` | 8 (3 new structs) |
| `frontend/src/routes/api/admin/active-session-term/+server.ts` | 8 (response shape) |
| `frontend/src/routes/api/admin/terms/+server.ts` | 8 (response shape) |
| `frontend/src/routes/api/admin/session-terms/+server.ts` | 8 (response shape) |
| `frontend/src/routes/api/admin/session-terms/create/+server.ts` | 8 (response shape) |

---

## Dependencies

None. All changes within existing MoonBit source files. `@api` already imported in `moon.pkg`:
```
"golemcloud/golem_sdk/api" @api,
```

---

## Verification Checklist

### Build
- [ ] `moon check --target wasm` — 0 errors
- [ ] `golem build` — 0 errors
- [ ] `pnpm build` — passes
- [ ] Warnings unchanged or decreased (baseline: 25, all generated code)

### SQL safety
- [ ] No `escape_surreal_string` usage in handler files (zero occurrences)
- [ ] No `escape_surreal_string` in `db_admin.mbt` except `fetch_students_by_class_levels` (documented exception)
- [ ] No `surreal_query` calls in handler files — all go through `db_*.mbt` helpers
- [ ] No `surreal_query` calls in `validation.mbt`

### Cache correctness
- [ ] No remaining raw `600UL` — all replaced with `CACHE_TTL`
- [ ] All 5 corrupt-cache paths use fallthrough (`catch { _ => () }`)
- [ ] No `Map::new()` in hand-written code
- [ ] `teacher_fetch_terms` and `teacher_fetch_lessons` use cache-first reads
- [ ] `teacher_toggle_term` and `teacher_toggle_lesson` invalidate teacher's own caches

### Error handling
- [ ] No `Err(_) => return Err(AppError::` that discards the original error in handler files
- [ ] `student_get_class_level` propagates original DB error
- [ ] `teacher_toggle_term` propagates prerequisite lookup errors (no silent `return Ok(())`)

### Saga atomicity
- [ ] All 6 multi-step sagas wrapped in `@api.with_atomic_operation`
- [ ] Cache invalidation RPCs remain outside atomic blocks (fire-and-forget)
- [ ] Compensation logic preserved in `admin_create_user` (Authentik delete on failure)
- [ ] Compensation logic preserved in `admin_delete_user` (SurrealDB undo on failure)

### Type consistency
- [ ] `SessionTermDetail`, `SessionTermInfo`, `TermSimple` defined in `types_admin.mbt`
- [ ] All 4 outlier endpoints return typed structs
- [ ] No manual JSON string-building in admin_handler.mbt (lines 220-243, 258-283, 300-345, 394-405 removed)
- [ ] Frontend proxy routes match new response shapes

### Dead code + naming
- [ ] `db_teacher_update_lesson_active` removed
- [ ] `admin_fetch_active_session_term` renamed to `admin_fetch_active_session_term_id`
- [ ] All 3 call sites updated to new name
- [ ] `meta_arr[0]` destructured once in `teacher_toggle_lesson`

### Cache invalidation coverage
- [ ] `admin_soft_delete_profile` fires targeted agent cache invalidation
- [ ] `admin_delete_user` fires targeted agent cache invalidation

### Manual smoke tests
- [ ] Create user → verify no duplicate Authentik accounts on replay
- [ ] Edit user → change role and class_level, verify SurrealDB and Authentik are consistent
- [ ] Delete user → verify both SurrealDB (soft-deleted) and Authentik (deleted) are consistent
- [ ] Corrupt a cache entry by injecting bad JSON → next request self-heals (returns fresh data, no error)
- [ ] Toggle term active → student fetches terms, sees updated active flag
- [ ] Toggle lesson active → student fetches lessons, sees updated active flag
- [ ] Create session term with active=true → verify previous active is deactivated, only one active
- [ ] Soft-delete profile for a student → verify their student agent caches are cleared on next access
