# Unit 21 — Teacher Agent: Term & Lesson Toggle

## Goal

Teacher can toggle term/lesson visibility on/off for students via `active` flags on the `terms` and `lessons` tables in SurrealDB. Toggling triggers targeted cache invalidation on all affected Student Agents via fire-and-forget RPC. Teachers always retain full access to all terms and lessons regardless of active state.

## Design

### Visual

**Term toggles** — On the teacher subject page (`/my-classes/[classId]/[subjectId]`), each term card gains a `Switch` component. All terms are clickable regardless of active state — the toggle controls student visibility only. Active terms show switch ON; inactive terms show switch OFF with a subtle "Hidden from students" badge. The current `opacity-50 pointer-events-none` + lock icon pattern for inactive items is removed entirely.

**Lesson toggles** — On the teacher lesson list page (`/my-classes/[classId]/[subjectId]/[termId]`), each lesson row gains a `Switch`. All lessons are clickable regardless of active state. Same pattern: switch ON/OFF indicates student visibility; inactive lessons get a subtle "Hidden" badge.

**Toast on toggle** — Success toast: `addToast('success', 'Term updated', 'Noel Term is now hidden from students.')`. Error toast on failure with the error message.

### Data Flow

```
Term toggle:
  Teacher clicks switch
  → POST /api/teacher/toggle-term { term_id, active }
  → TeacherAgent.toggle_term_active(term_id, active)
    → UPDATE terms SET active = {active}
    → Query teacher_assignment for teacher's class_levels (active session term)
    → Query user_profile for students in those class_levels (role='student')
    → Per student: fire-and-forget StudentAgent.trigger_invalidate_cache(key, "terms:{class_level}")
  → UI updates optimistically, toast shown

Lesson toggle:
  Teacher clicks switch
  → POST /api/teacher/toggle-lesson { lesson_id, active }
  → TeacherAgent.toggle_lesson_active(lesson_id, active)
    → Query lesson: SELECT topic.has_subject.{in,out}, topic.term FROM ONLY lessons
    → UPDATE lessons SET active = {active}
    → Query user_profile for students in lesson's class_level (role='student')
    → Per student:
        fire-and-forget StudentAgent.trigger_invalidate_cache(key, "lessons:{subj}|{term}")
        fire-and-forget StudentAgent.trigger_invalidate_cache(key, "lesson:{lesson_id}")
  → UI updates optimistically
```

### Cache Invalidation Strategy

| Toggle | Cache Keys Invalidated (per student) | Reason |
|--------|--------------------------------------|--------|
| Term | `"terms:{class_level}"` | Clears the student's cached term list for their class. Next fetch queries `terms WHERE active = true`. |
| Lesson | `"lessons:{subject_id}|{term_id}"` | Clears the lesson list cache for that subject+term combo. |
| Lesson | `"lesson:{lesson_id}"` | Clears the individual lesson content cache. |

An inactive (greyed-out) `has_subject` edge or a fully inactive term will cause the student's lesson list to return fewer results or an empty set, which triggers a `NotFound` error — the student UI handles this gracefully via `StatusCard`.

### Pre-existing Work

The following changes are already in place — no implementation work needed for these items:

| Item | Status | Location |
|------|--------|----------|
| `TeacherAgent.get_terms()` returns all terms (no `WHERE active = true` filter) | Done | `teacher_agent.mbt:267` |
| `TeacherAgent.get_lessons()` returns all lessons (no `AND active = true` filter), SELECT includes `active` | Done | `teacher_agent.mbt:330-331` |
| `TeacherAgent.get_lessons()` parses `active` from query result | Done | `teacher_agent.mbt:374-378` |
| `LessonInfo` struct has `active : Bool?` field | Done | `student_agent.mbt:32` |
| `Lesson` TypeScript interface has `active?: boolean` | Done | `types.ts:18` |
| Lesson link on term page points to `/my-classes/...` (not `/lms/...`) | Done | `[termId]/+page.svelte:29` |

## Implementation

### 1. Backend — Teacher Agent

**File:** `agents/app-agents/teacher_agent.mbt`

#### 1a. New endpoint: `toggle_term_active`

```
#derive.endpoint(post="/toggle-term-active?term_id={term_id}&active={active}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn TeacherAgent::toggle_term_active(
  self : Self,
  incoming_key : String,
  term_id : String,
  active : Bool,
) -> Result[String, String]
```

Logic:
1. `require_auth(self.config.value, incoming_key)` — bail on auth failure
2. Build `UPDATE {term_id} SET active = {active}` — term_id is a SurrealDB record ID (e.g., `terms:noel`), interpolated directly
3. Execute via `surreal_query(self.config.value, sql)` — return structured error on failure
4. Call `self.get_active_st()` to resolve active session term — skip fan-out if no active session term
5. Query affected class_levels:

```sql
SELECT VALUE has_subject.in
FROM teacher_assignment
WHERE teacher_id = '{escape(teacher_id)}'
  AND session_term = {active_st}
  AND deleted_at IS NONE
```

6. If no class_levels → return `Ok("ok")`
7. Query students in those class_levels:

```sql
SELECT auth_id, class_level
FROM user_profile
WHERE class_level IN [{class_levels}]
  AND role = 'student'
  AND deleted_at IS NONE
```

8. For each student row, fire-and-forget:
```moonbit
let auth_key_val = self.config.value.auth_key.get() catch { _ => "" }
for item in student_arr {
  match item {
    Object(obj) => {
      let student_id = ... // auth_id
      let cl = ... // class_level
      let _ = StudentAgentClient::scoped(student_id, fn(c) raise @common.AgentError {
        c.trigger_invalidate_cache(auth_key_val, "terms:{cl}")
      }) catch { _ => () }
    }
    _ => ()
  }
}
```

9. Return `Ok("ok")`

#### 1b. New endpoint: `toggle_lesson_active`

```
#derive.endpoint(post="/toggle-lesson-active?lesson_id={lesson_id}&active={active}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn TeacherAgent::toggle_lesson_active(
  self : Self,
  incoming_key : String,
  lesson_id : String,
  active : Bool,
) -> Result[String, String]
```

Logic:
1. `require_auth(self.config.value, incoming_key)`
2. Query lesson metadata to discover class_level, subject_id, term_id:

```sql
SELECT topic.has_subject.in AS class_level_id,
       topic.has_subject.out AS subject_id,
       topic.term AS term_id
FROM ONLY lessons
WHERE id = $lesson_id
```

3. Parse `class_level_id`, `subject_id`, `term_id` from the result Object
4. `UPDATE {lesson_id} SET active = {active}` via `surreal_query`
5. Query students in the lesson's class_level:

```sql
SELECT auth_id
FROM user_profile
WHERE class_level = {class_level_id}
  AND role = 'student'
  AND deleted_at IS NONE
```

6. For each student, fire-and-forget two invalidations:
```moonbit
let auth_key_val = self.config.value.auth_key.get() catch { _ => "" }
for item in student_arr {
  match item {
    Object(obj) => {
      let student_id = ... // auth_id
      let _ = StudentAgentClient::scoped(student_id, fn(c) raise @common.AgentError {
        c.trigger_invalidate_cache(auth_key_val, "lessons:{subject_id}|{term_id}")?!
        c.trigger_invalidate_cache(auth_key_val, "lesson:{lesson_id}")?!
      }) catch { _ => () }
    }
    _ => ()
  }
}
```

7. Return `Ok("ok")`

> **Note on RPC auth key:** The generated `StudentAgentClient::trigger_invalidate_cache` retains the `incoming_key` parameter from the HTTP endpoint signature. The `auth_key` shared across all agents is read from `self.config.value.auth_key.get()` (same value used by `require_auth`). This is passed to every fire-and-forget call so `require_auth` on the Student Agent side succeeds.

### 2. Backend — Student Agent

**File:** `agents/app-agents/student_agent.mbt`

No changes needed. The existing `invalidate_cache` method handles arbitrary cache key removal. Students re-fetch on next access — the `WHERE active = true` filter on `get_terms` and `get_lessons` naturally excludes toggled-off items.

### 3. Frontend — Install shadcn-svelte Switch

```bash
cd frontend && npx shadcn-svelte@latest add switch
```

### 4. Frontend — Proxy Routes

**New file:** `frontend/src/routes/api/teacher/toggle-term/+server.ts`

```typescript
import { proxyToTeacher, mapErrorCodeToHttpStatus } from '$lib/server/golem';
import type { RequestHandler } from './$types';

export const POST: RequestHandler = async (event) => {
  const userId = event.locals.user?.id;
  if (!userId) {
    return new Response(
      JSON.stringify({ error: { code: 'UNAUTHENTICATED', message: 'Not authenticated.' } }),
      { status: 401, headers: { 'content-type': 'application/json' } }
    );
  }

  const body = await event.request.json().catch(() => ({}));
  const { term_id, active } = body;
  if (!term_id || typeof active !== 'boolean') {
    return new Response(
      JSON.stringify({ error: { code: 'BAD_REQUEST', message: 'Missing term_id or active.' } }),
      { status: 400, headers: { 'content-type': 'application/json' } }
    );
  }

  const result = await proxyToTeacher(userId, '/toggle-term-active', { term_id, active: String(active) }, 'POST');

  if (result.error) {
    return new Response(JSON.stringify(result), {
      status: mapErrorCodeToHttpStatus(result.error.code),
      headers: { 'content-type': 'application/json' }
    });
  }

  return new Response(
    JSON.stringify({ data: { success: true } }),
    { status: 200, headers: { 'content-type': 'application/json' } }
  );
};
```

**New file:** `frontend/src/routes/api/teacher/toggle-lesson/+server.ts`

Same pattern — validates `lesson_id` (string) and `active` (boolean) from body, proxies to `/toggle-lesson-active`.

### 5. Frontend — Term Toggles (Subject Page)

**File:** `frontend/src/routes/my-classes/[classId]/[subjectId]/+page.svelte`

Imports to add:
```typescript
import { Switch } from '$lib/components/ui/switch/index.js';
import { Badge } from '$lib/components/ui/badge';
import { addToast } from '$lib/stores/toast';
```

Replace the `{#if term.active}...{:else}...` block with a single rendering for all terms:

```svelte
{#each terms as term (term.id)}
  <div class="relative">
    <a href="/my-classes/{$page.params.classId}/{$page.params.subjectId}/{term.id}">
      <Card class="w-48 hover:bg-primary-50 dark:hover:bg-primary-950/30 hover:ring-primary-200 dark:hover:ring-primary-700 transition cursor-pointer">
        <CardHeader class="pb-2">
          <CardTitle class="font-display text-base text-primary-700">{term.name}</CardTitle>
          {#if !term.active}
            <Badge variant="outline" class="text-xs text-amber-600 dark:text-amber-400 mt-1">Hidden from students</Badge>
          {/if}
        </CardHeader>
      </Card>
    </a>
    <div class="absolute top-2 right-2 z-10" onclick|stopPropagation>
      <Switch
        checked={term.active}
        onCheckedChange={() => handleToggleTerm(term.id, !term.active)}
      />
    </div>
  </div>
{/each}
```

Key details:
- The `Switch` is positioned absolutely (top-right of card) inside a relative container
- `onclick|stopPropagation` on the switch wrapper prevents the card's `<a>` navigation when toggling
- All cards render at full opacity regardless of active state
- Inactive terms get the amber "Hidden from students" badge

`handleToggleTerm` function:
```typescript
async function handleToggleTerm(termId: string, newActive: boolean) {
  // Optimistic update
  const idx = terms.findIndex(t => t.id === termId);
  if (idx === -1) return;
  const prev = terms[idx].active;
  terms[idx].active = newActive;
  terms = terms; // trigger reactivity

  try {
    const res = await fetch('/api/teacher/toggle-term', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ term_id: termId, active: newActive }),
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({ error: { message: 'Request failed' } }));
      throw new Error(err.error?.message ?? 'Request failed');
    }
    const termName = terms[idx].name;
    addToast('success', 'Term updated',
      newActive
        ? `${termName} is now visible to students.`
        : `${termName} is now hidden from students.`
    );
  } catch (e) {
    // Revert on failure
    terms[idx].active = prev;
    terms = terms;
    addToast('error', 'Failed to update term',
      e instanceof Error ? e.message : 'Unknown error'
    );
  }
}
```

### 6. Frontend — Lesson Toggles (Term Page)

**File:** `frontend/src/routes/my-classes/[classId]/[subjectId]/[termId]/+page.svelte`

Imports to add:
```typescript
import { Switch } from '$lib/components/ui/switch/index.js';
import { Badge } from '$lib/components/ui/badge';
import { addToast } from '$lib/stores/toast';
```

Replace the `{#if lesson.active !== false}...{:else}...` block:

```svelte
{#each lessons as lesson (lesson.id)}
  <div class="relative">
    <a href="/my-classes/{$page.params.classId}/{$page.params.subjectId}/{$page.params.termId}/{lesson.id}" class="block">
      <Card class="hover:bg-primary-50 dark:hover:bg-primary-950/30 transition cursor-pointer">
        <CardHeader class="pb-0">
          <div class="flex justify-between items-start">
            <div>
              <CardTitle class="font-display text-base text-primary-700">
                Week {lesson.week}: {lesson.topic_title ?? 'Untitled Lesson'}
              </CardTitle>
              {#if lesson.active === false}
                <Badge variant="outline" class="text-xs text-amber-600 dark:text-amber-400 mt-1">Hidden from students</Badge>
              {/if}
            </div>
          </div>
        </CardHeader>
      </Card>
    </a>
    <div class="absolute top-4 right-3 z-10" onclick|stopPropagation>
      <Switch
        checked={lesson.active !== false}
        onCheckedChange={() => handleToggleLesson(lesson.id, lesson.active === false)}
      />
    </div>
  </div>
{/each}
```

`handleToggleLesson` function — same pattern as `handleToggleTerm` but calls `/api/teacher/toggle-lesson` with `{ lesson_id, active }`.

### 7. Frontend — Types

**File:** `frontend/src/lib/types.ts`

No changes needed. `Lesson.active?: boolean` already exists at line 18.

## Dependencies

- **shadcn-svelte additions:** `switch` (`npx shadcn-svelte@latest add switch`)
- No new npm packages — `bits-ui` (dependency of switch) already installed
- No new MoonBit packages
- No database schema changes

## Verification Checklist

### Backend
- [ ] `moon info && moon fmt` — 0 errors
- [ ] `moon check --target wasm` — 0 errors
- [ ] `golem build` — 0 errors
- [ ] `golem deploy` — success
- [ ] `POST /teacher/{id}/toggle-term-active?term_id=terms:noel&active=false` returns 200, updates SurrealDB
- [ ] `POST /teacher/{id}/toggle-lesson-active?lesson_id=lessons:xxx&active=false` returns 200, updates SurrealDB
- [ ] `StudentAgent.get_terms()` still returns only active terms (no regression)
- [ ] `StudentAgent.get_lessons()` still returns only active lessons (no regression)

### Frontend
- [ ] `npx shadcn-svelte@latest add switch` succeeds
- [ ] `pnpm check` — 0 new errors
- [ ] Teacher subject page: ALL terms render at full opacity, each has a `Switch`
- [ ] Toggling a term off: switch updates, "Hidden from students" badge appears, toast fires
- [ ] Toggling a term on: switch updates, badge disappears, toast fires
- [ ] Inactive term card is still clickable — navigates to lesson list
- [ ] Clicking the `Switch` does NOT trigger navigation (stopPropagation works)
- [ ] Teacher lesson list page: ALL lessons are clickable, each has a `Switch`
- [ ] Toggling a lesson off/on: switch + badge + toast work correctly
- [ ] No `opacity-50` or `pointer-events-none` or lock icon SVG on any term or lesson card
- [ ] Toggle failure (network error): state reverts, error toast shown

### Integration
- [ ] Toggle a term off → student's `/lms` subject page does not show that term (after cache TTL or manual invalidation)
- [ ] Toggle a lesson off → student's lesson list does not show that lesson
- [ ] Teacher can still navigate into toggled-off term/lesson without restriction
- [ ] Toggle back on → student sees it again after cache TTL
- [ ] Rapid toggles are idempotent (no duplicate DB rows, no errors)
