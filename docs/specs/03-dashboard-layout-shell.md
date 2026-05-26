# Unit 3 — Dashboard Layout Shell

## Goal

Create the protected layout shell with a collapsible shadcn-svelte Sidebar (empty nav list), top navbar (sidebar toggle + breadcrumb placeholder + profile avatar with logout dropdown), and content area. Move the existing `/dashboard` page into the `(auth)` route group.

## Design

### Route Structure

```
src/routes/
├── +layout.svelte              # Root layout (app.css + favicon — unchanged)
├── +page.svelte                # Landing page (unchanged)
├── (auth)/                     # Route group — all protected pages
│   ├── +layout.server.ts       # Auth guard → redirects to /login if unauthenticated
│   ├── +layout.svelte          # Dashboard shell (sidebar + navbar + content)
│   └── dashboard/
│       └── +page.svelte        # "Welcome, {name}" + placeholder (migrated from /dashboard)
├── api/                        # API routes (unchanged)
└── login/                      # Login page (unchanged)
```

The `(auth)` group is a SvelteKit parenthesized route group. Pages inside it share the group's `+layout.svelte` and `+layout.server.ts`. URLs remain flat (`/dashboard`, `/lms/...`, `/admin/...`).

### Layout Zones

| Zone | Implementation | Contents |
|---|---|---|
| **Sidebar** | shadcn-svelte `Sidebar` | School brand/logo at top, empty nav list placeholder with heading, footer with user info |
| **Navbar** | `<header>` inside `SidebarInset` | Hamburger toggle (`SidebarTrigger`), breadcrumb placeholder `<p>`, flex spacer, avatar dropdown |
| **Content** | `<main>` inside `SidebarInset` | `{@render children()}` — page content |

### Sidebar Behavior

- Desktop: pinned sidebar collapsible via shadcn-svelte's built-in `Sidebar` component (icon-only when closed)
- Mobile (`< md`): sidebar renders as an overlay sheet via `Sheet` (shadcn-svelte handles this automatically)
- State persisted to `localStorage` key `"sidebar_state"`, default `true` (open)
- Collapsed state shows `Tooltip` on nav items (infrastructure in place, no items yet)
- `SidebarTrigger` button in the navbar toggles collapse

### Avatar Dropdown

- shadcn `Avatar` with user's first initial
- `DropdownMenu` on click: user name (bold), email (muted), `Separator`, "Sign out" item
- "Sign out" calls `POST /api/auth/logout`, on success redirects to the returned logout URL
- Error state: inline error text, dropdown stays open

### Dashboard Page (migrated)

- No longer shows a standalone logout button (that moves to the navbar)
- Shows "Welcome, {user.name}" heading, subtitle with role, placeholder cards grid for future widgets

---

## Implementation

### 1. Install shadcn-svelte components

```bash
npx shadcn-svelte add sidebar
npx shadcn-svelte add avatar
npx shadcn-svelte add dropdown-menu
npx shadcn-svelte add breadcrumb
npx shadcn-svelte add separator
npx shadcn-svelte add sheet
npx shadcn-svelte add tooltip
npx shadcn-svelte add input
npx shadcn-svelte add skeleton
npx shadcn-svelte add card
```

These are required by the Sidebar compound component or used directly in the layout.

### 2. `src/routes/(auth)/+layout.server.ts` — Auth guard

```ts
import { redirect } from '@sveltejs/kit';
import type { LayoutServerLoad } from './$types';

export const load: LayoutServerLoad = (event) => {
  if (!event.locals.user) {
    redirect(302, '/login');
  }
  return { user: event.locals.user };
};
```

Every page inside `(auth)` automatically gets `data.user` from this layout load. Individual pages may return additional data.

### 3. `src/routes/(auth)/+layout.svelte` — Dashboard shell

```svelte
<script lang="ts">
  import { Sidebar, SidebarContent, SidebarFooter, SidebarGroup, SidebarGroupLabel, SidebarHeader, SidebarInset, SidebarProvider, SidebarTrigger } from '$lib/components/ui/sidebar';
  import { Avatar, AvatarFallback } from '$lib/components/ui/avatar';
  import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger } from '$lib/components/ui/dropdown-menu';
  import { Breadcrumb, BreadcrumbList, BreadcrumbItem, BreadcrumbPage, BreadcrumbSeparator } from '$lib/components/ui/breadcrumb';
  import { Button } from '$lib/components/ui/button';
  import { Separator } from '$lib/components/ui/separator';
  import type { LayoutData } from './$types';
  import type { Snippet } from 'svelte';

  let { children, data }: { children: Snippet; data: LayoutData } = $props();

  let sidebarOpen = $state(true);
  let isLoggingOut = $state(false);
  let error = $state('');

  $effect(() => {
    const stored = localStorage.getItem('sidebar_state');
    if (stored !== null) {
      sidebarOpen = stored === 'true';
    }
  });

  $effect(() => {
    localStorage.setItem('sidebar_state', String(sidebarOpen));
  });

  async function handleLogout() {
    if (isLoggingOut) return;
    isLoggingOut = true;
    error = '';

    try {
      const res = await fetch('/api/auth/logout', {
        method: 'POST',
        headers: { 'X-Requested-With': 'XMLHttpRequest' }
      });
      if (!res.ok) {
        error = 'Logout failed. Please try again.';
        isLoggingOut = false;
        return;
      }
      const body = await res.json();
      if (body.url) {
        window.location.href = body.url;
      }
    } catch {
      error = 'An error occurred during logout. Please try again.';
      isLoggingOut = false;
    }
  }
</script>

<SidebarProvider open={sidebarOpen} onOpenChange={(v) => sidebarOpen = v}>
  <Sidebar>
    <SidebarHeader>
      <div class="flex items-center gap-2 px-4 py-2">
        <span class="text-lg font-display font-bold text-primary-700">School</span>
      </div>
    </SidebarHeader>

    <SidebarContent>
      <SidebarGroup>
        <SidebarGroupLabel>Navigation</SidebarGroupLabel>
      </SidebarGroup>
    </SidebarContent>

    <SidebarFooter>
      <Separator />
      <div class="p-4">
        <p class="text-sm font-medium text-surface-800">{data.user.name}</p>
        <p class="text-xs text-surface-700">{data.user.email}</p>
      </div>
    </SidebarFooter>
  </Sidebar>

  <SidebarInset>
    <header class="flex h-14 items-center gap-4 border-b border-border px-4">
      <SidebarTrigger />
      <Separator orientation="vertical" class="h-6" />
      <Breadcrumb>
        <BreadcrumbList>
          <BreadcrumbItem>
            <BreadcrumbPage>Dashboard</BreadcrumbPage>
          </BreadcrumbItem>
        </BreadcrumbList>
      </Breadcrumb>

      <div class="flex-1" />

		<DropdownMenu>
				<DropdownMenuTrigger>
					{#snippet child({ props })}
						<Button variant="ghost" class="h-8 w-8 rounded-full p-0" {...props}>
							<Avatar class="h-8 w-8">
								<AvatarFallback class="bg-primary-100 text-primary-700 text-sm font-medium">
									{data.user.name.charAt(0).toUpperCase()}
								</AvatarFallback>
							</Avatar>
						</Button>
					{/snippet}
				</DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <DropdownMenuLabel class="font-normal">
            <div class="flex flex-col gap-1">
              <p class="text-sm font-medium">{data.user.name}</p>
              <p class="text-xs text-muted-foreground">{data.user.email}</p>
            </div>
          </DropdownMenuLabel>
          <DropdownMenuSeparator />
          <DropdownMenuItem onclick={handleLogout} disabled={isLoggingOut}>
            {isLoggingOut ? 'Signing out...' : 'Sign out'}
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>

      {#if error}
        <p class="text-xs text-error-500">{error}</p>
      {/if}
    </header>

    <main class="flex-1 p-6">
      {@render children()}
    </main>
  </SidebarInset>
</SidebarProvider>
```

### 4. `src/routes/(auth)/dashboard/+page.server.ts`

```ts
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = (event) => {
  return { user: event.locals.user! };
};
```

Auth guard is inherited from the parent layout; this only provides typed data to the page.

### 5. `src/routes/(auth)/dashboard/+page.svelte`

```svelte
<script lang="ts">
  import type { PageData } from './$types';
  import { Card, CardContent, CardHeader, CardTitle } from '$lib/components/ui/card';

  let { data }: { data: PageData } = $props();
</script>

<div class="mx-auto max-w-4xl space-y-6">
  <div>
    <h1 class="text-2xl font-display font-bold text-primary-700">
      Welcome, {data.user.name}
    </h1>
    <p class="mt-1 text-sm text-surface-700">
      {data.user.roles[0] ?? 'User'} dashboard
    </p>
  </div>

  <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
    <Card>
      <CardHeader>
        <CardTitle class="text-base">Quick Actions</CardTitle>
      </CardHeader>
      <CardContent>
        <p class="text-sm text-surface-700">Dashboard widgets will appear here.</p>
      </CardContent>
    </Card>
  </div>
</div>
```

### 6. Delete old dashboard

Remove `src/routes/dashboard/` entirely (both `+page.server.ts` and `+page.svelte`).

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
| `shadcn-svelte` components | Install sidebar, avatar, dropdown-menu, breadcrumb, separator, sheet, tooltip, input, skeleton, card | UI primitives for the shell |

No npm packages — all additions are shadcn-svelte generated components.

---

## Verification Checklist

- [ ] `pnpm build` succeeds with zero errors
- [ ] `pnpm check` (svelte-check) passes with zero errors
- [ ] Unauthenticated user visits `/dashboard` → redirected to `/login`
- [ ] Authenticated user visits `/dashboard` → sees layout shell with sidebar, navbar, and welcome content
- [ ] Sidebar shows school brand at top, "Navigation" section label, and user name/email in footer
- [ ] Clicking the hamburger icon (`SidebarTrigger`) collapses sidebar to icon-only
- [ ] Clicking again expands the sidebar to full width
- [ ] Sidebar state persists across page reloads (`localStorage` key `"sidebar_state"`)
- [ ] On mobile viewport (< `md`), sidebar renders as overlay sheet from the left
- [ ] Navbar shows: hamburger trigger, vertical separator, breadcrumb "Dashboard", avatar on the right
- [ ] Clicking avatar opens a dropdown showing user name, email, and "Sign out"
- [ ] "Sign out" calls `POST /api/auth/logout`, redirects to Authentik logout URL
- [ ] Dashboard page at `/dashboard` shows "Welcome, {user.name}" and role-based subtitle
- [ ] Dashboard shows placeholder cards grid
- [ ] Old `src/routes/dashboard/` directory is deleted
- [ ] `src/app.d.ts` unchanged (auth types already defined in Unit 2)
- [ ] No console errors on page load (hydration, missing components, etc.)
- [ ] Avatar fallback shows first letter of user's name in `bg-primary-100 text-primary-700`
- [ ] Logout error state is handled (inline error text shown, dropdown remains open)
- [ ] Root `+layout.svelte` unchanged
