# Hotfix-12: UI Consistency & Branding Unification

## Goal

Unify the design language across all pages, implement dark mode toggle, add school branding (logo/favicon/title), fix layout bugs, standardize error/empty/loading states behind `StatusCard`, extract repeated patterns into shared components for DRY consistency, and ensure mobile responsiveness everywhere.

## Design

### Brand Identity

- Replace default Svelte kit favicon with a text-based school logo SVG
- Sidebar header: branded logo + school name (replacing bare `<span>School</span>`)
- Page title: `"{page} — School Management System"` consistently via `<svelte:head>` in layout
- `theme-color` meta tag for mobile browser chrome (primary blue `#3b82f6`)

### Dark Mode

- Toggle button in navbar (next to user avatar) with moon/sun icon
- Persisted in `localStorage`, respects `prefers-color-scheme` on first visit
- All existing `dark:` CSS variants already cover 47 components — just need the toggle

### UI Pattern: `PageHeader.svelte`

Reusable component for consistent page headers across the entire app:

```
Props:
  title: string              — page heading
  createLabel?: string       — shows AppButton if provided
  onCreate?: () => void
  backHref?: string          — shows back arrow if provided

Renders:
<div class="flex items-center justify-between">
  <div class="flex items-center gap-3">
    {#if backHref}<a href={backHref}>← Back</a>{/if}
    <h1 class="text-2xl font-display font-bold text-primary-700">{title}</h1>
  </div>
  {#if createLabel && onCreate}
    <AppButton onclick={onCreate}>{createLabel}</AppButton>
  {/if}
</div>
```

### UI Pattern: `StatusCard` everywhere

- No raw `<Alert>` anywhere for page-level states
- No custom inline HTML empty states (icon + h2 + p blocks)
- `StatusCard variant="error|info|warning"` for every error/empty/warning state
- Remove dual toast+StatusCard pattern (use StatusCard for page-level, toast for action feedback)

### Container Width

- All list/table pages: `space-y-6` (full width, matching user management pages)
- Lesson detail pages: keep `max-w-5xl` with `mx-auto` and responsive padding
- Remove stray `max-w-4xl`/`max-w-6xl` inconsistencies

---

## Implementation

### 1. Fix Known Bugs

| File | Line | Bug | Fix |
|---|---|---|---|
| `+layout.svelte` | 115 | `roles.includes('teachers')` — plural, never matches | Change to `'teacher'` |
| `+layout.svelte` | 119 | My Classes `href="/"` goes to dashboard | Change to `href="/my-classes"` |

---

### 2. Branding — Favicon, Logo, Title

#### `src/lib/assets/favicon.svg` — replace Svelte default

Replace with a school-brand SVG: primary-blue circle background with white book icon or school initials. Simple, professional, scales to any size.

#### `src/lib/assets/logo.svg` — NEW

Text-based logo: school name in bold Inter Display, primary-blue colored. Used in sidebar header. Can be enhanced with an icon later.

#### `+layout.svelte` — sidebar header

Replace:
```svelte
<span class="text-lg font-display font-bold text-primary-700">School</span>
```
With:
```svelte
<div class="flex items-center gap-2">
  <img src={logo} alt="" class="h-8 w-8" />
  <span class="text-lg font-display font-bold text-primary-700">School MS</span>
</div>
```
Where `logo` is imported from `$lib/assets/logo.svg`.

#### `+layout.svelte` — page title

Add `<svelte:head>` block:
```svelte
<svelte:head>
  <title>{$page.data.title ?? 'School Management System'}</title>
</svelte:head>
```

Each page sets `title` via its server load function:
```typescript
return { title: 'Student Users' };
```

#### `app.html` — theme-color meta

Add:
```html
<meta name="theme-color" content="#3b82f6" />
```

---

### 3. Dark Mode Toggle

#### New file: `$lib/components/ThemeToggle.svelte`

```svelte
<script lang="ts">
  import { onMount } from 'svelte';
  let dark = $state(false);

  onMount(() => {
    const stored = localStorage.getItem('theme');
    if (stored === 'dark' || (!stored && window.matchMedia('(prefers-color-scheme: dark)').matches)) {
      dark = true;
      document.documentElement.classList.add('dark');
    }
  });

  function toggle() {
    dark = !dark;
    document.documentElement.classList.toggle('dark', dark);
    localStorage.setItem('theme', dark ? 'dark' : 'light');
  }
</script>

<button onclick={toggle} class="rounded-md p-2 text-surface-600 hover:bg-surface-100 dark:text-surface-400 dark:hover:bg-surface-800" aria-label="Toggle theme">
  {#if dark}
    <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
      <path stroke-linecap="round" stroke-linejoin="round" d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z" />
    </svg>
  {:else}
    <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
      <path stroke-linecap="round" stroke-linejoin="round" d="M20.354 15.354A9 9 0 018.646 3.646 9.003 9.003 0 0012 21a9.003 9.003 0 008.354-5.646z" />
    </svg>
  {/if}
</button>
```

#### Placement

In `+layout.svelte` navbar header, between the sidebar trigger and the breadcrumbs (or between breadcrumbs and user dropdown).

---

### 4. PageHeader Component

#### New file: `$lib/components/PageHeader.svelte`

```svelte
<script lang="ts">
  import AppButton from './ui/app-button.svelte';

  let {
    title,
    createLabel = undefined as string | undefined,
    onCreate = undefined as (() => void) | undefined,
    backHref = undefined as string | undefined
  } = $props();
</script>

<div class="flex items-center justify-between">
  <div class="flex items-center gap-3">
    {#if backHref}
      <a href={backHref} class="rounded-md p-1 text-surface-400 hover:text-surface-700 hover:bg-surface-100 dark:hover:text-surface-300 dark:hover:bg-surface-800 transition" aria-label="Back">
        <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M15 19l-7-7 7-7" /></svg>
      </a>
    {/if}
    <h1 class="text-2xl font-display font-bold text-primary-700 dark:text-primary-300">{title}</h1>
  </div>
  {#if createLabel && onCreate}
    <AppButton onclick={onCreate}>{createLabel}</AppButton>
  {/if}
</div>
```

#### Applied to all pages

Every page swaps its inline `<h1>` + create button pattern for:
```svelte
<PageHeader title="Student Users" createLabel="Create Student" onCreate={() => showCreateDialog = true} />
```

Specific pages:
- All 4 user management pages: `<PageHeader title="..." createLabel="Create ..." onCreate={...} />`
- Session terms: `<PageHeader title="Session Terms" createLabel="Create Session Term" onCreate={...} />`
- Terms: `<PageHeader title="Terms" />` (no create — read-only)
- Student LMS subject page: `<PageHeader title={data.subjectName} />` or use it as inline heading
- Teacher My Classes pages: each gets PageHeader with heading + optional back button

---

### 5. Standardize StatusCard Across All Pages

#### Pages to fix:

| Page | Lines | Current | Replace With |
|---|---|---|---|
| `lms/[subjectId]/+page.svelte` | 22–29 | `<Alert variant="destructive">` + `<AlertAction>` + `<AppButton>` | `<StatusCard variant="error" title="Failed to load terms" description={data.termsError} onRetry={...} />` |
| `lms/[subjectId]/+page.svelte` | 30–40 | Custom inline HTML (centered div, SVG icon, `<h2>`, `<p>`) | `<StatusCard variant="info" title="No Terms Available" description="No terms are available for this subject yet." />` |
| `+page.svelte` | 16–31 | Dual toast + StatusCard for same error | Remove `addToast` in `$effect` blocks — keep StatusCard only for page-level errors |

#### Session terms page

- Move create button from scattered content blocks into `PageHeader`
- Existing StatusCard usage is already correct — just move create button
- Remove `goto()` navigation after create — refresh component state instead

---

### 6. Unify Container Widths

| Page | Current | Change To |
|---|---|---|
| All 4 user management pages | `space-y-6` | Keep |
| Session terms | `mx-auto max-w-4xl space-y-6` | `space-y-6` |
| Terms | `mx-auto max-w-6xl space-y-6` | `space-y-6` |
| `my-classes/[classId]` (subjects) | `mx-auto max-w-6xl space-y-6` | `space-y-6` |
| `my-classes/[subjectId]` (terms) | `mx-auto max-w-4xl space-y-6` | `space-y-6` |
| `my-classes/[termId]` (lessons) | `mx-auto max-w-4xl space-y-6` | `space-y-6` |
| `my-classes/[lessonId]` (lesson) | `mx-auto w-full max-w-5xl px-4 sm:px-6 lg:px-8` | Keep |
| `lms/[subjectId]` (terms) | `mx-auto max-w-4xl space-y-6` | `space-y-6` |
| `lms/[termId]` (lessons) | `mx-auto max-w-4xl space-y-6` | `space-y-6` |
| `lms/[lessonId]` (lesson) | `mx-auto w-full max-w-5xl px-4 sm:px-6 lg:px-8` | Keep |
| Root page (`+page.svelte`) | Various inner containers | `space-y-6` on outermost wrapper |

---

### 7. Mobile Responsiveness

**Already responsive:** Sidebar (shadcn handles collapse), lesson detail pages.

**Fixes needed:**
- Table components: wrap in `<div class="overflow-x-auto">` for horizontal scroll on mobile
- Card grids: ensure `grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4`
- Password field rows in dialogs: `flex-col sm:flex-row`
- NameFields already correct (`grid-cols-1 sm:grid-cols-3`)
- All dialog content: ensure `sm:max-w-lg` and inputs handle narrow widths

---

### 8. Data Fetching Unification

All LMS server load functions use the same `proxyToStudent()`/`proxyToTeacher()` helpers that the dashboard uses, instead of raw `fetch()`:

| File | Current | Change To |
|---|---|---|
| `lms/[subjectId]/+page.server.ts` | `fetch('/api/student/terms')` | `proxyToStudent(user.id, '/terms')` |
| `lms/[subjectId]/[termId]/+page.server.ts` | `fetch('/api/student/lessons?...')` | `proxyToStudent(user.id, '/lessons', { subject_id, term_id })` |
| `lms/[subjectId]/[termId]/[lessonId]/+page.server.ts` | `fetch('/api/student/lesson?...')` | `proxyToStudent(user.id, '/lesson', { lesson_id })` |

This ensures consistent auth token injection and error formatting.

---

### 9. Remove Redundant Patterns

| File | Pattern | Fix |
|---|---|---|
| `my-classes/[subjectId]/+page.svelte` | `$derived`+`$state`+`$effect` wrapper on `terms` | Use `data.terms` directly — terms are never mutated |
| `my-classes/[termId]/+page.svelte` | `lessonsSource` `$derived` variable | Inline or simplify — only needed because of optimistic UI mutation |
| `my-classes/[lessonId]/+page.server.ts:7` | Redundant `roles.includes('teacher')` check | Remove — layout already gates teacher routes |

---

### 10. Favicon & Logo Assets

#### `src/lib/assets/favicon.svg`

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
  <rect width="32" height="32" rx="8" fill="#3b82f6"/>
  <text x="16" y="22" text-anchor="middle" fill="white" font-family="Inter, system-ui, sans-serif" font-size="18" font-weight="700">SM</text>
</svg>
```

#### `src/lib/assets/logo.svg`

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 48">
  <rect x="4" y="4" width="40" height="40" rx="10" fill="#3b82f6"/>
  <text x="24" y="30" text-anchor="middle" fill="white" font-family="Inter, system-ui, sans-serif" font-size="22" font-weight="700">SM</text>
  <text x="56" y="34" fill="#1d4ed8" font-family="Inter, system-ui, sans-serif" font-size="20" font-weight="700">School MS</text>
</svg>
```

---

## Files Changed

| File | Change |
|---|---|
| `src/lib/assets/favicon.svg` | Replace with school brand SVG |
| `src/lib/assets/logo.svg` | NEW — school logo for sidebar |
| `src/app.html` | Add `theme-color` meta |
| `src/routes/+layout.svelte` | Logo in header, page title, ThemeToggle, fix sidebar bugs |
| `src/routes/+layout.server.ts` | Pass `title` through load |
| `src/lib/components/PageHeader.svelte` | NEW |
| `src/lib/components/ThemeToggle.svelte` | NEW |
| `src/routes/+page.svelte` | Remove dual toast, PageHeader |
| `src/routes/admin/users/*/+page.svelte` (4 files) | Use PageHeader |
| `src/routes/admin/configuration/session-terms/+page.svelte` | PageHeader + StatusCard consolidation |
| `src/routes/admin/configuration/terms/+page.svelte` | PageHeader, container fix |
| `src/routes/lms/[subjectId]/+page.svelte` | StatusCard (was Alert), container fix, PageHeader |
| `src/routes/lms/[subjectId]/+page.server.ts` | proxyToStudent |
| `src/routes/lms/[subjectId]/[termId]/+page.svelte` | Container fix, PageHeader |
| `src/routes/lms/[subjectId]/[termId]/+page.server.ts` | proxyToStudent |
| `src/routes/lms/[subjectId]/[termId]/[lessonId]/+page.svelte` | StatusCard verify |
| `src/routes/lms/[subjectId]/[termId]/[lessonId]/+page.server.ts` | proxyToStudent |
| `src/routes/my-classes/[classId]/+page.svelte` | Container fix, PageHeader |
| `src/routes/my-classes/[classId]/[subjectId]/+page.svelte` | Container fix, remove dead wrapper, PageHeader |
| `src/routes/my-classes/[classId]/[subjectId]/[termId]/+page.svelte` | Container fix, PageHeader |
| `src/routes/my-classes/[classId]/[subjectId]/[termId]/[lessonId]/+page.server.ts` | Remove redundant role check |

---

## Dependencies

No new packages required. All existing shadcn components used.

---

## Verification Checklist

- [ ] `pnpm check` 0 errors
- [ ] `pnpm build` passes
- [ ] School favicon visible in browser tab
- [ ] Logo visible in sidebar header (SVG with "SM" + "School MS")
- [ ] Page title shows "{page} — School Management System"
- [ ] Dark mode toggle works (light ↔ dark), persists across reloads
- [ ] Dark mode respects `prefers-color-scheme` on first visit
- [ ] All `dark:` variants render correctly in dark mode
- [ ] "My Classes" link navigates to `/my-classes` correctly
- [ ] "My Classes" link visible for teacher users
- [ ] All admin pages have consistent `PageHeader` (h1 + create button)
- [ ] Session terms create button in header (not scattered in content blocks)
- [ ] All LMS pages use `StatusCard` for error/empty (no `Alert`, no custom HTML)
- [ ] No dual toast+StatusCard error feedback on root page
- [ ] All page containers use `space-y-6` (or consistent pattern)
- [ ] Tables scroll horizontally on mobile
- [ ] Forms don't overflow on mobile
- [ ] Card grids responsive (1→2→3→4 cols)
- [ ] Password fields stack vertically on mobile
- [ ] LMS pages use `proxyToStudent` not raw `fetch`
- [ ] No leftover `$derived`+`$state` wrappers on unmutated data
- [ ] Breadcrumbs render correctly on all pages
- [ ] Toast notifications work for all CRUD operations
- [ ] No regressions on create/edit/delete user flows
- [ ] No regressions on teacher class assignment
- [ ] No regressions on session term management
- [ ] No regressions on term toggle
