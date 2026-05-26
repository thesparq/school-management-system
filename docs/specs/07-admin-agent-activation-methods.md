# Unit 7 — Admin Agent: Activation Methods

## Goal

Add `activateUser` and `isUserActive` methods to the Admin Agent using Golem's
in-memory durable state (agent struct fields), and extend the Gateway Agent to
check activation before forwarding any request, returning `NOT_ACTIVATED` for
non-active users. Testable via the existing `/api/ping` proxy route and
`golem invoke` CLI.

## Design

### Storage Model Change

**Before (architecture.md, code-standards.md):** Agent-local SQLite with
idempotent schema migrations, table definitions per agent type.

**After:** Each durable agent stores its state in MoonBit struct fields. Golem's
durable execution op-log persists these fields across restarts and replays. No
external database, no migration scripts — new fields are added with safe
defaults.

This affects the Admin Agent immediately and will be applied to Student and
Teacher agents in later units. The context files (`architecture.md`,
`code-standards.md`, `project-overview.md`, `00-build-plan.md`) are updated
alongside this spec.

### Shared Types (in `shared/src/types.mbt`)

```moonbit
enum ActivationStatus {
  NotFound
  Active
  Suspended
  Deactivated
}

struct UserActivation {
  user_id : String
  role : String
  status : ActivationStatus
  class_level : String?
  activated_at : UInt64
}
```

Both types require `#derive(golem_schema)` for Golem serialization.

`ActivationStatus` uses 4 variants so the Gateway Agent can distinguish
"never activated" from "explicitly suspended/deactivated" in the future.
For Unit 7, only `NotFound` and `Active` are produced; `Suspended` and
`Deactivated` are placeholder variants for later units.

### Admin Agent State

```moonbit
#derive.agent
struct AdminAgent {
  activated_users : Map[String, UserActivation]
}
```

Initialised as an empty map in `AdminAgent::new()`.

| Method | Signature | Behaviour |
|---|---|---|
| `activate_user` | `(Self, String, String, String?) -> Result[String, String]` | Upsert: creates or updates the record, sets `status = Active`, stores `activated_at` as wall-clock seconds. Returns `Ok("ok")` on success, `Err(String)` for invalid role. |
| `is_user_active` | `(Self, String) -> ActivationStatus` | Looks up `user_id` in map; returns `NotFound` if absent, otherwise the stored status. No error path. |

The `role` parameter accepts `"admin"`, `"teacher"`, or `"student"`. An
unknown role returns `Err("invalid role: {role}")`.

`class_level` is optional — meaningful for students, may be `None` for
admins and teachers.

### Gateway Agent Changes

The single endpoint `GET /gateway/ping/{user_id}` gains a `user_id` path parameter declared directly in the endpoint path.

Request flow:
1. Check `X-Golem-Auth-Key` header (existing behaviour).
2. If auth fails → return `"unauthorized"` (existing).
3. Call `AdminAgentClient::scoped(fn(admin) { admin.is_user_active(user_id) })`.
4. If result is not `Active` → return plain string `"NOT_ACTIVATED"`.
5. Otherwise → call `AdminAgentClient::scoped(fn(admin) { admin.ping() })` and return the result.

The gateway returns plain strings, not JSON. The SvelteKit proxy layer handles
translation to HTTP status codes and structured JSON bodies.

### SvelteKit Proxy Changes

The existing `proxyToGateway` helper in `frontend/src/lib/server/golem.ts`
already handles `"unauthorized"` and `"auth error"` as special strings.
A third check is added for `"NOT_ACTIVATED"`:

```typescript
if (text === 'NOT_ACTIVATED') {
  return {
    error: {
      code: 'NOT_ACTIVATED',
      message: 'Account not activated. Please contact your school administrator.'
    }
  };
}
```

The `/api/ping` route itself is unchanged — it already calls `proxyToGateway`
and returns the result.

### Activation Testing Flow

```
# Before activation (user "test123" not in Admin Agent)
curl -H "X-Golem-Auth-Key: dev-key" \
  "http://agents.localhost:9006/gateway/ping/test123"
→ "NOT_ACTIVATED"

# Via SvelteKit proxy (unactivated user)
GET /api/ping  (authenticated as test123)
→ 403 { error: { code: "NOT_ACTIVATED", message: "Account not activated..." } }

# Activate user via direct CLI
golem invoke AdminAgent activate_user "test123" "student" "M1"
→ (success)

# After activation
curl -H "X-Golem-Auth-Key: dev-key" \
  "http://agents.localhost:9006/gateway/ping/test123"
→ "admin online"
```

## Implementation

### 1. Add shared types — `shared/src/types.mbt`

Create/replace the file with:

```moonbit
#derive.golem_schema
enum ActivationStatus {
  NotFound
  Active
  Suspended
  Deactivated
} derive(Eq)

#derive.golem_schema
struct UserActivation {
  user_id : String
  role : String
  status : ActivationStatus
  class_level : String?
  activated_at : UInt64
}
```

The `shared` module must compile to both `wasm-gc` (Golem) and `js`
(SvelteKit). The existing `moon.mod.json` and `moon.pkg.json` in `shared/`
should already support both; verify after adding the `golem_schema` derive.

### 2. Rewrite Admin Agent — `agents/app-agents/admin_agent.mbt`

**Struct definition:**

```moonbit
#derive.agent
struct AdminAgent {
  activated_users : Map[String, UserActivation]
}
```

**Constructor:**

```moonbit
fn AdminAgent::new() -> AdminAgent {
  AdminAgent::{
    activated_users: Map::new()
  }
}
```

**`activate_user` method:**

```moonbit
pub fn AdminAgent::activate_user(
  self : Self,
  user_id : String,
  role : String,
  class_level : String?
) -> Result[String, String] {
  let valid_roles = ["admin", "teacher", "student"]
  if !valid_roles.contains(role) {
    return Err("invalid role: \{role}")
  }
  let now = @wallClock.now()
  let record = UserActivation::{
    user_id,
    role,
    status: Active,
    class_level,
    activated_at: now.seconds
  }
  self.activated_users.set(user_id, record)
  Ok("ok")
}
```

Note: `@wallClock` is already imported in `moon.pkg`.

**`is_user_active` method:**

```moonbit
pub fn AdminAgent::is_user_active(self : Self, user_id : String) -> ActivationStatus {
  match self.activated_users.get(user_id) {
    None => NotFound
    Some(record) => record.status
  }
}
```

**Existing `ping` method** remains unchanged.

### 3. Update Gateway Agent — `agents/app-agents/gateway_agent.mbt`

**Modified `ping` signature:**

```moonbit
#derive.endpoint(get="/ping/{user_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::ping(
  self : Self,
  incoming_key : String,
  user_id : String,
) -> String {
  // 1. Check auth
  match self.check_auth(incoming_key) {
    Some(msg) => return msg
    None => ()
  }

  // 2. Check activation via Admin Agent RPC
  let status = AdminAgentClient::scoped(fn(admin) raise @common.AgentError {
    admin.is_user_active(user_id)
  })

  if status != Active {
    return "NOT_ACTIVATED"
  }

  // 3. Forward to Admin Agent ping
  AdminAgentClient::scoped(fn(admin) raise @common.AgentError {
    admin.ping()
  })
}
```

The `{user_id}` syntax in the endpoint path binds the last URL segment to
the MoonBit `user_id` parameter. Golem extracts path parameters automatically
when declared in the URL pattern with `{var}` syntax. The SvelteKit proxy
embeds the user_id as the final path segment in every request URL.

### 4. Update SvelteKit proxy — `frontend/src/lib/server/golem.ts`

Insert between the `"auth error"` check and `return { data: text }`:

```typescript
if (text === 'NOT_ACTIVATED') {
  return {
    error: {
      code: 'NOT_ACTIVATED',
      message:
        'Account not activated. Please contact your school administrator.'
    }
  };
}
```

This follows the existing pattern where the gateway returns a plain string
and the proxy translates it to a structured error. The proxy should return
HTTP 403 (Forbidden) for `NOT_ACTIVATED` responses, matching the 403 shown
in the testing examples. No route changes needed to `/api/ping` — it already
returns the proxy result as-is.

### 5. Update moon.pkg (if needed)

The `agents/app-agents/moon.pkg` already imports `@wallClock` — verify
that `@wallClock` is available. The existing imports should suffice; no new
dependencies required.

### 6. Build and verify

```bash
cd agents

# Generate re-exports and agent stubs
.mooncakes/golemcloud/golem_sdk_tools/golem-sdk-tools reexports \
  .mooncakes/golemcloud/golem_sdk ./app-agents

.mooncakes/golemcloud/golem_sdk_tools/golem-sdk-tools agents .

# Build WASM
moon build --target wasm

# Embed and componentize
wasm-tools component embed \
  .mooncakes/golemcloud/golem_sdk/wit \
  ./_build/wasm/debug/build/app-agents/app-agents.wasm \
  --encoding utf16 \
  --output ./_build/wasm/debug/app_agents.embed.wasm

wasm-tools component new \
  ./_build/wasm/debug/app_agents.embed.wasm \
  --output ./_build/wasm/debug/app_agents.agent.wasm

# Build frontend
cd ../frontend
pnpm build
pnpm check
```

Run `moon info && moon fmt` in `agents/` and `shared/` before finalizing.

## Dependencies

| Package | Action | Purpose |
|---|---|---|
| None | — | No new packages. All required imports (`@wallClock`, `@common`, `AdminAgentClient`, typed RPC) are already in the project from Unit 4. |

## Verification Checklist

- [ ] `moon build --target wasm` succeeds in `agents/` (zero errors)
- [ ] `pnpm build` succeeds in `frontend/` (zero errors)
- [ ] `pnpm check` (svelte-check) passes (zero errors)
- [ ] `moon info && moon fmt` runs clean in both `shared/` and `agents/`
- [ ] `AdminAgent::new()` initialises `activated_users` as an empty `Map`
- [ ] `activate_user("u1", "student", Some("M1"))` returns `Ok("ok")` and stores record with `status = Active`
- [ ] `activate_user("u1", "student", Some("M1"))` is idempotent (second call overwrites, no error)
- [ ] `activate_user("u2", "invalid_role", None)` returns `Err("invalid role: invalid_role")`
- [ ] `is_user_active("u1")` returns `Active` after activation
- [ ] `is_user_active("nonexistent")` returns `NotFound`
- [ ] `is_user_active` on a suspended/deactivated user returns the stored status (future-proof)
- [ ] Gateway `ping` without auth header returns `"unauthorized"` (unchanged)
- [ ] Gateway `ping` with wrong auth key returns `"unauthorized"` (unchanged)
- [ ] Gateway `ping` with valid auth + inactive user returns `"NOT_ACTIVATED"`
- [ ] Gateway `ping` with valid auth + active user returns `"admin online"`
- [ ] Gateway `ping` when Admin Agent RPC fails returns `"admin unreachable"` (unchanged)
- [ ] SvelteKit `/api/ping` for unactivated user returns `{ error: { code: "NOT_ACTIVATED", message: "Account not activated. Please contact your school administrator." } }` with 403 status
- [ ] SvelteKit `/api/ping` for activated user returns `{ data: "admin online" }` with 200 status
- [ ] `proxyToGateway` distinguishes `NOT_ACTIVATED` from `unauthorized` and `auth error`
- [ ] Existing dashboard "Test Connection" button still works (admin agent must be activated first, or ping route updated — verify)
- [ ] No new MoonBit packages, npm packages, or shadcn-svelte components added
- [ ] Context files updated: `architecture.md`, `code-standards.md`, `project-overview.md`, `00-build-plan.md`
- [ ] `docs/progress-tracker.md` updated: Unit 7 marked as completed
- [ ] Auth flow not modified — `hooks.server.ts` unchanged
- [ ] All existing routes, proxy helpers, and dashboard page unchanged
