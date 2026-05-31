# Unit 19 — Lesson Content Page with Side Navigation

## Goal

Enhance the lesson detail page at `/lms/[subjectId]/[termId]/[lessonId]` with a fixed right-side navigation panel (hover to reveal section headings, click to smooth-scroll), a placeholder assignment section with empty state, mobile floating TOC button, and polishing of existing section rendering.

## Design

### Layout Structure

The page content (`max-w-4xl`) shifts from centered to `ml-auto mr-[120px]` on `md+` screens, creating a gutter on the right for the fixed side nav. On mobile (`<md`), the content remains centered (`mx-auto max-w-4xl`) and the side nav is replaced by a floating TOC button.

### Side Navigation Panel (Desktop)

| Element | Token / Class | Notes |
|---|---|---|
| **Container** | `fixed right-4 top-1/3 z-50 w-48 transition-all duration-200` | Hidden by default (`opacity-0 translate-x-4`), revealed on hover (`opacity-100 translate-x-0`) |
| **Trigger area (thin strip)** | `absolute -left-6 top-0 bottom-0 w-6 cursor-pointer` | Invisible hit area so hover is easy to catch |
| **Dot indicator** | `h-2 w-2 rounded-full bg-primary-300` | One per section — small dots in a vertical stack |
| **Section list** | `bg-white dark:bg-surface-900 border border-surface-200 rounded-lg shadow-lg p-3 space-y-2` | Appears on hover over the trigger area or the panel itself |
| **Section link** | `text-sm text-surface-600 hover:text-primary-600 dark:hover:text-primary-400 cursor-pointer truncate block leading-snug` | Click → `document.getElementById(sectionId).scrollIntoView({ behavior: 'smooth' })` |
| **Active section indicator** | `text-primary-600 font-medium` | JS tracks scroll position; highlights the current visible section |

**On-hover behavior:**
- Default: only the thin trigger strip + small dot stack visible at `opacity-60`
- Hover over trigger or panel: panel slides in (`opacity-100 translate-x-0`), section titles displayed
- Panel stays open while mouse is over the panel or trigger area

**Section IDs** (added to each content block):

| Section | ID |
|---|---|
| Page top / title | `lesson-top` |
| Learning Objectives | `section-objectives` |
| Each content section | `section-content-{section_number}` |
| Assignments | `section-assignments` |
| Key Points | `section-key-points` |

### Mobile Floating TOC Button

| Element | Token / Class | Notes |
|---|---|---|
| **FAB** | `fixed bottom-6 right-6 z-50 h-12 w-12 rounded-full bg-primary-500 text-white shadow-lg flex items-center justify-center` | Visible only on `<md` screens (`md:hidden`) |
| **Icon** | SVG hamburger list icon (`h-5 w-5`) | |
| **Dropdown** | Absolute-positioned card above the FAB | Contains same section list as desktop; clicking a heading closes the sheet and smooth-scrolls |

### Assignment Section (Placeholder)

A dedicated card section below the content sections and above key points:

| Element | Token / Class | Notes |
|---|---|---|
| **Card** | `border-dashed border-primary-300 bg-primary-50/30` | Dashed border to suggest "ready for content" |
| **CardHeader** | `pb-2` | |
| **CardTitle** | `text-xl font-display font-bold text-primary-700 flex items-center gap-2` | "Assignments" with a clipboard icon |
| **CardContent** | `pt-4` | |
| **Empty state** | `text-sm text-surface-500 text-center py-6` | "No active assignments for this lesson." |

Unit 23 will remove the empty state and render actual assignment questions here.

### Existing Content Sections (Polishing)

Add section IDs for scroll targeting. No behavioral changes to existing rendering.

### Breadcrumb

Already built in the Unit 18 post-deploy fix:
```
LMS > Subjects > Subject Name > Term Name > Lesson
```

No changes needed.

## Implementation

### 1. `frontend/src/lib/types.ts` — No changes needed

All types (`LessonContent`, `LessonObjective`, `LessonContentSection`, `SubPoint`, `BreadcrumbItem`) are already defined.

### 2. `[lessonId]/+page.svelte` — Add side nav, assignments, section IDs, mobile FAB

**Script additions:**

```typescript
import { onMount } from 'svelte';

const SECTION_IDS = {
  objectives: 'section-objectives',
  keyPoints: 'section-key-points',
  assignments: 'section-assignments',
};

function contentSectionId(sectionNumber: number): string {
  return `section-content-${sectionNumber}`;
}

let sideNavOpen = $state(false);
let sideNavMobileOpen = $state(false);
let activeSection = $state('lesson-top');

onMount(() => {
  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          activeSection = entry.target.id;
        }
      }
    },
    { rootMargin: '-80px 0px -60% 0px', threshold: 0 }
  );

  const sections = document.querySelectorAll('[data-section]');
  sections.forEach((el) => observer.observe(el));

  return () => observer.disconnect();
});

function scrollToSection(id: string) {
  const el = document.getElementById(id);
  if (el) {
    el.scrollIntoView({ behavior: 'smooth', block: 'start' });
    activeSection = id;
    sideNavMobileOpen = false;
  }
}
```

**Derived section headings:**

```typescript
let sectionHeadings = $derived.by(() => {
  const headings: { id: string; label: string }[] = [];

  if (objectives && objectives.length > 0) {
    headings.push({ id: SECTION_IDS.objectives, label: 'Learning Objectives' });
  }

  if (contentSections && contentSections.length > 0) {
    for (const section of contentSections) {
      if (section.header) {
        headings.push({ id: contentSectionId(section.section_number), label: stripBold(section.header) });
      }
    }
  }

  headings.push({ id: SECTION_IDS.assignments, label: 'Assignments' });

  if (keyPoints && keyPoints.length > 0) {
    headings.push({ id: SECTION_IDS.keyPoints, label: 'Key Points' });
  }

  return headings;
});
```

**Template — Change container class:**

```
class="mx-auto max-w-4xl space-y-8 md:ml-auto md:mr-[120px]"
```

**Template — Wrap each section block with `data-section` and `id`:**

Objectives card wrapper:
```svelte
<div id={SECTION_IDS.objectives} data-section>
  <!-- existing objectives Card -->
</div>
```

Content section card wrapper:
```svelte
<div id={contentSectionId(section.section_number)} data-section>
  <!-- existing content section Card -->
</div>
```

Key points card wrapper:
```svelte
<div id={SECTION_IDS.keyPoints} data-section>
  <!-- existing key points Card -->
</div>
```

**Template — Assignment section (between content sections and key points):**

```svelte
<div id={SECTION_IDS.assignments} data-section>
  <Card class="border-dashed border-primary-300 bg-primary-50/30 dark:bg-primary-950/10">
    <CardHeader class="pb-2">
      <CardTitle class="text-xl font-display font-bold text-primary-700 flex items-center gap-2">
        <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
        </svg>
        Assignments
      </CardTitle>
    </CardHeader>
    <CardContent class="pt-4">
      <p class="text-sm text-surface-500 text-center py-6">No active assignments for this lesson.</p>
    </CardContent>
  </Card>
</div>
```

**Template — Desktop side nav (after main content div, inside the page):**

```svelte
<div class="hidden md:block fixed right-4 top-1/3 z-50"
  role="navigation"
  aria-label="Lesson sections"
  onmouseenter={() => { sideNavOpen = true; }}
  onmouseleave={() => { sideNavOpen = false; }}>

  <div class="absolute -left-6 top-0 bottom-0 w-6 cursor-pointer"></div>

  <div class="transition-all duration-200"
    class:opacity-100={sideNavOpen}
    class:translate-x-0={sideNavOpen}
    class:opacity-0={!sideNavOpen}
    class:translate-x-4={!sideNavOpen}>

    {#if sideNavOpen}
      <div class="bg-white dark:bg-surface-900 border border-surface-200 rounded-lg shadow-lg p-3 space-y-2 min-w-40">
        {#each sectionHeadings as heading}
          <button
            onclick={() => scrollToSection(heading.id)}
            class="text-sm text-left w-full block cursor-pointer truncate leading-snug"
            class:text-primary-600={activeSection === heading.id}
            class:font-medium={activeSection === heading.id}
            class:text-surface-600={activeSection !== heading.id}>
            {heading.label}
          </button>
        {/each}
      </div>
    {:else}
      <div class="flex flex-col items-center gap-2 py-2 opacity-60">
        {#each sectionHeadings as heading}
          <span class="h-2 w-2 rounded-full"
            class:bg-primary-500={activeSection === heading.id}
            class:bg-primary-300={activeSection !== heading.id}>
          </span>
        {/each}
      </div>
    {/if}
  </div>
</div>
```

**Template — Mobile floating TOC:**

```svelte
<div class="md:hidden fixed bottom-6 right-6 z-50"
  role="navigation"
  aria-label="Lesson sections">

  <button
    class="h-12 w-12 rounded-full bg-primary-500 text-white shadow-lg flex items-center justify-center hover:bg-primary-600 transition"
    onclick={() => { sideNavMobileOpen = !sideNavMobileOpen; }}>
    <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
      <path stroke-linecap="round" stroke-linejoin="round" d="M4 6h16M4 12h16M4 18h16" />
    </svg>
  </button>

  {#if sideNavMobileOpen}
    <div class="fixed inset-0" onclick={() => { sideNavMobileOpen = false; }}></div>

    <div class="absolute bottom-16 right-0 bg-white dark:bg-surface-900 border border-surface-200 rounded-lg shadow-xl p-3 space-y-2 min-w-44 max-w-64">
      {#each sectionHeadings as heading}
        <button
          onclick={() => scrollToSection(heading.id)}
          class="text-sm text-left w-full block cursor-pointer truncate leading-snug py-1"
          class:text-primary-600={activeSection === heading.id}
          class:font-medium={activeSection === heading.id}
          class:text-surface-600={activeSection !== heading.id}>
          {heading.label}
        </button>
      {/each}
    </div>
  {/if}
</div>
```

### 3. No agent, gateway, or proxy changes

Lesson data already flows through Unit 18's infrastructure.

## Files Changed

| File | Change |
|---|---|
| `frontend/src/routes/lms/[subjectId]/[termId]/[lessonId]/+page.svelte` | Add side nav panel, mobile FAB, assignment placeholder section, section IDs with `data-section`, scroll spy with IntersectionObserver, layout shift (`md:mr-[120px]`), derived section headings |
| `docs/progress-tracker.md` | Mark Unit 19 completed |

## Dependencies

None. All shadcn-svelte components are installed. Intersection Observer is a native browser API.

## Verification Checklist

### Build & Typecheck
- [ ] `pnpm build` succeeds with zero errors
- [ ] `pnpm check` passes with zero errors
- [ ] No TypeScript errors from `$state`, `$derived`, IntersectionObserver

### Desktop Side Nav
- [ ] Fixed panel on right side of viewport (`fixed right-4 top-1/3`)
- [ ] Default: thin dots indicator at `opacity-60`
- [ ] Hover reveals section titles with slide-in animation (`opacity-100 translate-x-0`)
- [ ] Each heading clickable → smooth-scroll to corresponding `data-section` block
- [ ] Active section highlighted (primary color, medium font weight)
- [ ] Scroll spy updates active section as user scrolls
- [ ] Panel stays open while mouse is over panel or trigger area
- [ ] Dots correctly highlight active section when panel is collapsed
- [ ] Hidden on `<md` screens (`hidden md:block`)
- [ ] Content shifted left (`md:mr-[120px]`) to avoid overlap

### Mobile Floating TOC
- [ ] Fixed FAB at bottom-right on `<md` screens only
- [ ] Tapping FAB opens floating card with section headings
- [ ] Tapping heading closes card and scrolls
- [ ] Tapping backdrop overlay closes card
- [ ] Hidden on `md+` screens

### Assignment Section
- [ ] Dashed-border card between content sections and key points
- [ ] Title "Assignments" with clipboard icon
- [ ] "No active assignments for this lesson." centered text
- [ ] Responds to dark mode

### Section IDs & Scroll
- [ ] `section-objectives`, `section-assignments`, `section-key-points` present
- [ ] `section-content-{n}` on each content section
- [ ] Click-to-scroll works for all sections
- [ ] IntersectionObserver updates active section correctly

### Existing Content (No Regressions)
- [ ] Objectives, content sections, sub-points, key points render as before
- [ ] Back to lessons, week badge, title/metadata unchanged
- [ ] Skeleton loading, error with retry work correctly

### Dark Mode
- [ ] Side nav panel uses `dark:bg-surface-900`, `dark:border-surface-700`
- [ ] Mobile FAB/sheet use `dark:` variants
- [ ] All existing content responds to `dark:` correctly

### Regression
- [ ] Subject, term, lesson list pages still navigate correctly
- [ ] Direct URL to lesson loads correctly
- [ ] Invalid lesson ID shows error state
- [ ] Back button in browser works
- [ ] Sidebar and navbar render correctly from lesson page
- [ ] `docs/progress-tracker.md` updated
