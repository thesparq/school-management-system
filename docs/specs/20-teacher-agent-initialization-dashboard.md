# Unit 20 — Teacher Agent: Initialization & Dashboard

## Goal

Implement a durable Teacher Agent that stores assigned class-subject pairs as a cache (rebuilt from the `teacher_assignment` DB table), and a teacher dashboard at `/` showing "My Classes" cards. Teachers click a class → subjects → terms → lessons. Add an admin UI in the teacher users page to assign class-subject pairs using a search+badge pattern, persisting to the `teacher_assignment` SurrealDB table. Lesson detail view deferred to Unit 21.

**Architecture context:** This unit follows the DB-Backed Facts pattern (see `docs/architecture.md` Rules 1–10). Teacher assignments and user init status are stored in SurrealDB tables (`teacher_assignment`, `user_profile`), not in agent durable state. Agent struct fields hold only cached/derived data.

## Design

### Teacher Agent — Per-Teacher Durable Agent

Each teacher gets their own durable agent instance identified by `teacher_id` in the constructor. The Teacher Agent stores its assigned class-subject pairs as a **cache** (`class_groups`), rebuilt from the `teacher_assignment` DB table on init and invalidated by admin changes.

```moonbit
#derive.agent
struct TeacherAgent {
  config : @config.Config[SurrealConfig]
  teacher_id : String
  mut class_groups : Map[String, TeacherClassGroup]
}
```

**State fields:**

| Field | Type | Purpose | Cache Strategy |
|---|---|---|---|
| `config` | `@config.Config[SurrealConfig]` | SurrealDB connection (auto-loaded from env) | — |
| `teacher_id` | `String` | Agent identity — matches Authentik UUID | — |
| `class_groups` | `Map[String, TeacherClassGroup]` | Class→subjects, keyed by `class_level_id` | Push Invalidation (Rule 4A) |

**No entity data is stored in agent durable state.** The `teacher_assignment` table in SurrealDB is the single source of truth. The `class_groups` cache is rebuilt via `trigger_initialize()` which queries the DB directly, not the Admin Agent.

### Types

All new types use `#derive.golem_schema` for Golem serialization.

```moonbit
#derive.golem_schema
struct TeacherSubjectPair {
  class_level_id : String
  class_level_name : String
  subject_id : String
  subject_name : String
  subject_code : String?
}

#derive.golem_schema
struct TeacherClassGroup {
  class_level_id : String
  class_level_name : String
  subjects : Array[TeacherSubjectPair]
}
```

### Admin Agent Additions

Following Rule 1 (Two Layers, Clear Separation), the Admin Agent no longer holds `teacher_assignments` or `initialized_users` as struct fields. These are stored in SurrealDB tables (`teacher_assignment`, `user_profile`). The Admin Agent gains three new methods that read/write the DB:

| Field / Method | Signature | Purpose |
|---|---|---|
| `get_available_class_subjects()` | `-> Array[TeacherSubjectPair]` | Queries active `has_subject` edges from SurrealDB |
| `set_teacher_subjects(teacher_id, pairs)` | `-> Result[String, String]` | Writes to `teacher_assignment` table (upsert + soft-delete), fire-and-forgets Teacher Agent cache invalidation |
| `get_teacher_subjects(teacher_id)` | `-> Array[TeacherSubjectPair]` | Queries `teacher_assignment` table from SurrealDB (or `[]`) |

### Data Sources

**Available pairs (class+subject combos):** Admin Agent queries SurrealDB `has_subject` edges (active only). Each active edge produces one `TeacherSubjectPair`:

```sql
SELECT in.id AS class_level_id,
       in.name AS class_level_name,
       out.id AS subject_id,
       out.name AS subject_name,
       out.code AS subject_code
FROM has_subject
WHERE active = true
ORDER BY in.name ASC, out.name ASC
```

**Teacher's assigned pairs (from `teacher_assignment` table):** Admin Agent queries the `teacher_assignment` table joined with `class_levels` and `subjects` via dot-traversal:

```sql
SELECT in.id AS class_level_id,
       in.name AS class_level_name,
       out.id AS subject_id,
       out.name AS subject_name,
       out.code AS subject_code
FROM has_subject
WHERE active = true
ORDER BY in.name ASC, out.name ASC
```

**Teacher's assigned teacher_assignment query:**

```sql
SELECT class_level_id, subject_id,
       cl.name AS class_level_name,
       s.name AS subject_name,
       s.code AS subject_code
FROM teacher_assignment ta
LEFT JOIN class_levels cl ON cl.id = ta.class_level_id
LEFT JOIN subjects s ON s.id = ta.subject_id
WHERE ta.teacher_id = $teacher_id
  AND ta.deleted_at IS NONE
ORDER BY cl.name ASC, s.name ASC
```

### Route Structure

```
/  (root)
  └─ "My Classes" — class cards for teachers

/my-classes/[classId]/
  └─ Subject cards for that class

/my-classes/[classId]/[subjectId]/
  └─ Terms for that subject (same data as student view)

/my-classes/[classId]/[subjectId]/[termId]/
  └─ Lesson list (links to existing /lms/ lesson detail)

/lms/[subjectId]/[termId]/[lessonId]  (existing — Unit 18/19)
  └─ Lesson content — reused by teachers until Unit 21
```

### Admin Assignment UI Pattern

The assignment UI is embedded inline in the Manage panel of `UserTable.svelte` for teachers. It mirrors the group management pattern:

```
┌─ Class Subjects ─────────────────────────────────────┐
│ [JSS 1 — Basic Science] [JSS 1 — Mathematics] [×]  │
│ [JSS 2 — Basic Science] [×]                         │
│                                                      │
│ [Search class-subject…                  ]            │
│ ┌──────────────────────────────────────┐            │
│ │ JSS 1 — Basic Technology             │ ← suggestion│
│ │ JSS 2 — Cultural And Creative Arts   │   dropdown  │
│ └──────────────────────────────────────┘            │
│                                          [Save]     │
└──────────────────────────────────────────────────────┘
```

Each pair displays as `{Class} — {Subject}` in badges. Search filters across both class name and subject name. Selected pairs appear as removable badges (same X-icon pattern as group badges). A "Save" button persists changes. The section appears only when `role === 'teachers'` and the user is initialized.

### Data Flow

**Teacher initialization:**
1. Admin clicks "Initialize" on teacher user → Admin Agent writes to `user_profile` table (upsert)
2. Admin Agent fires `TeacherAgentClient::scoped(teacher_id, ...).trigger_initialize()` (fire-and-forget) inside `with_atomic_operation`
3. `trigger_initialize` queries `teacher_assignment` table from SurrealDB directly via `surreal_query`
4. Teacher Agent receives assignments, groups by `class_level_id`, stores in `self.class_groups` (cache)
5. If no assignments exist yet, `class_groups` remains empty — teacher sees "No subjects assigned"

**Assignment save flow:**
1. Admin modifies class-subject pairs in Manage panel, clicks "Save"
2. `POST /api/admin/teacher/subjects` → SvelteKit proxy → Gateway → `AdminAgent.set_teacher_subjects`
3. Admin Agent computes diff, writes upserts + soft-deletes to `teacher_assignment` table
4. Admin Agent fire-and-forgets `TeacherAgentClient::scoped(teacher_id, ...).trigger_initialize()` inside `with_atomic_operation`
5. Teacher Agent re-fetches from DB and rebuilds its `class_groups` cache

**Dashboard load:**
1. Teacher visits `/` → `+page.server.ts` calls `proxyToGateway('/gateway/teacher/classes', userId)`
2. Gateway checks init → queries `user_profile` table (via AdminAgent RPC → `surreal_query`)
3. Gateway calls `TeacherAgentClient::scoped(user_id, ...).get_my_classes()`
4. Teacher Agent returns `Array[TeacherClassGroup]` from cache (or empty)
5. Page renders "My Classes" card grid

**Term/lesson browsing:**
1. Teacher clicks class → `/my-classes/[classId]/[subjectId]/` calls `/api/teacher/terms`
2. Proxy → Gateway → `TeacherAgent.get_terms()` (same as student — returns all active terms)
3. Teacher clicks term → `/my-classes/[classId]/[subjectId]/[termId]/` calls `/api/teacher/lessons?class_level_id=...&subject_id=...&term_id=...`
4. Proxy → Gateway → `TeacherAgent.get_lessons(class_level_id, subject_id, term_id)` — queries SurrealDB with dot-traversal

**Teacher lesson (SurrealDB) queries:**

```sql
-- get_lessons
SELECT id, topic_title, week,
  class_subject.out.name AS subject_name, term.name AS term_name
FROM lessons
WHERE class_subject.in = $class_level_id
  AND class_subject.out = $subject_id
  AND class_subject.active = true
  AND term = $term_id AND active = true
ORDER BY week ASC
```

```sql
-- get_terms (same as student)
SELECT * FROM terms WHERE active = true ORDER BY sort_order ASC
```

### Route Map

```
SvelteKit                                     Gateway                                          Agent
─────────                                     ──────                                          ─────
GET /api/teacher/classes                      GET /gateway/teacher/classes                    TeacherAgent.get_my_classes()
GET /api/teacher/terms                        GET /gateway/teacher/terms                      TeacherAgent.get_terms()
GET /api/teacher/lessons                      GET /gateway/teacher/lessons                    TeacherAgent.get_lessons()
GET /api/admin/class-subjects                 GET /gateway/admin/class-subjects               AdminAgent.get_available_class_subjects()
GET /api/admin/teacher/{uuid}/subjects        GET /gateway/admin/teacher/{uuid}/subjects      AdminAgent.get_teacher_subjects()
POST /api/admin/teacher/subjects              POST /gateway/admin/teacher/subjects            AdminAgent.set_teacher_subjects()
```

---

## Implementation Phases

### Phase 1: Schema Migration + SurrealDB Client
**Files:** `docs/migration_v2.surql` (new), `agents/app-agents/surreal_client.mbt`

Create two new SurrealDB tables and add a retry wrapper for the `@json.parse` first-call bug.

**`docs/migration_v2.surql`:**

```surql
-- SCHEMAFULL definition for user_profile table
-- Replaces AdminAgent.initialized_users map + StudentAgent.profile
DEFINE TABLE IF NOT EXISTS user_profile SCHEMAFULL
  PERMISSIONS FOR select, create, update, delete NONE;

DEFINE FIELD IF NOT EXISTS auth_id ON user_profile TYPE string;
DEFINE FIELD IF NOT EXISTS role ON user_profile TYPE string
  ASSERT $value IN ["admin", "teacher", "student"];
DEFINE FIELD IF NOT EXISTS class_level ON user_profile TYPE option<string>;
DEFINE FIELD IF NOT EXISTS created_at ON user_profile TYPE datetime;
DEFINE FIELD IF NOT EXISTS updated_at ON user_profile TYPE option<datetime>;
DEFINE FIELD IF NOT EXISTS deleted_at ON user_profile TYPE option<datetime>;

DEFINE INDEX IF NOT EXISTS idx_user_profile_auth_id ON user_profile COLUMNS auth_id UNIQUE;

-- SCHEMAFULL definition for teacher_assignment table
-- Replaces AdminAgent.teacher_assignments map
DEFINE TABLE IF NOT EXISTS teacher_assignment SCHEMAFULL
  PERMISSIONS FOR select, create, update, delete NONE;

DEFINE FIELD IF NOT EXISTS teacher_id ON teacher_assignment TYPE string;
DEFINE FIELD IF NOT EXISTS class_level_id ON teacher_assignment TYPE string;
DEFINE FIELD IF NOT EXISTS subject_id ON teacher_assignment TYPE string;
DEFINE FIELD IF NOT EXISTS assigned_at ON teacher_assignment TYPE datetime;
DEFINE FIELD IF NOT EXISTS deleted_at ON teacher_assignment TYPE option<datetime>;

DEFINE INDEX IF NOT EXISTS idx_ta_teacher_cl_subj
  ON teacher_assignment COLUMNS teacher_id, class_level_id, subject_id UNIQUE;
```

**`surreal_query_retry()` in `surreal_client.mbt`:**

Add a wrapper that retries once on empty result or parse failure, replacing the ad-hoc retries scattered across agent methods:

```moonbit
///|
/// Wraps surreal_query with one retry on empty/failed parse.
/// Fixes the @json.parse first-call bug where structurally-valid
/// garbage is returned on the first WASM invocation.
pub fn surreal_query_retry(
  config : @config.Config[SurrealConfig],
  sql : String,
  bindings : Map[String, @json.JsonValue]?,
) -> Result[Array[@json.JsonValue], String] {
  let raw = match bindings {
    Some(b) => surreal_query(config, sql, bindings=b)
    None => surreal_query(config, sql)
  }
  let raw = match raw {
    Ok(body) => body
    Err(e) => return Err(e)
  }
  let result_arr = match parse_result_array(raw) {
    Ok(arr) => arr
    Err(_) => {
      // Retry once — @json.parse first-call bug
      let raw2 = match bindings {
        Some(b) => surreal_query(config, sql, bindings=b)
        None => surreal_query(config, sql)
      }
      match raw2 {
        Ok(body) => match parse_result_array(body) {
          Ok(arr) => arr
          Err(e) => return Err("parse failed after retry: " + e)
        }
        Err(e) => return Err("surreal_query failed after retry: " + e)
      }
    }
  }
  // If result_arr has one element with status="OK" and result is array, unwrap it
  // (SurrealDB wraps multi-statement results)
  Ok(result_arr)
}
```

### Phase 2: Admin Agent Refactor
**Files:** `agents/app-agents/admin_agent.mbt`

Remove `initialized_users` and `teacher_assignments` struct fields. All entity reads/writes go to SurrealDB. Use `with_atomic_operation` for atomic DB-write + fan-out (Rule 2). All writes use upsert semantics (Rule 2 idempotency).

See the code in [Section 2](#2-admin-agent-8212-teacher-assignments-and-class-subject-pairs) below.

### Phase 3: Teacher Agent Refactor
**Files:** `agents/app-agents/teacher_agent.mbt`

`trigger_initialize` reads from `teacher_assignment` table directly via `surreal_query_retry()` (no RPC to AdminAgent). `class_groups` is a Push-Invalidation cache (Rule 4A). Add `invalidate_cache()` method that clears `class_groups` for when AdminAgent signals a change.

See the code in [Section 1](#1-teacher-agent-8212-types-and-struct) below.

### Phase 4: Student Agent Profile → DB
**Files:** `agents/app-agents/student_agent.mbt`

Remove `profile` field from struct and constructor. `initialize()` writes to `user_profile` table via upsert. Keep all TTL caches (`subject_cache`, `terms_cache`, `lessons_cache`, `edge_cache`, `lesson_cache`) unchanged — they follow Rule 4B.

See the code in [Section 4](#4-student-agent-8212-profile-moved-to-db) below.

### Phase 5: Gateway Agent Endpoints
**Files:** `agents/app-agents/gateway_agent.mbt`

Add `GET /admin/teacher/{uuid}/subjects` endpoint. Adjust `set_teacher_subjects_admin` to parse ID-only payloads (`{class_level_id, subject_id}` without names — backend joins names from DB).

See the code in [Section 3](#3-gateway-endpoints) below.

### Phase 6: Frontend
**Files:** Multiple SvelteKit files and `UserTable.svelte`

- New proxy route for `GET /api/admin/teacher/[uuid]/subjects`
- Filter combobox suggestions against already-assigned pairs (exclude by matching both IDs)
- Disable subject assignment section for uninitialized teachers
- Save sends `{class_level_id, subject_id}` only

See the code in [Sections 4–11](#4-sveltekit-proxy-routes) below.

### Phase 7: Build & Deploy
**Files:** CI/manual build steps

```bash
# 1. Run schema migration
surreal sql --endpoint http://localhost:8000 --namespace school --db school \
  --file docs/migration_v2.surql

# 2. Build and deploy agents
cd agents
moon info && moon fmt
moon check --target wasm
golem build
golem deploy --reset -Y

# 3. Re-init admin (user_profile table is new, previous init was in agent state)
golem agent invoke 'GatewayAgent()' initialize_admin ...

# 4. Build frontend
cd ../frontend
npx svelte-kit sync
pnpm build
pnpm check
```

---

## Implementation

### [Phase 3] 1. Teacher Agent — Types and Struct

Rewrite `agents/app-agents/teacher_agent.mbt` entirely:

```moonbit
//|

///|
#derive.golem_schema
struct TeacherSubjectPair {
  class_level_id : String
  class_level_name : String
  subject_id : String
  subject_name : String
  subject_code : String?
}

///|
#derive.golem_schema
struct TeacherClassGroup {
  class_level_id : String
  class_level_name : String
  subjects : Array[TeacherSubjectPair]
}

///|
/// Durable per-teacher agent.
/// Identified by teacher_id — one instance per teacher.
/// Entity data lives in SurrealDB (teacher_assignment table).
/// class_groups is a Push-Invalidation cache (Rule 4A).
#derive.agent
struct TeacherAgent {
  config : @config.Config[SurrealConfig]
  teacher_id : String
  mut class_groups : Map[String, TeacherClassGroup]
}

///|
fn TeacherAgent::new(
  teacher_id : String,
  config : @config.Config[SurrealConfig],
) -> TeacherAgent {
  { config, teacher_id, class_groups: Map::new() }
}

///|
/// (Re)builds the class_groups cache from the teacher_assignment table.
/// Called by AdminAgent after assignments change (fire-and-forget RPC).
/// Queries SurrealDB directly — no RPC to AdminAgent needed.
pub fn TeacherAgent::trigger_initialize(self : Self) -> String {
  let sql = "SELECT class_level_id, subject_id, " +
    "cl.name AS class_level_name, " +
    "s.name AS subject_name, s.code AS subject_code " +
    "FROM teacher_assignment ta " +
    "LEFT JOIN class_levels cl ON cl.id = ta.class_level_id " +
    "LEFT JOIN subjects s ON s.id = ta.subject_id " +
    "WHERE ta.teacher_id = $teacher_id AND ta.deleted_at IS NONE " +
    "ORDER BY cl.name ASC, s.name ASC"

  let raw = match surreal_query(self.config, sql, bindings={
    "teacher_id": self.teacher_id,
  }) {
    Ok(body) => body
    Err(e) => return "ERROR: " + e
  }

  let result_arr = match parse_result_array(raw) {
    Ok(arr) => arr
    Err(_) => return "ERROR: parse failed"
  }

  let groups : Map[String, TeacherClassGroup] = Map::new()
  for item in result_arr {
    match item {
      Object(obj) => {
        let class_level_id = match obj.get("class_level_id") { Some(String(s)) => s; _ => continue }
        let class_level_name = match obj.get("class_level_name") { Some(String(s)) => s; _ => continue }
        let subject_id = match obj.get("subject_id") { Some(String(s)) => s; _ => continue }
        let subject_name = match obj.get("subject_name") { Some(String(s)) => s; _ => continue }
        let subject_code = match obj.get("subject_code") { Some(String(s)) => Some(s); _ => None }

        let pair = TeacherSubjectPair::{ class_level_id, class_level_name, subject_id, subject_name, subject_code }
        match groups.get(class_level_id) {
          Some(g) => {
            g.subjects.push(pair)
            groups.set(class_level_id, g)
          }
          None => {
            groups.set(class_level_id, TeacherClassGroup::{
              class_level_id,
              class_level_name,
              subjects: [pair],
            })
          }
        }
      }
      _ => ()
    }
  }
  self.class_groups = groups
  "OK"
}

///|
/// Returns the teacher's assigned classes with subjects.
/// Returns [] if not yet initialized.
pub fn TeacherAgent::get_my_classes(self : Self) -> Array[TeacherClassGroup] {
  self.class_groups.iter().map(fn((_, g)) { g }).collect()
}

///|
/// Returns all active terms (same query pattern as StudentAgent).
pub fn TeacherAgent::get_terms(self : Self) -> Array[TermInfo] {
  let sql = "SELECT * FROM terms WHERE active = true ORDER BY sort_order ASC"
  let raw = match surreal_query(self.config, sql) {
    Ok(body) => body
    Err(e) => return []
  }

  let result_arr = match parse_result_array(raw) {
    Ok(arr) => arr
    Err(_) => return []
  }

  let terms : Array[TermInfo] = []
  for item in result_arr {
    match item {
      Object(obj) => {
        let id = match obj.get("id") { Some(String(s)) => s; _ => continue }
        let name = match obj.get("name") { Some(String(s)) => s; _ => continue }
        let sort_order = match obj.get("sort_order") { Some(Number(d, ..)) => d.to_int(); _ => 0 }
        let active = match obj.get("active") { Some(True) => true; _ => false }
        terms.push(TermInfo::{ id, name, sort_order, active })
      }
      _ => ()
    }
  }
  terms
}

///|
/// Returns lessons for a given class_level + subject + term.
/// Uses dot-traversal on the has_subject edge.
pub fn TeacherAgent::get_lessons(
  self : Self,
  class_level_id : String,
  subject_id : String,
  term_id : String,
) -> Array[LessonInfo] {
  let sql = "SELECT id, topic_title, week, " +
    "class_subject.out.name AS subject_name, term.name AS term_name " +
    "FROM lessons " +
    "WHERE class_subject.in = $class_level_id " +
    "  AND class_subject.out = $subject_id " +
    "  AND class_subject.active = true " +
    "  AND term = $term_id AND active = true " +
    "ORDER BY week ASC"
  let raw = match
    surreal_query(self.config, sql, bindings={
      "class_level_id": class_level_id,
      "subject_id": subject_id,
      "term_id": term_id,
    }) {
    Ok(body) => body
    Err(_) => return []
  }

  let result_arr = match parse_result_array(raw) {
    Ok(arr) => arr
    Err(_) => return []
  }

  let lessons : Array[LessonInfo] = []
  for item in result_arr {
    match item {
      Object(obj) => {
        let id = match obj.get("id") { Some(String(s)) => s; _ => continue }
        let topic_title = match obj.get("topic_title") { Some(String(s)) => Some(s); _ => None }
        let week = match obj.get("week") { Some(Number(d, ..)) => Some(d.to_int()); _ => None }
        let subject_name = match obj.get("subject_name") { Some(String(s)) => Some(s); _ => None }
        let term_name = match obj.get("term_name") { Some(String(s)) => Some(s); _ => None }
        lessons.push(LessonInfo::{ id, topic_title, week, subject_name, term_name })
      }
      _ => ()
    }
  }
  lessons
}

//|
fn main {}
```

### [Phase 2] 2. Admin Agent — Teacher Assignments and Class-Subject Pairs

Update `agents/app-agents/admin_agent.mbt`:

**Update struct — remove `initialized_users` and `teacher_assignments`:**

Following Rule 1, these are now stored in SurrealDB tables.

```moonbit
#derive.agent
struct AdminAgent {
  config : @config.Config[SurrealConfig]
}
```

**Update constructor:**

```moonbit
fn AdminAgent::new(config : @config.Config[SurrealConfig]) -> AdminAgent {
  { config }
}
```

**Add `get_available_class_subjects`:**

```moonbit
///|
/// Returns all active class-subject pairs from has_subject edges.
pub fn AdminAgent::get_available_class_subjects(self : Self) -> Array[TeacherSubjectPair] {
  let sql = "SELECT in.id AS class_level_id, " +
    "in.name AS class_level_name, " +
    "out.id AS subject_id, out.name AS subject_name, " +
    "out.code AS subject_code " +
    "FROM has_subject WHERE active = true " +
    "ORDER BY in.name ASC, out.name ASC"
  let raw = match surreal_query(self.config, sql) {
    Ok(body) => body
    Err(_) => return []
  }

  let result_arr = match parse_result_array(raw) {
    Ok(arr) => arr
    Err(_) => return []
  }

  let pairs : Array[TeacherSubjectPair] = []
  for item in result_arr {
    match item {
      Object(obj) => {
        let class_level_id = match obj.get("class_level_id") { Some(String(s)) => s; _ => continue }
        let class_level_name = match obj.get("class_level_name") { Some(String(s)) => s; _ => continue }
        let subject_id = match obj.get("subject_id") { Some(String(s)) => s; _ => continue }
        let subject_name = match obj.get("subject_name") { Some(String(s)) => s; _ => continue }
        let subject_code = match obj.get("subject_code") { Some(String(s)) => Some(s); _ => None }
        pairs.push(TeacherSubjectPair::{
          class_level_id, class_level_name,
          subject_id, subject_name, subject_code,
        })
      }
      _ => ()
    }
  }
  pairs
}
```

**Add `set_teacher_subjects`:**

Uses SurrealDB write + fire-and-forget RPC inside `with_atomic_operation` (Rule 2). The DB write is idempotent via soft-delete + upsert pattern: existing records are soft-deleted, new ones inserted.

```moonbit
///|
/// Writes teacher's assigned class-subject pairs to the teacher_assignment
/// table (soft-delete + insert), then triggers Teacher Agent cache
/// rebuild via fire-and-forget RPC inside with_atomic_operation.
pub fn AdminAgent::set_teacher_subjects(
  self : Self,
  teacher_id : String,
  pairs : Array[TeacherSubjectPair],
) -> Result[String, String] {
  // Build SurrealQL queries for upsert+soft-delete
  // Phase 1: soft-delete all existing assignments for this teacher
  let del_sql = "UPDATE teacher_assignment SET deleted_at = time::now() " +
    "WHERE teacher_id = $teacher_id AND deleted_at IS NONE"

  // Phase 2: insert new assignments
  let ins_parts : Array[String] = []
  for pair in pairs {
    let cls_id = pair.class_level_id
    let subj_id = pair.subject_id
    ins_parts.push(
      "( $teacher_id, '" + cls_id + "', '" + subj_id + "', time::now() )"
    )
  }
  let ins_sql = "INSERT INTO teacher_assignment (teacher_id, class_level_id, subject_id, assigned_at) " +
    "VALUES " + ins_parts.join(",") + " " +
    "ON DUPLICATE KEY UPDATE deleted_at = NONE, assigned_at = time::now()"

  // Execute with atomic operation to ensure DB write + RPC are replayed together on crash
  @golem.with_atomic_operation(fn() {
    // Soft-delete existing
    let _ = surreal_query(self.config, del_sql, bindings={ "teacher_id": teacher_id })
    // Insert new
    if ins_parts.length() > 0 {
      let _ = surreal_query(self.config, ins_sql)
    }
    // Fire TeacherAgent cache rebuild
    let _ = TeacherAgentClient::scoped(teacher_id, fn(
      client,
    ) raise @common.AgentError {
      client.trigger_initialize()
    }) catch {
      _ => ()
    }
  })

  Ok("ok")
}
```

**Add `get_teacher_subjects`:**

```moonbit
///|
/// Queries the teacher_assignment table for a teacher's assigned pairs.
/// Returns [] if no assignments found.
pub fn AdminAgent::get_teacher_subjects(
  self : Self,
  teacher_id : String,
) -> Array[TeacherSubjectPair] {
  let sql = "SELECT ta.class_level_id, ta.subject_id, " +
    "cl.name AS class_level_name, " +
    "s.name AS subject_name, s.code AS subject_code " +
    "FROM teacher_assignment ta " +
    "LEFT JOIN class_levels cl ON cl.id = ta.class_level_id " +
    "LEFT JOIN subjects s ON s.id = ta.subject_id " +
    "WHERE ta.teacher_id = $teacher_id AND ta.deleted_at IS NONE " +
    "ORDER BY cl.name ASC, s.name ASC"

  let raw = match surreal_query(self.config, sql, bindings={ "teacher_id": teacher_id }) {
    Ok(body) => body
    Err(_) => return []
  }

  let result_arr = match parse_result_array(raw) {
    Ok(arr) => arr
    Err(_) => return []
  }

  let pairs : Array[TeacherSubjectPair] = []
  for item in result_arr {
    match item {
      Object(obj) => {
        let class_level_id = match obj.get("class_level_id") { Some(String(s)) => s; _ => continue }
        let class_level_name = match obj.get("class_level_name") { Some(String(s)) => s; _ => continue }
        let subject_id = match obj.get("subject_id") { Some(String(s)) => s; _ => continue }
        let subject_name = match obj.get("subject_name") { Some(String(s)) => s; _ => continue }
        let subject_code = match obj.get("subject_code") { Some(String(s)) => Some(s); _ => None }
        pairs.push(TeacherSubjectPair::{
          class_level_id, class_level_name,
          subject_id, subject_name, subject_code,
        })
      }
      _ => ()
    }
  }
  pairs
}
```

**Update `initialize_user` — write to `user_profile` table + fire TeacherAgent init for teachers:**

```moonbit
///|
/// Records user initialization in user_profile table and fires
/// TeacherAgent cache rebuild if role is "teacher".
pub fn AdminAgent::initialize_user(
  self : Self,
  user_id : String,
  role : String,
  class_level : String?,
) -> Result[String, String] {
  let sql = "INSERT INTO user_profile (auth_id, role, class_level, created_at) " +
    "VALUES ($auth_id, $role, $class_level, time::now()) " +
    "ON DUPLICATE KEY UPDATE role = $role, class_level = $class_level, updated_at = time::now()"

  let _ = surreal_query(self.config, sql, bindings={
    "auth_id": user_id,
    "role": role,
    "class_level": class_level,
  })

  if role == "teacher" {
    let _ = TeacherAgentClient::scoped(user_id, fn(
      client,
    ) raise @common.AgentError {
      client.trigger_initialize()
    }) catch {
      _ => ()
    }
  }

  Ok("ok")
}
```

**Add `is_user_initialized` — queries `user_profile` table:**

```moonbit
///|
/// Checks if a user has a record in the user_profile table.
pub fn AdminAgent::is_user_initialized(
  self : Self,
  user_id : String,
) -> Bool {
  let sql = "SELECT count() AS cnt FROM user_profile " +
    "WHERE auth_id = $auth_id AND deleted_at IS NONE"
  let raw = match surreal_query(self.config, sql, bindings={ "auth_id": user_id }) {
    Ok(body) => body
    Err(_) => return false
  }
  // Parse count — if cnt > 0, user is initialized
  match parse_result_array(raw) {
    Ok(arr) => {
      match arr[0] {
        Object(obj) => {
          match obj.get("cnt") {
            Some(Number(d, ..)) => d.to_int() > 0
            _ => false
          }
        }
        _ => false
      }
    }
    Err(_) => false
  }
}
```

**Update constructor:**

```moonbit
fn AdminAgent::new(config : @config.Config[SurrealConfig]) -> AdminAgent {
  { initialized_users: Map::new(), config, teacher_assignments: Map::new() }
}
```

**Add `get_available_class_subjects`:**

```moonbit
///|
/// Returns all active class-subject pairs from has_subject edges.
pub fn AdminAgent::get_available_class_subjects(self : Self) -> Array[TeacherSubjectPair] {
  let sql = "SELECT in.id AS class_level_id, " +
    "in.name AS class_level_name, " +
    "out.id AS subject_id, out.name AS subject_name, " +
    "out.code AS subject_code " +
    "FROM has_subject WHERE active = true " +
    "ORDER BY in.name ASC, out.name ASC"
  let raw = match surreal_query(self.config, sql) {
    Ok(body) => body
    Err(_) => return []
  }

  let result_arr = match parse_result_array(raw) {
    Ok(arr) => arr
    Err(_) => return []
  }

  let pairs : Array[TeacherSubjectPair] = []
  for item in result_arr {
    match item {
      Object(obj) => {
        let class_level_id = match obj.get("class_level_id") { Some(String(s)) => s; _ => continue }
        let class_level_name = match obj.get("class_level_name") { Some(String(s)) => s; _ => continue }
        let subject_id = match obj.get("subject_id") { Some(String(s)) => s; _ => continue }
        let subject_name = match obj.get("subject_name") { Some(String(s)) => s; _ => continue }
        let subject_code = match obj.get("subject_code") { Some(String(s)) => Some(s); _ => None }
        pairs.push(TeacherSubjectPair::{
          class_level_id, class_level_name,
          subject_id, subject_name, subject_code,
        })
      }
      _ => ()
    }
  }
  pairs
}
```

**Add `set_teacher_subjects`:**

```moonbit
///|
/// Stores a teacher's assigned class-subject pairs and triggers
/// Teacher Agent re-initialization via fire-and-forget RPC.
pub fn AdminAgent::set_teacher_subjects(
  self : Self,
  teacher_id : String,
  pairs : Array[TeacherSubjectPair],
) -> Result[String, String] {
  self.teacher_assignments.set(teacher_id, pairs)

  let _ = TeacherAgentClient::scoped(teacher_id, fn(
    client,
  ) raise @common.AgentError {
    client.trigger_initialize()
  }) catch {
    _ => ()
  }

  Ok("ok")
}
```

**Add `get_teacher_subjects`:**

```moonbit
///|
/// Returns the stored assignments for a teacher, or [] if none.
pub fn AdminAgent::get_teacher_subjects(
  self : Self,
  teacher_id : String,
) -> Array[TeacherSubjectPair] {
  match self.teacher_assignments.get(teacher_id) {
    Some(pairs) => pairs
    None => []
  }
}
```

**Update `initialize_user` — fire TeacherAgent init for teachers:**

After storing the init record, add:
```moonbit
if role == "teacher" {
  let _ = TeacherAgentClient::scoped(user_id, fn(
    client,
  ) raise @common.AgentError {
    client.trigger_initialize()
  }) catch {
    _ => ()
  }
}
```

### [Phase 5] 3. Gateway Endpoints

Add to `agents/app-agents/gateway_agent.mbt`:

**Teacher classes:**

```moonbit
///|
#derive.endpoint(get="/teacher/classes?user_id={user_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::teacher_classes(
  self : Self,
  incoming_key : String,
  user_id : String,
) -> Result[Array[TeacherClassGroup], String] {
  match self.check_auth(incoming_key) {
    Some(msg) => return Err(msg)
    None => ()
  }
  let initialized = AdminAgentClient::scoped(fn(
    admin,
  ) raise @common.AgentError {
    admin.is_user_initialized(user_id)
  }) catch {
    _ => return Err("admin unreachable")
  }
  if !initialized {
    return Err("NOT_INITIALIZED")
  }
  let result = TeacherAgentClient::scoped(user_id, fn(
    teacher,
  ) raise @common.AgentError {
    teacher.get_my_classes()
  }) catch {
    _ => return Err("teacher agent unreachable")
  }
  Ok(result)
}
```

**Teacher terms:**

```moonbit
///|
#derive.endpoint(get="/teacher/terms?user_id={user_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::teacher_terms(
  self : Self,
  incoming_key : String,
  user_id : String,
) -> Result[Array[TermInfo], String] {
  match self.check_auth(incoming_key) {
    Some(msg) => return Err(msg)
    None => ()
  }
  let initialized = AdminAgentClient::scoped(fn(
    admin,
  ) raise @common.AgentError {
    admin.is_user_initialized(user_id)
  }) catch {
    _ => return Err("admin unreachable")
  }
  if !initialized {
    return Err("NOT_INITIALIZED")
  }
  let result = TeacherAgentClient::scoped(user_id, fn(
    teacher,
  ) raise @common.AgentError {
    teacher.get_terms()
  }) catch {
    _ => return Err("teacher agent unreachable")
  }
  Ok(result)
}
```

**Teacher lessons:**

```moonbit
///|
#derive.endpoint(get="/teacher/lessons?user_id={user_id}&class_level_id={class_level_id}&subject_id={subject_id}&term_id={term_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::teacher_lessons(
  self : Self,
  incoming_key : String,
  user_id : String,
  class_level_id : String,
  subject_id : String,
  term_id : String,
) -> Result[Array[LessonInfo], String] {
  match self.check_auth(incoming_key) {
    Some(msg) => return Err(msg)
    None => ()
  }
  let initialized = AdminAgentClient::scoped(fn(
    admin,
  ) raise @common.AgentError {
    admin.is_user_initialized(user_id)
  }) catch {
    _ => return Err("admin unreachable")
  }
  if !initialized {
    return Err("NOT_INITIALIZED")
  }
  let result = TeacherAgentClient::scoped(user_id, fn(
    teacher,
  ) raise @common.AgentError {
    teacher.get_lessons(class_level_id, subject_id, term_id)
  }) catch {
    _ => return Err("teacher agent unreachable")
  }
  Ok(result)
}
```

**Admin — class-subject pairs:**

```moonbit
///|
/// Requires valid X-Golem-Auth-Key header, no per-user init check.
#derive.endpoint(get="/admin/class-subjects?user_id={admin_user_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::list_class_subjects(
  self : Self,
  incoming_key : String,
  admin_user_id : String,
) -> Result[Array[TeacherSubjectPair], String] {
  match self.check_auth(incoming_key) {
    Some(msg) => return Err(msg)
    None => ()
  }
  AdminAgentClient::scoped(fn(admin) raise @common.AgentError {
    admin.get_available_class_subjects()
  }) catch {
    _ => Err("admin unreachable")
  }
}
```

**Admin — get teacher subjects (current pairs for a specific teacher):**

```moonbit
///|
/// Returns the currently assigned class-subject pairs for a teacher.
/// Requires valid X-Golem-Auth-Key header.
#derive.endpoint(get="/admin/teacher/{target_teacher_id}/subjects?user_id={admin_user_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::get_teacher_subjects_admin(
  self : Self,
  incoming_key : String,
  admin_user_id : String,
  target_teacher_id : String,
) -> Result[Array[TeacherSubjectPair], String] {
  match self.check_auth(incoming_key) {
    Some(msg) => return Err(msg)
    None => ()
  }
  AdminAgentClient::scoped(fn(admin) raise @common.AgentError {
    admin.get_teacher_subjects(target_teacher_id)
  }) catch {
    _ => Err("admin unreachable")
  }
}
```

**Admin — set teacher subjects:**

```moonbit
///|
/// Body: JSON array of { class_level_id, subject_id } (ID-only payload,
/// no names needed — backend joins names from DB).
/// Requires valid X-Golem-Auth-Key header.
#derive.endpoint(post="/admin/teacher/subjects?user_id={admin_user_id}&target_teacher_id={target_teacher_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
#derive.endpoint_body("pairs_json")
pub fn GatewayAgent::set_teacher_subjects_admin(
  self : Self,
  incoming_key : String,
  admin_user_id : String,
  target_teacher_id : String,
  pairs_json : String,
) -> Result[String, String] {
  match self.check_auth(incoming_key) {
    Some(msg) => return Err(msg)
    None => ()
  }

  let pairs : Array[TeacherSubjectPair] = []
  // ID-only payload: frontend sends { class_level_id, subject_id } only
  let val = @json.parse(pairs_json) catch { _ => return Err("invalid JSON body") }
  match val {
    Array(arr) => {
      for item in arr {
        match item {
          Object(obj) => {
            let class_level_id = match obj.get("class_level_id") { Some(String(s)) => s; _ => continue }
            let subject_id = match obj.get("subject_id") { Some(String(s)) => s; _ => continue }
            // Names will be resolved by AdminAgent via DB join
            pairs.push(TeacherSubjectPair::{
              class_level_id, class_level_name: "",
              subject_id, subject_name: "", subject_code: None,
            })
          }
          _ => ()
        }
      }
    }
    _ => return Err("invalid JSON body")
  }

  AdminAgentClient::scoped(fn(admin) raise @common.AgentError {
    admin.set_teacher_subjects(target_teacher_id, pairs)
  }) catch {
    _ => Err("admin unreachable")
  }
}
```

### [Phase 4] 4. Student Agent — Profile Moved to DB

**Update `agents/app-agents/student_agent.mbt`:**

Remove `profile` field from struct — it moves to the `user_profile` table:

```moonbit
#derive.agent
struct StudentAgent {
  config : @config.Config[SurrealConfig]
  student_id : String
  // profile removed — now in user_profile table (Rule 1)
  mut subject_cache : SubjectCache?
  mut terms_cache : Map[String, TermCacheEntry]
  mut lessons_cache : Map[String, LessonCacheEntry]
  mut edge_cache : Map[String, EdgeCacheEntry]
  mut lesson_cache : Map[String, LessonContentCache]
}
```

**Update constructor:**

```moonbit
fn StudentAgent::new(
  student_id : String,
  config : @config.Config[SurrealConfig],
) -> StudentAgent {
  {
    config,
    student_id,
    subject_cache: None,
    terms_cache: Map::new(),
    lessons_cache: Map::new(),
    edge_cache: Map::new(),
    lesson_cache: Map::new(),
  }
}
```

**Rewrite `initialize` to write to `user_profile` table:**

```moonbit
///|
/// Records student initialization in user_profile table.
/// Writes own profile via upsert (idempotent — Rule 2).
pub fn StudentAgent::initialize(self : Self, class_level : String) -> String {
  let sql = "INSERT INTO user_profile (auth_id, role, class_level, created_at) " +
    "VALUES ($auth_id, 'student', $class_level, time::now()) " +
    "ON DUPLICATE KEY UPDATE class_level = $class_level, updated_at = time::now(), " +
    "  deleted_at = NONE"

  match surreal_query_retry(self.config, sql, Some({
    "auth_id": String(self.student_id),
    "class_level": String(class_level),
  })) {
    Ok(_) => "OK"
    Err(e) => "ERROR: " + e
  }
}
```

Note: `class_level` parameter is now the SurrealDB record ID string (e.g. `"class_levels:jss_3"`), not a `StudentProfile` struct. All TTL caches remain unchanged — they are in-progress/session data (Rule 1 test: if the agent is deleted, the school doesn't care about cached values).

### [Phase 6] 5. SvelteKit Proxy Routes

**`frontend/src/routes/api/teacher/classes/+server.ts`:**

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

  const result = await proxyToGateway('/gateway/teacher/classes', userId);

  if (result.error) {
    const status = result.error.code === 'NOT_INITIALIZED' ? 403 : 502;
    return new Response(JSON.stringify(result), { status, headers: { 'content-type': 'application/json' } });
  }

  let data: unknown;
  try {
    data = JSON.parse(result.data);
  } catch {
    return new Response(
      JSON.stringify({ error: { code: 'INVALID_RESPONSE', message: 'Failed to parse gateway response' } }),
      { status: 502, headers: { 'content-type': 'application/json' } }
    );
  }

  return new Response(
    JSON.stringify({ data }),
    { status: 200, headers: { 'content-type': 'application/json' } }
  );
};
```

**`frontend/src/routes/api/teacher/terms/+server.ts`:** Same pattern as `/api/teacher/classes`, proxy to `/gateway/teacher/terms`.

**`frontend/src/routes/api/teacher/lessons/+server.ts`:** Same pattern, proxy to `/gateway/teacher/lessons` with `class_level_id`, `subject_id`, `term_id` query params validated.

**`frontend/src/routes/api/admin/class-subjects/+server.ts`:**

```typescript
import { proxyToGateway } from '$lib/server/golem';
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

export const GET: RequestHandler = async (event) => {
  const user = event.locals.user;
  if (!user) error(401, 'Not authenticated');
  if (!user.roles.includes('admin')) error(403, 'Forbidden');

  const result = await proxyToGateway('/gateway/admin/class-subjects', user.id);

  if (result.error) {
    return new Response(JSON.stringify(result), {
      status: 502,
      headers: { 'content-type': 'application/json' }
    });
  }

  let data: unknown;
  try {
    data = JSON.parse(result.data);
  } catch {
    return new Response(
      JSON.stringify({ error: { code: 'INVALID_RESPONSE', message: 'Failed to parse gateway response' } }),
      { status: 502, headers: { 'content-type': 'application/json' } }
    );
  }

  return new Response(
    JSON.stringify({ data }),
    { status: 200, headers: { 'content-type': 'application/json' } }
  );
};
```

**`frontend/src/routes/api/admin/teacher/subjects/+server.ts`:**

```typescript
import { proxyToGateway } from '$lib/server/golem';
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

export const POST: RequestHandler = async (event) => {
  const user = event.locals.user;
  if (!user) error(401, 'Not authenticated');
  if (!user.roles.includes('admin')) error(403, 'Forbidden');

  const body = await event.request.json().catch(() => ({}));
  const targetTeacherId = body.target_teacher_id;
  const pairs = body.pairs;
  if (!targetTeacherId || !Array.isArray(pairs)) {
    return new Response(
      JSON.stringify({ error: { code: 'BAD_REQUEST', message: 'Missing target_teacher_id or pairs array.' } }),
      { status: 400, headers: { 'content-type': 'application/json' } }
    );
  }

  const result = await proxyToGateway(
    '/gateway/admin/teacher/subjects',
    user.id,
    { target_teacher_id: targetTeacherId, pairs_json: JSON.stringify(pairs) }
  );

  if (result.error) {
    return new Response(JSON.stringify(result), {
      status: 502,
      headers: { 'content-type': 'application/json' }
    });
  }

  return new Response(
    JSON.stringify({ data: { saved: true } }),
    { status: 200, headers: { 'content-type': 'application/json' } }
  );
};
```

### [Phase 6] 6. Frontend Types

Add to `frontend/src/lib/types.ts`:

```typescript
export interface TeacherSubjectPair {
  class_level_id: string;
  class_level_name: string;
  subject_id: string;
  subject_name: string;
  subject_code: string | null;
}

export interface TeacherClassGroup {
  class_level_id: string;
  class_level_name: string;
  subjects: TeacherSubjectPair[];
}
```

### [Phase 6] 7. Teacher Dashboard — Root Page

**Update `frontend/src/routes/+page.server.ts`:**

After the student subject fetching block and before the final return, add teacher handling:

```typescript
// Teacher dashboard: fetch my classes
if (user.roles.includes('teachers') && !user.roles.includes('students')) {
  try {
    const classesResult = await proxyToGateway('/gateway/teacher/classes', user.id);
    if (classesResult.error) {
      return { initialized: true, teacherClasses: null, teacherClassesError: classesResult.error.message, subjects: null, subjectsError: null };
    }
    const parsed = JSON.parse(classesResult.data);
    const teacherClasses = Array.isArray(parsed) ? parsed : [];
    return { initialized: true, teacherClasses, teacherClassesError: null, subjects: null, subjectsError: null };
  } catch {
    return { initialized: true, teacherClasses: null, teacherClassesError: 'Failed to reach backend service.', subjects: null, subjectsError: null };
  }
}
```

**Update `frontend/src/routes/+page.svelte`:**

Add a teacher section between the student subjects section and the generic dashboard:

```svelte
{:else if data.teacherClasses !== null}
  <div class="mx-auto max-w-6xl space-y-6">
    {#if $navigating && (!data.teacherClasses || data.teacherClasses.length === 0)}
      <h1 class="text-2xl font-display font-bold text-primary-700">My Classes</h1>
      <div class="grid gap-6 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
        {#each Array(6) as _}
          <Skeleton class="h-32" />
        {/each}
      </div>
    {:else if data.teacherClassesError}
      <Alert variant="destructive">
        <AlertTitle>Failed to load classes</AlertTitle>
        <AlertDescription>{data.teacherClassesError}</AlertDescription>
        <AlertAction>
          <Button variant="outline" onclick={() => goto('/')}>Retry</Button>
        </AlertAction>
      </Alert>
    {:else if data.teacherClasses.length === 0}
      <div class="mx-auto max-w-lg py-16 text-center space-y-6">
        <div class="rounded-full bg-secondary-100 dark:bg-secondary-900/20 mx-auto w-fit p-4">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-8 w-8 text-secondary-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <circle cx="12" cy="12" r="10" />
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 16v-4m0-4h.01" />
          </svg>
        </div>
        <h1 class="text-2xl font-display font-bold text-surface-800 dark:text-surface-200">No Classes Assigned</h1>
        <p class="text-surface-700 dark:text-surface-400">
          No classes have been assigned to you yet. Please contact your school administrator.
        </p>
      </div>
    {:else}
      <h1 class="text-2xl font-display font-bold text-primary-700">My Classes</h1>
      <div class="grid gap-6 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
        {#each data.teacherClasses as group (group.class_level_id)}
          <a href="/my-classes/{group.class_level_id}">
            <Card class="hover:bg-primary-50 dark:hover:bg-primary-950/30 hover:ring-primary-200 dark:hover:ring-primary-700 transition cursor-pointer">
              <CardHeader>
                <CardTitle class="font-display text-base text-primary-700 dark:text-primary-300">
                  {group.class_level_name}
                </CardTitle>
              </CardHeader>
              <CardContent>
                <p class="text-sm text-surface-700 dark:text-surface-400">
                  {group.subjects.length} {group.subjects.length === 1 ? 'subject' : 'subjects'}
                </p>
              </CardContent>
            </Card>
          </a>
        {/each}
      </div>
    {/if}
  </div>
```

### [Phase 6] 8. `/my-classes/[classId]/` Route — Subject List

**`frontend/src/routes/my-classes/[classId]/+page.server.ts`:**

```typescript
import { redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import type { TeacherClassGroup, TeacherSubjectPair, BreadcrumbItem } from '$lib/types';

export const load: PageServerLoad = async ({ params, locals, fetch }) => {
  const userId = locals.user?.id;
  if (!userId) redirect(302, '/');

  const classId = params.classId;

  const classesRes = await fetch('/api/teacher/classes');
  if (!classesRes.ok) {
    const err = await classesRes.json().catch(() => ({ error: { message: 'Failed to fetch classes' } }));
    return { subjects: [], classLevelName: null, subjectsError: err.error?.message ?? 'Unknown error', breadcrumbs: [{ label: 'My Classes', href: '/' }, { label: 'Class' }] };
  }

  let classGroup: TeacherClassGroup | null = null;
  let classLevelName = 'Class';
  try {
    const json = await classesRes.json();
    const groups: TeacherClassGroup[] = json.data ?? [];
    const match = groups.find((g: TeacherClassGroup) => g.class_level_id === classId);
    if (match) {
      classGroup = match;
      classLevelName = match.class_level_name;
    }
  } catch {
    // fallthrough
  }

  if (!classGroup) {
    return { subjects: [], classLevelName, subjectsError: 'Class not found.', breadcrumbs: [{ label: 'My Classes', href: '/' }, { label: classLevelName }] };
  }

  return {
    subjects: classGroup.subjects,
    classLevelName,
    subjectsError: null,
    breadcrumbs: [
      { label: 'My Classes', href: '/' } as BreadcrumbItem,
      { label: classLevelName } as BreadcrumbItem
    ]
  };
};
```

**`frontend/src/routes/my-classes/[classId]/+page.svelte`:**

Visually identical to student subject card page. Heading shows class name. Subject cards link to `/my-classes/[classId]/[subjectId]`. Skeleton/empty/error states matching existing patterns.

### [Phase 6] 9. `/my-classes/[classId]/[subjectId]/` Route — Terms

**Server load:** Calls `/api/teacher/terms`, returns `Array<TermInfo>`.

Finds the subject name from the class group data (fetched via `/api/teacher/classes`) for the breadcrumb.

**Page:** Identical visual pattern to `/lms/[subjectId]/`. Term cards link to `/my-classes/[classId]/[subjectId]/[termId]/`.

### [Phase 6] 10. `/my-classes/[classId]/[subjectId]/[termId]/` Route — Lesson List

**Server load:** Calls `/api/teacher/lessons?class_level_id=...&subject_id=...&term_id=...`, returns `Array<LessonInfo>`.

**Page:** Identical visual pattern to `/lms/[subjectId]/[termId]/`. Lesson cards link to existing `/lms/[subjectId]/[termId]/[lessonId]` (student lesson detail — reused for now; Unit 21 adds teacher-specific view).

### [Phase 6] 11. Admin UI — Teacher Assignment Panel

**Update `UserTable.svelte`:**

**Script additions:**

```typescript
interface SubjectPair {
  class_level_id: string;
  class_level_name: string;
  subject_id: string;
  subject_name: string;
  subject_code: string | null;
}

let allSubjectPairs = $state<SubjectPair[]>([]);
let currentTeacherPairs = $state<SubjectPair[]>({});
let subjectSearch = $state<Record<number, string>>({});
let showSubjectSuggestions = $state<Record<number, boolean>>({});
let teacherSubjectLoading = $state<Record<number, string>>({});
```

**Load available pairs on mount:**

```typescript
onMount(() => {
  if (role === 'students') loadClassLevels();
  if (role === 'teachers') loadAllSubjectPairs();
});

async function loadAllSubjectPairs() {
  try {
    const res = await fetch('/api/admin/class-subjects');
    if (!res.ok) throw new Error('Failed to load');
    const body = await res.json();
    if (body.data) allSubjectPairs = body.data;
  } catch {
    allSubjectPairs = [];
  }
}
```

**Load teacher's current pairs when expanded:**

```typescript
async function loadTeacherPairs(uuid: string, pk: number) {
  if (!uuid) return;
  try {
    const res = await fetch(`/api/admin/teacher/${uuid}/subjects`);
    if (!res.ok) throw new Error('Failed');
    const body = await res.json();
    if (body.data) currentTeacherPairs = { ...currentTeacherPairs, [pk]: body.data };
  } catch {
    currentTeacherPairs = { ...currentTeacherPairs, [pk]: [] };
  }
}
```

**Save handler:**

```typescript
async function handleSaveTeacherSubjects(pk: number, uuid: string) {
  teacherSubjectLoading = { ...teacherSubjectLoading, [pk]: 'loading' };
  try {
    const res = await fetch('/api/admin/teacher/subjects', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        target_teacher_id: uuid,
        pairs: currentTeacherPairs[pk] || []
      })
    });
    const body = await res.json();
    if (!res.ok || body.error) throw new Error(body.error?.message || 'Save failed');
  } catch (err) {
    actionErrors = { ...actionErrors, [pk]: err instanceof Error ? err.message : 'Save failed' };
  } finally {
    teacherSubjectLoading = { ...teacherSubjectLoading, [pk]: 'idle' };
  }
}
```

**Filtered suggestions (derived):**

```typescript
let filteredSubjectSuggestions = $derived.by(() => {
  const pk = expandedPk;
  if (!pk || !subjectSearch[pk]?.trim()) return [];
  const search = subjectSearch[pk].toLowerCase();
  const assigned = currentTeacherPairs[pk] || [];
  return allSubjectPairs.filter(
    p => !assigned.some(
      a => a.class_level_id === p.class_level_id && a.subject_id === p.subject_id
    ) &&
    (`${p.class_level_name} — ${p.subject_name}`.toLowerCase().includes(search))
  );
});
```

**Template section — add after the Groups section, inside the expanded panel:**

```svelte
{#if role === 'teachers' && isPending === false}
  <div class="border-t border-surface-200 pt-3">
    <span class="text-sm font-medium text-surface-700">Class Subjects</span>

    <div class="flex flex-wrap gap-1.5 mt-2">
      {#each (currentTeacherPairs[userObj.pk] || []) as pair}
        <span class="inline-flex items-center gap-1 rounded-md bg-primary-100 px-2 py-0.5 text-xs font-medium text-primary-700">
          {pair.class_level_name} — {pair.subject_name}
          <button
            type="button"
            aria-label="Remove {pair.subject_name}"
            class="inline-flex items-center justify-center rounded-full p-0.5 text-primary-500 hover:bg-primary-200 hover:text-primary-800 transition-colors cursor-pointer"
            onclick={() => {
              currentTeacherPairs = {
                ...currentTeacherPairs,
                [userObj.pk]: (currentTeacherPairs[userObj.pk] || []).filter(
                  (p: SubjectPair) => !(p.class_level_id === pair.class_level_id && p.subject_id === pair.subject_id)
                )
              };
            }}
          >
            <svg class="h-3 w-3" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </span>
      {/each}
      {#if (currentTeacherPairs[userObj.pk] || []).length === 0}
        <span class="text-xs text-surface-500 italic">No subjects assigned</span>
      {/if}
    </div>

    <div class="relative mt-2 flex items-center gap-2">
      <Input
        type="text"
        placeholder="Search class-subject…"
        class="h-8 flex-1 text-sm cursor-text"
        bind:value={subjectSearch[userObj.pk] ?? ''}
        oninput={(e) => subjectSearch = { ...subjectSearch, [userObj.pk]: e.currentTarget.value }}
        onfocus={() => showSubjectSuggestions = { ...showSubjectSuggestions, [userObj.pk]: true }}
        onblur={() => setTimeout(() => showSubjectSuggestions = { ...showSubjectSuggestions, [userObj.pk]: false }, 200)}
      />
      {#if showSubjectSuggestions[userObj.pk] && filteredSubjectSuggestions.length > 0}
        <div class="absolute bottom-full left-0 right-0 mb-1 z-20 rounded-md border border-surface-200 bg-white shadow-lg max-h-40 overflow-y-auto flex flex-col">
          {#each filteredSubjectSuggestions as suggestion}
            <button
              type="button"
              class="w-full shrink-0 px-3 py-1.5 text-left text-sm text-surface-800 hover:bg-surface-100 transition-colors cursor-pointer"
              onmousedown={() => {
                currentTeacherPairs = {
                  ...currentTeacherPairs,
                  [userObj.pk]: [...(currentTeacherPairs[userObj.pk] || []), suggestion]
                };
                subjectSearch = { ...subjectSearch, [userObj.pk]: '' };
              }}
            >
              {suggestion.class_level_name} — {suggestion.subject_name}
            </button>
          {/each}
        </div>
      {/if}
    </div>

    <div class="flex justify-end mt-2">
      <Button
        size="sm"
        class="cursor-pointer"
        onclick={() => handleSaveTeacherSubjects(userObj.pk, userObj.uuid)}
        disabled={teacherSubjectLoading[userObj.pk] === 'loading'}
      >
        {teacherSubjectLoading[userObj.pk] === 'loading' ? 'Saving...' : 'Save'}
      </Button>
    </div>
  </div>
{/if}
```

### [Phase 6] 12. Sidebar — "My Classes" Nav Item

In `frontend/src/routes/+layout.svelte`, after the LMS nav item in the Navigation group:

```svelte
{#if data.user.roles.includes('teachers')}
  <SidebarMenuItem>
    <SidebarMenuButton isActive={$page.url.pathname.startsWith('/my-classes')}>
      {#snippet child({ props })}
        <a href="/" {...props}>My Classes</a>
      {/snippet}
    </SidebarMenuButton>
  </SidebarMenuItem>
{/if}
```

### [Phase 7] 13. Build and Deploy

Follow the steps documented in [Phase 7](#phase-7-build--deploy) above:

---

## Files Changed

| File | Change |
|---|---|---|
| `docs/migration_v2.surql` | **New** — schema migration: create `user_profile` and `teacher_assignment` tables with unique indexes and soft-delete |
| `agents/app-agents/surreal_client.mbt` | Add `surreal_query_retry()` wrapper for @json.parse first-call bug |
| `agents/app-agents/teacher_agent.mbt` | Rewrite — trigger_initialize queries DB directly, class_groups is a Push-Invalidation cache |
| `agents/app-agents/admin_agent.mbt` | Remove `initialized_users`, `teacher_assignments` fields; add DB-backed methods (set_teacher_subjects, get_teacher_subjects, is_user_initialized, initialize_user) |
| `agents/app-agents/student_agent.mbt` | Remove `profile` field; `initialize()` writes to `user_profile` table |
| `agents/app-agents/gateway_agent.mbt` | Add 6 endpoints (including GET teacher/{uuid}/subjects); set_teacher_subjects_admin uses ID-only payload parsing |
| `frontend/src/lib/types.ts` | Add `TeacherSubjectPair`, `TeacherClassGroup` |
| `frontend/src/routes/+page.server.ts` | Add teacher class fetching |
| `frontend/src/routes/+page.svelte` | Add "My Classes" teacher section |
| `frontend/src/routes/+layout.svelte` | Add "My Classes" sidebar nav for teachers |
| `frontend/src/routes/my-classes/[classId]/+page.server.ts` | **New** — subject list for class |
| `frontend/src/routes/my-classes/[classId]/+page.svelte` | **New** — subject cards |
| `frontend/src/routes/my-classes/[classId]/[subjectId]/+page.server.ts` | **New** — terms |
| `frontend/src/routes/my-classes/[classId]/[subjectId]/+page.svelte` | **New** — term cards |
| `frontend/src/routes/my-classes/[classId]/[subjectId]/[termId]/+page.server.ts` | **New** — lesson list |
| `frontend/src/routes/my-classes/[classId]/[subjectId]/[termId]/+page.svelte` | **New** — lesson cards |
| `frontend/src/routes/api/teacher/classes/+server.ts` | **New** — proxy |
| `frontend/src/routes/api/teacher/terms/+server.ts` | **New** — proxy |
| `frontend/src/routes/api/teacher/lessons/+server.ts` | **New** — proxy |
| `frontend/src/routes/api/admin/class-subjects/+server.ts` | **New** — proxy |
| `frontend/src/routes/api/admin/teacher/subjects/+server.ts` | **New** — proxy |
| `frontend/src/routes/api/admin/teacher/[uuid]/subjects/+server.ts` | **New** — proxy (GET teacher's current pairs) |
| `frontend/src/routes/admin/users/UserTable.svelte` | Add Class Subjects section for teachers |
| `docs/architecture.md` | Update — add Rules 1-10, new DB tables, revised agent state tables |
| `docs/code-standards.md` | Update — DB-backed facts section |
| `docs/progress-tracker.md` | Update — move Unit 20 to In Progress with 7-phase breakdown |
| `docs/specs/00-build-plan.md` | Update — rewrite Unit 20 for DB-backed architecture, update Units 21-26 references |

---

## Dependencies

- SurrealDB instance with existing `has_subject`, `class_levels`, `subjects`, `lessons` tables (from Units 9/HF-01)
- Golem agents deployed with previous component version
- No new npm packages or shadcn-svelte components needed

---

## Verification Checklist

### DB Schema (`migration_v2.surql`)
- [ ] `migration_v2.surql` applies without errors on dev SurrealDB
- [ ] `user_profile` table exists with `auth_id`, `role`, `class_level`, `created_at`, `updated_at`, `deleted_at`
- [ ] `teacher_assignment` table exists with `teacher_id`, `class_level_id`, `subject_id`, `assigned_at`, `deleted_at`
- [ ] Unique index on `teacher_assignment(teacher_id, class_level_id, subject_id)` works
- [ ] Unique index on `user_profile(auth_id)` works
- [ ] Soft deletes filter correctly: `SELECT ... WHERE deleted_at IS NONE`

### Agent Layer — Student Agent
- [ ] `StudentAgent` struct has no `profile` field
- [ ] `StudentAgent::new()` has no profile field in constructor
- [ ] `initialize("class_levels:jss_3")` upserts row into `user_profile` table
- [ ] Existing TTL caches unchanged after initialization
- [ ] All previous student queries (`get_subjects`, `get_terms`, `get_lessons`, `get_lesson`) still work

### Agent Layer — Teacher Agent
- [ ] `moon check --target wasm` succeeds (zero errors)
- [ ] `golem build` succeeds
- [ ] `moon info && moon fmt` runs clean in `agents/`
- [ ] `TeacherAgent::new()` initializes `class_groups` as empty map
- [ ] `trigger_initialize()` queries `teacher_assignment` table directly via `surreal_query`
- [ ] `get_my_classes()` returns `Array[TeacherClassGroup]` after init, `[]` before
- [ ] `get_terms()` returns all active terms (same as student)
- [ ] `get_lessons("class_levels:jss_1", "subjects:basic_science", "terms:first")` returns filtered lessons
- [ ] Two different teacher agents maintain independent state

### Agent Layer — Admin Agent
- [ ] `AdminAgent::new(config)` has no `teacher_assignments` or `initialized_users` fields
- [ ] `get_available_class_subjects()` returns pairs from active `has_subject` edges
- [ ] `set_teacher_subjects("t1", pairs)` writes to `teacher_assignment` table (soft-delete + insert inside `with_atomic_operation`)
- [ ] `set_teacher_subjects("t1", pairs)` fires `TeacherAgentClient::scoped(t1, ...).trigger_initialize()` inside `with_atomic_operation`
- [ ] `get_teacher_subjects("t1")` queries `teacher_assignment` table, returns pairs, `[]` for unassigned teacher
- [ ] `is_user_initialized("t1")` queries `user_profile` table, returns `Bool`
- [ ] `initialize_user("t1", "teacher", None)` upserts into `user_profile` table
- [ ] `initialize_user("u1", "student", Some("class_levels:jss_1"))` upserts into `user_profile` table, does NOT fire TeacherAgent init

### Agent Layer — Gateway
- [ ] `/gateway/teacher/classes` returns `Ok([...])` for initialized teacher
- [ ] `/gateway/teacher/classes` returns `Err("NOT_INITIALIZED")` for uninitialized user
- [ ] `/gateway/teacher/classes` returns `Err("unauthorized")` on auth mismatch
- [ ] `/gateway/teacher/terms` returns `Ok([TermInfo, ...])`
- [ ] `/gateway/teacher/lessons` with params returns `Ok([LessonInfo, ...])`
- [ ] `/gateway/admin/class-subjects` returns all pairs
- [ ] `/gateway/admin/teacher/subjects` (POST) stores and returns `Ok("ok")`
- [ ] All endpoints check auth before any RPC

### SvelteKit Build
- [ ] `pnpm build` succeeds (zero errors)
- [ ] `pnpm check` passes (zero errors)

### Teacher Dashboard (`/`)
- [ ] Teacher with classes assigned → "My Classes" heading with card grid
- [ ] Each class card shows name and subject count
- [ ] Cards have hover effect, link to `/my-classes/[classId]`
- [ ] Teacher with no classes → centered "No Classes Assigned" with info icon
- [ ] Gateway unreachable → destructive Alert with Retry button
- [ ] Skeleton cards visible during navigation when cached data absent
- [ ] Non-teacher users never see "My Classes" section

### Subject List (`/my-classes/[classId]/`)
- [ ] Shows subject cards for the class
- [ ] Each card links to `/my-classes/[classId]/[subjectId]`
- [ ] Only subjects the teacher is assigned to appear
- [ ] Breadcrumb: "My Classes > JSS 1"
- [ ] Skeleton/empty/error states present

### Terms and Lesson List
- [ ] `/my-classes/[classId]/[subjectId]/` shows term cards
- [ ] `/my-classes/[classId]/[subjectId]/[termId]/` shows lesson cards
- [ ] Lesson card links to existing `/lms/[subjectId]/[termId]/[lessonId]`
- [ ] Breadcrumb: "My Classes > JSS 1 > Basic Science > Second Term"
- [ ] Active/inactive visual distinction for terms and lessons

### Admin — Teacher Assignment Panel
- [ ] Teacher Manage panel shows "Class Subjects" section when initialized (and role === 'teachers')
- [ ] Section not shown when role !== 'teachers'
- [ ] Available class-subject pairs load from `/api/admin/class-subjects`
- [ ] Search input filters by class name and subject name (both)
- [ ] Clicking a suggestion adds the badge, removes it from suggestions
- [ ] X button on badge removes it from current list
- [ ] "Save" button persists changes via `POST /api/admin/teacher/subjects`
- [ ] Save triggers `TeacherAgent.trigger_initialize` (teacher sees changes on next page load)
- [ ] Loading state on save button
- [ ] Error state if save fails

### SurrealDB Client
- [ ] `surreal_query_retry()` returns `Ok([...])` on first successful call
- [ ] `surreal_query_retry()` retries once on empty/failed parse, succeeds on retry
- [ ] Existing `surreal_query()` callers still work (no breaking signature change)

### Regression
- [ ] Student dashboard subject cards unchanged
- [ ] Student term/lesson browsing unchanged
- [ ] Admin dashboard unchanged
- [ ] Admin user management (create, delete, authenticate, group management) unchanged
- [ ] Student activation/initialization unchanged
- [ ] Sidebar shows "My Classes" only for teachers (visible alongside LMS for teacher+student roles)
- [ ] Existing `/api/student/*` proxy routes unchanged
- [ ] Existing `/api/auth/*` routes unchanged
- [ ] `docs/progress-tracker.md` updated

### Post-Deploy Verification
- [ ] Re-init admin: `golem agent invoke 'GatewayAgent()' initialize_admin ...`
- [ ] Init teacher: `golem agent invoke 'GatewayAgent()' initialize_admin ... 'teacher' 'None'`
- [ ] Assign subject to teacher via admin UI → verify `/api/teacher/classes` returns data
- [ ] Teacher dashboard shows class cards
- [ ] Teacher can browse class → subject → terms → lessons
- [ ] Student access to same subjects/terms/lessons unchanged
