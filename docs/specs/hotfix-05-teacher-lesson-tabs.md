# HF-05: Teacher Lesson Tabs

## Goal

Add a tabbed lesson page for teachers at `/my-classes/[classId]/[subjectId]/[termId]/[lessonId]` with three tabs: Lesson (existing content, no assignment section), Assessments (create-assessment modal populated from lesson questions, empty list), and Grading (empty placeholder). UI structure only — no backend assessment/grading logic, no persistence.

## Design

**Route:** `/my-classes/[classId]/[subjectId]/[termId]/[lessonId]` — teacher-only, non-teachers redirect to `/`.

**Tab bar:** Left-aligned, full-width bar with `border-b border-surface-200 mb-6`. Three buttons: "Lesson", "Assessments", "Grading". Active tab: `border-b-2 border-primary-500 text-primary-700 font-medium`. Inactive: `border-b-2 border-transparent text-surface-500 hover:text-surface-700`. Transitions on color and border. Tab state tracked via `let activeTab = $state('lesson')`.

**Tab 1 — Lesson:** Identical to the current `/lms/[subjectId]/[termId]/[lessonId]` page with two removals:

- The Assignments placeholder card (dashed-border card with clipboard icon)
- The `assignments` entry from `SECTION_IDS` and from the `sectionHeadings` computed array

Elements kept:

- Side navigation panel (hover dots → section headings → scroll-to), minus Assignments heading
- "Back to lessons" button linking to `/my-classes/[classId]/[subjectId]/[termId]`
- Week badge, learning objectives card, content sections loop with sub-points, key points card

**Tab 2 — Assessments:**

- **Empty list:** `<StatusCard variant="info" title="No Assessments" description="No assessments have been created for this lesson yet." />`
- **"Create Assessment" button:** `<Button variant="default">Create Assessment</Button>` above the list
- **Future list slot:** `<div class="space-y-2">` container where assessment accordion rows will render when wired (Units 22–25)
- **Create modal** (`<Dialog>` from shadcn-svelte):
  - `<DialogHeader>`: Title "Create Assessment"
  - **Title field:** `<Label>Assessment Title</Label>` + `<Input placeholder="e.g. Week 3 Quiz" />` bound to `let assessmentTitle = $state('')`
  - **Questions accordion** (`<Accordion.Root type="multiple">`):
    - **Item 1: "MCQ Questions ({count})"** — expanded by default. Shows a `<Checkbox>` list, one per MCQ parsed from `lesson.mcq_questions`. Each row: checkbox + question text + option count `<Badge>`.
    - **Item 2: "Theoretical Questions ({count})"** — collapsed by default. Same checkbox pattern from `lesson.theoretical_questions`.
  - `<DialogFooter>`: `<Button>Create</Button>` — closes dialog on click, no backend call (placeholder)
  - Button disabled until title is non-empty

**Tab 3 — Grading:**

- `<StatusCard variant="info" title="No Submissions" description="No submissions to grade yet." />`
- `<div>` slot for future assessment→submissions accordion list

**Skeleton/Loading/Error states:** Same pattern as existing lesson page — `<Skeleton>` placeholders during load, `<StatusCard variant="error">` if fetch fails, retry reloads the page.

**Breadcrumbs:** `My Classes > {classLevelName} > {subjectName} > {termName} > Week {week}: {topicTitle}`. Class and subject names resolved by fetching `/api/teacher/classes` (same pattern as current term page server).

## Implementation

### 1. Backend — Expose Question Fields

**File:** `agents/app-agents/student_agent.mbt`

**`LessonContent` struct** — add after `key_points` field:

```moonbit
mcq_questions : String?
theoretical_questions : String?
```

**`get_lesson` SQL SELECT** — add `mcq_questions, theoretical_questions` to the comma-separated field list.

**`get_lesson` Object match** — add after `key_points` parsing block:

```moonbit
let mcq = match obj.get("mcq_questions") {
  Some(v) => Some(v.stringify())
  _ => None
}
let tq = match obj.get("theoretical_questions") {
  Some(v) => Some(v.stringify())
  _ => None
}
```

Include `mcq_questions: mcq, theoretical_questions: tq` in the `LessonContent` construction.

### 2. Install shadcn-svelte Components

```bash
cd frontend && npx shadcn-svelte@latest add accordion checkbox
```

### 3. Frontend Types

**File:** `frontend/src/lib/types.ts`

Add to `LessonContent` interface:

```ts
mcq_questions: string | null;
theoretical_questions: string | null;
```

Add helper types for parsed question objects:

```ts
export interface McqQuestion {
  question: string;
  options: string[];
  answer: string;
}

export interface TheoreticalQuestion {
  question: string;
  answer: string;
}
```

### 4. New Route — Teacher Lesson Page

**File:** `frontend/src/routes/my-classes/[classId]/[subjectId]/[termId]/[lessonId]/+page.server.ts`

**Data loading:**

- Guard: `!locals.user?.roles.includes('teachers')` → `redirect(302, '/')`
- Load lesson: `fetch('/api/student/lesson?lesson_id=')` → `LessonContent | null`
- Load classes: `fetch('/api/teacher/classes')` → resolve `classLevelName`, `subjectName`
- Build breadcrumbs array with resolved names
- Return `{ streamed: { lesson: promise }, breadcrumbs }`

**Breadcrumb structure:**

```ts
[
  { label: 'My Classes', href: '/' },
  { label: classLevelName, href: `/my-classes/${classId}` },
  { label: subjectName, href: `/my-classes/${classId}/${subjectId}` },
  { label: termName, href: `/my-classes/${classId}/${subjectId}/${termId}` },
  { label: `Week ${week}: ${topicTitle}` }
]
```

**File:** `frontend/src/routes/my-classes/[classId]/[subjectId]/[termId]/[lessonId]/+page.svelte`

**State variables:**

```ts
let activeTab = $state<'lesson' | 'assessments' | 'grading'>('lesson');
let assessmentModalOpen = $state(false);
let assessmentTitle = $state('');
let selectedMcq = $state(new Set<number>());
let selectedTheory = $state(new Set<number>());
```

**Side nav state (reuse from current lesson page):**

```ts
let sideNavOpen = $state(false);
let sideNavMobileOpen = $state(false);
let activeSection = $state('lesson-top');
let closeTimer: ReturnType<typeof setTimeout> | undefined = $state();
```

**Constants:**

```ts
const SECTION_IDS = {
  objectives: 'section-objectives',
  keyPoints: 'section-key-points',
};
// NOTE: No 'assignments' entry
```

**Helper functions (copied from current lesson page):**

- `parseJson<T>()`, `isLessonObjective()`, `isLessonContentSection()`, `isString()`
- `isMcqQuestion()`, `isTheoreticalQuestion()`
- `stripBold()`, `cleanNum()`, `formatSubPoint()`
- `scrollSpy()`, `scrollToSection()`, `handleSideNavEnter()`, `handleSideNavLeave()`
- `contentSectionId()`

**Section headings computed block (no assignments):**

```ts
const sectionHeadings = (() => {
  const headings: { id: string; label: string }[] = [];
  if (objectives && objectives.length > 0) {
    headings.push({ id: SECTION_IDS.objectives, label: 'Learning Objectives' });
  }
  if (contentSections && contentSections.length > 0) {
    for (const s of contentSections) {
      if (s.header) {
        headings.push({ id: contentSectionId(s.section_number), label: stripBold(s.header) });
      }
    }
  }
  if (keyPoints && keyPoints.length > 0) {
    headings.push({ id: SECTION_IDS.keyPoints, label: 'Key Points' });
  }
  return headings;
})();
```

**Render structure:**

1. Loading skeletons (same as current lesson page)
2. Error state (StatusCard + goto retry)
3. Tab bar — 3 buttons, `onclick` sets `activeTab`
4. Conditional tab content:
   - **lesson:** Copied render blocks from current page:
     - Back link → `/my-classes/[classId]/[subjectId]/[termId]`
     - Title + week badge
     - Objectives card
     - Content sections loop with sub-points
     - Key Points card
     - Side nav (desktop dots + mobile FAB)
     - No assignments section, no assignments heading in side nav
   - **assessments:**
     ```
     <Button>Create Assessment</Button>
     <div class="space-y-2"><!-- future assessment rows --></div>
     <StatusCard variant="info" ... />
     ```
   - **grading:**
     ```
     <div><!-- future submissions list --></div>
     <StatusCard variant="info" title="No Submissions" ... />
     ```
5. Assessment create `<Dialog>` (rendered at top level):
   ```svelte
   <Dialog.Root bind:open={assessmentModalOpen}>
     <Dialog.Content>
       <Dialog.Header>
         <Dialog.Title>Create Assessment</Dialog.Title>
         <Dialog.Description>Select questions from this lesson.</Dialog.Description>
       </Dialog.Header>
       <div class="space-y-4">
         <div>
           <Label for="assessment-title">Assessment Title</Label>
           <Input id="assessment-title" bind:value={assessmentTitle} placeholder="e.g. Week 3 Quiz" />
         </div>
         <Accordion.Root type="multiple" value={['mcq']}>
           <Accordion.Item value="mcq">
             <Accordion.Trigger>MCQ Questions ({mcqQuestions.length})</Accordion.Trigger>
             <Accordion.Content>
               {#each mcqQuestions as q, i}
                 <div class="flex items-start gap-3 py-1">
                   <Checkbox checked={selectedMcq.has(i)} onCheckedChange={...} />
                   <span class="text-sm">{q.question}</span>
                   <Badge variant="outline" class="shrink-0">{q.options.length} options</Badge>
                 </div>
               {/each}
             </Accordion.Content>
           </Accordion.Item>
           <Accordion.Item value="theory">
             <Accordion.Trigger>Theoretical Questions ({theoryQuestions.length})</Accordion.Trigger>
             <Accordion.Content>
               {#each theoryQuestions as q, i}
                 <div class="flex items-start gap-3 py-1">
                   <Checkbox checked={selectedTheory.has(i)} onCheckedChange={...} />
                   <span class="text-sm">{q.question}</span>
                 </div>
               {/each}
             </Accordion.Content>
           </Accordion.Item>
         </Accordion.Root>
       </div>
       <Dialog.Footer>
         <Dialog.Close>Cancel</Dialog.Close>
         <Button disabled={!assessmentTitle.trim()} onclick={() => { assessmentModalOpen = false; }}>Create</Button>
       </Dialog.Footer>
     </Dialog.Content>
   </Dialog.Root>
   ```
   - `assessmentTitle`, `selectedMcq`, `selectedTheory` reset when modal opens
   - "Create" disabled until title is non-empty

**Side nav:** Copied verbatim from current lesson page — desktop hover dots (sticky centered, `right-full` text card on hover) and mobile floating TOC button. No Assignments heading.

### 5. Update Lesson Link on Term Page

**File:** `frontend/src/routes/my-classes/[classId]/[subjectId]/[termId]/+page.svelte`

Change lesson `href` from:

```svelte
href="/lms/{$page.params.subjectId}/{$page.params.termId}/{lesson.id}"
```

to:

```svelte
href="/my-classes/{$page.params.classId}/{$page.params.subjectId}/{$page.params.termId}/{lesson.id}"
```

### 6. Build & Deploy

```bash
# Backend
cd agents
moon info && moon fmt
golem build
golem deploy

# Frontend
cd ../frontend
pnpm check
```

## Dependencies

- **shadcn-svelte additions:** `accordion`, `checkbox` (installed via `npx shadcn-svelte@latest add`)
- No new npm packages — `bits-ui` (dependency of accordion/checkbox) is already installed
- No new MoonBit packages
- No database schema changes

## Verification Checklist

- [ ] `npx shadcn-svelte@latest add accordion checkbox` succeeds, files created in `lib/components/ui/`
- [ ] `moon info && moon fmt` — 0 errors
- [ ] `golem build` — 0 errors
- [ ] `golem deploy` — success
- [ ] `pnpm check` — 0 new errors
- [ ] Teacher clicks a lesson from term page → navigates to new tabbed page
- [ ] Lesson tab renders objectives, content sections, key points (same as before)
- [ ] Assignments section is absent from lesson tab and side nav
- [ ] Side nav dots appear, hover reveals section headings, click scrolls to section
- [ ] "Back to lessons" links to teacher's term page with correct params
- [ ] Assessments tab shows "No Assessments" status card + "Create Assessment" button
- [ ] Clicking "Create Assessment" opens dialog with title input + MCQ accordion (expanded) + theoretical accordion (collapsed)
- [ ] MCQ/theoretical checkboxes render from lesson data, can be toggled
- [ ] "Create" button is disabled when title is empty
- [ ] "Create" button closes dialog when title is non-empty (no backend call)
- [ ] Grading tab shows "No Submissions" status card
- [ ] Breadcrumbs render with resolved class name, subject name, term name
- [ ] Non-teacher accessing the route redirects to `/`
- [ ] Student LMS lesson page at `/lms/...` still works (with assignments section intact)
- [ ] Switching tabs preserves scroll position within tab content
