# Unit 6 — Admin User List Page

## Goal

Create an admin-only route `/admin/users` that fetches internal (human) users from Authentik's REST API via a service account Bearer token and renders them in a shadcn-svelte Table with columns: name, email, status (always "Pending"). Protected by role check against `locals.user.roles`. Add role-based "Admin > Users" navigation item to the sidebar.

## Design

### Route Structure

```
src/routes/(auth)/
├── admin/
│   └── users/
│       ├── +page.server.ts    # Load: admin role check + fetch users from Authentik
│       └── +page.svelte       # Table with skeleton loading, empty, error, and data states
├── +layout.server.ts          # unchanged — auth guard
└── +layout.svelte             # modified — add conditional "Admin > Users" sidebar nav
```

Both new files live inside the `(auth)` route group, inheriting its auth guard (`+layout.server.ts`) and dashboard shell layout (`+layout.svelte`).

### Authentik Admin API Access

A single service account Bearer token is used for server-to-server API access:

| Env Variable | Purpose |
|---|---|
| `AUTHENTIK_HOST` | Authentik hostname (e.g., `auth.johnethel.school`) |
| `AUTHENTIK_SERVICE_ACCOUNT_TOKEN` | Bearer token generated in Authentik for a superuser service account |

The API base URL is `https://{AUTHENTIK_HOST}/api/v3`. The Bearer token is sent directly — no username, no OAuth2 flow, no caching needed.

### Authentik User Data Mapping

The `GET /api/v3/core/users/` endpoint returns paginated user objects. Only users with `type === 'internal'` (human users) are included. Additionally, only users belonging to at least one of the `admin`, `students`, or `teachers` groups are shown — users outside those groups (e.g., unassigned accounts, API-only accounts) are excluded. Group membership is determined by fetching all groups from `GET /api/v3/core/groups/` and cross-referencing user `groups` (array of group PKs). Mapping to table columns:

| Table Column | Authentik API Field | Notes |
|---|---|---|
| Name | `name` | Falls back to `username` if `name` is empty |
| Email | `email` | May be empty for service accounts |
| Status | — | Hardcoded `"Pending"` (Unit 7 + 8 add activation) |
| Actions | — | Empty column slot (wired in Unit 8 with activate/deactivate buttons) |

The status column is static because the Admin Agent activation check is built in Unit 7 and wired into the UI in Unit 8.

### Sidebar Nav Items

The `(auth)/+layout.svelte` gains a conditional `SidebarGroup`. When `data.user.roles` includes `"admin"`, a "Admin" group appears with a single "Users" `SidebarMenuItem` linking to `/admin/users`. Uses the `child` snippet pattern (not `asChild`) for the menu button.

### Table States

| State | Trigger | Visual |
|---|---|---|
| **Loading** | Initial page load (before `load` resolves) | 5 skeleton rows matching table column widths |
| **Error** | `data.error` is set (fetch or auth failure) | Destructive `Alert` with error message + "Retry" button |
| **Empty** | `data.users` is an empty array | "No users found" message with guidance |
| **Data** | `data.users` has 1+ entries | Full shadcn-svelte `Table` with header row + data rows |

---

## Implementation

### 1. Install shadcn-svelte components

```bash
npx shadcn-svelte add table
npx shadcn-svelte add badge
npx shadcn-svelte add alert
```

### 2. Environment variables

Add to `frontend/.env` and `frontend/.env.example`:

```env
# Authentik admin API — service account Bearer token
# Create a service account in Authentik with superuser status,
# then generate an API token for it.
AUTHENTIK_HOST="auth.example.com"
AUTHENTIK_SERVICE_ACCOUNT_TOKEN=""
```

### 3. Extend `src/lib/server/authentik.ts` — admin API helpers

Add the following below the existing OIDC helper functions (after `getEndSessionUrl`).

```typescript
// ─── Admin API ───────────────────────────────────────────────

export interface AuthentikUser {
	pk: number;
	username: string;
	name: string;
	email: string;
	type: 'internal' | 'service_account' | 'external';
	groups: number[];
}

interface AuthentikGroup {
	pk: number;
	name: string;
}

interface AuthentikPaginatedResponse {
	results: AuthentikUser[];
	next: string | null;
	previous: string | null;
	count: number;
}

/** Fetches group PKs for "admin", "students", "teachers" groups.
 *  Only users belonging to at least one of these groups are shown. */
async function getTargetGroupPks(): Promise<Set<number>> {
	const host = env.AUTHENTIK_HOST;
	const token = env.AUTHENTIK_SERVICE_ACCOUNT_TOKEN;
	if (!host || !token) return new Set();

	const targetNames = ['admin', 'students', 'teachers'];
	const targetPks = new Set<number>();

	let nextUrl: string | null = `https://${host}/api/v3/core/groups/?page_size=100`;

	while (nextUrl) {
		const res = await fetch(nextUrl, {
			headers: { authorization: `Bearer ${token}` }
		});
		if (!res.ok) break;

		const page: { results: AuthentikGroup[]; next: string | null } = await res.json();
		for (const group of page.results) {
			if (targetNames.includes(group.name.toLowerCase())) {
				targetPks.add(group.pk);
			}
		}
		nextUrl = page.next;
	}

	return targetPks;
}

/** Fetches internal users from Authentik that belong to at least
 *  one of the admin/students/teachers groups. Paginates all pages,
 *  filters out service accounts and external users, then filters
 *  by group membership. */
export async function fetchAllUsers(): Promise<AuthentikUser[]> {
	const host = env.AUTHENTIK_HOST;
	const token = env.AUTHENTIK_SERVICE_ACCOUNT_TOKEN;
	if (!host || !token) {
		throw new Error('Missing AUTHENTIK_HOST or AUTHENTIK_SERVICE_ACCOUNT_TOKEN');
	}

	const allUsers: AuthentikUser[] = [];
	let nextUrl: string | null = `https://${host}/api/v3/core/users/?page_size=100`;

	while (nextUrl) {
		const res = await fetch(nextUrl, {
			headers: { authorization: `Bearer ${token}` }
		});

		if (!res.ok) {
			const text = await res.text();
			throw new Error(
				`Authentik API returned ${res.status} — check service account permissions. ${text}`
			);
		}

		const page: AuthentikPaginatedResponse = await res.json();
		allUsers.push(...page.results.filter((u) => u.type === 'internal'));
		nextUrl = page.next;
	}

	const targetPks = await getTargetGroupPks();
	if (targetPks.size === 0) return [];

	return allUsers.filter((u) => (u.groups ?? []).some((g) => targetPks.has(g)));
}
```

**Implementation notes:**
- `AUTHENTIK_HOST` is used directly (not derived from the issuer URL).
- Token sent as `Authorization: Bearer <token>` — no Basic auth, no username.
- First pass: fetch all internal users (type === 'internal'), paginating through all pages.
- Second pass: fetch all group PKs for groups named "admin", "students", "teachers".
- Third pass: filter users to only those whose `groups` array overlaps with the target group PKs.
- If no target groups are found in Authentik, returns an empty array (prevents showing all users when group config is incomplete).
- `(u.groups ?? [])` safely handles users missing the `groups` field.
- The `decodeJwt` import from the original spec is not needed — no OAuth2 token caching.

### 4. Create `src/routes/(auth)/admin/users/+page.server.ts`

```typescript
import { error } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import { fetchAllUsers } from '$lib/server/authentik';

export const load: PageServerLoad = async (event) => {
	const user = event.locals.user;
	if (!user || !user.roles.includes('admin')) {
		error(403, 'Forbidden');
	}

	try {
		const users = await fetchAllUsers();
		return { users };
	} catch (err) {
		return {
			users: [],
			error: err instanceof Error ? err.message : 'Failed to fetch users from Authentik.'
		};
	}
};
```

### 5. Create `src/routes/(auth)/admin/users/+page.svelte`

```svelte
<script lang="ts">
	import type { PageData } from './$types';
	import {
		Table,
		TableBody,
		TableCell,
		TableHead,
		TableHeader,
		TableRow
	} from '$lib/components/ui/table';
	import { Badge } from '$lib/components/ui/badge';
	import { Card, CardContent, CardHeader, CardTitle } from '$lib/components/ui/card';
	import { Skeleton } from '$lib/components/ui/skeleton';
	import { Alert, AlertDescription, AlertTitle } from '$lib/components/ui/alert';
	import { Button } from '$lib/components/ui/button';

	let { data }: { data: PageData } = $props();

	let hasUsers = $derived(data.users && data.users.length > 0);
	let isLoading = $derived(!data.users && !data.error);
	let hasError = $derived(!!data.error);

	function handleRetry() {
		window.location.reload();
	}
</script>

<div class="mx-auto max-w-4xl space-y-6">
	<div>
		<h1 class="text-2xl font-display font-bold text-primary-700">User Management</h1>
		<p class="mt-1 text-sm text-surface-700">
			Manage user activation and roles
		</p>
	</div>

	{#if isLoading}
		<Card>
			<CardHeader>
				<Skeleton class="h-5 w-32" />
			</CardHeader>
			<CardContent class="space-y-3">
				{#each Array(5) as _}
					<div class="flex gap-4">
						<Skeleton class="h-4 flex-1" />
						<Skeleton class="h-4 flex-1" />
						<Skeleton class="h-4 w-20" />
						<Skeleton class="h-4 w-16" />
					</div>
				{/each}
			</CardContent>
		</Card>

	{:else if hasError}
		<Alert variant="destructive">
			<AlertTitle>Failed to load users</AlertTitle>
			<AlertDescription>
				{data.error}
			</AlertDescription>
			<Button onclick={handleRetry} variant="outline" class="mt-3">
				Retry
			</Button>
		</Alert>

	{:else if !hasUsers}
		<Card>
			<CardContent class="py-8 text-center">
				<p class="text-surface-700">No users found.</p>
				<p class="mt-1 text-sm text-surface-700">
					Ensure your Authentik service account has the correct permissions.
				</p>
			</CardContent>
		</Card>

	{:else}
		<Card>
			<CardContent class="p-0">
				<Table>
					<TableHeader>
						<TableRow>
							<TableHead>Name</TableHead>
							<TableHead>Email</TableHead>
							<TableHead>Status</TableHead>
							<TableHead class="w-20">Actions</TableHead>
						</TableRow>
					</TableHeader>
					<TableBody>
						{#each data.users as user (user.pk)}
							<TableRow>
								<TableCell class="font-medium">
									{user.name || user.username}
								</TableCell>
								<TableCell class="text-surface-700">
									{user.email || '—'}
								</TableCell>
								<TableCell>
									<Badge variant="secondary">Pending</Badge>
								</TableCell>
								<TableCell>
									<!-- Actions wired in Unit 8 -->
								</TableCell>
							</TableRow>
						{/each}
					</TableBody>
				</Table>
			</CardContent>
		</Card>
	{/if}
</div>
```

### 6. Update `src/routes/(auth)/+layout.svelte` — sidebar nav items

Inside `<SidebarContent>`, after the "Navigation" group, add:

```svelte
{#if data.user.roles.includes('admin')}
	<SidebarGroup>
		<SidebarGroupLabel>Admin</SidebarGroupLabel>
		<SidebarMenu>
			<SidebarMenuItem>
				<SidebarMenuButton>
					{#snippet child({ props })}
						<a href="/admin/users" {...props}>Users</a>
					{/snippet}
				</SidebarMenuButton>
			</SidebarMenuItem>
		</SidebarMenu>
	</SidebarGroup>
{/if}
```

The `child` snippet pattern is used (not `asChild`) since shadcn-svelte's `SidebarMenuButton` supports it.

### 7. Verify build

```bash
pnpm build
pnpm check
```

Both must succeed with zero errors.

---

## Dependencies

| Package | Action | Purpose |
|---|---|---|
| `shadcn-svelte table` | `npx shadcn-svelte add table` | Data table for user list |
| `shadcn-svelte badge` | `npx shadcn-svelte add badge` | Status label column |
| `shadcn-svelte alert` | `npx shadcn-svelte add alert` | Error state display |

### Authentik Setup Required

1. Create a service account user in Authentik with superuser status
2. Generate an API token for that user in Authentik admin
3. Set environment variables:
   - `AUTHENTIK_HOST` — Authentik hostname
   - `AUTHENTIK_SERVICE_ACCOUNT_TOKEN` — the Bearer token

---

## Verification Checklist

- [ ] `pnpm build` succeeds with zero errors
- [ ] `pnpm check` (svelte-check) passes with zero errors
- [ ] Unauthenticated user visits `/admin/users` → redirected to `/login`
- [ ] Authenticated non-admin user visits `/admin/users` → sees 403 Forbidden page
- [ ] Admin user visits `/admin/users` → sees "User Management" heading with subtitle
- [ ] Page renders a shadcn-svelte Table with columns: Name, Email, Status, Actions
- [ ] Each user row shows name (or username fallback), email, and a "Pending" badge
- [ ] Status badge uses `Badge variant="secondary"` with text "Pending"
- [ ] Loading state shows skeleton rows (5 rows of Skeleton elements)
- [ ] Empty state shows "No users found." message with guidance
- [ ] Error state shows a destructive `Alert` with descriptive error message and "Retry" button
- [ ] Retry button calls `window.location.reload()`
- [ ] Sidebar shows "Admin" group with "Users" link for admin-role users only (uses `child` snippet)
- [ ] Non-admin users do NOT see "Admin" section in the sidebar
- [ ] Clicking "Users" in the sidebar navigates to `/admin/users` with client-side routing
- [ ] `fetchAllUsers()` fetches from `https://{host}/api/v3/core/users/?page_size=100`
- [ ] `getTargetGroupPks()` fetches groups from `https://{host}/api/v3/core/groups/?page_size=100`
- [ ] Only users with `type === 'internal'` appear in the table (no service accounts)
- [ ] Only users in the `admin`, `students`, or `teachers` groups appear (no ungrouped users)
- [ ] A user in multiple target groups still appears once (deduplication by `pk`)
- [ ] If no target groups exist in Authentik, the table is empty (not a data fetch error)
- [ ] Each row uses `user.pk` as the each-block key (not `user.id`)
- [ ] Authorization header is `Bearer {token}` (not Basic auth)
- [ ] Actions column is empty (no buttons; wired in Unit 8)
- [ ] `(auth)/+layout.server.ts` unchanged
- [ ] `hooks.server.ts` unchanged
- [ ] Existing Dashboard, `proxyToGateway`, and auth routes unchanged
- [ ] No new npm packages — only shadcn-svelte components added
- [ ] Documentation updated: `docs/progress-tracker.md` reflects Unit 6 as completed
