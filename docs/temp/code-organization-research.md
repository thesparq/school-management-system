Here's the full breakdown your coding agent can follow directly.

```
src/
  your_package/
    moon.pkg.json

    agents/
      admin.mbt
      teacher.mbt
      student.mbt

    handlers/
      admin.mbt
      teacher.mbt
      student.mbt

    db/
      client.mbt
      admin.mbt
      teacher.mbt
      student.mbt

    cache/
      system.mbt
      instance.mbt

    types/
      admin.mbt
      teacher.mbt
      student.mbt
      common.mbt

    serializers/
      admin.mbt
      teacher.mbt
      student.mbt

    auth.mbt
```

---

**`agents/admin.mbt`** — the AdminAgent struct and all its exported WIT methods. Each method does exactly two things: call `validate_auth()`, then delegate to the corresponding handler function. No logic lives here.

**`agents/teacher.mbt`** — same pattern for TeacherAgent.

**`agents/student.mbt`** — same pattern for StudentAgent.

---

**`handlers/admin.mbt`** — all `get_or_fetch_*` and action functions that AdminAgent methods delegate to. These are the functions that contain actual business logic. They call into `cache/instance.mbt` first, on miss call into `db/admin.mbt`, store result in cache, return. Function names prefixed: `admin_fetch_*`, `admin_create_*`, `admin_update_*` etc.

**`handlers/teacher.mbt`** — same for teacher-specific logic. Functions prefixed `teacher_fetch_*`, `teacher_create_*` etc.

**`handlers/student.mbt`** — same for student-specific logic. Functions prefixed `student_fetch_*` etc.

---

**`db/client.mbt`** — the SurrealDB connection and the raw query executor function. This is the only place that actually talks to SurrealDB. Everything else calls through this. No domain knowledge here — just takes a query string and parameters, returns raw result.

**`db/admin.mbt`** — admin-specific SurrealDB queries. Builds query strings, calls `db/client.mbt` to execute. Functions prefixed `db_admin_*`.

**`db/teacher.mbt`** — teacher-specific queries. Functions prefixed `db_teacher_*`.

**`db/student.mbt`** — student-specific queries. Functions prefixed `db_student_*`.

---

**`cache/system.mbt`** — the `CacheSystem` struct definition, plus all its methods: `get`, `set`, `invalidate`, `invalidate_all`. Pure cache logic, no awareness of agents or database.

**`cache/instance.mbt`** — a single package-level `let` that creates the one `CacheSystem` instance all handlers share. Nothing else.

```moonbit
let _cache : CacheSystem = CacheSystem::new()
```

---

**`types/common.mbt`** — structs shared across agents. `CacheEntry`, any shared response wrappers, error types.

**`types/admin.mbt`** — structs only AdminAgent uses. `AdminRecord`, `AdminResponse` etc.

**`types/teacher.mbt`** — structs only TeacherAgent uses.

**`types/student.mbt`** — structs only StudentAgent uses.

---

**`serializers/admin.mbt`** — `to_json` and `from_json` for every type in `types/admin.mbt`. Functions prefixed `admin_serialize_*`, `admin_deserialize_*`.

**`serializers/teacher.mbt`** — same for teacher types.

**`serializers/student.mbt`** — same for student types.

---

**`auth.mbt`** — just `validate_auth(key: String) -> Unit`. Raises on failure. Called at the top of every agent method in `agents/`.

---

**The call chain to make explicit for your coding agent:**

```
agents/admin.mbt
  → auth.mbt
  → handlers/admin.mbt
      → cache/instance.mbt   (check cache first)
      → db/admin.mbt         (on cache miss)
          → db/client.mbt    (execute query)
      → cache/instance.mbt   (store result)
      → serializers/admin.mbt (serialize before cache write, deserialize after read)
```

No file should ever skip a layer. `agents/` never calls `db/` directly. `db/admin.mbt` never calls `cache/`. `handlers/` never calls `auth.mbt`. If your coding agent finds itself writing a cross-layer call, that's the signal something belongs somewhere else.
