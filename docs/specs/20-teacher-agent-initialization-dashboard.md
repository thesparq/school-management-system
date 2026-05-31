# Unit 20 — Teacher Agent: Initialization & Dashboard

## Goal

Implement a durable Teacher Agent that stores assigned class-subject pairs (queried from Admin Agent), and a teacher dashboard at `/` showing "My Classes" cards. Teachers click a class → subjects → terms → lessons. Add an admin UI in the teacher users page to assign class-subject pairs (fetched from `has_subject` edges) using a search+badge pattern. Lesson detail view deferred to Unit 21.

## Design

### Teacher Agent — Per-Teacher Durable Agent

Each teacher gets their own durable agent instance identified by `teacher_id` in the constructor. The Teacher Agent stores its assigned class-subject pairs, grouped by class, in durable memory.

```moonbit
#derive.agent
struct TeacherAgent {
  config : @config.Config[SurrealConfig]
  teacher_id : String
  mut class_groups : Map[String, TeacherClassGroup]
}
```

**State fields:**

| Field | Type | Purpose |
|---|---|---|
| `config` | `@config.Config[SurrealConfig]` | SurrealDB connection (auto-loaded from env) |
| `teacher_id` | `String` | Agent identity — matches Authentik UUID |
| `class_groups` | `Map[String, TeacherClassGroup]` | Class→subjects, keyed by `class_level_id` |

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

The Admin Agent gains a `teacher_assignments` field and four new methods:

| Field / Method | Signature | Purpose |
|---|---|---|
| `teacher_assignments` | `Map[String, Array[TeacherSubjectPair]]` | Stores assigned class-subject pairs per teacher |
| `get_available_class_subjects()` | `-> Array[TeacherSubjectPair]` | Queries active `has_subject` edges from SurrealDB |
| `set_teacher_subjects(teacher_id, pairs)` | `-> Result[String, String]` | Stores assignments, fire-and-forgets Teacher Agent init |
| `get_teacher_subjects(teacher_id)` | `-> Array[TeacherSubjectPair]` | Returns stored assignments (or `[]`) |

### Data Source for Assignments

Admin Agent queries SurrealDB `has_subject` edges (active only) to get all available class-subject pairs. Each active edge produces one `TeacherSubjectPair`:

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
1. Admin clicks "Initialize" on teacher user → Admin Agent stores init record
2. Admin Agent fires `TeacherAgentClient::scoped(teacher_id, ...).trigger_initialize()` (fire-and-forget)
3. `trigger_initialize` calls `AdminAgent.get_teacher_subjects(teacher_id)`
4. Teacher Agent receives assignments, groups by `class_level_id`, stores in `self.class_groups`
5. If no assignments exist yet, `class_groups` remains empty — teacher sees "No subjects assigned"

**Assignment save flow:**
1. Admin modifies class-subject pairs in Manage panel, clicks "Save"
2. `POST /api/admin/teacher/subjects` → SvelteKit proxy → Gateway → `AdminAgent.set_teacher_subjects`
3. Admin Agent stores pairs, fire-and-forgets `TeacherAgentClient::scoped(teacher_id, ...).trigger_initialize()`
4. Teacher Agent re-fetches and rebuilds its `class_groups`

**Dashboard load:**
1. Teacher visits `/` → `+page.server.ts` calls `proxyToGateway('/gateway/teacher/classes', userId)`
2. Gateway checks init → `TeacherAgentClient::scoped(user_id, ...).get_my_classes()`
3. Teacher Agent returns `Array[TeacherClassGroup]` from durable state
4. Page renders "My Classes" card grid

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
POST /api/admin/teacher/subjects              POST /gateway/admin/teacher/subjects            AdminAgent.set_teacher_subjects()
```

---

## Implementation

### 1. Teacher Agent — Types and Struct

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
/// Fetches assigned class-subject pairs from Admin Agent,
/// groups them by class_level_id, and stores in durable state.
pub fn TeacherAgent::trigger_initialize(self : Self) -> String {
  let pairs = AdminAgentClient::scoped(fn(admin) raise @common.AgentError {
    admin.get_teacher_subjects(self.teacher_id)
  }) catch {
    _ => return "ERROR: admin unreachable"
  }

  let groups : Map[String, TeacherClassGroup] = Map::new()
  for pair in pairs {
    let gid = pair.class_level_id
    match groups.get(gid) {
      Some(g) => {
        g.subjects.push(pair)
        groups.set(gid, g)
      }
      None => {
        groups.set(gid, TeacherClassGroup::{
          class_level_id: gid,
          class_level_name: pair.class_level_name,
          subjects: [pair],
        })
      }
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

### 2. Admin Agent — Teacher Assignments and Class-Subject Pairs

Add to `agents/app-agents/admin_agent.mbt`:

**Update struct — add `teacher_assignments` field:**

```moonbit
#derive.agent
struct AdminAgent {
  initialized_users : Map[String, UserInitialization]
  config : @config.Config[SurrealConfig]
  mut teacher_assignments : Map[String, Array[TeacherSubjectPair]]
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

### 3. Gateway Endpoints

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

**Admin — set teacher subjects:**

```moonbit
///|
/// Body: JSON array of TeacherSubjectPair
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
  // Parse pairs_json using @json.parse and extract array of TeacherSubjectPair
  // ... JSON parsing logic to convert pairs_json → Array[TeacherSubjectPair]
  let val = @json.parse(pairs_json) catch { _ => return Err("invalid JSON body") }
  match val {
    Array(arr) => {
      for item in arr {
        match item {
          Object(obj) => {
            let class_level_id = match obj.get("class_level_id") { Some(String(s)) => s; _ => continue }
            let class_level_name = match obj.get("class_level_name") { Some(String(s)) => s; _ => continue }
            let subject_id = match obj.get("subject_id") { Some(String(s)) => s; _ => continue }
            let subject_name = match obj.get("subject_name") { Some(String(s)) => s; _ => continue }
            let subject_code = match obj.get("subject_code") { Some(String(s)) => Some(s); _ => None }
            pairs.push(TeacherSubjectPair::{ class_level_id, class_level_name, subject_id, subject_name, subject_code })
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

### 4. SvelteKit Proxy Routes

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

### 5. Frontend Types

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

### 6. Teacher Dashboard — Root Page

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

### 7. `/my-classes/[classId]/` Route — Subject List

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

### 8. `/my-classes/[classId]/[subjectId]/` Route — Terms

**Server load:** Calls `/api/teacher/terms`, returns `Array<TermInfo>`.

Finds the subject name from the class group data (fetched via `/api/teacher/classes`) for the breadcrumb.

**Page:** Identical visual pattern to `/lms/[subjectId]/`. Term cards link to `/my-classes/[classId]/[subjectId]/[termId]/`.

### 9. `/my-classes/[classId]/[subjectId]/[termId]/` Route — Lesson List

**Server load:** Calls `/api/teacher/lessons?class_level_id=...&subject_id=...&term_id=...`, returns `Array<LessonInfo>`.

**Page:** Identical visual pattern to `/lms/[subjectId]/[termId]/`. Lesson cards link to existing `/lms/[subjectId]/[termId]/[lessonId]` (student lesson detail — reused for now; Unit 21 adds teacher-specific view).

### 10. Admin UI — Teacher Assignment Panel

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

### 11. Sidebar — "My Classes" Nav Item

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

### 12. Build and Deploy

```bash
cd agents
moon info && moon fmt
moon check --target wasm
golem build
golem deploy --reset -Y

cd ../frontend
npx svelte-kit sync
pnpm build
pnpm check
```

---

## Files Changed

| File | Change |
|---|---|
| `agents/app-agents/teacher_agent.mbt` | Rewrite — add types, struct, initialize, get_my_classes, get_terms, get_lessons |
| `agents/app-agents/admin_agent.mbt` | Add `teacher_assignments` field, 4 new methods, update constructor and initialize_user |
| `agents/app-agents/gateway_agent.mbt` | Add 5 new endpoints |
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
| `docs/progress-tracker.md` | Mark Unit 20 as completed |

---

## Dependencies

None. No new npm packages or shadcn-svelte components needed.

---

## Verification Checklist

### Agent Layer — Teacher Agent
- [ ] `moon check --target wasm` succeeds (zero errors)
- [ ] `golem build` succeeds
- [ ] `moon info && moon fmt` runs clean in `agents/`
- [ ] `TeacherAgent::new()` initializes `class_groups` as empty map
- [ ] `trigger_initialize()` fetches from Admin Agent, groups by `class_level_id`
- [ ] `get_my_classes()` returns `Array[TeacherClassGroup]` after init, `[]` before
- [ ] `get_terms()` returns all active terms (same as student)
- [ ] `get_lessons("class_levels:jss_1", "subjects:basic_science", "terms:first")` returns filtered lessons
- [ ] Two different teacher agents maintain independent state

### Agent Layer — Admin Agent
- [ ] `AdminAgent::new(config)` initializes `teacher_assignments` as empty map
- [ ] `get_available_class_subjects()` returns pairs from active `has_subject` edges
- [ ] `set_teacher_subjects("t1", pairs)` stores and fires TeacherAgent init via RPC
- [ ] `get_teacher_subjects("t1")` returns stored pairs, `[]` for unassigned teacher
- [ ] `initialize_user("t1", "teacher", None)` fires `TeacherAgentClient::scoped(t1, ...)` with `trigger_initialize`
- [ ] `initialize_user("u1", "student", Some("JSS 1"))` does NOT fire TeacherAgent init (unchanged student path)

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
