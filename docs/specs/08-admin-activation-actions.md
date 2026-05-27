# Unit 8 — Admin Portal: Activation Actions

## Goal

Add Activate/Deactivate buttons to the admin user management table that call the Admin Agent via Gateway proxy, with optimistic UI updates. Inactive users see a clear "Account Not Activated" error page on the dashboard. The status column dynamically reflects each user's actual activation state fetched from the Admin Agent.

## Design

### Overview

```
SvelteKit Admin Page
  → /api/admin/activations           (GET)  → Gateway → AdminAgent.get_all_activations
  → /api/admin/users/[pk]/activate   (POST) → Gateway → AdminAgent.activate_user
  → /api/admin/users/[pk]/deactivate (POST) → Gateway → AdminAgent.deactivate_user

Dashboard
  → /api/auth/status                 (GET)  → Gateway → AdminAgent.is_user_active
```

### Route Structure

```
src/routes/
├── (auth)/
│   ├── admin/
│   │   ├── activations/
│   │   │   └── +server.ts           # New — returns all activation statuses
│   │   └── users/
│   │       ├── +page.server.ts       # Modified — also fetches activation data
│   │       ├── +page.svelte          # Modified — dynamic status + action buttons
│   │       └── [uuid]/
│   │           ├── activate/
│   │           │   └── +server.ts    # New — POST proxies to AdminAgent.activate_user
│   │           └── deactivate/
│   │               └── +server.ts    # New — POST proxies to AdminAgent.deactivate_user
│   ├── dashboard/
│   │   ├── +page.server.ts           # New — checks activation status
│   │   └── +page.svelte              # Modified — not-activated error state
│   └── +layout.svelte               # Unchanged
├── api/
│   └── auth/
│       └── status/
│           └── +server.ts            # New — returns activation status for current user
└── lib/
    └── server/
        └── golem.ts                  # Modified — extra params + parseActivations helper
```

### Gateway — 4 New Endpoints

| Endpoint | Method | Purpose |
|---|---|---|
| `/gateway/check-activation` | GET | Returns `"OK"` or `"NOT_ACTIVATED"` for a user |
| `/gateway/admin/activate` | GET | Proxies `activate_user` to Admin Agent (idempotent upsert) |
| `/gateway/admin/deactivate` | GET | Proxies `deactivate_user` to Admin Agent |
| `/gateway/admin/activations` | GET | Returns all activation records as text lines |

All admin endpoints:
1. Check `X-Golem-Auth-Key` header (existing pattern)
2. Proxy to the Admin Agent action
3. Return a plain string result

The admin activation check (`is_user_active`) is intentionally omitted from admin
endpoints to avoid a bootstrapping problem — no activated admin exists yet to
activate the first user. SvelteKit role authorization (`locals.user.roles`) is
the sole admin gate.

### Activation Status Text Protocol

The `/gateway/admin/activations` endpoint returns a plain-text response where each line is `user_id|status`:

```
42|active
56|deactivated
```

Status values: `active`, `deactivated`, `suspended`, `not_found`. Users absent from the response are not in the Admin Agent's registry — displayed as "Pending" in the UI.

### Admin Table — Optimistic Updates

When the admin clicks Activate or Deactivate on a row:

1. **Optimistic render**: Status badge immediately updates (Active or Deactivated), button shows spinner
2. **API call**: POST to `/api/admin/users/[pk]/activate` or `deactivate`
3. **Success**: Badge stays in new state, button updates (Deactivate for active, Activate for non-active)
4. **Failure**: Badge reverts to previous state, inline error text appears below the button

This requires maintaining per-user state (current status, loading state, error message) in the page component using `$state`.

### Inactive User — Dashboard Error

The dashboard `+page.server.ts` checks activation via `/api/auth/status`. If not activated, `data.activated = false` and the page renders a full-width error card (warning icon, heading, descriptive message). The sidebar and navbar remain functional so the user can still log out.

---

## Implementation

### 1. Admin Agent — Add `deactivate_user` method

In `agents/app-agents/admin_agent.mbt`, add after the `is_user_active` method block:

```moonbit
///|
/// Deactivates a previously activated user.
/// Returns Err if the user is not in the registry.
pub fn AdminAgent::deactivate_user(
  self : Self,
  user_id : String,
) -> Result[String, String] {
  match self.activated_users.get(user_id) {
    None => Err("user not found: \{user_id}")
    Some(record) => {
      let updated = UserActivation::{ ..record, status: Deactivated }
      self.activated_users.set(user_id, updated)
      Ok("ok")
    }
  }
}
```

The user must exist in the registry (must have been activated first). Idempotent: setting `Deactivated` repeatedly returns `Ok("ok")`.

### 2. Admin Agent — Add `get_all_activations` method

In `agents/app-agents/admin_agent.mbt`, add:

```moonbit
///|
/// Returns all activation records as a list of (user_id, status) tuples.
pub fn AdminAgent::get_all_activations(
  self : Self,
) -> List[(String, ActivationStatus)] {
  self.activated_users.iter().to_list()
}
```

### 3. Gateway Agent — Add `check_activation` endpoint

In `agents/app-agents/gateway_agent.mbt`, add a new method block:

```moonbit
///|
/// Checks whether a user is activated.
/// Returns OK if active, NOT_ACTIVATED if not.
#derive.endpoint(get="/check-activation?user_id={user_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::check_activation(
  self : Self,
  incoming_key : String,
  user_id : String,
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
  if status != Active {
    return "NOT_ACTIVATED"
  }
  "OK"
}
```

### 4. Gateway Agent — Add `activate_user` admin endpoint

In `agents/app-agents/gateway_agent.mbt`, add:

```moonbit
///|
/// Admin-only: activates a target user.
/// Requires the admin caller to be active.
#derive.endpoint(get="/admin/activate?user_id={admin_user_id}&target_user_id={target_user_id}&role={role}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::activate_admin(
  self : Self,
  incoming_key : String,
  admin_user_id : String,
  target_user_id : String,
  role : String,
) -> String {
  match self.check_auth(incoming_key) {
    Some(msg) => return msg
    None => ()
  }
  let admin_status = AdminAgentClient::scoped(fn(admin) raise @common.AgentError {
    admin.is_user_active(admin_user_id)
  }) catch {
    _ => return "admin unreachable"
  }
  if admin_status != Active {
    return "FORBIDDEN"
  }
  match AdminAgentClient::scoped(fn(admin) raise @common.AgentError {
    admin.activate_user(target_user_id, role, None)
  }) catch {
    _ => return "admin unreachable"
  } {
    Ok(_) => "OK"
    Err(msg) => msg
  }
}
```

Note: `class_level` is omitted (always `None`) for now. Unit 10 will extend the activation form to include class level for students.

### 5. Gateway Agent — Add `deactivate_user` admin endpoint

```moonbit
///|
/// Admin-only: deactivates a target user.
/// Requires the admin caller to be active.
#derive.endpoint(get="/admin/deactivate?user_id={admin_user_id}&target_user_id={target_user_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::deactivate_admin(
  self : Self,
  incoming_key : String,
  admin_user_id : String,
  target_user_id : String,
) -> String {
  match self.check_auth(incoming_key) {
    Some(msg) => return msg
    None => ()
  }
  let admin_status = AdminAgentClient::scoped(fn(admin) raise @common.AgentError {
    admin.is_user_active(admin_user_id)
  }) catch {
    _ => return "admin unreachable"
  }
  if admin_status != Active {
    return "FORBIDDEN"
  }
  match AdminAgentClient::scoped(fn(admin) raise @common.AgentError {
    admin.deactivate_user(target_user_id)
  }) catch {
    _ => return "admin unreachable"
  } {
    Ok(_) => "OK"
    Err(msg) => msg
  }
}
```

### 6. Gateway Agent — Add `list_activations` admin endpoint

Add a helper and the endpoint to `gateway_agent.mbt`:

```moonbit
///|
fn activation_status_to_string(status : ActivationStatus) -> String {
  match status {
    Active => "active"
    Deactivated => "deactivated"
    Suspended => "suspended"
    NotFound => "not_found"
  }
}

///|
/// Admin-only: returns all activation records as newline-separated
/// user_id|status lines. Requires the admin caller to be active.
#derive.endpoint(get="/admin/activations?user_id={admin_user_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::list_activations(
  self : Self,
  incoming_key : String,
  admin_user_id : String,
) -> String {
  match self.check_auth(incoming_key) {
    Some(msg) => return msg
    None => ()
  }
  let admin_status = AdminAgentClient::scoped(fn(admin) raise @common.AgentError {
    admin.is_user_active(admin_user_id)
  }) catch {
    _ => return "admin unreachable"
  }
  if admin_status != Active {
    return "FORBIDDEN"
  }
  let activations = AdminAgentClient::scoped(fn(admin) raise @common.AgentError {
    admin.get_all_activations()
  }) catch {
    _ => return "admin unreachable"
  }
  let mut lines = ""
  for (user_id, status) in activations {
    lines = lines + user_id + "|" + activation_status_to_string(status) + "\n"
  }
  lines
}
```

### 7. Extend `proxyToGateway` helper — add extra params + `parseActivations`

Update `frontend/src/lib/server/golem.ts`:

Add the `extraParams` parameter to `proxyToGateway`:

```typescript
export async function proxyToGateway(
	path: string,
	userId: string,
	extraParams?: Record<string, string>
): Promise<ProxyResult> {
	let url = `${getGatewayUrl()}${path}?user_id=${encodeURIComponent(userId)}`;

	if (extraParams) {
		for (const [key, value] of Object.entries(extraParams)) {
			url += `&${encodeURIComponent(key)}=${encodeURIComponent(value)}`;
		}
	}
	// ... rest unchanged
```

Add `parseActivations` helper after the `proxyToGateway` function:

```typescript
export function parseActivations(text: string): Map<string, string> {
	const map = new Map<string, string>();
	const lines = text.trim().split('\n');
	for (const line of lines) {
		if (!line.trim()) continue;
		const sep = line.indexOf('|');
		if (sep === -1) continue;
		const userId = line.slice(0, sep);
		const status = line.slice(sep + 1).toLowerCase();
		if (userId && status) {
			map.set(userId, status);
		}
	}
	return map;
}
```

### 8. Create `/api/auth/status` route

`frontend/src/routes/api/auth/status/+server.ts`:

```typescript
import { proxyToGateway } from '$lib/server/golem';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async (event) => {
	const userId = event.locals.user?.id;
	if (!userId) {
		return new Response(
			JSON.stringify({
				error: { code: 'UNAUTHENTICATED', message: 'Not authenticated.' }
			}),
			{ status: 401, headers: { 'content-type': 'application/json' } }
		);
	}

	const result = await proxyToGateway('/gateway/check-activation', userId);

	if (result.error) {
		const status = result.error.code === 'NOT_ACTIVATED' ? 403 : 502;
		return new Response(JSON.stringify(result), {
			status,
			headers: { 'content-type': 'application/json' }
		});
	}

	return new Response(
		JSON.stringify({ data: { activated: true } }),
		{ status: 200, headers: { 'content-type': 'application/json' } }
	);
};
```

### 9. Create `/api/admin/activations` route

`frontend/src/routes/api/admin/activations/+server.ts`:

```typescript
import { proxyToGateway, parseActivations } from '$lib/server/golem';
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

export const GET: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user) error(401, 'Not authenticated');
	if (!user.roles.includes('admin')) error(403, 'Forbidden');

	const result = await proxyToGateway('/gateway/admin/activations', user.id);

	if (result.error) {
		return new Response(JSON.stringify(result), {
			status: 502,
			headers: { 'content-type': 'application/json' }
		});
	}

	const activationMap = parseActivations(result.data);
	const obj: Record<string, string> = {};
	for (const [key, val] of activationMap) {
		obj[key] = val;
	}

	return new Response(
		JSON.stringify({ data: obj }),
		{ status: 200, headers: { 'content-type': 'application/json' } }
	);
};
```

### 10. Create `/api/admin/users/[uuid]/activate` route

`frontend/src/routes/api/admin/users/[uuid]/activate/+server.ts`:

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

	const result = await proxyToGateway('/gateway/admin/activate', user.id, {
		target_user_id: targetUserId,
		role
	});

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

The `role` defaults to `'student'` since activation from the admin table will not yet include a role picker. The admin can specify a different role by sending `{ "role": "teacher" }` in the POST body. The target UUID comes from the URL path parameter, not the body.

### 11. Create `/api/admin/users/[uuid]/deactivate` route

`frontend/src/routes/api/admin/users/[uuid]/deactivate/+server.ts`:

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

	const result = await proxyToGateway('/gateway/admin/deactivate', user.id, {
		target_user_id: targetUserId
	});

	if (result.error) {
		return new Response(JSON.stringify(result), {
			status: 502,
			headers: { 'content-type': 'application/json' }
		});
	}

	return new Response(
		JSON.stringify({ data: { deactivated: true } }),
		{ status: 200, headers: { 'content-type': 'application/json' } }
	);
};
```

### 12. Dashboard — server load with activation check

Create `frontend/src/routes/(auth)/dashboard/+page.server.ts`:

```typescript
import { proxyToGateway } from '$lib/server/golem';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async (event) => {
	const userId = event.locals.user?.id;
	if (!userId) return { activated: true };

	const result = await proxyToGateway('/gateway/check-activation', userId);
	if (result.error?.code === 'NOT_ACTIVATED') {
		return { activated: false };
	}
	return { activated: true };
};
```

Update `frontend/src/routes/(auth)/dashboard/+page.svelte` to add the not-activated error state as the first branch. Wrap the existing content in an `{:else}`:

```svelte
<script lang="ts">
	// ...existing imports unchanged...
	let { data }: { data: PageData } = $props();

	// Move the existing ping logic inside the else block
	// No changes needed to the ping logic itself
</script>

{#if data.activated === false}
	<div class="mx-auto max-w-lg py-16 text-center space-y-6">
		<div class="rounded-full bg-warning-100 dark:bg-warning-900/20 mx-auto w-fit p-4">
			<svg
				xmlns="http://www.w3.org/2000/svg"
				class="h-8 w-8 text-warning-600 dark:text-warning-400"
				fill="none"
				viewBox="0 0 24 24"
				stroke="currentColor"
			>
				<path
					stroke-linecap="round"
					stroke-linejoin="round"
					stroke-width="2"
					d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4.5c-.77-.833-2.694-.833-3.464 0L3.34 16.5c-.77.833.192 2.5 1.732 2.5z"
				/>
			</svg>
		</div>
		<h1 class="text-2xl font-display font-bold text-surface-800 dark:text-surface-200">
			Account Not Activated
		</h1>
		<p class="text-surface-700 dark:text-surface-400">
			Your account has not yet been activated. Please contact your school administrator.
		</p>
	</div>
{:else}
	<!-- existing dashboard content — welcome heading, quick actions, connection status cards -->
	<div class="mx-auto max-w-4xl space-y-6">
		...
	</div>
{/if}
```

### 13. Admin Users Page — dynamic status + activation buttons

Update `frontend/src/routes/(auth)/admin/users/+page.server.ts`:

```typescript
import { error } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import { fetchAllUsers } from '$lib/server/authentik';
import { proxyToGateway, parseActivations } from '$lib/server/golem';

export const load: PageServerLoad = async (event) => {
	const user = event.locals.user;
	if (!user || !user.roles.includes('admin')) {
		error(403, 'Forbidden');
	}

	try {
		const [authentikUsers, activationsResult] = await Promise.all([
			fetchAllUsers(),
			proxyToGateway('/gateway/admin/activations', user.id)
		]);

		const activationMap = activationsResult.data
			? parseActivations(activationsResult.data)
			: new Map<string, string>();

		const users = authentikUsers.map((u) => ({
			...u,
			activationStatus: activationMap.get(u.uuid) || 'not_found'
		}));

		return { users };
	} catch (err) {
		return {
			users: [],
			error: err instanceof Error ? err.message : 'Failed to fetch users.'
		};
	}
};
```

Update `frontend/src/routes/(auth)/admin/users/+page.svelte`:

**Script section** — add activation state management and action handlers:

```typescript
// Extend the imported AuthentikUser shape with activation status
interface UserWithStatus {
	pk: number;
	uuid: string;
	username: string;
	name: string;
	email: string;
	type: string;
	groups: number[];
	activationStatus: string;
}

let { data }: { data: PageData } = $props();

// Use a local copy so we can optimistically update
let users = $state<UserWithStatus[]>(data.users || []);
let hasUsers = $derived(users.length > 0);
let isLoading = $derived(!data.users && !data.error);
let hasError = $derived(!!data.error);

// Per-user action state
let actionStates = $state<Record<number, string>>({});
let actionErrors = $state<Record<number, string>>({});

function handleRetry() {
	window.location.reload();
}

function getUser(pk: number): UserWithStatus | undefined {
	return users.find(u => u.pk === pk);
}

function statusVariant(status: string) {
	switch (status) {
		case 'active': return 'default';
		case 'deactivated': return 'destructive';
		case 'suspended': return 'secondary';
		default: return 'secondary';
	}
}

function statusLabel(status: string) {
	switch (status) {
		case 'active': return 'Active';
		case 'deactivated': return 'Deactivated';
		case 'suspended': return 'Suspended';
		default: return 'Pending';
	}
}

async function handleActivate(pk: number) {
	const user = getUser(pk);
	if (!user) return;
	const originalStatus = user.activationStatus;

	actionStates = { ...actionStates, [pk]: 'loading' };
	actionErrors = { ...actionErrors, [pk]: '' };

	// Optimistic update
	users = users.map(u => u.pk === pk ? { ...u, activationStatus: 'active' } : u);

	try {
		const res = await fetch(`/api/admin/users/${user.uuid}/activate`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({ role: 'student' })
		});
		const body = await res.json();
		if (!res.ok || body.error) {
			throw new Error(body.error?.message || 'Activation failed');
		}
	} catch (err) {
		// Rollback to original status
		users = users.map(u =>
			u.pk === pk ? { ...u, activationStatus: originalStatus } : u
		);
		actionErrors = { ...actionErrors, [pk]: err instanceof Error ? err.message : 'Activation failed' };
	} finally {
		actionStates = { ...actionStates, [pk]: 'idle' };
	}
}

async function handleDeactivate(pk: number) {
	const user = getUser(pk);
	if (!user) return;
	const originalStatus = user.activationStatus;

	actionStates = { ...actionStates, [pk]: 'loading' };
	actionErrors = { ...actionErrors, [pk]: '' };

	// Optimistic update
	users = users.map(u => u.pk === pk ? { ...u, activationStatus: 'deactivated' } : u);

	try {
		const res = await fetch(`/api/admin/users/${user.uuid}/deactivate`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' }
		});
		const body = await res.json();
		if (!res.ok || body.error) {
			throw new Error(body.error?.message || 'Deactivation failed');
		}
	} catch (err) {
		// Rollback to original status
		users = users.map(u =>
			u.pk === pk ? { ...u, activationStatus: originalStatus } : u
		);
		actionErrors = { ...actionErrors, [pk]: err instanceof Error ? err.message : 'Deactivation failed' };
	} finally {
		actionStates = { ...actionStates, [pk]: 'idle' };
	}
}
```

**Template changes** — Status column and Actions column:

Replace the Status column:

```svelte
<TableCell>
	<Badge variant={statusVariant(user.activationStatus)}>
		{statusLabel(user.activationStatus)}
	</Badge>
</TableCell>
```

Replace the Actions column:

```svelte
<TableCell class="w-32">
	{#if user.activationStatus === 'active'}
		<Button
			variant="destructive"
			size="sm"
			onclick={() => handleDeactivate(user.pk)}
			disabled={actionStates[user.pk] === 'loading'}
		>
			{actionStates[user.pk] === 'loading' ? '...' : 'Deactivate'}
		</Button>
	{:else}
		<Button
			variant="default"
			size="sm"
			onclick={() => handleActivate(user.pk)}
			disabled={actionStates[user.pk] === 'loading'}
		>
			{actionStates[user.pk] === 'loading' ? '...' : 'Activate'}
		</Button>
	{/if}
	{#if actionErrors[user.pk]}
		<p class="mt-1 text-xs text-error-500">{actionErrors[user.pk]}</p>
	{/if}
</TableCell>
```

### 14. Build and verify

```bash
cd agents

# Type-check
moon check --target wasm

# Generate artifacts
golem build

# Frontend
cd ../frontend
pnpm build
pnpm check
```

Run `moon info && moon fmt` in `agents/` before finalizing.

---

## Dependencies

| Package | Action | Purpose |
|---|---|---|
| None | — | No new npm packages, MoonBit packages, or shadcn-svelte components needed. |

## Verification Checklist

### Agent Layer
- [ ] `moon check --target wasm` succeeds (zero errors)
- [ ] `golem build` succeeds
- [ ] `moon info && moon fmt` runs clean in `agents/`
- [ ] `AdminAgent::deactivate_user("existing_id")` returns `Ok("ok")` and sets status to `Deactivated`
- [ ] `AdminAgent::deactivate_user("nonexistent")` returns `Err("user not found: {id}")`
- [ ] `AdminAgent::deactivate_user` on already-deactivated user returns `Ok("ok")` (idempotent)
- [ ] `AdminAgent::get_all_activations()` returns all records as `List[(String, ActivationStatus)]`
- [ ] Gateway `/gateway/check-activation` returns `"OK"` for active user, `"NOT_ACTIVATED"` for inactive
- [ ] Gateway `/gateway/check-activation` checks auth first (returns `"unauthorized"` on mismatch)
- [ ] Gateway `/gateway/admin/activate` checks admin is active before proxying
- [ ] Gateway `/gateway/admin/activate` calls `AdminAgent.activate_user` and returns `"OK"`
- [ ] Gateway `/gateway/admin/deactivate` calls `AdminAgent.deactivate_user` and returns `"OK"`
- [ ] Gateway `/gateway/admin/activations` returns newline-separated `user_id|status` for all activated users
- [ ] Gateway `/gateway/admin/activations` returns empty string when no users activated

### SvelteKit Proxy Layer
- [ ] `pnpm build` succeeds (zero errors)
- [ ] `pnpm check` passes (zero errors)
- [ ] `proxyToGateway` accepts optional `extraParams` without breaking existing callers
- [ ] `proxyToGateway` with `extraParams` appends correct `&key=value` params to URL
- [ ] `parseActivations("42|active\n56|deactivated\n")` returns Map with `42 → active`, `56 → deactivated`
- [ ] `parseActivations("")` returns empty Map
- [ ] `GET /api/auth/status` returns `{ data: { activated: true } }` for active user with 200
- [ ] `GET /api/auth/status` returns 403 with `{ error: { code: "NOT_ACTIVATED", ... } }` for inactive user
- [ ] `GET /api/auth/status` returns 401 for unauthenticated requests
- [ ] `GET /api/admin/activations` returns `{ data: { "42": "active", "56": "deactivated" } }` with 200
- [ ] `GET /api/admin/activations` returns 403 for non-admin users
- [ ] `POST /api/admin/users/[pk]/activate` proxies and returns `{ data: { activated: true } }` with 200
- [ ] `POST /api/admin/users/[pk]/activate` returns 403 for non-admin users
- [ ] `POST /api/admin/users/[pk]/activate` returns 400 with `ACTIVATION_FAILED` on Admin Agent error
- [ ] `POST /api/admin/users/[pk]/deactivate` mirrors activate pattern with `DEACTIVATION_FAILED`

### Admin Users Page
- [ ] Status column shows dynamic Badge: Active (default), Deactivated (destructive), Pending (secondary)
- [ ] Actions column shows "Activate" button for Pending/Deactivated users
- [ ] Actions column shows "Deactivate" button for Active users
- [ ] Clicking "Activate" immediately shows Active badge (optimistic), button shows "..."
- [ ] Clicking "Deactivate" immediately shows Deactivated badge (optimistic), button shows "..."
- [ ] On API success, badge stays in new state, button updates for next action
- [ ] On API failure, badge reverts to previous state (rollback)
- [ ] On API failure, inline error text appears below the button
- [ ] Skeleton loading, error alert, and empty states unchanged from Unit 6
- [ ] "Retry" button on error state still works (page reload)

### Dashboard — Not Activated State
- [ ] Active user visits `/dashboard` → normal dashboard (welcome heading, Quick Actions, Connection Status cards)
- [ ] Inactive user visits `/dashboard` → sees "Account Not Activated" card with warning icon
- [ ] Not-activated view includes "Your account has not yet been activated. Please contact your school administrator."
- [ ] Sidebar and navbar remain visible in not-activated state
- [ ] Logout button in navbar works in not-activated state
- [ ] Active user dashboard shows no visible activation-related content (no regression)

### Regression
- [ ] Existing `/api/ping` route unchanged — still returns ping result for active users
- [ ] Existing `proxyToGateway` calls (ping route) work without extra params (backward compatible)
- [ ] Existing admin user list works when Gateway is unreachable (shows error state)
- [ ] Existing dashboard "Test Connection" button works for active users
- [ ] Existing login/logout flow unchanged
- [ ] Auth guard (`+layout.server.ts`) unchanged
- [ ] `hooks.server.ts` unchanged
- [ ] No new npm packages installed
- [ ] Context files preserved — `docs/progress-tracker.md` updated: Unit 8 marked as completed
