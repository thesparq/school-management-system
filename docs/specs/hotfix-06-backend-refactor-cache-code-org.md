# HF-06: Backend Refactor — Code Organization, Cache System & Handlers

## Goal

Reorganize the flat `app-agents/` package into layered files with strict separation of concerns (agents → handlers → db → cache). Build a deterministic, dependency-tracked `CacheSystem`. Enhance error construction. Adopt `derive(ToJson, FromJson)` on all types. Extract all business logic into handler files so agents become thin endpoints (~3-5 lines per method).

## Delivered (All Phases)

### Types Extracted
- `types_admin.mbt` — `ClassLevelInfo`, `UserProfileInfo`, `CreateUserResponse` — with `derive(ToJson, FromJson)`
- `types_student.mbt` — `SubjectInfo`, `StudentProfile`, `TermInfo`, `LessonInfo`, `LessonContent` — with `derive(ToJson, FromJson)`
- `types_teacher.mbt` — `TeacherSubjectPair`, `TeacherClassGroup` — with `derive(ToJson, FromJson)`
- `types_common.mbt` — placeholder for future cross-cutting types
- All struct definitions removed from agent files. `#derive.golem_schema` annotations preserved. `derive(ToJson, FromJson)` placed on closing `}` of each struct — correct MoonBit syntax.

### Cache System Built & Adopted
- `cache_system.mbt` — `CacheSystem` struct with `store` (Map) + `dep_graph` (Map), methods: `new()`, `get()`, `set()`, `invalidate()`, `invalidate_all()`. Deterministic, dependency-tracked, TTL-based. Values are JSON strings — handlers own serialize/deserialize.
- `cache_instance.mbt` — factory `pub fn new_cache() -> CacheSystem`.
- `cache_types.mbt` deleted — `CacheData` enum, `CacheItem` struct, and `CACHE_TTL` constant fully replaced.
- All three agent structs use `cache : CacheSystem`. Constructors call `new_cache()`.
- Cache invalidation via `self.cache.invalidate(key)` or `self.cache.invalidate_all()`.

### DB Layer Separated
- `db_client.mbt` — raw SurrealDB HTTP transport (replaces `surreal_client.mbt`). Contains: `escape_surreal_string`, `url_encode`, `parse_result_array`, `surreal_query`, `surreal_query_internal`.
- `db_admin.mbt` — 17 admin query functions: `fetch_profile`, `save_profile`, `soft_delete_user`, `undo_soft_delete`, `fetch_class_levels`, `fetch_class_subjects`, `fetch_has_subject_for_class`, `fetch_teacher_subjects`, `soft_delete_teacher_assignments`, `fetch_active_session_term`, `fetch_active_session_term_detail`, `fetch_terms`, `fetch_session_terms`, `deactivate_all_session_terms`, `create_session_term`, `activate_session_term`, `fetch_students_by_class_levels`.
- `db_teacher.mbt` — 7 teacher query functions: `fetch_class_groups`, `fetch_terms`, `fetch_lessons`, `update_term_active`, `fetch_class_levels_for_teacher`, `fetch_lesson_meta`, `update_lesson_active`.
- `db_student.mbt` — 5 student query functions: `fetch_profile`, `fetch_subjects`, `fetch_terms`, `fetch_lessons`, `fetch_lesson_content`.
- `surreal_client.mbt` deleted. Admin agent's domain functions migrated to `db_admin_*` equivalents.

### Handlers (Phase 4)
- `admin_handler.mbt` — 16 handler functions (all match spec table below).
- `teacher_handler.mbt` — 5 public + 1 internal handler functions (all match spec table).
- `student_handler.mbt` — 5 handler functions (all match spec table).
- Handlers receive `cache : CacheSystem`, `config : SharedConfig`, `now : UInt64`, and domain params.
- Handlers use `to_json().stringify()` for cache writes, `@json.parse()` + manual `Json` pattern matching for cache reads.
- Handlers never call `require_auth()` — auth stays in agents.

**`admin_handler.mbt` functions:**

| Function | Cache | Cache Key | TTL | Deps | Notes |
|---|---|---|---|---|---|
| `admin_fetch_class_levels` | No | — | — | — | Calls `db_admin_fetch_class_levels` |
| `admin_fetch_class_subjects` | No | — | — | — | Two-phase query via `db_admin_fetch_class_subjects` + `db_admin_fetch_has_subject_for_class` |
| `admin_fetch_teacher_subjects` | No | — | — | — | Calls `db_admin_fetch_teacher_subjects` |
| `admin_set_teacher_subjects` | No | — | — | — | DB writes + RPC invalidation to teacher |
| `admin_fetch_active_session_term` | Yes | `"active_session_term"` | 600s | none | Cached as string. Stale-fallback on DB error |
| `admin_fetch_session_terms` | Yes | `"session_terms"` | 600s | none | Cached as JSON string. Stale-fallback on DB error |
| `admin_fetch_terms` | No | — | — | — | Manual JSON build from DB rows |
| `admin_create_session_term` | No | — | — | — | Invalidates both session-term cache keys |
| `admin_activate_session_term` | No | — | — | — | Invalidates both session-term cache keys |
| `admin_fetch_profile` | No | — | — | — | Calls `db_admin_fetch_profile` |
| `admin_soft_delete_profile` | No | — | — | — | Calls `db_admin_soft_delete_user` |
| `admin_create_user` | No | — | — | — | Saga pattern: validate → Authentik → profile → RPC invalidation |
| `admin_edit_user` | No | — | — | — | Saga pattern: validate → update → group management → profile → RPC invalidation |
| `admin_delete_user` | No | — | — | — | Saga: soft-delete → delete Authentik → undo on failure |
| `admin_set_user_active` | No | — | — | — | Calls `authentik_set_active` |

**`teacher_handler.mbt` functions:**

| Function | Cache | Cache Key | TTL | Deps | Notes |
|---|---|---|---|---|---|
| `teacher_fetch_classes` | Yes | `"class_groups"` | 600s | none | Backbone key. Manual JSON parse from cache |
| `teacher_fetch_terms` | No | — | — | — | Calls `db_teacher_fetch_terms` |
| `teacher_fetch_lessons` | No | — | — | — | Calls `db_teacher_fetch_lessons` |
| `teacher_toggle_term` | No | — | — | — | DB update + fan-out `trigger_invalidate_cache` per student |
| `teacher_toggle_lesson` | No | — | — | — | Fetch lesson meta → DB update → fan-out two invalidations per student |
| `get_active_st` | (internal) | `"active_session_term"` | 600s | none | Helper for fetch_classes and toggle functions |

**`student_handler.mbt` functions:**

| Function | Cache | Cache Key | TTL | Deps | Notes |
|---|---|---|---|---|---|
| `student_get_class_level` | Yes | `"profile"` | 600s | none | Reactive gatekeeper. Returns class_level or NotInitialized error |
| `student_fetch_subjects` | Yes | `"subjects"` | 600s | `["profile"]` | Stale-fallback on DB error |
| `student_fetch_terms` | Yes | `"terms:{class_level_id}"` | 600s | `["profile"]` | Stale-fallback |
| `student_fetch_lessons` | Yes | `"lessons:{subject_id}\|{term_id}"` | 600s | `["profile"]` | Stale-fallback |
| `student_fetch_lesson` | Yes | `"lesson:{lesson_id}"` | 600s | `["lessons:{subj}\|{term}"]` | Returns `LessonContent?`. Parent context from DB result |

### Thin Agents (Phase 5)
- `admin_agent.mbt` — 108 lines (down from 1,440). 17 endpoint methods, each ~3-5 lines: `require_auth` → `let now = ...` → delegate to handler.
- `student_agent.mbt` — 48 lines (down from 532). 6 endpoints: ping, subjects, terms, lessons, lesson, invalidate-cache.
- `teacher_agent.mbt` — 53 lines (down from 627). 7 endpoints: ping, classes, terms, lessons, invalidate-cache, toggle-term-active, toggle-lesson-active.
- All agents use `cache : CacheSystem` (no `mut` — Map methods mutate in-place).
- `invalidate_cache` RPC endpoints use `self.cache.invalidate(key)` or `self.cache.invalidate_all()`.
- No SQL, no cache logic, no JSON parsing in agents — all delegated to handlers.

### Error Enhancement (Phase 6)
- Constructor helpers in `errors.mbt`: `surreal_error(body, sql?)`, `authentik_error(status, body, operation)`, `not_found_error(resource)`, `validation_error(msg)`.
- `db_client.mbt` uses `surreal_error()` for all DB errors.
- `AppError` struct and `ErrorCode` enum unchanged.

### Build Verified (Phase 7)
- `golem build` — 0 errors
- `pnpm build` — passes (no frontend changes)

## Call Chain

```
agents/admin_agent.mbt::get_class_levels()
  → require_auth()                          [auth.mbt]
  → admin_fetch_class_levels(cache, config, now)  [admin_handler.mbt]
      → db_admin_fetch_class_levels(config)       [db_admin.mbt]
          → surreal_query(config, sql)            [db_client.mbt]
      → manual JSON parse → Array[ClassLevelInfo]
      → return Ok(items)
```

## Dependencies

- No new MoonBit packages to install
- No new npm packages to install
- Build tools: `moon info`, `moon fmt`, `moon check --target wasm`, `golem build`, `golem deploy`
- Golem 1.5.3+ (same as current)

## Verification Checklist

### Build
1. `moon info` — 0 errors
2. `moon fmt` — all files formatted
3. `moon check --target wasm` — 0 errors
4. `golem build` — 0 errors
5. `pnpm build` — 0 errors
6. `pnpm check` — 0 errors

### Cache System
7. Cache hit: second request within TTL returns cached without DB call
8. Cache miss: first request fetches from DB, stores, returns
9. TTL expiry: fetches fresh from DB
10. Cascading invalidation: invalidating `"profile"` clears subjects, terms, lessons
11. Lesson invalidation chains through parent key

### Agent Endpoints
12. All student endpoints work (subjects, terms, lessons, lesson, invalidate-cache)
13. All teacher endpoints work (classes, terms, lessons, toggle-term, toggle-lesson, invalidate-cache)
14. All admin endpoints work (class-levels, class-subjects, teacher/subjects, session-terms, create/activate ST, CRUD operations)
15. Uninitialized student returns `NOT_INITIALIZED`

### Separation of Concerns
16. No agent file contains SQL query strings (all in `db_*.mbt`)
17. No agent file contains business logic (all delegated to handlers)
18. No handler file calls `require_auth()`
19. No db file calls cache or handler functions
