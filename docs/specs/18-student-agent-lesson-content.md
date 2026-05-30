# Unit 18 — Student Agent: Lesson Content (Student View)

## Goal

Add `getLesson(lessonId)` to the Student Agent that fetches a lesson from SurrealDB (cache with TTL) and returns only student-visible content fields (`objectives`, `content_sections`, `key_points`, plus identifying metadata). No teacher-only fields, no question bank, no assignment info. Surface through a Gateway endpoint and SvelteKit proxy route.

## Design

### Data Flow

```
Lesson card click (Unit 19)
  → +page.server.ts → GET /api/student/lesson?lesson_id={lessonId}
  → proxyToGateway('/gateway/student/lesson', userId, { lesson_id })
  → Gateway → StudentAgent.get_lesson(lesson_id)
    → lesson_cache[lesson_id] hit + fresh (< 600s) → return cached LessonContent
    → miss/stale → SurrealDB query by record ID
    → extract student-visible fields → cache → return LessonContent
  → Gateway wraps in Result::Ok → {"Ok":{...}}
  → SvelteKit returns { data: LessonContent }
```

### LessonContent Struct — Student-Visible Only

```moonbit
#derive.golem_schema
struct LessonContent {
  id : String
  topic_title : String?
  week : Int?
  subject_name : String?
  term_name : String?
  objectives : Array[Json]?
  content_sections : Array[Json]?
  key_points : Array[Json]?
}
```

**Note on `Array[Json]`:** If `#derive.golem_schema` does not support `@json.JsonValue` from `moonbitlang/core/json`, fall back to `String?` (JSON string) for each content field and let the frontend `JSON.parse()`.

**NOT returned** (teacher-only fields):
- `lesson_steps`, `materials`, `prior_knowledge`, `success_criteria`
- `extension_activities`, `textbook_references`
- `introduction`, `conclusion`
- `formative_assessment`, `summative_assessment`, `remediation`, `teacher_tips`
- `duration_mins`, `active`, `class_subject`, `term`
- `mcq_questions`, `theoretical_questions` (question bank — deferred to Unit 22/23)

### Cache

- New field on Student Agent: `mut lesson_cache : Map[String, LessonContentCache]`
- Cache entry:
  ```moonbit
  #derive.golem_schema
  struct LessonContentCache {
    data : LessonContent
    fetched_at : UInt64
  }
  ```
- Key: lesson_id (SurrealDB record ID, e.g. `lessons:01J8...`)
- TTL: 600 seconds (consistent with `CACHE_TTL`)

### SurrealDB Query

```surql
SELECT id, topic_title, week,
  class_subject.out.name AS subject_name,
  term.name AS term_name,
  objectives, content_sections, key_points
FROM lessons
WHERE id = $lesson_id
```

Uses dot-traversal to resolve `subject_name` and `term_name` from FKs. Content fields are returned from the single record.

### Content Fields — Parsing Pattern

The `parse_result_array` helper (already used by `get_lessons`, `get_terms`, etc.) extracts the SurrealDB JSON envelope. After getting the single lesson result object, content fields are extracted:

```moonbit
let objectives = match obj.get("objectives") {
  Some(v) => Some(v)
  None => None
}
let content_sections = match obj.get("content_sections") {
  Some(v) => Some(v)
  None => None
}
let key_points = match obj.get("key_points") {
  Some(v) => Some(v)
  None => None
}
```

Content fields stay as `Json` values. If `Array[Json]` isn't compatible with `#derive.golem_schema`, convert with `@json.to_string(v)` and store as `String?`.

## Implementation

### 1. Student Agent — Types

Add to `agents/app-agents/student_agent.mbt`:

```moonbit
#derive.golem_schema
struct LessonContent {
  id : String
  topic_title : String?
  week : Int?
  subject_name : String?
  term_name : String?
  objectives : Array[Json]?
  content_sections : Array[Json]?
  key_points : Array[Json]?
}

#derive.golem_schema
struct LessonContentCache {
  data : LessonContent
  fetched_at : UInt64
}
```

### 2. Student Agent — Field and Constructor

Add field to `StudentAgent` struct:
```moonbit
mut lesson_cache : Map[String, LessonContentCache]
```

Update `new()`:
```moonbit
lesson_cache: Map::new()
```

### 3. Student Agent — `get_lesson` Method

```moonbit
pub fn StudentAgent::get_lesson(self : Self, lesson_id : String) -> LessonContent? {
  let now = @wallClock.now().seconds

  let cached = self.lesson_cache.get(lesson_id)
  match cached {
    Some(entry) if now - entry.fetched_at < CACHE_TTL => return Some(entry.data)
    _ => ()
  }

  let sql =
    "SELECT id, topic_title, week, " +
    "class_subject.out.name AS subject_name, term.name AS term_name, " +
    "objectives, content_sections, key_points " +
    "FROM lessons WHERE id = $lesson_id"

  let raw = match surreal_query(self.config, sql, bindings={ "lesson_id": lesson_id }) {
    Ok(body) => body
    Err(_) => {
      let old = self.lesson_cache.get(lesson_id)
      match old {
        Some(e) => return Some(e.data)
        None => return None
      }
    }
  }

  let result_arr = match parse_result_array(raw) {
    Ok(arr) => arr
    Err(_) => {
      let old = self.lesson_cache.get(lesson_id)
      match old {
        Some(e) => return Some(e.data)
        None => return None
      }
    }
  }

  if result_arr.length() == 0 {
    return None
  }

  let lesson = match result_arr[0] {
    Object(obj) => extract_lesson_content(obj)
    _ => {
      let old = self.lesson_cache.get(lesson_id)
      match old {
        Some(e) => return Some(e.data)
        None => return None
      }
    }
  }

  self.lesson_cache.set(lesson_id, LessonContentCache::{
    data: lesson,
    fetched_at: now,
  })
  Some(lesson)
}

fn extract_lesson_content(obj : @json.JsonObject) -> LessonContent {
  let id = match obj.get("id") {
    Some(v) => match v { String(s) => s, _ => "" }
    None => ""
  }
  let topic_title = match obj.get("topic_title") {
    Some(v) => match v { String(s) => Some(s), _ => None }
    None => None
  }
  let week = match obj.get("week") {
    Some(v) => match v { Number(d, ..) => Some(d.to_int()), _ => None }
    None => None
  }
  let subject_name = match obj.get("subject_name") {
    Some(v) => match v { String(s) => Some(s), _ => None }
    None => None
  }
  let term_name = match obj.get("term_name") {
    Some(v) => match v { String(s) => Some(s), _ => None }
    None => None
  }
  let objectives = match obj.get("objectives") {
    Some(v) => Some(v)
    None => None
  }
  let content_sections = match obj.get("content_sections") {
    Some(v) => Some(v)
    None => None
  }
  let key_points = match obj.get("key_points") {
    Some(v) => Some(v)
    None => None
  }

  LessonContent::{
    id,
    topic_title,
    week,
    subject_name,
    term_name,
    objectives,
    content_sections,
    key_points,
  }
}
```

If `Array[Json]` is incompatible with `#derive.golem_schema`, replace `Some(v)` with `Some(@json.to_string(v))` and change the struct field type from `Array[Json]?` to `String?`.

### 4. Gateway Agent — Endpoint

Add to `agents/app-agents/gateway_agent.mbt`:

```moonbit
#derive.endpoint(get="/student/lesson?user_id={user_id}&lesson_id={lesson_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::student_lesson(
  self : Self,
  incoming_key : String,
  user_id : String,
  lesson_id : String,
) -> Result[LessonContent?, String] {
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

  let result = StudentAgentClient::scoped(user_id, fn(
    student,
  ) raise @common.AgentError {
    student.get_lesson(lesson_id)
  }) catch {
    _ => return Err("student agent unreachable")
  }
  Ok(result)
}
```

### 5. SvelteKit Proxy Route

**New: `frontend/src/routes/api/student/lesson/+server.ts`**

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

  const lessonId = event.url.searchParams.get('lesson_id');
  if (!lessonId) {
    return new Response(
      JSON.stringify({ error: { code: 'BAD_REQUEST', message: 'Missing lesson_id query parameter.' } }),
      { status: 400, headers: { 'content-type': 'application/json' } }
    );
  }

  const result = await proxyToGateway('/gateway/student/lesson', userId, { lesson_id: lessonId });

  if (result.error) {
    const status = result.error.code === 'NOT_INITIALIZED' ? 403 : 502;
    return new Response(JSON.stringify(result), { status, headers: { 'content-type': 'application/json' } });
  }

  let lesson: unknown;
  try {
    lesson = JSON.parse(result.data);
  } catch {
    return new Response(
      JSON.stringify({ error: { code: 'INVALID_RESPONSE', message: 'Failed to parse gateway response' } }),
      { status: 502, headers: { 'content-type': 'application/json' } }
    );
  }

  return new Response(
    JSON.stringify({ data: lesson }),
    { status: 200, headers: { 'content-type': 'application/json' } }
  );
};
```

### 6. Frontend Types

Add to `frontend/src/lib/types.ts`:

```typescript
export interface LessonContent {
  id: string;
  topic_title: string | null;
  week: number | null;
  subject_name: string | null;
  term_name: string | null;
  objectives: unknown[] | null;
  content_sections: unknown[] | null;
  key_points: unknown[] | null;
}
```

If content fields end up as `String?` in MoonBit, change to `string | null` here and the frontend will need to `JSON.parse()` each.

## Files Changed

| File | Change |
|---|---|
| `agents/app-agents/student_agent.mbt` | Add `LessonContent`, `LessonContentCache` structs; add `lesson_cache` field to `StudentAgent`; add `get_lesson()` method; add `extract_lesson_content()` helper; update `new()` |
| `agents/app-agents/gateway_agent.mbt` | Add `student_lesson` Gateway endpoint |
| `frontend/src/routes/api/student/lesson/+server.ts` | **New** — proxy to `/gateway/student/lesson` |
| `frontend/src/lib/types.ts` | Add `LessonContent` interface |
| `docs/progress-tracker.md` | Mark Unit 18 complete |

## Dependencies

None. All infra in place from Units 15-17. `parse_result_array`, `surreal_query`, `surreal_client.mbt`, and the Student Agent's SurrealDB config are all operational.

## Verification Checklist

### Build & Typecheck
- [ ] `golem build` succeeds with zero errors
- [ ] `pnpm build` succeeds with zero errors
- [ ] `pnpm check` passes with zero errors
- [ ] `moon check --target wasm` zero errors

### Student Agent — `get_lesson`
- [ ] Returns `Some(LessonContent)` for valid lesson_id
- [ ] Returns `None` for non-existent lesson_id
- [ ] Student-visible fields populated: `topic_title`, `week`, `subject_name`, `term_name`
- [ ] Content fields populated: `objectives`, `content_sections`, `key_points`
- [ ] Content arrays parsed correctly from SurrealDB JSON response
- [ ] No teacher-only fields leaked (`lesson_steps`, `materials`, etc.)
- [ ] No question bank fields (`mcq_questions`, `theoretical_questions`)

### TTL Caching
- [ ] First call queries SurrealDB; second call within 600s returns cached
- [ ] Different lesson_id values produce independent cache entries
- [ ] Cache miss after 600s re-queries SurrealDB
- [ ] SurrealDB error → falls back to stale cache (if any) → returns `None` if no cache

### Gateway Endpoint
- [ ] `GET /gateway/student/lesson?...` returns `{"Ok":{"id":"...","topic_title":"...",...}}`
- [ ] Invalid lesson_id returns `{"Ok":null}`
- [ ] Wrong auth → `{"Err":"unauthorized"}`
- [ ] Uninitialized user → `{"Err":"NOT_INITIALIZED"}`
- [ ] SurrealDB error → `{"Err":"ERROR:..."}`

### SvelteKit Proxy
- [ ] `GET /api/student/lesson?lesson_id={id}` → `200 { data: LessonContent }`
- [ ] Missing `lesson_id` → `400 BAD_REQUEST`
- [ ] Unauthenticated → `401 UNAUTHENTICATED`
- [ ] Uninitialized → `403 NOT_INITIALIZED`
- [ ] Gateway error → `502 with error code`

### Frontend Types
- [ ] `LessonContent` interface compiles without errors
- [ ] Content arrays typed as `unknown[] | null` (flexible for AI drift)

### Regression
- [ ] Subject list, term list, lesson list still load correctly
- [ ] Student dashboard unchanged
- [ ] Admin dashboard unchanged
- [ ] `pnpm build` zero errors, `pnpm check` zero errors
- [ ] `docs/progress-tracker.md` updated
