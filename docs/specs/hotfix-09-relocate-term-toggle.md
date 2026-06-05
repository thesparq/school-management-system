# HF-09 — Relocate Term Toggle from Teacher to Admin

## Goal

Move term active/inactive toggling from the Teacher Agent to the Admin Agent, add a new admin "Terms" page under Configuration with a table layout matching the session terms pattern, and update the teacher term page to display inactive terms with a padlock icon instead of a toggle switch.

## Design

### Visual

**Admin terms page** — table layout (matching session terms page): columns for Name, Active (Switch toggle), Sort Order. No navigation on click — purely for toggling.

**Teacher term page** — same card layout as before, but without Switch toggles. Inactive term cards show a padlock icon + amber "Hidden from students" badge. Cards remain clickable (teacher still browses inactive terms' lessons).

**Sidebar** — new "Terms" link under Configuration group, between "Session Terms" and the Users group.

### Structural

| Component | Action |
|-----------|--------|
| `teacher_agent.mbt` | Remove `toggle_term_active` endpoint |
| `teacher_handler.mbt` | Remove `teacher_toggle_term` function |
| `admin_agent.mbt` | Add `toggle_term_active` endpoint |
| `admin_handler.mbt` | Add `admin_toggle_term` handler |
| `db_admin.mbt` | Add `db_admin_fetch_users_by_role` helper |
| `frontend/api/teacher/toggle-term/+server.ts` | Delete |
| `frontend/my-classes/[classId]/[subjectId]/+page.svelte` | Remove Switch, add padlock icon |
| `frontend/admin/configuration/terms/+page.svelte` | New — terms table with toggle |
| `frontend/admin/configuration/terms/+page.server.ts` | New — fetch terms |
| `frontend/api/admin/toggle-term/+server.ts` | New — proxy route |
| `frontend/+layout.svelte` | Add Terms to sidebar |

### Invalidation strategy

Fire-and-forget via `trigger_invalidate_cache` to all students and teachers — same pattern the teacher toggle already uses. One `db_admin_fetch_users_by_role` query per role. Loop-based dispatch; each `trigger_*` is async enqueue with zero wait. Golem's fire-and-forget handles the rest.

---

## Implementation

### 1. Backend: Remove term toggle from Teacher Agent

**1a. `teacher_agent.mbt`** — remove lines 42-48 (`toggle_term_active` endpoint).

**1b. `teacher_handler.mbt`** — remove `teacher_toggle_term` function (lines 97-115).

### 2. Backend: New DB helper

**2a. `db_admin.mbt`** — new function:

```moonbit
pub fn db_admin_fetch_users_by_role(
  config : SharedConfig,
  role : String
) -> Result[Array[Json], AppError] {
  surreal_query(config, "SELECT auth_id FROM user_profile WHERE role = $role AND deleted_at IS NONE", bindings={ "role": role })
}
```

### 3. Backend: New Admin term toggle handler

**3a. `admin_handler.mbt`** — new function:

```moonbit
///|
pub fn admin_toggle_term(
  config : SharedConfig,
  term_id : String,
  active : Bool,
) -> Result[Unit, AppError] {
  match db_teacher_update_record_active(config, term_id, active) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let students = match db_admin_fetch_users_by_role(config, "student") {
    Ok(a) => a
    Err(_) => []
  }
  let teachers = match db_admin_fetch_users_by_role(config, "teacher") {
    Ok(a) => a
    Err(_) => []
  }
  let ak = config.auth_key.get() catch { _ => "" }
  if ak != "" {
    for item in students {
      match item {
        Object(obj) => {
          let uid = match obj.get("auth_id") {
            Some(String(s)) => s
            _ => continue
          }
          let _ = StudentAgentClient::scoped(uid, fn(c) raise @common.AgentError {
            c.trigger_invalidate_cache(ak, "all")
          }) catch { _ => () }
        }
        _ => ()
      }
    }
    for item in teachers {
      match item {
        Object(obj) => {
          let uid = match obj.get("auth_id") {
            Some(String(s)) => s
            _ => continue
          }
          let _ = TeacherAgentClient::scoped(uid, fn(c) raise @common.AgentError {
            c.trigger_invalidate_cache(ak, "class_groups")
          }) catch { _ => () }
        }
        _ => ()
      }
    }
  }
  Ok(())
}
```

### 4. Backend: New Admin Agent endpoint

**4a. `admin_agent.mbt`** — new endpoint after the existing `activate_session_term` endpoint:

```moonbit
#derive.endpoint(post="/toggle-term-active?term_id={term_id}&active={active}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::toggle_term_active(self : Self, incoming_key : String, term_id : String, active : Bool) -> Result[String, String] {
  match require_auth(self.config.value, incoming_key) { Err(e) => return Err(e.to_json_string()); Ok(_) => () }
  match admin_toggle_term(self.config.value, term_id, active) { Ok(_) => Ok("ok"); Err(e) => Err(e.to_json_string()) }
}
```

### 5. Frontend: Remove teacher toggle route

**5a.** Delete `frontend/src/routes/api/teacher/toggle-term/+server.ts` entirely.

### 6. Frontend: Teacher term page — replace Switch with padlock icon

**6a. `frontend/src/routes/my-classes/[classId]/[subjectId]/+page.svelte`:**

- Remove `Switch` import (line 5)
- Remove `addToast` import if no longer used (line 10)
- Remove `handleToggleTerm` function (lines 25-48)
- Remove `visibleLabel` function (lines 21-23)
- Replace the Switch block (lines 75-87) with:

```svelte
{#if !term.active}
  <div class="flex items-center gap-1.5 mt-2 pl-1">
    <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5 text-amber-500" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
      <path stroke-linecap="round" stroke-linejoin="round" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
    </svg>
    <span class="text-xs text-amber-600">Hidden from students</span>
  </div>
{/if}
```

- Keep the card `<a>` link — teacher still needs to access inactive terms' lessons.

### 7. Frontend: New admin Terms page

**7a. `frontend/src/routes/admin/configuration/terms/+page.svelte`** — new file:

```svelte
<script lang="ts">
  import type { PageData } from './$types';
  import { Card, CardContent } from '$lib/components/ui/card';
  import { Switch } from '$lib/components/ui/switch/index.js';
  import {
    Table, TableBody, TableCell, TableHead, TableHeader, TableRow
  } from '$lib/components/ui/table';
  import { Skeleton } from '$lib/components/ui/skeleton';
  import StatusCard from '$lib/components/ui/status-card/status-card.svelte';
  import { addToast } from '$lib/stores/toast';
  import { goto } from '$app/navigation';

  interface Term {
    id: string;
    name: string;
  }

  let { data }: { data: PageData } = $props();
  let terms: Term[] = $state(data.terms);

  $effect(() => { terms = data.terms; });

  async function handleToggle(termId: string, newActive: boolean) {
    const idx = terms.findIndex(t => t.id === termId);
    if (idx === -1) return;
    const prev = terms[idx].active;
    terms[idx].active = newActive;
    terms = [...terms];

    try {
      const res = await fetch('/api/admin/toggle-term', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ term_id: termId, active: newActive }),
      });
      if (!res.ok) {
        const err = await res.json().catch(() => ({ error: { message: 'Request failed' } }));
        throw new Error(err.error?.message ?? 'Request failed');
      }
      addToast('success', 'Term updated', `${terms[idx].name} is now ${newActive ? 'visible' : 'hidden'} to students.`);
    } catch (e) {
      terms[idx].active = prev;
      terms = [...terms];
      addToast('error', 'Failed to update term', e instanceof Error ? e.message : 'Unknown error');
    }
  }
</script>

<div class="mx-auto max-w-6xl space-y-6">
  <h1 class="text-2xl font-display font-bold text-primary-700">Terms</h1>

  {#if !terms || terms.length === 0}
    <StatusCard variant="info" title="No Terms Available" description="No terms exist in the database yet." />
  {:else}
    <Card>
      <CardContent class="p-0">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Name</TableHead>
              <TableHead class="w-24">Active</TableHead>
              <TableHead class="w-24">Sort Order</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {#each terms as term (term.id)}
              <TableRow>
                <TableCell class="font-medium">{term.name}</TableCell>
                <TableCell>
                  <Switch
                    checked={term.active}
                    onCheckedChange={(checked) => handleToggle(term.id, checked)}
                  />
                </TableCell>
                <TableCell class="text-surface-500 text-sm">{term.sort_order}</TableCell>
              </TableRow>
            {/each}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  {/if}
</div>
```

Wait — I need `active` and `sort_order` fields on the Term type. The current `admin_fetch_terms` returns `Array[TermSimple]` which only has `id` and `name`. I need a richer struct. Let me add `active` and `sort_order` to `TermSimple`, or create a new `TermAdmin` struct that includes all fields. Actually, `admin_fetch_terms` queries `SELECT id, name, sort_order FROM terms` — I just need to add `active` to the query and struct.

Let me revise the plan to include that.

**7a. `types_admin.mbt`** — update `TermSimple` to include `active` and `sort_order`:

```moonbit
#derive.golem_schema
struct TermSimple {
  id : String
  name : String
  active : Bool
  sort_order : Int
} derive(ToJson, FromJson)
```

**7b. `db_admin.mbt`** — update `db_admin_fetch_terms` query:

```moonbit
surreal_query(config, "SELECT id, name, sort_order, active FROM terms ORDER BY sort_order ASC")
```

**7c. `admin_handler.mbt`** — update `admin_fetch_terms` to include `active` and `sort_order` in the extraction:

```moonbit
pub fn admin_fetch_terms(config : SharedConfig) -> Result[Array[TermSimple], AppError] {
  let arr = match db_admin_fetch_terms(config) { Ok(a) => a; Err(e) => return Err(e) }
  let items : Array[TermSimple] = []
  for item in arr {
    match item {
      Object(o) => items.push(TermSimple::{
        id: match o.get("id") { Some(String(s)) => s; _ => continue },
        name: match o.get("name") { Some(String(s)) => s; _ => continue },
        active: match o.get("active") { Some(True) => true; _ => false },
        sort_order: match o.get("sort_order") { Some(Number(d, ..)) => d.to_int(); _ => 0 },
      })
      _ => ()
    }
  }
  Ok(items)
}
```

OK, so I need to modify 3 backend files for the TermSimple struct update. Let me incorporate this into the spec.

Actually, wait. Let me not make the spec too verbose with full component code. I'll describe the key parts.<｜end▁of▁thinking｜>

<｜｜DSML｜｜tool_calls>
<｜｜DSML｜｜invoke name="write">
<｜｜DSML｜｜parameter name="content" string="true"># HF-09 — Relocate Term Toggle from Teacher to Admin

## Goal

Move term active/inactive toggling from the Teacher Agent to the Admin Agent, add a new admin "Terms" page under Configuration with a table layout matching the session terms pattern, and update the teacher term page to display inactive terms with a padlock badge instead of a toggle switch.

## Design

### Visual

**Admin terms page** — table layout (same shadcn-svelte Table components as session terms page). Columns: Name, Active (Switch toggle), Sort Order. No navigation on row click — the page exists purely for toggling.

**Teacher term page** — same card grid layout as before, but without Switch toggles. Inactive term cards show a padlock icon + amber "Hidden from students" badge below the card. Cards remain clickable links (teacher still accesses inactive terms' lessons).

**Sidebar** — new "Terms" link under Configuration group, between "Session Terms" and the Users group.

### Structural

| Component | Action |
|-----------|--------|
| `teacher_agent.mbt` | Remove `toggle_term_active` endpoint |
| `teacher_handler.mbt` | Remove `teacher_toggle_term` function |
| `admin_agent.mbt` | Add `toggle_term_active` endpoint |
| `admin_handler.mbt` | Add `admin_toggle_term` handler; update `admin_fetch_terms` to extract `active` + `sort_order` |
| `db_admin.mbt` | Add `db_admin_fetch_users_by_role`; update `db_admin_fetch_terms` SQL to include `active` |
| `types_admin.mbt` | `TermSimple` gains `active : Bool` and `sort_order : Int` fields |
| `frontend/api/teacher/toggle-term/+server.ts` | Delete |
| `frontend/my-classes/[classId]/[subjectId]/+page.svelte` | Remove Switch, add padlock badge |
| `frontend/admin/configuration/terms/+page.svelte` | New |
| `frontend/admin/configuration/terms/+page.server.ts` | New |
| `frontend/api/admin/toggle-term/+server.ts` | New |
| `frontend/+layout.svelte` | Add Terms to sidebar |

### Invalidation strategy

Fire-and-forget via `trigger_invalidate_cache` to all students (`"all"`) and teachers (`"class_groups"`). Same loop-based pattern the teacher toggle already uses. One `db_admin_fetch_users_by_role` query per role. Each `trigger_*` is async enqueue with zero wait — 200 iterations runs sub-second.

---

## Implementation

### 1. Backend: Remove term toggle from Teacher Agent

**1a. `teacher_agent.mbt`** — remove `toggle_term_active` endpoint (lines 42-48).

**1b. `teacher_handler.mbt`** — remove `teacher_toggle_term` function (lines 97-115).

### 2. Backend: Update `TermSimple` struct with `active` + `sort_order`

The admin terms table needs `active` (for the Switch toggle) and `sort_order` (display column).

**2a. `types_admin.mbt`** — `TermSimple` gains two fields:

```moonbit
#derive.golem_schema
struct TermSimple {
  id : String
  name : String
  active : Bool
  sort_order : Int
} derive(ToJson, FromJson)
```

**2b. `db_admin.mbt`** — `db_admin_fetch_terms` SQL includes `active`:

```moonbit
pub fn db_admin_fetch_terms(config : SharedConfig) -> Result[Array[Json], AppError] {
  surreal_query(config, "SELECT id, name, sort_order, active FROM terms ORDER BY sort_order ASC")
}
```

**2c. `admin_handler.mbt`** — `admin_fetch_terms` extracts `active` and `sort_order`:

```moonbit
pub fn admin_fetch_terms(config : SharedConfig) -> Result[Array[TermSimple], AppError] {
  let arr = match db_admin_fetch_terms(config) { Ok(a) => a; Err(e) => return Err(e) }
  let items : Array[TermSimple] = []
  for item in arr {
    match item {
      Object(o) => items.push(TermSimple::{
        id: match o.get("id") { Some(String(s)) => s; _ => continue },
        name: match o.get("name") { Some(String(s)) => s; _ => continue },
        active: match o.get("active") { Some(True) => true; _ => false },
        sort_order: match o.get("sort_order") { Some(Number(d, ..)) => d.to_int(); _ => 0 },
      })
      _ => ()
    }
  }
  Ok(items)
}
```

### 3. Backend: New DB helper for fetching users by role

**3a. `db_admin.mbt`** — new function:

```moonbit
pub fn db_admin_fetch_users_by_role(
  config : SharedConfig,
  role : String
) -> Result[Array[Json], AppError] {
  surreal_query(config, "SELECT auth_id FROM user_profile WHERE role = $role AND deleted_at IS NONE", bindings={ "role": role })
}
```

### 4. Backend: New Admin term toggle handler

**4a. `admin_handler.mbt`** — new function after `admin_activate_session_term`:

```moonbit
///|
pub fn admin_toggle_term(
  config : SharedConfig,
  term_id : String,
  active : Bool,
) -> Result[Unit, AppError] {
  match db_teacher_update_record_active(config, term_id, active) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let students = match db_admin_fetch_users_by_role(config, "student") {
    Ok(a) => a
    Err(_) => []
  }
  let teachers = match db_admin_fetch_users_by_role(config, "teacher") {
    Ok(a) => a
    Err(_) => []
  }
  let ak = config.auth_key.get() catch { _ => "" }
  if ak != "" {
    for item in students {
      match item {
        Object(obj) => {
          let uid = match obj.get("auth_id") { Some(String(s)) => s; _ => continue }
          let _ = StudentAgentClient::scoped(uid, fn(c) raise @common.AgentError {
            c.trigger_invalidate_cache(ak, "all")
          }) catch { _ => () }
        }
        _ => ()
      }
    }
    for item in teachers {
      match item {
        Object(obj) => {
          let uid = match obj.get("auth_id") { Some(String(s)) => s; _ => continue }
          let _ = TeacherAgentClient::scoped(uid, fn(c) raise @common.AgentError {
            c.trigger_invalidate_cache(ak, "class_groups")
          }) catch { _ => () }
        }
        _ => ()
      }
    }
  }
  Ok(())
}
```

### 5. Backend: New Admin Agent endpoint

**5a. `admin_agent.mbt`** — new endpoint after `activate_session_term`:

```moonbit
#derive.endpoint(post="/toggle-term-active?term_id={term_id}&active={active}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::toggle_term_active(self : Self, incoming_key : String, term_id : String, active : Bool) -> Result[String, String] {
  match require_auth(self.config.value, incoming_key) { Err(e) => return Err(e.to_json_string()); Ok(_) => () }
  match admin_toggle_term(self.config.value, term_id, active) { Ok(_) => Ok("ok"); Err(e) => Err(e.to_json_string()) }
}
```

### 6. Frontend: Delete teacher toggle route

**6a.** Delete `frontend/src/routes/api/teacher/toggle-term/+server.ts`.

### 7. Frontend: Teacher term page — replace Switch with padlock badge

**7a. `frontend/src/routes/my-classes/[classId]/[subjectId]/+page.svelte`:**

- Remove `Switch` import
- Remove `addToast` import (if no other usage remains)
- Remove `visibleLabel` function
- Remove `handleToggleTerm` function
- Replace the Switch block (currently lines 75-87) with a padlock badge shown only for inactive terms:

```svelte
{#if !term.active}
  <div class="flex items-center gap-1.5 mt-2 pl-1">
    <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5 text-amber-500" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
      <path stroke-linecap="round" stroke-linejoin="round" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
    </svg>
    <span class="text-xs text-amber-600">Hidden from students</span>
  </div>
{/if}
```

- The card's `<a>` link stays — teacher still navigates into inactive terms' lessons.

### 8. Frontend: New admin terms page

**8a. `frontend/src/routes/admin/configuration/terms/+page.server.ts`** — new file:

```ts
import { error } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import { adminProxy } from '$lib/server/golem';

interface TermItem {
  id: string;
  name: string;
  active: boolean;
  sort_order: number;
}

export const load: PageServerLoad = async (event) => {
  const user = event.locals.user;
  if (!user || !user.roles.includes('admin')) error(403, 'Forbidden');

  const proxy = adminProxy(user);
  let terms: TermItem[] = [];
  let termsError: string | null = null;

  try {
    const result = await proxy('/terms');
    if (result.error) {
      termsError = result.error.message;
    } else {
      const parsed = JSON.parse(result.data);
      terms = Array.isArray(parsed) ? parsed : [];
    }
  } catch {
    termsError = 'Failed to reach backend service.';
  }

  return { terms, termsError, breadcrumbs: [{ label: 'Configuration' }, { label: 'Terms' }] as { label: string; href?: string }[] };
};
```

**8b. `frontend/src/routes/admin/configuration/terms/+page.svelte`** — new file:

- Table layout with shadcn-svelte `Table`, `TableHeader`, `TableBody`, `TableRow`, `TableCell`, `TableHead`
- Columns: Name, Active (Switch), Sort Order
- `handleToggle` function with optimistic update + toast + rollback on error — same pattern as session terms activate toggle
- Error state via StatusCard if `data.termsError`
- Uses `TermItem` interface from page.server.ts

### 9. Frontend: New admin toggle-term proxy route

**9a. `frontend/src/routes/api/admin/toggle-term/+server.ts`** — new file:

```ts
import { adminProxy, mapErrorCodeToHttpStatus } from '$lib/server/golem';
import type { RequestHandler } from './$types';

export const POST: RequestHandler = async (event) => {
  const user = event.locals.user;
  if (!user) return new Response(JSON.stringify({ error: { code: 'UNAUTHENTICATED', message: 'Not authenticated.' } }), { status: 401, headers: { 'content-type': 'application/json' } });
  if (!user.roles.includes('admin')) return new Response(JSON.stringify({ error: { code: 'FORBIDDEN', message: 'Forbidden' } }), { status: 403, headers: { 'content-type': 'application/json' } });

  const body = await event.request.json().catch(() => ({}));
  const { term_id, active } = body;
  if (!term_id || typeof active !== 'boolean') {
    return new Response(JSON.stringify({ error: { code: 'BAD_REQUEST', message: 'Missing term_id or active.' } }), { status: 400, headers: { 'content-type': 'application/json' } });
  }

  const proxy = adminProxy(user);
  const result = await proxy('/toggle-term-active', { term_id, active: String(active) }, 'POST');

  if (result.error) {
    return new Response(JSON.stringify(result), { status: mapErrorCodeToHttpStatus(result.error.code), headers: { 'content-type': 'application/json' } });
  }

  return new Response(JSON.stringify({ data: { success: true } }), { status: 200, headers: { 'content-type': 'application/json' } });
};
```

### 10. Frontend: Add Terms to admin sidebar

**10a. `frontend/src/routes/+layout.svelte`** — inside the Configuration `SidebarGroup` (after Session Terms):

```svelte
<SidebarMenuItem>
  <SidebarMenuButton isActive={$page.url.pathname.startsWith('/admin/configuration/terms')}>
    {#snippet child({ props })}
      <a href="/admin/configuration/terms" {...props}>Terms</a>
    {/snippet}
  </SidebarMenuButton>
</SidebarMenuItem>
```

---

## Dependencies

None. All changes within existing files plus 4 new frontend files. No new packages.

---

## Files Changed (summary)

| File | Action |
|------|--------|
| `agents/app-agents/teacher_agent.mbt` | Remove `toggle_term_active` endpoint |
| `agents/app-agents/teacher_handler.mbt` | Remove `teacher_toggle_term` function |
| `agents/app-agents/admin_agent.mbt` | Add `toggle_term_active` endpoint |
| `agents/app-agents/admin_handler.mbt` | Add `admin_toggle_term` handler; update `admin_fetch_terms` extraction |
| `agents/app-agents/db_admin.mbt` | Add `db_admin_fetch_users_by_role`; update `db_admin_fetch_terms` SQL |
| `agents/app-agents/types_admin.mbt` | `TermSimple` gains `active : Bool` + `sort_order : Int` |
| `frontend/src/routes/api/teacher/toggle-term/+server.ts` | Delete |
| `frontend/src/routes/my-classes/[classId]/[subjectId]/+page.svelte` | Remove Switch, add padlock badge |
| `frontend/src/routes/admin/configuration/terms/+page.svelte` | New |
| `frontend/src/routes/admin/configuration/terms/+page.server.ts` | New |
| `frontend/src/routes/api/admin/toggle-term/+server.ts` | New |
| `frontend/src/routes/+layout.svelte` | Add Terms to Configuration sidebar |

---

## Verification Checklist

### Build
- [ ] `moon check --target wasm` — 0 errors
- [ ] `golem build` — 0 errors
- [ ] `pnpm build` — passes

### Teacher Agent
- [ ] `toggle_term_active` endpoint removed from `teacher_agent.mbt`
- [ ] `teacher_toggle_term` function removed from `teacher_handler.mbt`
- [ ] No remaining references to `teacher_toggle_term` or `/toggle-term-active` in teacher files
- [ ] `toggle_lesson_active` endpoint still present

### Admin Agent
- [ ] `toggle_term_active` endpoint present in `admin_agent.mbt`
- [ ] `admin_toggle_term` handler present in `admin_handler.mbt`
- [ ] `db_admin_fetch_users_by_role` helper present in `db_admin.mbt`
- [ ] `TermSimple` struct has `active : Bool` and `sort_order : Int` fields
- [ ] `admin_fetch_terms` returns terms with active status and sort order

### Frontend — Teacher term page
- [ ] Switch component removed
- [ ] `handleToggleTerm` function removed
- [ ] Inactive terms show padlock icon + "Hidden from students" badge
- [ ] Active terms show no badge
- [ ] Card links still navigate to term's lesson list

### Frontend — Admin terms page
- [ ] Page renders at `/admin/configuration/terms`
- [ ] Table shows Name, Active (Switch toggle), Sort Order columns
- [ ] Toggling Switch sends `POST /api/admin/toggle-term`
- [ ] Optimistic update + toast on success
- [ ] Rollback + error toast on failure
- [ ] Error state via StatusCard when `data.termsError`

### Frontend — Sidebar + routes
- [ ] "Terms" link appears under Configuration in admin sidebar
- [ ] `POST /api/admin/toggle-term` proxy route exists and validates input
- [ ] `GET /api/teacher/toggle-term` route deleted

### Manual smoke
- [ ] Admin toggles a term inactive → students fetch terms, see updated active flag
- [ ] Admin toggles a term active → students fetch terms, see updated active flag
- [ ] Teacher views term page → sees padlock icon on inactive terms, can still click into lessons
- [ ] `TermSimple` struct change doesn't break `admin_agent.mbt` `get_terms` return type (auto-regenerated by golem build)
