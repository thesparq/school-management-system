# HF-02: GatewayAgent Removal — Per-User Agent Architecture

## Goal

Eliminate the Ephemeral Gateway Agent entirely. Each durable agent (Admin, Student, Teacher) becomes its own HTTP endpoint with path-based worker ID extraction. SuperAdminAgent (triggered by JWT username `thesparq`) handles all admin operations with no init check. Per-user agents use a unified `CacheData` enum map for cache-first init and data caching. SvelteKit proxies via per-role helpers instead of `proxyToGateway()`.

## Design

### No Gateway Agent

`gateway_agent.mbt` is deleted. The 15+ endpoints it proxied (auth check → AdminAgent RPC → return) are gone. Each agent exposes its own `#derive.endpoint` annotations directly to HTTP.

### Agent HTTP Mounts & Access Control

| Agent | Mount | Worker ID | Init Check | Accessed When |
|-------|-------|-----------|------------|---------------|
| SuperAdminAgent | `/super-admin` | Singleton | None | JWT `username == "thesparq"` |
| AdminAgent | `/admin/{admin_id}` | Path param | cache-first via `CacheData::Profile` | Normal admin users |
| StudentAgent | `/student/{student_id}` | Path param | cache-first via `CacheData::Profile` | Students |
| TeacherAgent | `/teacher/{teacher_id}` | Path param | cache-first via `CacheData::Profile` | Teachers |

All endpoints require `X-Golem-Auth-Key` header verified against `SharedConfig.auth_key`.

### SuperAdminAgent

SuperAdminAgent is a durable singleton with no init check — it is always ready. It hosts the same set of admin capabilities as AdminAgent (initialize users, get class levels, assign teachers/subjects, list initializations, etc.) plus a `bootstrap` convenience endpoint.

SuperAdminAgent is used when SvelteKit detects `event.locals.user.username === 'thesparq'` in the JWT. All admin API calls from this user route to SuperAdminAgent instead of AdminAgent.

The superadmin user `thesparq` exists in Authentik (created manually). SuperAdminAgent writes their `user_profile` on first use. Since there is no init check, there is no chicken-and-egg problem.

**Note:** The recommended production setup is to create a normal admin user via SuperAdminAgent and deactivate the superadmin. The superadmin exists for bootstrapping and development convenience.

### Unified Cache Map

Every agent stores all cached data in a single `Map[String, CacheItem]`. This replaces separate named fields (`subject_cache`, `terms_cache`, `lessons_cache`, `edge_cache`, `lesson_cache`, `class_groups`).

```moonbit
enum CacheData {
  Empty
  Profile(UserProfileData)
  Subjects(Array[SubjectInfo])
  Terms(Array[TermInfo])
  Lessons(Array[LessonInfo])
  Edge(String)
  LessonContent(LessonContent)
  ClassGroups(Map[String, TeacherClassGroup])
}

struct CacheItem {
  data : CacheData
  fetched_at : UInt64
  invalidated : Bool
}
```

Cache key constants / helpers:

| Field | Key | Example |
|-------|-----|---------|
| Profile | `"profile"` | `"profile"` |
| Subjects | `"subjects"` | `"subjects"` |
| Terms | `"terms:{class_level}"` | `"terms:class_levels:jss_1"` |
| Lessons | `"lessons:{subject_id}\|{term_id}"` | `"lessons:subjects:basic_science\|terms:first"` |
| Edge | `"edge:{subject_id}"` | `"edge:subjects:basic_science"` |
| Lesson | `"lesson:{lesson_id}"` | `"lesson:lessons:s48v5um2fyzq6ad5lplu"` |
| ClassGroups | `"class_groups"` | `"class_groups"` |

### Cache-First Init Pattern

On every authenticated endpoint call, each per-user agent (Admin, Student, Teacher):

1. Check `caches["profile"]` — if `CacheItem` exists, not `Empty`, not `invalidated`, and TTL not expired → proceed
2. If stale, `invalidated`, or missing → query `user_profile` table from SurrealDB
3. If record exists → set `caches["profile"] = CacheItem { data: Profile(...), fetched_at: now, invalidated: false }`, proceed
4. If no record → set `caches["profile"] = CacheItem { data: Empty, fetched_at: now, invalidated: false }`, return `"NOT_INITIALIZED"` error

### Invalidation

Single generic RPC method on every agent:

```moonbit
pub fn StudentAgent::invalidate_cache(self : Self, key : String) -> String {
  if key == "all" {
    self.caches = Map::new()
  } else {
    self.caches.remove(key)
  }
  "OK"
}
```

Admin Agent calls `StudentAgentClient::scoped(student_id, fn(c) { c.invalidate_cache("profile") })` after writing `user_profile` to DB. The next request from that student re-fetches from SurrealDB.

### SharedConfig

A single `#derive.config` struct used by all agents:

```moonbit
#derive.config
pub(all) struct SharedConfig {
  host      : @config.Secret[String]
  ns        : @config.Secret[String]
  database  : @config.Secret[String]
  username  : @config.Secret[String]
  password  : @config.Secret[String]
  auth_key  : @config.Secret[String]
}
```

### SvelteKit Proxy Layer

`proxyToGateway()` replaced with per-role helpers in `golem.ts`:

| Helper | When | Constructs URL |
|--------|------|---------------|
| `proxySuperAdmin(path, extra?)` | username == `"thesparq"` | `{base}/super-admin{path}` |
| `proxyAdmin(path, adminId, extra?)` | admin role | `{base}/admin/{admin_id}{path}` |
| `proxyStudent(path, studentId, extra?)` | student role | `{base}/student/{student_id}{path}` |
| `proxyTeacher(path, teacherId, extra?)` | teacher role | `{base}/teacher/{teacher_id}{path}` |

Each helper attaches `X-Golem-Auth-Key` header. No `user_id` query param — worker ID is in the mount path.

**Route selection logic in each proxy route:**

```typescript
// Before:
const result = await proxyToGateway('/gateway/student/subjects', userId);

// After:
const userId = event.locals.user?.id;
const username = event.locals.user?.username;
if (username === 'thesparq') {
  // superadmin — use SuperAdminAgent
  proxySuperAdmin('/whatever-endpoint', { target_user_id: userId });
} else {
  proxyStudent('/subjects', userId);
}
```

## Implementation

### Phase 1: Delete GatewayAgent

- Remove `agents/app-agents/gateway_agent.mbt`
- Update `agents/app-agents/moon.pkg` if it references gateway_agent

### Phase 2: Create Shared Cache Types

New file `agents/app-agents/cache_types.mbt`:

```moonbit
#derive.golem_schema
enum CacheData {
  Empty
  Profile(String)
  Subjects(Array[SubjectInfo])
  Terms(Array[TermInfo])
  Lessons(Array[LessonInfo])
  Edge(String)
  LessonContent(LessonContent)
  ClassGroups(Array[TeacherClassGroup])
}

#derive.golem_schema
struct CacheItem {
  data : CacheData
  fetched_at : UInt64
  invalidated : Bool
}
```

The `Profile` variant stores the JSON string of the user profile record (or a typed struct `UserProfileData` with `auth_id`, `role`, `class_level`).

### Phase 3: Consolidate Config

- Rename `SurrealConfig` → `SharedConfig` in `surreal_client.mbt`
- Add `auth_key : @config.Secret[String]` field
- Update all agent constructors to accept `@config.Config[SharedConfig]`
- Update `golem.yaml` `secretDefaults` to include all 6 fields (host, ns, database, username, password, authKey — the last already exists)

### Phase 4: Create SuperAdminAgent

New file `agents/app-agents/super_admin_agent.mbt`:

```moonbit
#derive.agent
#derive.mount("/super-admin")
struct SuperAdminAgent {
  config : @config.Config[SharedConfig]
}

fn SuperAdminAgent::new(config : @config.Config[SharedConfig]) -> SuperAdminAgent {
  { config, }
}
```

Endpoints (all require `X-Golem-Auth-Key`, no init check):

| Method | Endpoint | Maps to |
|--------|----------|---------|
| `ping` | `GET /ping` | Returns `"super admin online"` |
| `initialize_user` | `POST /initialize` | Writes user_profile + invalidates target agent cache |
| `get_class_levels` | `GET /class-levels` | Same as AdminAgent |
| `get_available_class_subjects` | `GET /class-subjects` | Same as AdminAgent |
| `get_teacher_subjects` | `GET /teacher/subjects` | Same as AdminAgent |
| `set_teacher_subjects` | `POST /teacher/subjects` | Same as AdminAgent |
| `get_all_initialized` | `GET /initializations` | Same as AdminAgent |
| `db_test` | `GET /db-test` | SurrealDB connectivity test |

No `profile_cache` check, no init check — superadmin is always ready.

### Phase 5: Refactor AdminAgent

- Change `#derive.agent` → add `#derive.mount("/admin/{admin_id}")`
- Add `admin_id : String` constructor param
- Remove dedicated struct fields for state — all caches go in `caches : Map[String, CacheItem]` (same trait for all agents but AdminAgent only uses `"profile"` key for now)
- Change `@config.Config[SurrealConfig]` → `@config.Config[SharedConfig]`
- Add `#derive.endpoint` annotations to all existing methods (see mapping below)
- Add `invalidate_cache(key)` RPC method
- Add auth key check via `#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")` on every endpoint
- Add cache-first init check at start of every endpoint (skip for methods that don't need it like `get_class_levels` which are admin-level queries)

Endpoint mapping:

| Current | New `@derive.endpoint` |
|---------|----------------------|
| `ping()` | `get="/ping"` |
| `initialize_user(user_id, role, class_level)` | `post="/initialize?target_user_id={target_user_id}&role={role}&class_level={class_level}"` |
| `is_user_initialized(user_id)` | `get="/check-init?target_user_id={target_user_id}"` |
| `get_all_initialized()` | `get="/initializations"` |
| `get_class_levels()` | `get="/class-levels"` |
| `get_available_class_subjects()` | `get="/class-subjects"` |
| `get_teacher_subjects(teacher_id)` | `get="/teacher/subjects?target_teacher_id={target_teacher_id}"` |
| `set_teacher_subjects(teacher_id, pairs)` | `post="/teacher/subjects?target_teacher_id={target_teacher_id}#derive.endpoint_body("pairs_json")` |
| `invalidate_cache(key)` | `post="/invalidate-cache?key={key}"` |

### Phase 6: Refactor StudentAgent

- Add `#derive.mount("/student/{student_id}")`
- Remove `initialize()` method entirely
- Remove dedicated cache fields (`subject_cache`, `terms_cache`, `lessons_cache`, `edge_cache`, `lesson_cache`) — replace with `caches : Map[String, CacheItem]`
- Change `@config.Config[SurrealConfig]` → `@config.Config[SharedConfig]`
- Add `invalidate_cache(key)` RPC method
- Add `#derive.endpoint` annotations:
  - `get_subjects()` → `get="/subjects"`
  - `get_terms()` → `get="/terms"`
  - `get_lessons(subject_id, term_id)` → `get="/lessons?subject_id={subject_id}&term_id={term_id}"`
  - `get_lesson(lesson_id)` → `get="/lesson?lesson_id={lesson_id}"`
  - `invalidate_cache(key)` → `post="/invalidate-cache?key={key}"`
- Modify `get_class_level()` to read from `caches["profile"]` instead of a direct DB query on every call
- Modify `get_subjects()` to check `caches["subjects"]`, fall back to DB, then cache
- Modify `get_terms()` to check `caches["terms:{cl}"]`, fall back to DB, then cache
- Modify `get_lessons()` to check `caches["lessons:{subj}|{term}"]`, fall back to DB using edge cache `caches["edge:{subj}"]`, then cache
- Modify `get_lesson()` to check `caches["lesson:{id}"]`, fall back to DB, then cache

### Phase 7: Refactor TeacherAgent

- Add `#derive.mount("/teacher/{teacher_id}")`
- Remove `trigger_initialize()` method entirely
- Replace `class_groups : Map[String, TeacherClassGroup]` with `caches : Map[String, CacheItem]`
- Change `@config.Config[SurrealConfig]` → `@config.Config[SharedConfig]`
- Add `invalidate_cache(key)` RPC method
- Add `#derive.endpoint` annotations:
  - `get_my_classes()` → `get="/classes"` (reads from `caches["class_groups"]`, populates via DB query on miss)
  - `get_terms()` → `get="/terms"`
  - `get_lessons(class_level_id, subject_id, term_id)` → `get="/lessons?class_level_id={class_level_id}&subject_id={subject_id}&term_id={term_id}"`
  - `invalidate_cache(key)` → `post="/invalidate-cache?key={key}"`
- Remove `invalidate_cache()` (replaced by the generic one that takes a key)

### Phase 8: Move Shared Helpers

- Move `parse_result_array()` from `student_agent.mbt` to `surreal_client.mbt`
- Move `escape_surreal_string()` from `admin_agent.mbt` to `surreal_client.mbt`
- Ensure both are `pub` so all agents can use them

### Phase 9: Agent Files to Update in moon.pkg

If `moon.pkg` explicitly lists source files, update it:
- Remove `gateway_agent.mbt`
- Add `super_admin_agent.mbt`
- Add `cache_types.mbt`

### Phase 10: Update golem.yaml

Replace the `httpApi` section:

```yaml
httpApi:
  deployments:
    local:
      - domain: agents.localhost:9006
        agents:
          SuperAdminAgent: {}
          AdminAgent: {}
          StudentAgent: {}
          TeacherAgent: {}

secretDefaults:
  local:
    authKey: "dev-auth-key-change-in-production"
    host: "{{ SURREAL_DB_HOST }}"
    ns: "{{ SURREAL_DB_NS }}"
    database: "{{ SURREAL_DB }}"
    username: "{{ SURREAL_DB_USERNAME }}"
    password: "{{ SURREAL_DB_PASSWORD }}"
```

### Phase 11: Regenerate Stubs

```bash
cd agents
moon info
moon fmt
golem app build
```

### Phase 12: Rewrite SvelteKit Proxy Layer

Replace `golem.ts`:

```typescript
import { env } from '$env/dynamic/private';

let baseUrl: string | null = null;
let authKey: string | null = null;

function getBaseUrl(): string {
  if (baseUrl) return baseUrl;
  if (!env.GOLEM_GATEWAY_URL) throw new Error('Missing GOLEM_GATEWAY_URL');
  baseUrl = env.GOLEM_GATEWAY_URL.replace(/\/+$/, '');
  return baseUrl;
}

function getAuthKey(): string {
  if (authKey) return authKey;
  if (!env.GOLEM_AUTH_KEY) throw new Error('Missing GOLEM_AUTH_KEY');
  authKey = env.GOLEM_AUTH_KEY;
  return authKey;
}

interface ProxySuccess { data: string; error?: never }
interface ProxyError { data?: never; error: { code: string; message: string } }
type ProxyResult = ProxySuccess | ProxyError;

function errorResult(code: string, message: string): ProxyResult {
  return { error: { code, message } };
}

// Check for known error strings in Golem text responses
function isErrMsg(text: string): ProxyResult | null {
  if (text === 'unauthorized') return errorResult('UNAUTHORIZED', 'Request to backend was rejected (auth key mismatch).');
  if (text === 'auth error') return errorResult('AUTH_ERROR', 'Backend encountered an error reading its auth configuration.');
  if (text === 'NOT_INITIALIZED') return errorResult('NOT_INITIALIZED', 'Account not initialized. Please contact your school administrator.');
  return null;
}

async function proxy(agentPath: string, extraParams?: Record<string, string>): Promise<ProxyResult> {
  let url = `${getBaseUrl()}${agentPath}`;
  if (extraParams) {
    const params = new URLSearchParams();
    for (const [key, value] of Object.entries(extraParams)) {
      params.set(key, value);
    }
    url += '?' + params.toString();
  }
  try {
    const res = await fetch(url, { headers: { 'X-Golem-Auth-Key': getAuthKey() } });
    const raw = await res.text();
    // Parse Result[T, String] envelope from Golem
    try {
      const parsed = JSON.parse(raw);
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        if ('Ok' in parsed) return { data: JSON.stringify(parsed.Ok) };
        if ('Err' in parsed && typeof parsed.Err === 'string') {
          const check = isErrMsg(parsed.Err);
          if (check) return check;
          return errorResult('GATEWAY_ERROR', parsed.Err);
        }
      }
    } catch { /* fall through */ }
    // Legacy string responses
    let text: string;
    try {
      const jsonParsed = JSON.parse(raw);
      text = typeof jsonParsed === 'string' ? jsonParsed : raw;
    } catch { text = raw; }
    const check = isErrMsg(text);
    if (check) return check;
    return { data: text };
  } catch (err) {
    return errorResult('PROXY_ERROR', err instanceof Error ? err.message : 'Failed to reach backend service.');
  }
}

export function proxySuperAdmin(path: string, extraParams?: Record<string, string>): Promise<ProxyResult> {
  return proxy(`/super-admin${path}`, extraParams);
}

export function proxyAdmin(path: string, adminId: string, extraParams?: Record<string, string>): Promise<ProxyResult> {
  return proxy(`/admin/${encodeURIComponent(adminId)}${path}`, extraParams);
}

export function proxyStudent(path: string, studentId: string, extraParams?: Record<string, string>): Promise<ProxyResult> {
  return proxy(`/student/${encodeURIComponent(studentId)}${path}`, extraParams);
}

export function proxyTeacher(path: string, teacherId: string, extraParams?: Record<string, string>): Promise<ProxyResult> {
  return proxy(`/teacher/${encodeURIComponent(teacherId)}${path}`, extraParams);
}
```

### Phase 13: Update All Proxy Routes

Each `+server.ts` file under `frontend/src/routes/api/` that currently calls `proxyToGateway` must be updated to import and call the correct per-role helper.

**Student routes** (`api/student/subjects`, `api/student/terms`, `api/student/lessons`, `api/student/lesson`):

```typescript
import { proxyStudent } from '$lib/server/golem';
// ...
const result = await proxyStudent('/subjects', userId);
// or: proxyStudent('/terms', userId);
// or: proxyStudent('/lessons', userId, { subject_id, term_id });
// or: proxyStudent('/lesson', userId, { lesson_id });
```

**Teacher routes** (`api/teacher/classes`, `api/teacher/terms`, `api/teacher/lessons`):

```typescript
import { proxyTeacher } from '$lib/server/golem';
// ...
const result = await proxyTeacher('/classes', userId);
// or: proxyTeacher('/terms', userId);
// or: proxyTeacher('/lessons', userId, { class_level_id, subject_id, term_id });
```

**Admin routes** (`api/admin/class-levels`, `api/admin/class-subjects`, `api/admin/initializations`, `api/admin/teacher/subjects`, `api/admin/teacher/[uuid]/subjects`, `api/admin/users/[pk]/initialize`):

Each must check `event.locals.user?.username === 'thesparq'` and use `proxySuperAdmin()` if true, otherwise `proxyAdmin()`:

```typescript
import { proxySuperAdmin, proxyAdmin } from '$lib/server/golem';

const user = event.locals.user;
const isSuperAdmin = user?.username === 'thesparq';
const adminId = user?.id;

if (isSuperAdmin) {
  result = await proxySuperAdmin('/initialize', {
    target_user_id, role, class_level
  });
} else {
  result = await proxyAdmin('/initialize', adminId, {
    target_user_id, role, class_level
  });
}
```

**Auth status route** (`api/auth/status`):

No longer calls proxyToGateway. Instead calls the appropriate agent's ping endpoint and checks for `"NOT_INITIALIZED"`:

```typescript
const isSuperAdmin = user?.username === 'thesparq';
if (isSuperAdmin) {
  // Always initialized
  return Response.json({ data: { initialized: true } });
}
// Call the agent's ping to check init
const result = await proxyStudent('/ping', userId);
// proxyTeacher or proxyAdmin depending on role
```

### Phase 14: Update Auth Status Route & Dashboard Init Guard

The dashboard's init check logic changes:
- Superadmin (`thesparq`) → always initialized
- Admin → call `proxyAdmin('/ping', adminId)` → if no error, initialized
- Student → call `proxyStudent('/ping', studentId)` → if no error, initialized
- Teacher → call `proxyTeacher('/ping', teacherId)` → if no error, initialized

The `NOT_INITIALIZED` error is returned by the agent itself (no gateway).

## Dependencies

- Golem 1.5.3+ with path-based mount variable support (`#derive.mount("/admin/{admin_id}")`)
- No new packages to install
- Build tools: `moon info`, `moon fmt`, `golem app build`

## Verification Checklist

1. **Build**: `moon build --target wasm` — 0 errors
2. **Build**: `pnpm build` — 0 errors
3. **Type check**: `pnpm check` — 0 errors (3 pre-existing warnings OK)
4. **No GatewayAgent**: `gateway_agent.mbt` deleted, no references remain
5. **SuperAdminAgent accessible**: `curl "http://agents.localhost:9006/super-admin/ping" -H "X-Golem-Auth-Key: dev-auth-key-change-in-production"` → `"super admin online"`
6. **Init check works**: First `GET /student/{id}/subjects` without `user_profile` → `"NOT_INITIALIZED"`
7. **Admin init writes DB + invalidates**: `POST /admin/{admin_id}/initialize?target_user_id=...&role=student` → writes `user_profile`, calls `invalidate_cache("profile")` on student agent
8. **Student subjects after init**: `GET /student/{id}/subjects` → returns subjects (cache populated from DB)
9. **Cache expiry**: Second call within TTL returns cached data instantly
10. **Invalidation**: `POST /student/{id}/invalidate-cache?key=subjects` → next `get_subjects()` re-fetches from DB
11. **Invalidate all**: `POST /student/{id}/invalidate-cache?key=all` → clears entire cache map
12. **Superadmin routing**: Login as `thesparq` → all admin calls hit SuperAdminAgent
13. **Normal admin routing**: Login as another admin → calls hit AdminAgent(admin_id)
14. **Teacher endpoints**: Classes, terms, lessons all return correct data
15. **Student endpoints**: Subjects, terms, lessons, lesson content all return correct data
16. **Admin endpoints**: Class-levels, class-subjects, teacher assignments all work
17. **`SharedConfig` everywhere**: No remaining `SurrealConfig` or `GatewayConfig` references
18. **No `initialize()` on StudentAgent**: Method removed, agent lazily populates caches
19. **No `trigger_initialize()` on TeacherAgent**: Method removed, `class_groups` populated on first `get_my_classes()` call
20. **`invalidate_cache(key)` RPC present**: On AdminAgent, StudentAgent, TeacherAgent
21. **`isErrMsg` still catches `NOT_INITIALIZED`**: Frontend shows correct error for uninitialized users
