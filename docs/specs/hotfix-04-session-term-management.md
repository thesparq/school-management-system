# HF-04 — Session Term Management (Admin Configuration)

## Goal

Add a "Configuration" sidebar group with a "Session Terms" management page where admins can list, create, and activate session terms. Each session term links a school session (e.g., "2024") to an academic term (e.g., "Noel Term"). Only one session term can be active at a time, scoping teacher assignments, future assessments, fees, and results.

## Design

### Sidebar Structure

```
Configuration          ← NEW group (above Users)
  └── Session Terms    ← NEW link, icon: calendar
Users                  ← existing group
  ├── Students
  ├── Teachers
  └── Admin
```

The "Configuration" sidebar group appears only for users with the `admin` role. The "Session Terms" link is active when the current path starts with `/admin/configuration/session-terms`.

### Page UI

**Table**: Displays all session terms sorted by `created_at DESC`. Columns:
- **Session** — Year string (e.g., "2024")
- **Term** — Term name (e.g., "Noel Term"), resolved via dot-traversal from `term.name`
- **Active** — Badge: "Active" (green/success) or "Inactive" (gray/secondary)
- **Created At** — Formatted datetime
- **Actions** — "Activate" button, only visible on inactive rows

**Create dialog** (triggered by "Create Session Term" button above table):
- **"Session"** — Text input (e.g., "2024")
- **"Term"** — Dropdown/select, populated from `GET /admin/{id}/terms` (all terms sorted by `sort_order ASC`)
- **"Set as active session term"** — Checkbox, checked by default
- On submit: calls `POST /admin/{id}/create-session-term`. If checkbox checked, the new record is auto-activated and all other session terms are deactivated.
- On success: dialog closes, table refreshes. New record appears at top.

**Activate button**: Clicking "Activate" on an inactive row shows a confirmation (avoid accidental deactivation of the current active term). On confirm: calls `POST /admin/{id}/activate-session-term?session_term_id=...`. Target is activated, all others deactivated. Table refreshes.

**Warning state**: When no session term has `active = true`, the page shows `StatusCard(variant="warning")` with the message: "No active session term. Teacher assignments cannot be scoped to a term."

**Error state**: `StatusCard(variant="error")` with the agent's error message and a Retry button.

**Loading state**: Skeleton table rows.

### Cache Strategy

The Admin Agent's `get_active_st()` private helper (created in HF-03) caches the active session term ID under the key `"active_session_term"` with TTL 600s. On create/activate, the cache key is removed via `self.caches.remove("active_session_term")` — the next request re-fetches from SurrealDB.

Teacher agents have their own independently cached `"active_session_term"` key (also TTL 600s, created in HF-03). They re-fetch on next use. No multi-agent fan-out is needed — session terms change once per academic term, and 600s delay is negligible for this use case.

The `GET /terms` and `GET /session-terms` endpoints do no caching. Terms are static (3 entries, almost never change). Session terms are low-volume (one row per academic term) and fetched only by admins.

### Schema

No new schema changes. The `session_term` table was defined in HF-03:

```surql
DEFINE TABLE session_term SCHEMAFULL PERMISSIONS FOR select, create, update, delete NONE;
DEFINE FIELD session     ON session_term TYPE string;
DEFINE FIELD term        ON session_term TYPE record<terms>;
DEFINE FIELD active      ON session_term TYPE bool DEFAULT false;
DEFINE FIELD created_at  ON session_term TYPE datetime DEFAULT time::now();
DEFINE FIELD deleted_at  ON session_term TYPE option<datetime>;
DEFINE INDEX idx_st_combo ON session_term COLUMNS session, term UNIQUE;
```

### Directory Structure

```
frontend/src/routes/admin/
├── configuration/                          ← NEW directory
│   └── session-terms/
│       ├── +page.server.ts                 ← Loads session terms + terms list
│       └── +page.svelte                    ← Table + Create dialog UI
└── api/admin/
    ├── session-terms/
    │   ├── +server.ts                      ← GET  /admin/{id}/session-terms
    │   ├── create/+server.ts               ← POST /admin/{id}/create-session-term
    │   └── activate/+server.ts             ← POST /admin/{id}/activate-session-term
    └── terms/
        └── +server.ts                      ← GET  /admin/{id}/terms
```

## Implementation

### A. Backend — `agents/app-agents/admin_agent.mbt`

Four new HTTP endpoints on the Admin Agent:

**1. `GET /terms`** — List all terms for the create dialog dropdown.

```moonbit
#derive.endpoint(get="/terms")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::get_terms(self: Self, incoming_key: String) -> Result[String, String] {
    // Auth check via require_auth
    // SQL: SELECT id, name FROM terms ORDER BY sort_order ASC
    // Returns JSON array: [{"id":"terms:noel_term","name":"Noel Term"},...]
}
```

No caching — terms are static (3 entries).

**2. `GET /session-terms`** — List all session terms with resolved term names.

```moonbit
#derive.endpoint(get="/session-terms")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::get_session_terms(self: Self, incoming_key: String) -> Result[String, String] {
    // SQL: SELECT id, session, term.name AS term_name, active, created_at
    //      FROM session_term ORDER BY created_at DESC
    // Returns JSON array: [{"id":"...","session":"2024","term_name":"Noel Term","active":true,"created_at":"..."},...]
}
```

No caching — admin page, low frequency.

**3. `POST /create-session-term`** — Create a new session term. Optionally auto-activate.

```moonbit
#derive.endpoint(post="/create-session-term")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
#derive.endpoint_body("body_json")
pub fn AdminAgent::create_session_term(self: Self, incoming_key: String, body_json: String) -> Result[String, String] {
    // Parse body: { session, term_id, active }
    // If active: UPDATE session_term SET active = false; (deactivate all)
    // CREATE session_term SET session = '<session>', term = <term_id>,
    //   active = true/false, created_at = time::now();
    // Invalidate: self.caches.remove("active_session_term")
    // Query full record (with term.name) and return it
}
```

**4. `POST /activate-session-term`** — Activate a specific session term, deactivating all others.

```moonbit
#derive.endpoint(post="/activate-session-term?session_term_id={session_term_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::activate_session_term(self: Self, incoming_key: String, session_term_id: String) -> Result[String, String] {
    // UPDATE session_term SET active = false;
    // UPDATE session_term SET active = true WHERE id = <session_term_id>;
    // Invalidate: self.caches.remove("active_session_term")
    // Return "ok"
}
```

### B. Frontend — API Proxy Routes

All proxy routes follow the existing boilerplate pattern (auth gate → `adminProxy(user)` → `mapErrorCodeToHttpStatus` → JSON response). Four new routes:

| File | Endpoint | Method |
|------|----------|--------|
| `api/admin/terms/+server.ts` | `/admin/{id}/terms` | GET |
| `api/admin/session-terms/+server.ts` | `/admin/{id}/session-terms` | GET |
| `api/admin/session-terms/create/+server.ts` | `/admin/{id}/create-session-term` | POST |
| `api/admin/session-terms/activate/+server.ts` | `/admin/{id}/activate-session-term?session_term_id=...` | POST |

Each ~30 lines, identical pattern to existing `api/admin/class-levels/+server.ts`.

### C. Frontend — Page Server

**`admin/configuration/session-terms/+page.server.ts`**:

```typescript
export const load: PageServerLoad = async (event) => {
    const user = event.locals.user;
    if (!user || !user.roles.includes('admin')) error(403, 'Forbidden');

    // Fetch session terms and terms list in parallel
    const proxy = adminProxy(user);
    const [stResult, termsResult] = await Promise.all([
        proxy('/session-terms'),
        proxy('/terms')
    ]);

    // Process session terms (parse, handle errors)
    // Process terms (parse, handle errors)
    // Return { sessionTerms, terms, ...error fields }
};
```

### D. Frontend — Page Component

**`admin/configuration/session-terms/+page.svelte`**:

**States**:
1. **Loading**: Skeleton table (5 rows)
2. **Error**: `StatusCard(variant="error")` with retry → `goto('/admin/configuration/session-terms')`
3. **Warning** (no active term): `StatusCard(variant="warning")` above the table: "No active session term. Teacher assignments cannot be scoped to a term."
4. **Empty** (no terms at all): `StatusCard(variant="info")` with "No session terms created yet."
5. **Data**: Table with rows, "Create Session Term" button above

**Components used**: `Table`, `Card`, `Button`, `Dialog`, `Badge`, `Input`, `Label`, `StatusCard`, `Skeleton`

**Create dialog state**:
- `session: string` (text input)
- `termId: string` (select dropdown from terms list)
- `active: boolean` (checkbox, default true)
- `createLoading: boolean`, `createError: string`
- On submit → fetch POST → on success, refresh table

**Activate handler**:
- Click "Activate" → confirmation prompt → fetch POST → refresh table
- `activateLoading`: Record<string, boolean> per session term ID

### E. Frontend — Sidebar

**`+layout.svelte`** — Add new sidebar group above Users:

```svelte
<!-- Configuration -->
{#if data.user?.roles.includes('admin')}
    <SidebarGroup>
        <SidebarGroupLabel>Configuration</SidebarGroupLabel>
        <SidebarMenu>
            <SidebarMenuItem>
                <SidebarMenuButton
                    isActive={$page.url.pathname.startsWith('/admin/configuration/session-terms')}
                    {href="/admin/configuration/session-terms"}
                >
                    <Calendar class="h-4 w-4" />
                    <span>Session Terms</span>
                </SidebarMenuButton>
            </SidebarMenuItem>
        </SidebarMenu>
    </SidebarGroup>
{/if}
```

Uses the `Calendar` icon from lucide-svelte (already available in the project via shadcn-svelte).

## Dependencies

- **No new packages to install.** All imports already exist in the project:
  - `lucide-svelte` for Calendar icon (already installed via shadcn-svelte)
  - `$lib/components/ui/*` for all UI primitives
  - `$lib/components/ui/status-card/status-card.svelte` (from HF-03)
  - `$lib/server/golem` for `adminProxy` and `mapErrorCodeToHttpStatus`
- **HF-03 required.** Depends on: `session_term` table schema, `get_active_st()` helper, `StatusCard` component, reactive cache pattern, structured error handling.

## Verification Checklist

1. **Build**: `moon check --target wasm` — 0 errors
2. **Build**: `golem build` — 0 errors
3. **Build**: `pnpm check` — 0 errors
4. **Build**: `pnpm build` — 0 errors
5. **Sidebar**: "Configuration" group appears above "Users" for admin users only
6. **Sidebar**: "Session Terms" link active when on that page
7. **Page**: `/admin/configuration/session-terms` renders table with session, term, active, created_at columns
8. **Empty state**: Shows "No session terms created yet." when table is empty
9. **Warning state**: Shows amber warning when no active session term exists
10. **Create dialog**: Opens with session text input, term dropdown (sorted), active checkbox (checked default)
11. **Create dialog**: Creating with `active: true` deactivates all other session terms
12. **Create dialog**: Table refreshes with new record at top on success
13. **Create dialog**: Error displayed in dialog on failure (e.g., duplicate session+term)
14. **Activate**: Clicking "Activate" on inactive row switches active flag, deactivates others
15. **Activate**: Clicking "Activate" on already-active row does nothing (button hidden for active rows)
16. **Activate**: Active badge updates correctly after activation
17. **Activate**: Confirmation shown before deactivation
18. **Cache**: Admin agent's `"active_session_term"` cache key is removed after create/activate
19. **Teacher impact**: Teacher agents re-fetch active session term on next request (lazy TTL-based invalidation)
20. **Error handling**: All proxy routes use `mapErrorCodeToHttpStatus` — 0 hardcoded 502s
21. **Error handling**: StatusCard used for all error/empty/warning states — 0 raw Alert components
22. **Context docs**: `architecture.md`, `00-build-plan.md`, `progress-tracker.md` updated with HF-04 entry
