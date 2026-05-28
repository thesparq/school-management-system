# Unit 15 — Student Dashboard: Subject Cards

## Goal

Replace the generic dashboard at `/` for student users with a responsive grid of subject cards fetched from the Student Agent. Show skeleton placeholders during route transitions, an empty state when no subjects are assigned, and an error state with retry when the gateway is unreachable. Admin users continue to see the existing generic dashboard.

## Design

### Layout & Grid

- Student section of the dashboard uses a responsive card grid: `grid gap-6 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4`
- Matches the existing grid pattern from the current dashboard (`+page.svelte:70`) but adds the `xl:grid-cols-4` breakpoint to make better use of wide screens
- The heading line shows "Your Subjects" — the user's name is already visible in the sidebar footer, so it does not need to be repeated

### Subject Card

Uses the existing shadcn-svelte `Card` compound component (`Card`, `CardHeader`, `CardTitle`, `CardContent`).

| Element | Token / Class | Notes |
|---|---|---|
| **Card** | `hover:bg-primary-50 dark:hover:bg-primary-950/30 hover:ring-primary-200 dark:hover:ring-primary-700 transition cursor-pointer` | Wrapped in `<a href="/lms/{id}">` so the entire card is a link |
| **CardHeader** | `pb-0` | Reduces default padding — the title sits close to the top |
| **CardTitle** | `font-display text-base text-primary-700 dark:text-primary-300` | Subject name, one line, truncated with `truncate` |
| **CardContent** | `pt-2` | Minimal top padding after the tight header |
| **Subject code** | `text-sm text-surface-700 dark:text-surface-400` | Rendered only when `code` is non-null; placed below the title |

**Navigation note:** The `/lms/[id]` route does not exist yet — it will be built in Unit 17. Clicking a card produces a 404 until then. This is intentional; the card component will not need modification in Unit 17.

### States

| State | What renders | Notes |
|---|---|---|
| **Loading** | 12 `Skeleton` rectangles (`h-28` each) in the same grid layout | Visible during client-side navigation when `$navigating` is true and cached data is absent |
| **Data** | Grid of subject `Card`s | Each card clickable, links to `/lms/{id}` |
| **Empty** | Centered block with an info circle icon and "No subjects assigned." paragraph | Informational status — uses `secondary-400` for the icon (amber, not warning/error) |
| **Error** | `Alert` (variant `destructive`) with error message and "Retry" `Button` | Retry calls `goto('/')` to re-run the server load function |

### Color & spacing tokens

- Card hover: `bg-primary-50` / `dark:bg-primary-950/30` background, `ring-primary-200` / `dark:ring-primary-700` border
- Skeleton: shadcn's `bg-muted` class (maps to `--color-muted` in `app.css`)
- Empty state icon: `secondary-400` (amber, not red — this is informational, not an error)
- Subject code: `surface-700` / `surface-400` (dark)
- Subject name: `primary-700` / `primary-300` (dark)

## Implementation

### 1. Shared types — Subject interface

Create `frontend/src/lib/types.ts` with the subject shape returned by the gateway, mirroring the MoonBit `SubjectInfo` type in `student_agent.mbt` (`{ id: String, name: String, code: String? }`):

```typescript
export interface Subject {
  id: string;
  name: string;
  code: string | null;
}
```

### 2. `frontend/src/routes/+page.server.ts` — Add student subject loading

**Imports to add:**
- `proxyToGateway` from `$lib/server/golem` (already present — reused from the initialization check)

**Logic changes (after existing initialization check):**

```
existing: if (!user) return { initialized: true };
existing: if (user.roles.includes('admin')) return { initialized: true };
existing: init check via proxyToGateway → { initialized: false } or { initialized: true }

new:  if the user is NOT an admin AND is initialized:
        fetch subjects via proxyToGateway('/gateway/student/subjects', user.id)
        on error:   subjectsError = error.message, subjects = null
        on success: try JSON.parse → subjects = parsed array
                    on parse failure → subjectsError = "Invalid response from server."
      else:
        subjects = null, subjectsError = null  (admin or teacher — show generic dashboard)
```

**Return shape:**
```typescript
return {
  user,
  initialized: true,          // existing
  subjects: Subject[] | null,  // null when admin/teacher or when fetch errored
  subjectsError: string | null // non-null when fetch or parse failed
};
```

The existing `initialized: false` path is unchanged.

**Edge cases:**
- `proxyToGateway` throws → caught, `subjectsError: "Failed to reach backend service."`
- Gateway returns `NOT_INITIALIZED` (race where init status changed between check and subjects call) → caught by error path, `subjectsError: error.message`
- `JSON.parse` fails → `subjectsError: "Invalid response from server."`
- Teacher or unknown role user → `subjects` is `null`, `subjectsError` is `null` — page renders generic welcome section

### 3. `frontend/src/routes/+page.svelte` — Add student view

**Script additions:**
```typescript
import { navigating } from '$app/stores';
import { goto } from '$app/navigation';
import { Alert, AlertTitle, AlertDescription, AlertAction } from '$lib/components/ui/alert';
import { Skeleton } from '$lib/components/ui/skeleton';
import { Card, CardContent, CardHeader, CardTitle } from '$lib/components/ui/card';
import type { Subject } from '$lib/types';
```

**Template structure** (after the `data.initialized === false` block):

```
if not initialized:
    └─ "Account Not Initialized" warning (unchanged)

else if user is NOT admin:
    if $navigating AND (no subjects loaded yet):
        └─ "Your Subjects" heading + skeleton grid (12 Skeleton cards)
    else if subjectsError:
        └─ destructive Alert with error message + "Retry" button (goto('/'))
    else if subjects.length === 0:
        └─ centered info icon + "No subjects assigned."
    else:
        └─ "Your Subjects" heading + card grid
            each card → <a href="/lms/{subject.id}">
                          <Card>
                            <CardHeader class="pb-0">
                              <CardTitle class="truncate ...">{subject.name}</CardTitle>
                            </CardHeader>
                            <CardContent class="pt-2">
                              {#if subject.code}
                                <p class="text-sm ...">{subject.code}</p>
                              {/if}
                            </CardContent>
                          </Card>
                        </a>

else (admin):
    └─ existing generic dashboard (welcome heading, Quick Actions, Connection Status)
```

**Empty state icon** (info circle):
```svg
<svg xmlns="http://www.w3.org/2000/svg" class="h-8 w-8 text-secondary-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
  <circle cx="12" cy="12" r="10" />
  <path stroke-linecap="round" stroke-linejoin="round" d="M12 16v-4m0-4h.01" />
</svg>
```

**Error retry button:**
```svelte
<Button onclick={() => goto('/')}>Retry</Button>
```

### 4. No agent or proxy changes needed

The existing Student Agent `get_subjects()`, Gateway endpoint `/gateway/student/subjects`, and SvelteKit proxy at `/api/student/subjects` all already return the correct shape: `{ data: Subject[] }`.

### 5. No layout changes needed

The `+layout.svelte` already renders the sidebar, navbar, breadcrumb ("Dashboard"), and content area. No breadcrumb changes needed — clicking into a subject will update the breadcrumb in Unit 17.

## Files Changed

| File | Change |
|---|---|
| `frontend/src/lib/types.ts` | **New file**: `Subject` interface |
| `frontend/src/routes/+page.server.ts` | Add student subject loading via `proxyToGateway` |
| `frontend/src/routes/+page.svelte` | Add student section: subject card grid, skeleton, empty, error states |

## Dependencies

None. `Card`, `Skeleton`, `Alert`, `Button`, and all other shadcn-svelte components are already installed.

## Verification Checklist

### Build & Typecheck
- [ ] `pnpm build` succeeds with zero errors
- [ ] `pnpm check` passes with zero errors
- [ ] No TypeScript errors from the new `Subject` interface or `subjects`/`subjectsError` page data fields
- [ ] No TypeScript errors from `navigating` store usage

### Student — Data state
- [ ] Student initialized with subjects assigned → page shows "Your Subjects" heading and a card grid
- [ ] Each card displays the subject name (truncated with `truncate`) and code (when non-null)
- [ ] Cards have hover effect (`bg-primary-50` background tint, darker ring, pointer cursor)
- [ ] Clicking a card navigates to `/lms/{subject.id}` (produces 404 — expected until Unit 17)
- [ ] Grid is responsive: 1 col on mobile, 2 on `sm`, 3 on `lg`, 4 on `xl`
- [ ] Skeleton cards are never shown when data is already loaded (no flash of skeleton)

### Student — Empty state
- [ ] Student initialized with no subjects → centered "No subjects assigned." message with amber info circle icon
- [ ] No card grid is rendered
- [ ] No "Your Subjects" heading is rendered (only the empty state block)

### Student — Error state
- [ ] Gateway unreachable → `Alert` with `destructive` variant showing the error message
- [ ] "Retry" button calls `goto('/')` — user sees navigation loading bar, then fresh data
- [ ] Gateway returns `NOT_INITIALIZED` (race condition) → error state shown with gateway's message
- [ ] Invalid JSON from gateway → error state with "Invalid response from server." message

### Student — Loading state
- [ ] During client-side navigation (e.g., clicking sidebar link) → 12 skeleton rectangles visible in grid layout
- [ ] Skeletons have `animate-pulse` and match card dimensions (`h-28`)
- [ ] Skeletons render in the same 4-column responsive grid as cards
- [ ] Skeletons disappear and cards/text appear once data resolves

### Admin — Unchanged
- [ ] Admin user sees the existing generic dashboard with "Welcome, {name}" heading and "Quick Actions" / "Connection Status" cards
- [ ] No subject-related UI is shown
- [ ] "Test Connection" button still works (uses `apiFetch` from Unit 14)

### Regression
- [ ] Uninitialized user still sees "Account Not Initialized" warning (no change)
- [ ] Sidebar, navbar, breadcrumb ("Dashboard"), avatar dropdown all render correctly
- [ ] Logout works
- [ ] Dark mode: cards, skeletons, alerts respond to `dark:` variant
- [ ] Empty state icon visible on dark background
- [ ] Teacher or other non-student, non-admin users see generic dashboard (no subject cards, no error)
- [ ] `docs/progress-tracker.md` updated
