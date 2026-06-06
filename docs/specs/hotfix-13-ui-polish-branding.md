# Hotfix-13: UI Polish, Branding Assets & Edit Dialog Lazy-Load

## Goal

Replace placeholder SVGs with actual school logo assets, fix 502 backend errors, unblock edit dialogs with lazy-load pattern, migrate all UI to semantic CSS tokens, add global cursor/hover consistency, apply amber accent polish, and slim the loading bar.

## Design

### 1. Branding Assets

- **Logo**: User's `logo.jpg` (includes title text) replaces `logo.svg` in the sidebar header
- **Favicon**: User's `logo.png` served from `/favicon.png`, referenced in `app.html`
- Retain the existing SVG files as fallbacks

| File | Content | Placement |
|------|---------|-----------|
| `docs/temp/images/logo.jpg` | Full school logo with title text | Sidebar header (`<img src={logo}>`) |
| `docs/temp/images/logo.png` | Square icon | Favicon (`app.html` → `<link rel="icon">`) |
| `src/lib/assets/favicon.svg` | Keep as fallback | Delete or keep for reference |
| `src/lib/assets/logo.svg` | Old placeholder | Delete |

### 2. Edit Dialog Lazy-Load (All 4 Role Tables)

**Current problem:** `openEditDialog()` blocks dialog opening until the profile API returns. On 502/timeout, the dialog never opens.

**New contract:**

1. User clicks "Edit"
2. Dialog opens **immediately** with empty fields
3. Loading indicator shown: spinner + "Loading profile data..."
4. **Save button disabled** until profile data arrives
5. Profile fetch runs in background — fields populate as they resolve
6. If fetch fails: fields stay empty, user can fill manually, save becomes enabled (no lockout)

**Implementation** (same pattern in all 4 files):

```
StudentUserTable.svelte:openEditDialog  (line 201)
TeacherUserTable.svelte:openEditDialog  (line 119)
AdminUserTable.svelte:openEditDialog    (line 53)
ParentUserTable.svelte:openEditDialog   (line 70)
```

Each changes from:
```ts
editProfileLoading = true;
const res = await fetch(...);
// populate form
editProfileLoading = false;
editDialogOpen = true;    // ← BAD: opens AFTER await
```

To:
```ts
editDialogOpen = true;    // ← GOOD: opens immediately
editProfileLoading = true;
const res = await fetch(...);
// populate form
editProfileLoading = false;
```

And the Save button gets:
```svelte
<AppButton onclick={handleEdit} loading={editLoading} disabled={editLoading || editProfileLoading}>Save</AppButton>
```

### 3. 502 Error Investigation (Not Assumption — Trace)

**Step 1 — Check frontend proxy routes:**

| Route | File | What URL does it call? |
|-------|------|----------------------|
| `/api/admin/students/list` | `routes/api/admin/students/list/+server.ts` | ??? |
| `/api/admin/users/[pk]/profile` | `routes/api/admin/users/[pk]/profile/+server.ts` | ??? |

**Step 2 — Check agent endpoints:**

- Does `AdminAgent` or `ParentAgent` have matching endpoints?
- Check `agents/app-agents/<agent>_agent.mbt` for `#derive.endpoint` annotations
- Check `agents/app-agents/<agent>_handler.mbt` for handler functions

**Step 3 — Check `golem.yaml` for route registration:**

- Is the agent registered under `httpApi` → `routes`?
- Is the path correct?

**Step 4 — Test connectivity:**
```
golem agent invoke SuperAdminAgent() db_test
```

**Mitigation (frontend):** Add `proxyFetch` error logging to surface the actual HTTP status and agent error message in the browser console for debugging.

### 4. Semantic Token Migration (App-wide)

**Goal:** Every color class comes from `@theme inline` tokens in `app.css`, not raw Tailwind palette classes.

**Tokens available:**
- `primary-50` through `primary-950` (blue)
- `secondary-50` through `secondary-900` (amber)
- `surface-50`, `surface-100`, `surface-200`, `surface-700`, `surface-800`, `surface-900`, `surface-950` (zinc)
- `success-50`, `success-100`, `success-500`, `success-600` (green)
- `error-50`, `error-100`, `error-500`, `error-600` (red)
- `background` / `foreground`
- `card` / `card-foreground`
- `popover` / `popover-foreground`
- `muted` / `muted-foreground`
- `accent` / `accent-foreground`
- `destructive` / `destructive-foreground`
- `border` / `input` / `ring`
- `sidebar` / `sidebar-foreground` / `sidebar-primary` / `sidebar-accent` / `sidebar-border`

**Pattern — map raw → semantic:**

| Raw Class | Semantic Token | Rationale |
|-----------|---------------|-----------|
| `text-surface-800` | `text-foreground` or `text-card-foreground` or `text-sidebar-foreground` | Dark text on light bg |
| `text-surface-700` | `text-muted-foreground` | Secondary text |
| `text-surface-600` | `text-muted-foreground` | Secondary text |
| `text-surface-400` | `text-muted-foreground` | Placeholder/muted |
| `text-error-500` | `text-destructive` | Error text |
| `bg-surface-100` | `bg-muted` or `bg-accent` | Subtle background |
| `bg-surface-900` (dark) | `bg-card` or `bg-accent` | Card background in dark |
| `bg-white` | `bg-background` | Default background |
| `border-surface-200` | `border-border` | Borders |
| `border-surface-300` | `border-input` | Form inputs |

**Files requiring migration** (full audit):

All `.svelte` files in:
- `src/routes/+layout.svelte`
- `src/routes/+page.svelte`
- `src/routes/admin/users/*/`
- `src/routes/admin/configuration/*/`
- `src/routes/lms/*/[subjectId]/`
- `src/routes/my-classes/*/`
- `src/lib/components/PageHeader.svelte`
- `src/lib/components/ThemeToggle.svelte`
- `src/lib/components/ui/status-card/status-card.svelte`
- `src/lib/components/ui/app-button.svelte`
- `src/lib/components/LessonPage.svelte`
- `src/lib/components/ui/toast/toast.svelte`

**Method:** Global grep for `text-surface-`, `bg-surface-`, `text-error-`, `border-surface-`, `bg-white`, `bg-amber-`, then replace case-by-case using the mapping above.

### 5. Global Cursor CSS

**`app.css`** `@layer base` block:
```css
button:not(:disabled),
a[href],
[role="button"]:not(:disabled),
summary,
input[type="checkbox"],
input[type="radio"],
select,
label:has(input[type="checkbox"]),
label:has(input[type="radio"]) {
  cursor: pointer;
}
button:disabled,
a[aria-disabled="true"] {
  cursor: not-allowed;
}
```

### 6. Amber Accent Polish

**Loading bar** (`+layout.svelte:98`):
- Reduce height: `h-2` → `h-0.5`
- Increase brightness in light mode: use `bg-secondary-400` (brighter amber) for light, keep `bg-secondary-500` for dark

**Tab active indicator** (`LessonPage.svelte:203`):
- Active tab: add `border-secondary-500`

**Selection/focus rings:**
- Form element focus: use `ring-secondary-500` on key inputs (username, email) as subtle amber glow

**Active sidebar item:**
- If shadcn sidebar supports active state customization, add subtle `bg-secondary-50/50 dark:bg-secondary-900/20` for active nav items

### 7. Top Loading Bar Refinement

- Slim from `h-2` (8px) to `h-0.5` (2px)
- Use `bg-secondary-400` for light mode (brighter = more visible), `bg-secondary-500` for dark
- Keep `fixed top-0 left-0 right-0 z-50`
- Keep `animate-pulse`

### 8. Skeleton Page Component

**New file:** `src/lib/components/ui/skeleton/PageSkeleton.svelte`

```svelte
<script lang="ts">
  let { layout = 'list', rows = 6 }: { layout?: 'list' | 'grid' | 'card'; rows?: number } = $props();
</script>

{#if layout === 'list'}
  <div class="space-y-3">
    {#each Array(rows) as _}
      <div class="h-12 bg-muted animate-pulse rounded-md" />
    {/each}
  </div>
{:else if layout === 'grid'}
  <div class="grid gap-6 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
    {#each Array(rows) as _}
      <div class="h-28 bg-muted animate-pulse rounded-lg" />
    {/each}
  </div>
{:else if layout === 'card'}
  <div class="h-48 bg-muted animate-pulse rounded-lg" />
{/if}
```

**Apply to:**
- `+page.svelte` lines 42-45 (teacher dash) and 77-80 (student dash): replace inline skeletons
- `lms/[subjectId]/+page.svelte` lines 17-20
- `lms/[subjectId]/[termId]/+page.svelte` (similar pattern)
- `my-classes/[classId]/+page.svelte`
- `my-classes/[classId]/[subjectId]/+page.svelte`
- `my-classes/[classId]/[subjectId]/[termId]/+page.svelte`
- All 4 UserTable pages (loading states)

### 9. Mobile Sidebar Auto-Close on Navigation

**`+layout.svelte`** — Add:
```ts
import { useSidebar } from '$lib/components/ui/sidebar/context.svelte.js';
const sb = useSidebar();
$effect(() => {
  $page.url.pathname;
  sb.setOpenMobile(false);
});
```

### 10. Interactive Hover Effects

| Location | Current | Fix |
|----------|---------|-----|
| `<TableRow>` in all UserTables | None | `class="hover:bg-muted/50 transition-colors"` |
| Sidebar footer user info `+layout.svelte:193-196` | Plain div | `class="p-4 hover:bg-sidebar-accent rounded-md transition-colors"` |
| StatusCard Retry button | `hover:bg-surface-100` | Change `bg-surface-100` to `bg-muted` (semantic) |

## Implementation Order

1. Branding images — copy assets, update imports, update `app.html`
2. Global cursor CSS — one block in `app.css`
3. Semantic token migration — grep-and-replace across all `.svelte` files
4. Edit dialog lazy-load — 4 tables, same pattern
5. Amber accent polish — `app.css` + `LessonPage.svelte`
6. Top loading bar refinement — `+layout.svelte`
7. PageSkeleton component — new file + integrate into pages
8. Mobile sidebar auto-close — `+layout.svelte`
9. Table row + sidebar footer hover — UserTables + layout
10. 502 error investigation — trace proxy routes to agent endpoints

## Files Changed

| File | Change |
|------|--------|
| `docs/temp/images/logo.jpg` → `src/lib/assets/logo.jpg` | New logo asset |
| `docs/temp/images/logo.png` → `static/favicon.png` | New favicon asset |
| `src/lib/assets/favicon.svg` | Delete (replaced by PNG) |
| `src/lib/assets/logo.svg` | Delete (replaced by JPG) |
| `src/app.html` | Add `<link rel="icon" href="/favicon.png">` |
| `src/app.css` | Global cursor rules, amber accent ring, semantic token fixes |
| `src/routes/+layout.svelte` | Logo import, slim loading bar, mobile sidebar close, sidebar footer hover |
| `src/routes/+page.svelte` | Semantic tokens, PageSkeleton |
| `src/routes/admin/users/students/StudentUserTable.svelte` | Lazy edit dialog, semantic tokens, table row hover |
| `src/routes/admin/users/teachers/TeacherUserTable.svelte` | Lazy edit dialog, semantic tokens, table row hover |
| `src/routes/admin/users/admin-role/AdminUserTable.svelte` | Lazy edit dialog, semantic tokens, table row hover |
| `src/routes/admin/users/parents/ParentUserTable.svelte` | Lazy edit dialog, semantic tokens, table row hover |
| `src/routes/admin/configuration/session-terms/+page.svelte` | Semantic tokens |
| `src/routes/admin/configuration/terms/+page.svelte` | Semantic tokens |
| `src/routes/lms/[subjectId]/+page.svelte` | Semantic tokens, PageSkeleton |
| `src/routes/lms/[subjectId]/[termId]/+page.svelte` | Semantic tokens, PageSkeleton |
| `src/routes/my-classes/[classId]/+page.svelte` | Semantic tokens, PageSkeleton |
| `src/routes/my-classes/[classId]/[subjectId]/+page.svelte` | Semantic tokens, PageSkeleton |
| `src/routes/my-classes/[classId]/[subjectId]/[termId]/+page.svelte` | Semantic tokens, PageSkeleton |
| `src/lib/components/PageHeader.svelte` | Semantic tokens |
| `src/lib/components/ThemeToggle.svelte` | Semantic tokens, cursor-pointer |
| `src/lib/components/LessonPage.svelte` | Amber tab indicator, semantic tokens |
| `src/lib/components/ui/status-card/status-card.svelte` | Semantic tokens, cursor |
| `src/lib/components/ui/toast/toast.svelte` | Semantic tokens |
| `src/lib/components/ui/skeleton/PageSkeleton.svelte` | **NEW** |
| `src/routes/api/admin/students/list/+server.ts` | 502 investigation |
| `src/routes/api/admin/users/[pk]/profile/+server.ts` | 502 investigation |

## Dependencies

No new packages. All existing shadcn-svelte and Tailwind tokens used.

## Verification Checklist

- [ ] `pnpm check` 0 errors
- [ ] `pnpm build` passes
- [ ] School logo (JPG) visible in sidebar header
- [ ] Favicon (PNG) visible in browser tab
- [ ] Edit dialogs open immediately on click (all 4 roles)
- [ ] Edit dialogs show "Loading profile data..." with disabled save button while fetching
- [ ] Edit dialogs populate fields when data arrives
- [ ] Edit dialogs allow manual fill if fetch fails
- [ ] No `text-surface-*`, `bg-surface-*`, `text-error-500`, `border-surface-*`, `bg-white` raw classes remain — all semantic
- [ ] Dark mode text contrast acceptable on sidebar footer, status cards, dashboard
- [ ] Global cursor-pointer on all clickable elements (buttons, links, checkboxes, selects)
- [ ] Top loading bar is slimmer (`h-0.5`) and visible amber in light mode
- [ ] Amber accent visible on active tab indicator
- [ ] Mobile sidebar closes automatically on navigation
- [ ] Table rows have hover highlight
- [ ] Sidebar footer user info has hover effect
- [ ] 502 errors traced and either fixed or documented with root cause
- [ ] No regressions on user CRUD flows
- [ ] No regressions on teacher class assignment
- [ ] No regressions on LMS browsing (subjects → terms → lessons)
- [ ] No regressions on session term management
- [ ] No regressions on term toggle
