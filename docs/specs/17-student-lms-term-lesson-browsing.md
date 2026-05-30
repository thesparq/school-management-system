# Unit 17 — Student LMS: Term & Lesson Browsing

## Goal

Enable students to browse the academic terms available for a subject and view the lesson list within a selected term, with clear visual distinction between active and inactive items and dynamic breadcrumb navigation.

## Design

### Routes

| Route | Page | Data |
|---|---|---|
| `/lms/[subjectId]` | Term selection | Terms loaded via existing `/api/student/terms?subject_id=...` |
| `/lms/[subjectId]/[termId]` | Lesson list | Lessons loaded via existing `/api/student/lessons?subject_id=...&term_id=...` |

The `[subjectId]` param is the subject's SurrealDB record ID (e.g., `subjects:basic_science`, returned as `subject.id` from `/gateway/student/subjects`). The Student Agent resolves the corresponding `has_subject` edge ID from its `edge_cache`. The `[termId]` param is the term's record ID (e.g., `terms:first`).

### Term Page (`/lms/[subjectId]`)

- **Heading**: Subject name in `font-display text-2xl text-primary-700`
- **Term cards**: Horizontal row of compact shadcn-svelte `Card` components:

| Element | Token / Class | Notes |
|---|---|---|
| **Card** | `w-48 hover:bg-primary-50 dark:hover:bg-primary-950/30 hover:ring-primary-200 dark:hover:ring-primary-700 transition cursor-pointer` | Wrapped in `<a href="/lms/{subjectId}/{term.id}">` for active terms |
| **CardHeader** | `pb-2` | |
| **CardTitle** | `font-display text-base text-primary-700` | Term name (e.g., "First Term") |

**Inactive term card**:

- `opacity-50 pointer-events-none` on the outer element (a `<div>` instead of `<a>`)
- Small lock SVG icon (`h-4 w-4 text-surface-400`) in the top-right corner of the CardHeader
- Title text: `text-surface-400` instead of `text-primary-700`

**States**:

| State | Rendering |
|---|---|
| **Loading** | 3 `Skeleton` blocks (`h-28 w-48`) in the same flex layout — visible only during client-side navigation when `$navigating` is true and terms are not yet loaded |
| **Data** | Heading + horizontal row of term cards |
| **Empty** | Centered info circle icon (amber, `secondary-400`) + "No terms available for this subject." |
| **Error** | Destructive `Alert` with error message + "Retry" `Button` (calls `goto('/lms/' + subjectId)`) |

### Lesson List Page (`/lms/[subjectId]/[termId]`)

- **Back link**: `<a href="/lms/{subjectId}"` with `"← Back to terms"` text in `text-sm text-primary-500 hover:underline`
- **Heading**: `"{Term Name} — Lessons"` in `font-display text-2xl text-primary-700`
- **Lesson list**: Vertical stack (`space-y-3`) of compact Cards:

| Element | Token / Class | Notes |
|---|---|---|
| **Card** | `hover:bg-primary-50 dark:hover:bg-primary-950/30 transition cursor-pointer` | Wrapped in `<a>` for active lessons; `<div>` with `opacity-50 pointer-events-none` for inactive |
| **CardHeader** | `pb-0` | |
| **CardTitle** | `font-display text-base text-primary-700` | `"Week {n}: {topic_title}"` |

**Inactive lesson card**: Same treatment as inactive terms (greyed + lock icon).

**States**:

| State | Rendering |
|---|---|
| **Loading** | 5 `Skeleton` blocks (`h-16` each) in a vertical stack |
| **Data** | Heading + vertical list of lesson cards |
| **Empty** | Centered info circle + "No lessons available for this term." |
| **Error** | Destructive `Alert` + "Retry" button |

**Navigation note:** Active lesson cards link to `/lms/{subjectId}/{termId}/{lessonId}` which will 404 until Unit 19 builds that route. This is intentional — the card component will not need modification in Unit 19.

### Breadcrumb

**Type** (`frontend/src/lib/types.ts`):

```typescript
export interface BreadcrumbItem {
  label: string;
  href?: string;
}
```

**Layout rendering** (`frontend/src/routes/+layout.svelte`):

Replace the static `BreadcrumbPage>Dashboard</BreadcrumbPage` block with a dynamic loop reading from `$page.data.breadcrumbs`:

```svelte
<Breadcrumb>
  <BreadcrumbList>
    {#each ($page.data.breadcrumbs ?? [{ label: 'Dashboard' }]) as crumb, i (i)}
      <BreadcrumbItem>
        {#if (crumb.href ?? false) && i < ($page.data.breadcrumbs?.length ?? 1) - 1}
          <BreadcrumbLink href={crumb.href}>{crumb.label}</BreadcrumbLink>
        {:else}
          <BreadcrumbPage>{crumb.label}</BreadcrumbPage>
        {/if}
      </BreadcrumbItem>
      {#if i < ($page.data.breadcrumbs?.length ?? 1) - 1}
        <BreadcrumbSeparator />
      {/if}
    {/each}
  </BreadcrumbList>
</Breadcrumb>
```

- `$page` is already imported in the layout from `$app/stores`
- Fallback to `[{ label: 'Dashboard' }]` ensures backward compatibility with all existing pages
- The last item is always rendered as `BreadcrumbPage` (bold, non-clickable)
- Items with no `href` render as `BreadcrumbPage` (non-clickable)
- Items with `href` that are not the last item render as `BreadcrumbLink` (clickable)

**Breadcrumb values per route**:

| Route | Breadcrumbs |
|---|---|
| `/` (dashboard) | `undefined` → defaults to `[{ label: 'Dashboard' }]` |
| `/lms/[subjectId]` | `[{ label: 'LMS' }, { label: subjectName }]` |
| `/lms/[subjectId]/[termId]` | `[{ label: 'LMS' }, { label: subjectName, href: '/lms/{subjectId}' }, { label: termName }]` |
| `/admin/*` | `undefined` → defaults to `[{ label: 'Dashboard' }]` |

The subject name and term name are resolved server-side in the page load function by scanning the cached subjects/terms lists.

### Layout & Color Tokens

- Term card container: `flex gap-4 flex-wrap` — cards wrap naturally on small screens
- Lesson list container: `space-y-3`
- Lock icon SVG: `h-4 w-4 text-surface-400`, positioned via `flex justify-between items-start` in CardHeader
- Inactive title: `text-surface-400` title, `opacity-50` on wrapper
- Skeleton: shadcn's `bg-muted` with `h-16` (lesson) or `h-28 w-48` (term)

## Implementation

### 1. `frontend/src/lib/types.ts` — Add BreadcrumbItem and Lesson.active

Add:

```typescript
export interface BreadcrumbItem {
  label: string;
  href?: string;
}
```

Update `Lesson`:

```typescript
export interface Lesson {
  id: string;
  topic_title: string | null;
  week: number | null;
  active?: boolean;
}
```

The `active` field is optional (backward-compatible) because the agent may or may not include it depending on the query. `{#if lesson.active !== false}` treats `undefined` as active.

### 2. `frontend/src/routes/+layout.svelte` — Dynamic breadcrumb

**Add import**:

```typescript
import { BreadcrumbLink, BreadcrumbSeparator } from '$lib/components/ui/breadcrumb';
```

**Replace** the static Breadcrumb block (lines 122-128) with the dynamic render loop in the Design section above.

**Remove** unused imports (none needed — `page` and `navigating` are already imported; no new store imports required).

### 3. `frontend/src/routes/lms/[subjectId]/+page.server.ts` — Terms page load

```typescript
import { proxyToGateway } from '$lib/server/golem';
import type { PageServerLoad } from './$types';
import type { Term, BreadcrumbItem } from '$lib/types';

export const load: PageServerLoad = async ({ params, locals }) => {
  const userId = locals.user?.id;
  if (!userId) {
    return { terms: [], subjectName: null, termsError: 'Not authenticated.', breadcrumbs: [{ label: 'LMS' }] as BreadcrumbItem[] };
  }

  const subjectId = params.subjectId;

  const termsResult = await proxyToGateway('/gateway/student/terms', userId, { subject_id: subjectId });
  if (termsResult.error) {
    return { terms: [], subjectName: null, termsError: termsResult.error.message, breadcrumbs: [{ label: 'LMS' }, { label: 'Subject' }] };
  }

  let terms: Term[];
  try {
    terms = JSON.parse(termsResult.data);
  } catch {
    return { terms: [], subjectName: null, termsError: 'Invalid response from server.', breadcrumbs: [{ label: 'LMS' }, { label: 'Subject' }] };
  }

  let subjectName = 'Subject';
  let subjectName = 'Subject';
  const subjectsResult = await proxyToGateway('/gateway/student/subjects', userId);
  if (!subjectsResult.error) {
    try {
      const subjects = JSON.parse(subjectsResult.data);
      const match = Array.isArray(subjects) ? subjects.find((s: any) => s.id === subjectId) : null;
      if (match) subjectName = match.name;
    } catch { /* fallback to default */ }
  }

  return {
    terms,
    subjectName,
    termsError: null,
    breadcrumbs: [
      { label: 'LMS' } as BreadcrumbItem,
      { label: subjectName } as BreadcrumbItem
    ]
  };
};
```

### 4. `frontend/src/routes/lms/[subjectId]/+page.svelte` — Terms page

```svelte
<script lang="ts">
  import type { PageData } from './$types';
  import { Card, CardContent, CardHeader, CardTitle } from '$lib/components/ui/card';
  import { Alert, AlertTitle, AlertDescription, AlertAction } from '$lib/components/ui/alert';
  import { Skeleton } from '$lib/components/ui/skeleton';
  import { Button } from '$lib/components/ui/button';
  import { page, navigating } from '$app/stores';
  import { goto } from '$app/navigation';

  let { data }: { data: PageData } = $props();
</script>

<div class="mx-auto max-w-4xl space-y-6">
  <h1 class="text-2xl font-display font-bold text-primary-700">{data.subjectName}</h1>

  {#if $navigating && (!data.terms || data.terms.length === 0)}
    <div class="flex gap-4 flex-wrap">
      {#each Array(3) as _}
        <Skeleton class="h-28 w-48" />
      {/each}
    </div>
  {:else if data.termsError}
    <Alert variant="destructive">
      <AlertTitle>Failed to load terms</AlertTitle>
      <AlertDescription>{data.termsError}</AlertDescription>
      <AlertAction>
        <Button variant="outline" onclick={() => goto('/lms/' + $page.params.subjectId)}>Retry</Button>
      </AlertAction>
    </Alert>
  {:else if data.terms.length === 0}
    <div class="mx-auto max-w-lg py-16 text-center space-y-6">
      <div class="rounded-full bg-secondary-100 dark:bg-secondary-900/20 mx-auto w-fit p-4">
        <svg xmlns="http://www.w3.org/2000/svg" class="h-8 w-8 text-secondary-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <circle cx="12" cy="12" r="10" />
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 16v-4m0-4h.01" />
        </svg>
      </div>
      <h2 class="text-xl font-semibold text-surface-800">No Terms Available</h2>
      <p class="text-surface-700">No terms are available for this subject yet.</p>
    </div>
  {:else}
    <div class="flex gap-4 flex-wrap">
      {#each data.terms as term (term.id)}
        {#if term.active}
          <a href="/lms/{$page.params.subjectId}/{term.id}">
            <Card class="w-48 hover:bg-primary-50 dark:hover:bg-primary-950/30 hover:ring-primary-200 dark:hover:ring-primary-700 transition cursor-pointer">
              <CardHeader class="pb-2">
                <CardTitle class="font-display text-base text-primary-700">{term.name}</CardTitle>
              </CardHeader>
            </Card>
          </a>
        {:else}
          <Card class="w-48 opacity-50 pointer-events-none">
            <CardHeader class="pb-2">
              <div class="flex justify-between items-start">
                <CardTitle class="font-display text-base text-surface-400">{term.name}</CardTitle>
                <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-surface-400 shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                </svg>
              </div>
            </CardHeader>
          </Card>
        {/if}
      {/each}
    </div>
  {/if}
</div>
```

### 5. `frontend/src/routes/lms/[subjectId]/[termId]/+page.server.ts` — Lessons page load

```typescript
import { proxyToGateway } from '$lib/server/golem';
import type { PageServerLoad } from './$types';
import type { Lesson, BreadcrumbItem } from '$lib/types';

export const load: PageServerLoad = async ({ params, locals }) => {
  const userId = locals.user?.id;
  if (!userId) {
    return { lessons: [], termName: null, lessonsError: 'Not authenticated.', breadcrumbs: [{ label: 'LMS' }] as BreadcrumbItem[] };
  }

  const subjectId = params.subjectId;
  const termId = params.termId;

  const lessonsResult = await proxyToGateway('/gateway/student/lessons', userId, { subject_id: subjectId, term_id: termId });
  if (lessonsResult.error) {
    return { lessons: [], termName: null, lessonsError: lessonsResult.error.message, breadcrumbs: [{ label: 'LMS' }, { label: 'Subject' }, { label: 'Term' }] };
  }

  let lessons: Lesson[];
  try {
    lessons = JSON.parse(lessonsResult.data);
  } catch {
    return { lessons: [], termName: null, lessonsError: 'Invalid response from server.', breadcrumbs: [{ label: 'LMS' }, { label: 'Subject' }, { label: 'Term' }] };
  }

  let termName = 'Term';
  const termsResult = await proxyToGateway('/gateway/student/terms', userId, { subject_id: subjectId });
  if (!termsResult.error) {
    try {
      const terms = JSON.parse(termsResult.data);
      const match = Array.isArray(terms) ? terms.find((t: any) => t.id === termId) : null;
      if (match) termName = match.name;
    } catch { /* fallback */ }
  }

  // Fetch subject name
  let subjectName = 'Subject';
  const subjectsResult = await proxyToGateway('/gateway/student/subjects', userId);
  if (!subjectsResult.error) {
    try {
      const subjects = JSON.parse(subjectsResult.data);
      const match = Array.isArray(subjects) ? subjects.find((s: any) => s.id === subjectId) : null;
      if (match) subjectName = match.name;
    } catch { /* fallback */ }
  }

  return {
    lessons,
    termName,
    lessonsError: null,
    breadcrumbs: [
      { label: 'LMS' } as BreadcrumbItem,
      { label: subjectName, href: `/lms/${subjectId}` } as BreadcrumbItem,
      { label: termName } as BreadcrumbItem
    ]
  };
};
```

### 6. `frontend/src/routes/lms/[subjectId]/[termId]/+page.svelte` — Lessons page

```svelte
<script lang="ts">
  import type { PageData } from './$types';
  import { Card, CardHeader, CardTitle } from '$lib/components/ui/card';
  import { Alert, AlertTitle, AlertDescription, AlertAction } from '$lib/components/ui/alert';
  import { Skeleton } from '$lib/components/ui/skeleton';
  import { Button } from '$lib/components/ui/button';
  import { page, navigating } from '$app/stores';
  import { goto } from '$app/navigation';

  let { data }: { data: PageData } = $props();
</script>

<div class="mx-auto max-w-4xl space-y-6">
  <a href="/lms/{$page.params.subjectId}" class="text-sm text-primary-500 hover:underline inline-flex items-center gap-1">
    ← Back to terms
  </a>

  <h1 class="text-2xl font-display font-bold text-primary-700">{data.termName} — Lessons</h1>

  {#if $navigating && (!data.lessons || data.lessons.length === 0)}
    <div class="space-y-3">
      {#each Array(5) as _}
        <Skeleton class="h-16" />
      {/each}
    </div>
  {:else if data.lessonsError}
    <Alert variant="destructive">
      <AlertTitle>Failed to load lessons</AlertTitle>
      <AlertDescription>{data.lessonsError}</AlertDescription>
      <AlertAction>
        <Button variant="outline" onclick={() => goto('/lms/' + $page.params.subjectId + '/' + $page.params.termId)}>Retry</Button>
      </AlertAction>
    </Alert>
  {:else if data.lessons.length === 0}
    <div class="mx-auto max-w-lg py-16 text-center space-y-6">
      <div class="rounded-full bg-secondary-100 dark:bg-secondary-900/20 mx-auto w-fit p-4">
        <svg xmlns="http://www.w3.org/2000/svg" class="h-8 w-8 text-secondary-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <circle cx="12" cy="12" r="10" />
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 16v-4m0-4h.01" />
        </svg>
      </div>
      <h2 class="text-xl font-semibold text-surface-800">No Lessons Available</h2>
      <p class="text-surface-700">No lessons are available for this term yet.</p>
    </div>
  {:else}
    <div class="space-y-3">
      {#each data.lessons as lesson (lesson.id)}
        {#if lesson.active !== false}
          <a href="/lms/{$page.params.subjectId}/{$page.params.termId}/{lesson.id}" class="block">
            <Card class="hover:bg-primary-50 dark:hover:bg-primary-950/30 transition cursor-pointer">
              <CardHeader class="pb-0">
                <div class="flex justify-between items-start">
                  <CardTitle class="font-display text-base text-primary-700">
                    Week {lesson.week}: {lesson.topic_title ?? 'Untitled Lesson'}
                  </CardTitle>
                </div>
              </CardHeader>
            </Card>
          </a>
        {:else}
          <Card class="opacity-50 pointer-events-none">
            <CardHeader class="pb-0">
              <div class="flex justify-between items-start">
                <CardTitle class="font-display text-base text-surface-400">
                  Week {lesson.week}: {lesson.topic_title ?? 'Untitled Lesson'}
                </CardTitle>
                <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-surface-400 shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                </svg>
              </div>
            </CardHeader>
          </Card>
        {/if}
      {/each}
    </div>
  {/if}
</div>
```

### 7. No agent, gateway, or proxy changes

The proxy routes at `/api/student/terms` and `/api/student/lessons` are already built (Unit 16). Agent methods are functional. This unit is pure frontend.

## Files Changed

| File | Change |
|---|---|
| `frontend/src/lib/types.ts` | Add `BreadcrumbItem` interface; add optional `active` to `Lesson` |
| `frontend/src/routes/+layout.svelte` | Replace static breadcrumb with dynamic render loop; import `BreadcrumbSeparator`, `BreadcrumbLink` |
| `frontend/src/routes/lms/[subjectId]/+page.server.ts` | **New** — terms + subject name loader |
| `frontend/src/routes/lms/[subjectId]/+page.svelte` | **New** — term card grid |
| `frontend/src/routes/lms/[subjectId]/[termId]/+page.server.ts` | **New** — lessons + names loader |
| `frontend/src/routes/lms/[subjectId]/[termId]/+page.svelte` | **New** — lesson list |
| `docs/progress-tracker.md` | Mark Unit 17 in progress |

## Dependencies

None. All shadcn-svelte components (`Card`, `Skeleton`, `Alert`, `Button`) are installed. `BreadcrumbSeparator` and `BreadcrumbLink` are already available in the breadcrumb component file. Proxy routes from Unit 16 are functional.

## Verification Checklist

### Build & Typecheck
- [ ] `pnpm build` succeeds with zero errors
- [ ] `pnpm check` passes with zero errors
- [ ] No TypeScript errors from new `BreadcrumbItem` interface or `active` on `Lesson`
- [ ] No type errors from `$page.data.breadcrumbs` usage in layout

### Breadcrumb
- [ ] Dashboard shows "Dashboard" as a static breadcrumb (unchanged)
- [ ] Terms page at `/lms/{subjectId}` shows `LMS > Subject Name`
- [ ] Lessons page at `/lms/{subjectId}/{termId}` shows `LMS > Subject Name > Term Name` with subject name clickable (links back to terms page)
- [ ] Admin pages show "Dashboard" (no regression)
- [ ] `BreadcrumbSeparator` renders between items
- [ ] Last item uses `BreadcrumbPage` (bold, non-clickable)

### Term Page (`/lms/{subjectId}`)
- [ ] Heading shows subject name
- [ ] Terms rendered as compact Card components in a horizontal flex wrap row
- [ ] Active term cards are clickable, navigate to `/lms/{subjectId}/{termId}`
- [ ] Inactive term cards have `opacity-50`, lock SVG icon, `text-surface-400`, not clickable
- [ ] Empty state: centered info circle + "No terms available for this subject."
- [ ] Error state: destructive Alert + "Retry" button
- [ ] Loading state: 3 skeleton cards during client-side nav

### Lesson List Page (`/lms/{subjectId}/{termId}`)
- [ ] "← Back to terms" link navigates to `/lms/{subjectId}`
- [ ] Heading shows `"{Term Name} — Lessons"`
- [ ] Active lesson cards show `"Week {n}: {topic_title}"`, clickable (404 until Unit 19)
- [ ] Inactive lesson cards have `opacity-50`, lock icon, not clickable
- [ ] Vertical stack with `space-y-3`
- [ ] Empty state: centered info circle + "No lessons available for this term."
- [ ] Error state: destructive Alert + "Retry" button
- [ ] Loading state: 5 skeleton cards during client-side nav

### Inactive Items
- [ ] `opacity-50 pointer-events-none` applied
- [ ] Lock SVG icon present in top-right of CardHeader
- [ ] Title uses `text-surface-400`
- [ ] Lock icon visible on dark background

### Dark Mode
- [ ] Cards, skeletons, alerts respond to `dark:` variant
- [ ] Inactive items visible on dark background
- [ ] Breadcrumb text readable in dark mode

### Regression
- [ ] Dashboard loads without breadcrumb errors
- [ ] Admin pages load without breadcrumb errors
- [ ] Sidebar, navbar, avatar dropdown render correctly
- [ ] Logout works
- [ ] Direct URL navigation to `/lms/{subjectId}` loads correctly
- [ ] Direct URL navigation to `/lms/{subjectId}/{termId}` loads correctly
- [ ] Invalid subjectId returns empty terms (empty state, not a crash)
- [ ] `docs/progress-tracker.md` updated
