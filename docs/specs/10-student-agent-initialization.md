# Unit 10 — Student Agent: Initialization and Subject List

## Goal

Implement the per‑student durable Student Agent with `initialize(classLevel)` and `getSubjects()` methods that query SurrealDB for the student's class subjects. Extend the Admin Agent activation flow to initialize student agents during activation. Add Gateway and SvelteKit proxy endpoints for subject retrieval and class‑level lookup. Add a class‑level dropdown to the admin activation UI.

## Design

### Student Agent — Per‑Student Durable Agent

Each student gets their own durable agent instance identified by `student_id` in the constructor. The Golem SDK generates typed RPC clients with `StudentAgentClient::scoped(student_id, ...)` so the Gateway and Admin Agent address the correct agent for each student.

```moonbit
#derive.agent
struct StudentAgent {
  config     : @config.Config[SurrealConfig]
  student_id : String          // constructor param — agent identity
  profile    : StudentProfile?
  subjects   : Map[String, SubjectInfo]
}
```

**State fields:**

| Field | Type | Purpose |
|---|---|---|
| `config` | `@config.Config[SurrealConfig]` | SurrealDB connection (auto‑loaded from env) |
| `student_id` | `String` | Agent identity — matches Authentik UUID |
| `profile` | `StudentProfile?` | Student's class level, set once by `initialize` |
| `subjects` | `Map[String, SubjectInfo]` | Subjects for the student's class, keyed by SurrealDB record ID |

### Types

Both types live in `student_agent.mbt` with `#derive.golem_schema` for Golem serialization (consistent with existing `ActivationStatus`/`UserActivation` pattern in `admin_agent.mbt`). The frontend defines matching TypeScript interfaces.

```moonbit
#derive.golem_schema
struct SubjectInfo {
  id   : String
  name : String
  code : String?
}

#derive.golem_schema
struct StudentProfile {
  class_level : String
}
```

### Activation Flow

```
1. Admin selects class_level "Primary 1" and clicks Activate
2. POST /api/admin/users/{uuid}/activate  { role:"student", class_level:"Primary 1" }
3. SvelteKit → /gateway/admin/activate?target_user_id=...&role=student&class_level=Primary+1
4. Gateway checks auth → AdminAgent.activate_user(target_id, "student", Some("Primary 1"))
5. AdminAgent stores activation record in durable memory
6. AdminAgent fires StudentAgentClient::scoped(target_id, fn(c) { c.trigger_initialize("Primary 1") })
   — fire‑and‑forget, best‑effort. Init failure does not roll back activation.
7. Golem creates/adresses StudentAgent(student_id=target_id)
8. StudentAgent.initialize:
   a. Stores StudentProfile { class_level } in self.profile
   b. Queries SurrealDB for class_level record ID
   c. Queries class_subjects JOIN subjects for that class_level
   d. Parses JSON response, populates self.subjects map
   e. Returns JSON summary
```

### Subject Retrieval Flow

```
1. Student visits dashboard → GET /api/student/subjects
2. SvelteKit → /gateway/student/subjects?user_id={user_id}
3. Gateway checks activation → StudentAgentClient::scoped(user_id, fn(c) { c.get_subjects() })
4. StudentAgent builds JSON array from self.subjects, returns as String
5. Gateway returns the JSON string → SvelteKit parses and nests in standard envelope
```

### Route Map

```
SvelteKit                          Gateway                              Agent
─────────                          ───────                              ─────
GET /api/student/subjects          GET /gateway/student/subjects        StudentAgent.get_subjects()
GET /api/admin/class-levels        GET /gateway/admin/class-levels      AdminAgent.get_class_levels()
POST /api/admin/users/[uuid]/activate  (class_level param added)       AdminAgent.activate_user → StudentAgent.initialize
```

### Admin Agent — New Capabilities

The Admin Agent gains `@config.Config[SurrealConfig]` so it can query SurrealDB for class levels. Its `activate_user` method now fires `StudentAgent.trigger_initialize` for student activations.

```moonbit
#derive.agent
struct AdminAgent {
  activated_users : Map[String, UserActivation]
  config          : @config.Config[SurrealConfig]
}
```

### JSON Format — SurrealDB Responses

All SurrealDB queries use the `/sql` endpoint. The JSON response shape is:

```json
[
  { "status": "OK", "time": "...", "result": [ ... ] }
]
```

The `surreal_query` function returns the raw response body as `String`. Agents parse it with `moonbitlang/core/json`.

### SubjectInfo JSON — HTTP Response Format

`get_subjects()` returns a JSON string matching:

```json
[
  { "id": "subjects:abc", "name": "Basic Science", "code": "BSC" },
  { "id": "subjects:def", "name": "Mathematics", "code": null }
]
```

### Class‑Level Dropdown in Admin UI

The admin activation page fetches class levels from `/api/admin/class-levels` and renders a `<select>` populated with the names. Selecting a class level and clicking Activate sends `class_level` in the POST body.

---

## Implementation

### 1. Add `moonbitlang/core/json` to `agents/app-agents/moon.pkg`

```moonbit
"moonbitlang/core/json" @json,
```

### 2. Rewrite `agents/app-agents/student_agent.mbt`

Full file:

```moonbit
//|
#derive.golem_schema
struct SubjectInfo {
  id   : String
  name : String
  code : String?
}

//|
#derive.golem_schema
struct StudentProfile {
  class_level : String
}

//|
/// Durable per-student agent.
/// Identified by student_id — one instance per student.
#derive.agent
struct StudentAgent {
  config     : @config.Config[SurrealConfig]
  student_id : String
  profile    : StudentProfile?
  subjects   : Map[String, SubjectInfo]
}

//|
fn StudentAgent::new(
  student_id : String,
  config     : @config.Config[SurrealConfig],
) -> StudentAgent {
  { config, student_id, profile: None, subjects: Map::new() }
}

///|
/// Tests SurrealDB connectivity.
pub fn StudentAgent::test_db(self : Self) -> String {
  match surreal_query(self.config, "SELECT * FROM 1") {
    Ok(body) => "OK: " + body
    Err(e)   => "ERROR: " + e
  }
}

///|
/// Initializes this student's profile and fetches subjects from SurrealDB.
/// Idempotent — calling again with the same class_level is a no-op update.
pub fn StudentAgent::initialize(self : Self, class_level : String) -> String {
  // 1. Store profile
  self.profile = Some(StudentProfile::{ class_level })

  // 2. Resolve class_level name → record ID
  let cl_escaped = class_level.replace("'", "\\'")
  let cl_sql = "SELECT VALUE id FROM class_levels WHERE name = '" + cl_escaped + "' LIMIT 1"
  let cl_raw = match surreal_query(self.config, cl_sql) {
    Ok(body) => body
    Err(e)   => return "ERROR: lookup class_level failed: " + e
  }

  let cl_id = match @json.from_string(cl_raw) {
    Err(_) => return "ERROR: parse class_level response failed"
    Ok(val) => {
      match val.as_array() {
        None => return "ERROR: class_level response not an array"
        Some(arr) => {
          if arr.length() == 0 { return "ERROR: class_level response empty" }
          match arr[0].as_object() {
            None => return "ERROR: class_level element not an object"
            Some(obj) => {
              match obj.get("result") {
                None => return "ERROR: class_level result missing"
                Some(r) => {
                  match r.as_array() {
                    None => return "ERROR: class_level result not an array"
                    Some(res) => {
                      if res.length() == 0 {
                        return "ERROR: class_level not found: " + class_level
                      }
                      match res[0].as_string() {
                        None => return "ERROR: class_level id not a string"
                        Some(id) => id
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // 3. Query subjects for that class
  let subj_sql = "SELECT subject_id.id, subject_id.name, subject_id.code " +
    "FROM class_subjects WHERE class_level_id = " + cl_id +
    " AND active = true ORDER BY subject_id.name ASC"
  let subj_raw = match surreal_query(self.config, subj_sql) {
    Ok(body) => body
    Err(e)   => return "ERROR: query subjects failed: " + e
  }

  // 4. Parse subjects JSON → populate self.subjects
  let parsed = match @json.from_string(subj_raw) {
    Err(e) => return "ERROR: parse subjects response: " + e
    Ok(v) => v
  }

  let result_arr = match parsed.as_array() {
    None => return "ERROR: subjects response not an array"
    Some(a) => {
      if a.length() == 0 { return "ERROR: subjects response empty" }
      match a[0].as_object() {
        None => return "ERROR: subjects element not an object"
        Some(obj) => {
          match obj.get("result") {
            None => return "ERROR: subjects result missing"
            Some(r) => {
              match r.as_array() {
                None => return "ERROR: subjects result not an array"
                Some(arr) => arr
              }
            }
          }
        }
      }
    }
  }

  for item in result_arr {
    match item.as_object() {
      None => ()
      Some(obj) => {
        match obj.get("subject_id") {
          None => ()
          Some(subj_val) => {
            match subj_val.as_object() {
              None => ()
              Some(subj) => {
                let id = match subj.get("id") { None => continue; Some(v) => match v.as_string() { None => continue; Some(s) => s } }
                let name = match subj.get("name") { None => continue; Some(v) => match v.as_string() { None => continue; Some(s) => s } }
                let code = match subj.get("code") { None => None; Some(v) => v.as_string() }
                self.subjects.set(id, SubjectInfo::{ id, name, code })
              }
            }
          }
        }
      }
    }
  }

  // 5. Return JSON summary
  "OK"
}

///|
/// Returns this student's subjects as a JSON array string.
/// Returns "[]" if the student has not been initialized.
pub fn StudentAgent::get_subjects(self : Self) -> String {
  let items = self.subjects.iter().map(fn(pair) {
    let (_id, info) = pair
    let code_str = match info.code {
      None => "null"
      Some(c) => "\"" + c.replace("\"", "\\\"") + "\""
    }
    "{\"id\":\"" + info.id.replace("\"", "\\\"") + "\"," +
    "\"name\":\"" + info.name.replace("\"", "\\\"") + "\"," +
    "\"code\":" + code_str + "}"
  }).collect()
  "[" + items.join(",") + "]"
}

//|
fn main {}
```

### 3. Update `agents/app-agents/admin_agent.mbt`

**Add config field and update constructor:**

```moonbit
//|
/// Central registry agent — durable singleton.
#derive.agent
struct AdminAgent {
  activated_users : Map[String, UserActivation]
  config          : @config.Config[SurrealConfig]
}

//|
fn AdminAgent::new(config : @config.Config[SurrealConfig]) -> AdminAgent {
  { activated_users: Map::new(), config }
}
```

**Add `get_class_levels` method:**

```moonbit
///|
/// Returns all active class levels as a JSON array string.
pub fn AdminAgent::get_class_levels(self : Self) -> String {
  let sql = "SELECT id, name FROM class_levels WHERE active = true ORDER BY name ASC"
  let raw = match surreal_query(self.config, sql) {
    Ok(body) => body
    Err(e)   => return "ERROR: " + e
  }

  match @json.from_string(raw) {
    Err(_) => "ERROR: parse class_levels response failed"
    Ok(val) => {
      let arr = match val.as_array() { None => return "[]"; Some(a) => a }
      if arr.length() == 0 { return "[]" }
      let result_arr = match arr[0].as_object() {
        None => return "[]"
        Some(obj) => match obj.get("result") {
          None => return "[]"
          Some(r) => match r.as_array() { None => return "[]"; Some(a) => a }
        }
      }
      let items = result_arr.map(fn(item) {
        let obj = item.as_object()
        let id = match obj { None => ""; Some(o) => match o.get("id") { None => ""; Some(v) => match v.as_string() { None => ""; Some(s) => s } } }
        let name = match obj { None => ""; Some(o) => match o.get("name") { None => ""; Some(v) => match v.as_string() { None => ""; Some(s) => s } } }
        "{\"id\":\"" + id.replace(old="\"", new="\\\"") + "\",\"name\":\"" + name.replace(old="\"", new="\\\"") + "\"}"
      })
      "[" + items.join(",") + "]"
    }
  }
}
```

**Update `activate_user` to fire StudentAgent init for students:**

```moonbit
///|
/// Activates a user. For students with a class_level, fire-and-forget
/// initializes the Student Agent (best-effort; does not fail activation).
pub fn AdminAgent::activate_user(
  self        : Self,
  user_id     : String,
  role        : String,
  class_level : String?,
) -> Result[String, String] {
  if !["admin", "teacher", "student"].contains(role) {
    return Err("invalid role: \{role}")
  }
  let now = @wallClock.now()
  let record = UserActivation::{
    user_id, role, status: Active, class_level, activated_at: now.seconds,
  }
  self.activated_users.set(user_id, record)

  if role == "student" {
    match class_level {
      Some(cl) => {
        let _ = StudentAgentClient::scoped(user_id, fn(client) raise @common.AgentError {
          client.trigger_initialize(cl)
        }) catch { _ => () }
      }
      None => ()
    }
  }

  Ok("ok")
}
```

Existing methods `ping`, `is_user_active`, `deactivate_user`, `get_all_activations` remain unchanged.

### 4. Add Gateway endpoints in `agents/app-agents/gateway_agent.mbt`

**Add `/gateway/student/subjects`:**

```moonbit
///|
/// Returns the authenticated student's subjects as a JSON array string.
/// Requires activation check.
#derive.endpoint(get="/student/subjects?user_id={user_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::student_subjects(
  self         : Self,
  incoming_key : String,
  user_id      : String,
) -> String {
  match self.check_auth(incoming_key) {
    Some(msg) => return msg
    None => ()
  }
  let status = AdminAgentClient::scoped(fn(admin) raise @common.AgentError {
    admin.is_user_active(user_id)
  }) catch {
    _ => return "admin unreachable"
  }
  if status != Active { return "NOT_ACTIVATED" }

  StudentAgentClient::scoped(user_id, fn(student) raise @common.AgentError {
    student.get_subjects()
  }) catch {
    _ => "ERROR: student agent unreachable"
  }
}
```

**Add `/gateway/admin/class-levels`:**

```moonbit
///|
/// Returns all active class levels as a JSON array string.
/// Requires valid X-Golem-Auth-Key header.
#derive.endpoint(get="/admin/class-levels?user_id={admin_user_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::list_class_levels(
  self          : Self,
  incoming_key  : String,
  admin_user_id : String,
) -> String {
  match self.check_auth(incoming_key) {
    Some(msg) => return msg
    None => ()
  }
  AdminAgentClient::scoped(fn(admin) raise @common.AgentError {
    admin.get_class_levels()
  }) catch {
    _ => "admin unreachable"
  }
}
```

**Extend `/gateway/admin/activate` with class_level:**

```moonbit
#derive.endpoint(get="/admin/activate?user_id={admin_user_id}&target_user_id={target_user_id}&role={role}&class_level={class_level}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::activate_admin(
  self           : Self,
  incoming_key   : String,
  admin_user_id  : String,
  target_user_id : String,
  role           : String,
  class_level    : String?,
) -> String {
  match self.check_auth(incoming_key) {
    Some(msg) => return msg
    None => ()
  }
  match AdminAgentClient::scoped(fn(admin) raise @common.AgentError {
    admin.activate_user(target_user_id, role, class_level)
  }) catch {
    _ => return "admin unreachable"
  } {
    Ok(_) => "OK"
    Err(msg) => msg
  }
}
```

**Update `/gateway/db-test` to pass a student_id:**

The existing `db_test` endpoint calls `StudentAgentClient::scoped(fn(student) { student.test_db() })` which no longer compiles after the StudentAgent constructor requires `student_id`. Update it to accept a `user_id` query param:

```moonbit
#derive.endpoint(get="/db-test?user_id={user_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::db_test(self : Self, incoming_key : String, user_id : String) -> String {
  match self.check_auth(incoming_key) {
    Some(msg) => return msg
    None => ()
  }
  StudentAgentClient::scoped(user_id, fn(student) raise @common.AgentError {
    student.test_db()
  }) catch {
    _ => "ERROR: student agent unreachable"
  }
}
```

### 5. Create `/api/student/subjects` SvelteKit proxy

`frontend/src/routes/api/student/subjects/+server.ts`:

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

	const result = await proxyToGateway('/gateway/student/subjects', userId);

	if (result.error) {
		const status = result.error.code === 'NOT_ACTIVATED' ? 403 : 502;
		return new Response(JSON.stringify(result), { status, headers: { 'content-type': 'application/json' } });
	}

	// result.data is a JSON array string (double-parsed by proxyToGateway already)
	// Parse it to produce the final array
	const subjects = JSON.parse(result.data);

	return new Response(
		JSON.stringify({ data: subjects }),
		{ status: 200, headers: { 'content-type': 'application/json' } }
	);
};
```

### 6. Create `/api/admin/class-levels` SvelteKit proxy

`frontend/src/routes/api/admin/class-levels/+server.ts`:

```typescript
import { proxyToGateway } from '$lib/server/golem';
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

export const GET: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user) error(401, 'Not authenticated');
	if (!user.roles.includes('admin')) error(403, 'Forbidden');

	const result = await proxyToGateway('/gateway/admin/class-levels', user.id);

	if (result.error) {
		return new Response(JSON.stringify(result), {
			status: 502,
			headers: { 'content-type': 'application/json' }
		});
	}

	const classLevels = JSON.parse(result.data);

	return new Response(
		JSON.stringify({ data: classLevels }),
		{ status: 200, headers: { 'content-type': 'application/json' } }
	);
};
```

### 7. Extend activate route — accept `class_level`

Update `frontend/src/routes/api/admin/users/[uuid]/activate/+server.ts`:

```typescript
import { proxyToGateway } from '$lib/server/golem';
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

export const POST: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user) error(401, 'Not authenticated');
	if (!user.roles.includes('admin')) error(403, 'Forbidden');

	const targetUserId = event.params.uuid;
	if (!targetUserId) error(400, 'Missing uuid in request path');

	const body = await event.request.json().catch(() => ({}));
	const role: string = body.role || 'student';
	const classLevel: string | undefined = body.class_level;

	const extraParams: Record<string, string> = {
		target_user_id: targetUserId,
		role
	};
	if (classLevel) {
		extraParams.class_level = classLevel;
	}

	const result = await proxyToGateway('/gateway/admin/activate', user.id, extraParams);

	if (result.error) {
		return new Response(JSON.stringify(result), {
			status: 502,
			headers: { 'content-type': 'application/json' }
		});
	}

	return new Response(
		JSON.stringify({ data: { activated: true } }),
		{ status: 200, headers: { 'content-type': 'application/json' } }
	);
};
```

### 8. Add class-level dropdown to admin users page

Update `frontend/src/routes/(auth)/admin/users/+page.svelte`:

**Script section — add state and loader:**

```typescript
interface ClassLevel {
	id: string;
	name: string;
}

let classLevels = $state<ClassLevel[]>([]);
let selectedClassLevel = $state<string>('');

async function loadClassLevels() {
	try {
		const res = await fetch('/api/admin/class-levels');
		const body = await res.json();
		if (body.data) {
			classLevels = body.data;
		}
	} catch {
		classLevels = [];
	}
}

$effect(() => {
	loadClassLevels();
});
```

**Update `handleActivate` to use selected class_level — change the fetch body:**

```typescript
async function handleActivate(pk: number) {
	const userObj = getUser(pk);
	if (!userObj) return;
	const originalStatus = userObj.activationStatus;

	actionStates = { ...actionStates, [pk]: 'loading' };
	actionErrors = { ...actionErrors, [pk]: '' };

	users = users.map(u => u.pk === pk ? { ...u, activationStatus: 'active' } : u);

	try {
		const res = await fetch(`/api/admin/users/${userObj.uuid}/activate`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({
				role: 'student',
				...(selectedClassLevel ? { class_level: selectedClassLevel } : {})
			})
		});
		const body = await res.json();
		if (!res.ok || body.error) {
			throw new Error(body.error?.message || 'Activation failed');
		}
	} catch (err) {
		users = users.map(u =>
			u.pk === pk ? { ...u, activationStatus: originalStatus } : u
		);
		actionErrors = { ...actionErrors, [pk]: err instanceof Error ? err.message : 'Activation failed' };
	} finally {
		actionStates = { ...actionStates, [pk]: 'idle' };
	}
}
```

**Template — replace the Activate button section:**

Inside the `Actions` table cell (`{@html user.activationStatus === 'active' ? ... : ...}` block), replace the `{:else}` branch:

```svelte
{:else}
	<div class="flex flex-col gap-1.5">
		{#if classLevels.length > 0}
			<select
				class="w-full rounded border border-surface-200 bg-surface-50 px-2 py-1 text-xs text-surface-800"
				bind:value={selectedClassLevel}
			>
				<option value="">Select class…</option>
				{#each classLevels as cl}
					<option value={cl.name}>{cl.name}</option>
				{/each}
			</select>
		{/if}
		<Button
			variant="default"
			size="sm"
			onclick={() => handleActivate(user.pk)}
			disabled={actionStates[user.pk] === 'loading'}
		>
			{actionStates[user.pk] === 'loading' ? '...' : 'Activate'}
		</Button>
	</div>
{/if}
```



### 9. Regenerate Golem clients and build

```bash
cd agents

# Regenerate re-exports and agent stubs
.mooncakes/golemcloud/golem_sdk_tools/golem-sdk-tools reexports \
  .mooncakes/golemcloud/golem_sdk ./app-agents

.mooncakes/golemcloud/golem_sdk_tools/golem-sdk-tools agents .

# Type-check
moon check --target wasm

# Build WASM
golem build

# Format and info
moon info && moon fmt

# Frontend
cd ../frontend
pnpm build
pnpm check
```

---

## Dependencies

| Package | Action | Purpose |
|---|---|---|
| `moonbitlang/core/json` | Add to `agents/app-agents/moon.pkg` as `@json` | Parse SurrealDB JSON responses in agent code |
| None (npm) | — | No new npm packages or shadcn-svelte components needed |

---

## Verification Checklist

### Agent Layer — Student Agent
- [ ] `moon check --target wasm` succeeds (zero errors)
- [ ] `golem build` succeeds
- [ ] `moon info && moon fmt` runs clean in `agents/`
- [ ] `StudentAgent::new()` initializes `profile` as `None`, `subjects` as empty `Map`
- [ ] `StudentAgent::initialize("Primary 1")` stores profile, fetches subjects from SurrealDB
- [ ] `StudentAgent::initialize("Nonexistent")` returns error string `"ERROR: class_level not found: Nonexistent"`
- [ ] `StudentAgent::initialize` is idempotent (second call overwrites state, no error)
- [ ] `StudentAgent::get_subjects()` returns JSON array after initialization
- [ ] `StudentAgent::get_subjects()` on uninitialized agent returns `"[]"`
- [ ] JSON returned by `get_subjects()` parses as valid JSON and contains `id`, `name`, `code` fields
- [ ] `code` is `null` in JSON when the `SubjectInfo.code` is `None`
- [ ] Two different student agents maintain independent state

### Agent Layer — Admin Agent
- [ ] `AdminAgent::new(config)` now accepts `@config.Config[SurrealConfig]`
- [ ] `AdminAgent::get_class_levels()` returns JSON array of active class levels
- [ ] `AdminAgent::activate_user("u1", "student", Some("Primary 1"))` stores activation AND calls `StudentAgentClient::scoped(u1, ...)` with `trigger_initialize`
- [ ] `AdminAgent::activate_user("u1", "teacher", None)` does NOT fire StudentAgent init
- [ ] `AdminAgent::activate_user("u1", "admin", None)` does NOT fire StudentAgent init
- [ ] Init failure does not roll back activation (best-effort)

### Agent Layer — Gateway
- [ ] `/gateway/student/subjects` returns subjects JSON for activated student
- [ ] `/gateway/student/subjects` returns `"NOT_ACTIVATED"` for inactive user
- [ ] `/gateway/student/subjects` checks auth first (returns `"unauthorized"` on mismatch)
- [ ] `/gateway/student/subjects` addresses the correct student agent via `scoped(user_id, ...)`
- [ ] `/gateway/admin/class-levels` returns JSON array for admin user
- [ ] `/gateway/admin/class-levels` checks auth
- [ ] `/gateway/admin/activate` accepts `class_level` query param and passes it through
- [ ] `/gateway/admin/activate` without `class_level` passes `None` (backward compatible)
- [ ] `/gateway/db-test` updated to accept `user_id` and passes it to StudentAgentClient::scoped

### SvelteKit Proxy Layer
- [ ] `pnpm build` succeeds (zero errors)
- [ ] `pnpm check` passes (zero errors)
- [ ] `GET /api/student/subjects` returns `{ data: [...] }` with subjects for activated student
- [ ] `GET /api/student/subjects` returns 403 with `NOT_ACTIVATED` for inactive user
- [ ] `GET /api/student/subjects` returns 401 for unauthenticated request
- [ ] `GET /api/admin/class-levels` returns `{ data: [...] }` for admin user
- [ ] `GET /api/admin/class-levels` returns 403 for non-admin user
- [ ] `POST /api/admin/users/[uuid]/activate` without `class_level` still works
- [ ] `POST /api/admin/users/[uuid]/activate` with `class_level` passes it to Gateway

### Admin Users Page
- [ ] Class levels load into a dropdown when activating a student
- [ ] Selecting a class level and clicking Activate sends `class_level` in POST body
- [ ] Activating without a class level selected still works
- [ ] Existing activate/deactivate optimistic updates unchanged
- [ ] Existing status badges, error states, loading skeletons unchanged

### Regression
- [ ] Existing `/api/ping` route unchanged (now passes user_id to Gateway which passes to StudentAgent — verify it still returns results for active users)
- [ ] Existing `/api/db-test`, `/api/auth/status` unchanged
- [ ] Existing admin deactivate flow unchanged
- [ ] Existing admin activations list unchanged
- [ ] Existing dashboard not-activated error state unchanged
- [ ] Existing `proxyToGateway` calls without `extraParams` still work
- [ ] Existing login/logout flow unchanged
- [ ] Auth guard (`+layout.server.ts`) unchanged
- [ ] `hooks.server.ts` unchanged
- [ ] `docs/progress-tracker.md` updated: Unit 10 marked as completed
