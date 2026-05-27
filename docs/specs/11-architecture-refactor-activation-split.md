# Unit 11 — Architecture Refactor: Activation → Initialization Split

## Goal

Refactor the codebase to split the conflated "activation" concept into two independent concerns: **initialization** (Golem-side agent creation, managed by Admin Agent) and **activation** (Authentik-side login permission, managed via SvelteKit API calls to Authentik). The Admin Agent singleton no longer tracks activation state — it tracks initialization state only. The admin users page is restructured into role-based sub-pages under a "Users" sidebar section. Update all context files and the build plan to reflect the new model.

## Design

### Conceptual Split

| Before (conflated) | After (split) |
|---|---|
| `ActivationStatus` enum (Active/Suspended/Deactivated/NotFound) | Removed entirely — no Golem-level status |
| `UserActivation` struct with status field | `UserInitialization` struct — just stores role, class_level, initialized_at |
| `activate_user` creates agent + tracks status | `initialize_user` creates agent only (no status) |
| `is_user_active` returns status enum | `is_user_initialized` returns bool |
| `deactivate_user` changes Golem status | Removed — deactivation is Authentik's job |
| `NOT_ACTIVATED` error from gateway | `NOT_INITIALIZED` error from gateway |
| Admin page: single "Activation" column | Admin page: two columns — "Authentik Status" + "Init Status" |

### Gateway Auth Strategy

Admin endpoints (`/gateway/admin/*`) check only `X-Golem-Auth-Key`. No init check — admin users share the singleton Admin Agent and don't need initialization. SvelteKit role guard is the sole admin gate. User-facing endpoints (`/gateway/ping/*`, `/gateway/student/*`, `/gateway/check-initialization`) check `is_user_initialized` before proxying.

### Sidebar Structure

A new **Users** sidebar section (using shadcn-svelte `SidebarGroup` + `SidebarGroupLabel`) groups three role-based sub-pages under the admin area:

```
Dashboard
LMS
Admin
Users                ← SidebarGroupLabel "Users"
├── Students         ← /admin/users/students
├── Teachers         ← /admin/users/teachers
└── Admin            ← /admin/users/admin
```

Each sub-page renders the same user table component, filtered by Authentik group membership. The route path determines which tab is active and which group filter is applied.

### Route Structure

```
src/routes/(auth)/
├── admin/
│   └── users/
│       ├── +layout.server.ts       # Auth guard — admin role check
│       ├── +layout.svelte           # Shared layout — sidebar nav indicators
│       ├── students/
│       │   └── +page.server.ts      # Student user list
│       └── teachers/
│           └── +page.server.ts      # Teacher user list
│       └── admin-role/
│           └── +page.server.ts      # Admin/bursar user list
```

Or alternatively use a single page with route params (`/admin/users/[role]`) and a catch-all route. Prefer separate route groups for clarity — each `+page.server.ts` loads the same data but filters differently.

### Admin Page Layout (per role tab)

Columns per table:

| Column | Source | Notes |
|--------|--------|-------|
| Name | Authentik API (`fetchAllUsers`) | — |
| Email | Authentik API | — |
| Authentik Status | `user.is_active` from API | Badge: "Active" / "Inactive" |
| Init Status | Admin Agent `get_all_initialized` | Badge: "Initialized" / "Pending" |
| Actions | Mixed | See below |

**Actions per user state:**

| Authentik Status | Init Status | Available Actions |
|---|---|---|
| Active | Initialized | Deactivate (Authentik), Reset Password, Add/Remove Group |
| Active | Pending | Deactivate (Authentik), Reset Password, Add/Remove Group, **Initialize** (with class dropdown for students) |
| Inactive | Initialized | Activate (Authentik), Reset Password, Add/Remove Group |
| Inactive | Pending | Activate (Authentik), **Initialize** (with class dropdown for students) |

Optimistic updates on all actions with rollback on error.

---

## Implementation

### 1. Update shared types — `shared/src/types.mbt`

Remove `ActivationStatus` enum entirely. Rename `UserActivation` -> `UserInitialization`:

```moonbit
#derive.golem_schema
struct UserInitialization {
  user_id        : String
  role           : String
  class_level    : String?
  initialized_at : UInt64
} derive(Eq)
```

No status field. No enum. The Admin Agent's map becomes `Map[String, UserInitialization]`.

### 2. Rewrite Admin Agent — `agents/app-agents/admin_agent.mbt`

```moonbit
#derive.agent
struct AdminAgent {
  initialized_users : Map[String, UserInitialization]
  config            : @config.Config[SurrealConfig]
}
```

**Constructor:**
```moonbit
fn AdminAgent::new(config : @config.Config[SurrealConfig]) -> AdminAgent {
  { initialized_users: Map::new(), config }
}
```

**`initialize_user`:**
```moonbit
pub fn AdminAgent::initialize_user(
  self        : Self,
  user_id     : String,
  role        : String,
  class_level : String?,
) -> Result[String, String] {
  if !["admin", "teacher", "student"].contains(role) {
    return Err("invalid role: \{role}")
  }
  let now = @wallClock.now()
  let record = UserInitialization::{
    user_id, role, class_level, initialized_at: now.seconds,
  }
  self.initialized_users.set(user_id, record)

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

**`is_user_initialized`:**
```moonbit
pub fn AdminAgent::is_user_initialized(self : Self, user_id : String) -> Bool {
  self.initialized_users.contains(user_id)
}
```

**`get_all_initialized`:**
```moonbit
pub fn AdminAgent::get_all_initialized(self : Self) -> List[(String, String)] {
  self.initialized_users.iter().map(fn((id, record)) {
    (id, record.role)
  }).to_list()
}
```

**Removed methods:** `deactivate_user`, `get_all_activations`.

**Unchanged methods:** `ping`, `get_class_levels`.

### 3. Update Gateway Agent — `agents/app-agents/gateway_agent.mbt`

**Rename endpoints and update logic:**

| Old | New |
|-----|-----|
| `ping` — checks `is_user_active`, returns `"NOT_ACTIVATED"` | Checks `is_user_initialized`, returns `"NOT_INITIALIZED"` |
| `check_activation` — calls `is_user_active` | Rename to `check_initialization` — calls `is_user_initialized`, returns `"OK"` or `"NOT_INITIALIZED"` |
| `activate_admin` — calls `activate_user` | Rename to `initialize_admin` — calls `initialize_user` |
| `deactivate_admin` — calls `deactivate_user` | **Remove** |
| `list_activations` — text serialization | Rename to `list_initializations` — returns JSON array |
| `student_subjects` — checks `is_user_active` | Checks `is_user_initialized`, returns `"NOT_INITIALIZED"` |

**Example: updated ping endpoint:**
```moonbit
#derive.endpoint(get="/ping/{user_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::ping(
  self : Self,
  incoming_key : String,
  user_id : String,
) -> String {
  match self.check_auth(incoming_key) {
    Some(msg) => return msg
    None => ()
  }
  let initialized = AdminAgentClient::scoped(fn(admin) raise @common.AgentError {
    admin.is_user_initialized(user_id)
  })
  if !initialized {
    return "NOT_INITIALIZED"
  }
  AdminAgentClient::scoped(fn(admin) raise @common.AgentError {
    admin.ping()
  })
}
```

**Example: new `list_initializations` endpoint:**
```moonbit
#derive.endpoint(get="/admin/initializations?user_id={admin_user_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::list_initializations(
  self : Self,
  incoming_key : String,
  admin_user_id : String,
) -> String {
  match self.check_auth(incoming_key) {
    Some(msg) => return msg
    None => ()
  }
  let inits = AdminAgentClient::scoped(fn(admin) raise @common.AgentError {
    admin.get_all_initialized()
  }) catch {
    _ => return "admin unreachable"
  }
  let items = inits.map(fn((uid, role)) {
    "[\"" + uid.replace("\"", "\\\"") + "\",\"" + role.replace("\"", "\\\"") + "\"]"
  })
  "[" + items.join(",") + "]"
}
```

**Remove:** `activation_status_to_string` helper.

### 4. Update SvelteKit proxy — `frontend/src/lib/server/golem.ts`

```typescript
// Replace NOT_ACTIVATED with NOT_INITIALIZED
if (text === 'NOT_INITIALIZED') {
  return {
    error: {
      code: 'NOT_INITIALIZED',
      message: 'Account not initialized. Please contact your school administrator.'
    }
  };
}
```

**Remove:** `parseActivations` function and its export.

### 5. Extend Authentik helpers — `frontend/src/lib/server/authentik.ts`

Add these exports:

```typescript
export async function activateUser(uuid: string): Promise<void>;
export async function deactivateUser(uuid: string): Promise<void>;
export async function resetPassword(uuid: string, password: string): Promise<void>;
export async function addUserToGroup(uuid: string, groupPk: number): Promise<void>;
export async function removeUserFromGroup(uuid: string, groupPk: number): Promise<void>;
```

**`setUserActive` (internal helper):**
```typescript
async function setUserActive(uuid: string, isActive: boolean): Promise<void> {
  const response = await fetch(
    `${AUTHENTIK_HOST}/api/v3/core/users/${uuid}/`,
    {
      method: 'PATCH',
      headers: {
        'Authorization': `Bearer ${AUTHENTIK_SERVICE_ACCOUNT_TOKEN}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ is_active: isActive })
    }
  );
  if (!response.ok) throw new Error(`Authentik PATCH failed: ${response.status}`);
}
export const activateUser = (uuid: string) => setUserActive(uuid, true);
export const deactivateUser = (uuid: string) => setUserActive(uuid, false);
```

**`resetPassword`:**
```typescript
export async function resetPassword(uuid: string, password: string): Promise<void> {
  const response = await fetch(
    `${AUTHENTIK_HOST}/api/v3/core/users/${uuid}/set_password/`,
    {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${AUTHENTIK_SERVICE_ACCOUNT_TOKEN}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ password })
    }
  );
  if (!response.ok) throw new Error(`Authentik set_password failed: ${response.status}`);
}
```

**`addUserToGroup`:**
```typescript
export async function addUserToGroup(uuid: string, groupPk: number): Promise<void> {
  const userResp = await fetch(`${AUTHENTIK_HOST}/api/v3/core/users/${uuid}/`, {
    headers: { 'Authorization': `Bearer ${AUTHENTIK_SERVICE_ACCOUNT_TOKEN}` }
  });
  if (!userResp.ok) throw new Error(`Authentik GET user failed: ${userResp.status}`);
  const user = await userResp.json();
  const currentGroups: number[] = user.groups || [];
  if (currentGroups.includes(groupPk)) return;
  const patchResp = await fetch(`${AUTHENTIK_HOST}/api/v3/core/users/${uuid}/`, {
    method: 'PATCH',
    headers: { 'Authorization': `Bearer ${AUTHENTIK_SERVICE_ACCOUNT_TOKEN}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ groups: [...currentGroups, groupPk] })
  });
  if (!patchResp.ok) throw new Error(`Authentik PATCH add group failed: ${patchResp.status}`);
}
```

**`removeUserFromGroup`:**
```typescript
export async function removeUserFromGroup(uuid: string, groupPk: number): Promise<void> {
  const userResp = await fetch(`${AUTHENTIK_HOST}/api/v3/core/users/${uuid}/`, {
    headers: { 'Authorization': `Bearer ${AUTHENTIK_SERVICE_ACCOUNT_TOKEN}` }
  });
  if (!userResp.ok) throw new Error(`Authentik GET user failed: ${userResp.status}`);
  const user = await userResp.json();
  const currentGroups: number[] = user.groups || [];
  if (!currentGroups.includes(groupPk)) return;
  const patchResp = await fetch(`${AUTHENTIK_HOST}/api/v3/core/users/${uuid}/`, {
    method: 'PATCH',
    headers: { 'Authorization': `Bearer ${AUTHENTIK_SERVICE_ACCOUNT_TOKEN}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ groups: currentGroups.filter(g => g !== groupPk) })
  });
  if (!patchResp.ok) throw new Error(`Authentik PATCH remove group failed: ${patchResp.status}`);
}
```

### 6. Create new SvelteKit API routes

**`POST /api/admin/users/[uuid]/activate-authentik`** — `frontend/src/routes/api/admin/users/[uuid]/activate-authentik/+server.ts`:
```typescript
import { activateUser } from '$lib/server/authentik';
import { error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

export const POST: RequestHandler = async (event) => {
  const user = event.locals.user;
  if (!user) error(401, 'Not authenticated');
  if (!user.roles.includes('admin')) error(403, 'Forbidden');
  const targetUuid = event.params.uuid;
  if (!targetUuid) error(400, 'Missing uuid');
  try {
    await activateUser(targetUuid);
    return new Response(
      JSON.stringify({ data: { activated: true } }),
      { status: 200, headers: { 'content-type': 'application/json' } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: { code: 'AUTHENTIK_ERROR', message: err instanceof Error ? err.message : 'Failed to activate user' } }),
      { status: 502, headers: { 'content-type': 'application/json' } }
    );
  }
};
```

**`POST /api/admin/users/[uuid]/deactivate-authentik`** — same pattern, calls `deactivateUser`.

**`POST /api/admin/users/[uuid]/reset-password`** — accepts `{ password }` body, calls `resetPassword`.

**`POST /api/admin/users/[uuid]/add-group`** — accepts `{ group_pk }` body, calls `addUserToGroup`.

**`POST /api/admin/users/[uuid]/remove-group`** — accepts `{ group_pk }` body, calls `removeUserFromGroup`.

All follow the same guard pattern: check auth -> check admin role -> call helper -> return standard envelope.

### 7. Rename/update existing SvelteKit API routes

| Old path | Action |
|----------|--------|
| `.../activate/+server.ts` | Rename directory to `initialize/+server.ts`. Update body: call gateway `/admin/initialize`, rename response field `activated` -> `initialized`. |
| `.../deactivate/+server.ts` | Delete entire directory |
| `../activations/+server.ts` | Rename directory to `initializations/+server.ts`. Update body: call gateway `/admin/initializations`, parse JSON array response into `Record<string, string>`. |
| `../status/+server.ts` | Update gateway path to `/check-initialization`. Update error code to `NOT_INITIALIZED`. |

### 8. Update dashboard

**`frontend/src/routes/(auth)/dashboard/+page.server.ts`:**
```typescript
const result = await proxyToGateway('/gateway/check-initialization', userId);
if (result.error?.code === 'NOT_INITIALIZED') {
  return { initialized: false };
}
return { initialized: true };
```

**`frontend/src/routes/(auth)/dashboard/+page.svelte`:**
```svelte
{#if data.initialized === false}
  <!-- "Account Not Initialized" error card -->
  ...
{:else}
  <!-- existing dashboard content -->
{/if}
```

### 9. Restructure sidebar — add Users section

Update `frontend/src/routes/(auth)/+layout.svelte` to add a Users sidebar section:

```svelte
<SidebarGroup>
  <SidebarGroupLabel>Users</SidebarGroupLabel>
  <SidebarMenu>
    <SidebarMenuItem>
      <SidebarMenuButton href="/admin/users/students" isActive={$page.url.pathname.startsWith('/admin/users/students')}>
        Students
      </SidebarMenuButton>
    </SidebarMenuItem>
    <SidebarMenuItem>
      <SidebarMenuButton href="/admin/users/teachers" isActive={$page.url.pathname.startsWith('/admin/users/teachers')}>
        Teachers
      </SidebarMenuButton>
    </SidebarMenuItem>
    <SidebarMenuItem>
      <SidebarMenuButton href="/admin/users/admin-role" isActive={$page.url.pathname.startsWith('/admin/users/admin-role')}>
        Admin
      </SidebarMenuButton>
    </SidebarMenuItem>
  </SidebarMenu>
</SidebarGroup>
```

The `SidebarGroupLabel` renders "Users" as a section header in the sidebar, visually grouping the three role sub-pages under a common heading.

### 10. Create role-based admin user pages

**Route structure:**
```
src/routes/(auth)/admin/users/
├── +layout.server.ts        # Shared auth guard
├── +layout.svelte           # Shared layout
├── students/
│   └── +page.server.ts
│   └── +page.svelte
├── teachers/
│   └── +page.server.ts
│   └── +page.svelte
└── admin-role/
    └── +page.server.ts
    └── +page.svelte
```

**`+layout.server.ts`** (shared guard):
```typescript
import { error } from '@sveltejs/kit';
import type { LayoutServerLoad } from './$types';

export const load: LayoutServerLoad = async (event) => {
  const user = event.locals.user;
  if (!user) error(401, 'Not authenticated');
  if (!user.roles.includes('admin')) error(403, 'Forbidden');
  return {};
};
```

**Each `+page.server.ts`** loads Authentik users + init data, filters by group:

```typescript
export const load: PageServerLoad = async (event) => {
  const user = event.locals.user;
  const [authentikUsers, initsResult] = await Promise.all([
    fetchAllUsers(),
    proxyToGateway('/gateway/admin/initializations', user.id)
  ]);

  const initMap = new Map<string, string>();
  if (initsResult.data) {
    const pairs: [string, string][] = JSON.parse(initsResult.data);
    for (const [uid, role] of pairs) initMap.set(uid, role);
  }

  // Filter by role group — e.g., for students page:
  const studentsGroupPk = await getGroupPkByName('students'); // cached
  const filteredUsers = authentikUsers.filter(u =>
    u.groups.includes(studentsGroupPk)
  );

  return {
    users: filteredUsers,
    initMap: Object.fromEntries(initMap),
    role: 'students' // or 'teachers', 'admin'
  };
};
```

The `+page.svelte` is shared via a component — each role page imports and renders the same `UserTable` component with different data. This avoids duplicating the table markup three times.

Create `frontend/src/routes/(auth)/admin/users/UserTable.svelte` with:
- Accepts `users`, `initMap`, `role` as props
- Two status columns (Authentik Status + Init Status)
- Initialize button (with class dropdown for `role === 'students'`)
- Activate/Deactivate buttons
- Reset password dialog
- Add/Remove group dialog
- All optimistic update logic

### 11. Update context files

**`docs/project-overview.md`:**
- Goal 4: "pre‑initialized" not "pre‑activated"
- Step 2 (Dashboard Access): Gateway checks initialization, error -> "Account not initialized"
- Step 5 (Admin Operations): Split into initialization (Golem) and activation/deactivation (Authentik)
- Admin Features: Update activation description
- In Scope: Remove "admin" from per-user durable agents
- Success Criteria 4: Deactivated = Authentik login block

**`docs/architecture.md`:**
- Admin Agent: "user initialization orchestrator"
- Gateway: checks initialization
- `activated_users` -> `initialized_users`
- Invariant 2: "explicit admin initialization"
- Invariant 3: "single source of truth for user initialization status"
- Agent-Level Access Control section: simplified to init check only
- Communication diagram: update gateway -> admin interaction

**`docs/code-standards.md`:**
- Error code: `INITIALIZATION_REQUIRED` instead of `ACTIVATION_REQUIRED`
- Add note: "Authentik activation/deactivation is handled by dedicated SvelteKit API routes, not by Golem agents"

**`docs/specs/00-build-plan.md`:**
- Insert Unit 11 as "Architecture Refactor — Activation -> Initialization Split"
- Renumber Units 11-23 -> 12-24

**`docs/progress-tracker.md`:**
- Current Phase: Unit 11
- Remove stale architecture decisions (activation text protocol, bootstrap problem, activation keyed by UUID)
- Add new architecture decisions

### 12. Build and verify

```bash
cd agents && golem build && cd ../frontend && pnpm build && pnpm check
```

---

## Dependencies

| Package | Action | Purpose |
|---------|--------|---------|
| None | — | No new MoonBit packages, npm packages, or shadcn-svelte components needed |

---

## Verification Checklist

### Agent Layer — Admin Agent
- [ ] `golem build` succeeds (zero errors)
- [ ] `AdminAgent::new(config)` initializes `initialized_users` as empty Map
- [ ] `initialize_user("u1", "student", Some("Primary 1"))` stores record
- [ ] `initialize_user("u1", "student", Some("Primary 1"))` is idempotent
- [ ] `initialize_user("u2", "invalid_role", None)` returns error
- [ ] `is_user_initialized("u1")` returns true after init
- [ ] `is_user_initialized("nonexistent")` returns false
- [ ] `get_all_initialized()` returns `[("u1", "student")]`
- [ ] No `ActivationStatus` enum referenced
- [ ] No `deactivate_user` method exists

### Agent Layer — Gateway
- [ ] Gateway `ping` returns `"NOT_INITIALIZED"` for uninitialized user
- [ ] Gateway `ping` returns `"admin online"` for initialized user
- [ ] `/gateway/check-initialization` returns `"OK"` / `"NOT_INITIALIZED"`
- [ ] `/gateway/admin/initialize` returns `"OK"` on success
- [ ] `/gateway/admin/initializations` returns JSON array
- [ ] `/gateway/student/subjects` returns `"NOT_INITIALIZED"` for uninitialized
- [ ] No `/gateway/admin/deactivate` endpoint
- [ ] No `/gateway/admin/activations` endpoint
- [ ] No `/gateway/check-activation` endpoint

### SvelteKit Proxy + API Layer
- [ ] `pnpm build` succeeds (zero errors)
- [ ] `pnpm check` passes (zero errors)
- [ ] `proxyToGateway` handles `NOT_INITIALIZED` correctly
- [ ] `parseActivations` no longer exists in `golem.ts`
- [ ] `POST /api/admin/users/[uuid]/initialize` returns `{ data: { initialized: true } }`
- [ ] `POST /api/admin/users/[uuid]/activate-authentik` returns `{ data: { activated: true } }`
- [ ] `POST /api/admin/users/[uuid]/deactivate-authentik` returns `{ data: { deactivated: true } }`
- [ ] `POST /api/admin/users/[uuid]/reset-password` returns `{ data: { success: true } }`
- [ ] `POST /api/admin/users/[uuid]/add-group` returns `{ data: { success: true } }`
- [ ] `POST /api/admin/users/[uuid]/remove-group` returns `{ data: { success: true } }`
- [ ] `GET /api/admin/initializations` returns `{ data: { "uuid1": "student" } }`
- [ ] `GET /api/auth/status` returns `{ data: { initialized: true } }` for initialized user
- [ ] `GET /api/auth/status` returns 403 with `NOT_INITIALIZED` for uninitialized
- [ ] All new routes return 401/403 for unauthenticated/non-admin

### Admin Users Pages — Sidebar
- [ ] Sidebar shows "Users" section header label
- [ ] Three sub-items under Users: Students, Teachers, Admin
- [ ] "Students" link navigates to `/admin/users/students`
- [ ] "Teachers" link navigates to `/admin/users/teachers`
- [ ] "Admin" link navigates to `/admin/users/admin-role`
- [ ] Correct nav item is highlighted (isActive) on each page
- [ ] Existing sidebar items (Dashboard, Admin) remain unchanged

### Admin Users Pages — Students Tab
- [ ] Shows only users in "students" Authentik group
- [ ] Authentik Status column shows Active/Inactive badge
- [ ] Init Status column shows Initialized/Pending badge
- [ ] Initialize button shows class-level dropdown
- [ ] Activate/Deactivate buttons call Authentik API
- [ ] Reset password dialog works
- [ ] Add/Remove group dialog works
- [ ] All actions have optimistic updates with rollback

### Admin Users Pages — Teachers Tab
- [ ] Shows only users in "teachers" Authentik group
- [ ] Initialize button does NOT show class-level dropdown
- [ ] All other columns and actions same as Students

### Admin Users Pages — Admin Tab
- [ ] Shows only users in "admin" Authentik group
- [ ] No Initialize button (admins share singleton Admin Agent)
- [ ] All other columns and actions same as Students

### Dashboard
- [ ] Initialized user sees normal dashboard
- [ ] Uninitialized user sees "Account Not Initialized" error
- [ ] Sidebar/navbar remain visible in error state

### Context Files
- [ ] `project-overview.md` — no stale activation references
- [ ] `architecture.md` — updated descriptions, invariants, storage model
- [ ] `code-standards.md` — error code updated
- [ ] `00-build-plan.md` — Unit 11 inserted, renumbered
- [ ] `progress-tracker.md` — updated

### Regression
- [ ] Existing `/api/ping`, `/api/student/subjects`, `/api/db-test` still work
- [ ] Existing `/api/admin/class-levels` unchanged
- [ ] Login/logout flow unchanged
- [ ] `hooks.server.ts` unchanged
- [ ] Class-level dropdown works in student init
