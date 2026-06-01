# Progress Tracker

Update this file after every meaningful implementation change.

## Most Recent Fix — User Init Persists to SurrealDB (Session 2026-06-01)

**Root cause:** `initialize_user()` used `INSERT INTO ... VALUES ... ON DUPLICATE KEY UPDATE` which executes on Surreal Cloud (v2.6.5) but returns a response format where `result` is not an array — `_parse_surreal_result` fails with "result not an array". Additionally, `StudentAgent.initialize()` redundantly wrote to `user_profile` instead of relying on AdminAgent's write.

**Key findings:**
- Surreal Cloud runs **surrealdb-2.6.5** (confirmed via response header `surreal-version: surrealdb-2.6.5+20260324.8afd2ba`)
- `CREATE ... CONTENT { ... } ON DUPLICATE KEY UPDATE` IS invalid syntax in 2.x (parse error)
- `INSERT INTO ... VALUES ... ON DUPLICATE KEY UPDATE` executes but response `result` field is not an array
- Old WASM (revision 0) used in-memory `initialized_users` map — never hit SurrealDB, could not persist across restarts

**Fix applied:**
1. Changed `admin_agent.mbt` SQL: removed `ON DUPLICATE KEY UPDATE`, use simple `INSERT INTO ... VALUES ...` + check error for duplicate key (treat as "already initialized")
2. Changed from `surreal_query_retry` (which expects array result) to raw `surreal_query` (returns body string, no parse expectation)
3. Removed redundant `user_profile` write from `StudentAgent.initialize()` — AdminAgent is single authority
4. Fixed StudentAgent RPC method name: `trigger_initialize` → `initialize` (typo in AdminAgent)

**Verification:**
- `golem agent invoke GatewayAgent() initialize_admin` returns `"OK"`
- `golem agent invoke AdminAgent() get_all_initialized` returns `[("st1", "student"), ("student-test-1", "student"), ("student-with-class", "student")]`
- StudentAgent instance created for `student-with-class` (idempotent, `Idle`, revision 3)
- StudentAgent `student_subjects` returns `Ok([])` (empty — no subjects assigned, but no errors)

## In Progress

- **Unit 20: Teacher Agent – Initialization & Dashboard (DB-Backed Architecture)** — All 7 phases complete.

   **Phases:**
   1. Schema + `surreal_query_retry()` wrapper — **Done**
   2. AdminAgent refactor (remove maps, DB queries) — **Done**
   3. TeacherAgent refactor (`trigger_initialize` from DB) — **Done**
   4. StudentAgent profile → `user_profile` table — **Done**
   5. GatewayAgent endpoints (ID-only payloads) — **Done**
   6. Frontend (filtered combobox, init guard, ID-only save) — **Done**
   7. Build, migrate DB, deploy, verify — **Done**

## Completed

- Unit 19: **Lesson Content Page with Side Navigation** — Enhanced lesson detail page at `/lms/[subjectId]/[termId]/[lessonId]` with sticky side navigation panel: dots column (w-14) at content's right edge uses `sticky top-50vh translateY(-50%)` to stay vertically centered. Hovering dots reveals section headings card to the left (`absolute right-full`). Scroll spy via `use:scrollSpy` action (passive scroll listener with rAF throttling, scanning `[data-section]` children). Mobile floating TOC button with FAB at bottom-right. Placeholder assignment card with dashed border. Key Points/Assignments sections swapped (assignments last). Removed Separator between title and content. Added `pb-16` after last section. `px-6` on all card headers/content. Fixed scroll spy: `position: fixed` broken by `<SidebarInset>` parent transform → replaced with `sticky` flex layout. A11y fixes: `aria-label` on nav/FAB, keyboard handler on backdrop. Open redirect fix: backslash bypass blocked via regex. Week badge guard: `!= null` catches `undefined`. (`pnpm build` zero errors, `pnpm check` 0 errors 3 warnings — same baseline.)

- Unit 17: **Student LMS – Term & Lesson Browsing** — Build `/lms/[subjectId]` (term selection page with compact Card grid, active/inactive distinction, lock icon) and `/lms/[subjectId]/[termId]` (lesson list page with numbered cards, back link). Dynamic breadcrumb in root layout reads from `$page.data.breadcrumbs`. Skeleton loading, empty, and error states on both pages.

  **Fixes applied (retroactive):**
  - **(A)** `db/schema-v2.surql`: replaced `CREATE has_subject CONTENT` with `RELATE` pattern.
  - **(B)** Both page servers use `event.fetch()` to SvelteKit proxy routes instead of `proxyToGateway()`.
  - **(C)** Golem agents rebuilt and redeployed.
  - **(D)** Breadcrumbs include `{ label: 'Subjects', href: '/' }`.
  - **(E)** `get_lessons(subject_id, term_id)` resolves `has_subject` edge via single SQL with nested `IN` subqueries.

  **Session additions:**
  - **(F)** **Root-caused `get_subjects` disappearing bug:** `get_subjects()` passed `self.profile.class_level` (name string, e.g. `"JSS_1"`) as `$class_level_id`, but SQL said `WHERE in = $class_level_id` against `record<class_levels>`. Result: `WHERE in = "JSS_1"` matched nothing. Fixed: nested subquery `WHERE in IN (SELECT VALUE id FROM class_levels WHERE name = $class_level LIMIT 1)`. Cached subjects only worked until cache expiry (TTL=600s), then vanished.
  - **(G)** **Custom IDs migration (`db/fix-ids.surql`):** Converted `class_levels`, `subjects`, `terms` from UUID-based IDs to human-readable record IDs (`class_levels:jss_1`, `subjects:basic_science`, `terms:first`). Rebuilt `class_subjects` and `has_subject` edges (98 each) with new IDs.
  - **(H)** **Lessons migration (1919 records):** Root cause of "0 lessons created" — `LET $hs = NONE; IF $cl_id != NONE { LET $hs = ...; }` fails because `LET` inside `IF` scopes locally and doesn't persist. Fixed by removing `LET $hs = NONE` and `IF` guard, doing the lookup unconditionally. Migrated in 3 batches of ~600 records each.
  - **(I)** **Missing indexes confirmed to exist:** `INFORMATION_SCHEMA.INDEXES` returned `[]` initially (query format issue), but `DEFINE INDEX` commands confirmed indexes already exist. 60-second load was caused by empty table returning no results.
  - **(J)** Agents rebuilt and deployed (`golem deploy --reset -Y`, component revision 5). Admin agent, student agent re-initialized via `golem agent invoke GatewayAgent() initialize_admin`.
  
  **End-to-end verification (via `golem agent invoke`):**
  - `get_subjects` → 6 subjects with correct custom IDs: `subjects:computer_studies`, `subjects:basic_technology`, `subjects:cultural_and_creative_arts`, `subjects:basic_science`, `subjects:agriculture`, `subjects:civic_education`
  - `student_terms` → 3 terms (`terms:first`, `terms:second`, `terms:third`)
  - `student_lessons("subjects:computer_studies", "terms:first")` → 10 lessons with topic titles and week numbers (e.g. "Computer Career Opportunities", week 1; through "Using Search Engines for Research", week 10). All through the Gateway agent, wrapped in `Ok(...)`.

- Unit 18: **Student Agent – Lesson Content (Student View)** — Added `get_lesson(lesson_id)` to Student Agent: fetches lesson from SurrealDB with TTL caching (600s), returns only student-visible fields (`topic_title`, `week`, `subject_name`, `term_name`, `objectives`, `content_sections`, `key_points`). Content arrays serialized as JSON strings via `Json::stringify()`. Added `LessonContent`, `LessonContentCache` structs, `lesson_cache` field. Gateway endpoint at `/gateway/student/lesson` with init check. SvelteKit proxy route at `/api/student/lesson`. Frontend `LessonContent` type. (`golem build`, `pnpm build`, `pnpm check` all pass with zero errors. Deployed revision 9.)

  **Post-deploy fix (part 1):** Lesson list page (Unit 17) linked to `/lms/[subjectId]/[termId]/[lessonId]` but no frontend route existed — caused 404 on click. Created `[lessonId]/+page.server.ts` (fetches via `/api/student/lesson`, returns `LessonContent` + breadcrumbs) and `[lessonId]/+page.svelte` (renders objectives bullet list, content sections as cards, key points bullet list; skeleton loading, error with retry, and empty states).

  **Post-deploy fix (part 2):** The lesson detail page hung (amber loader forever) due to the Gateway endpoint at `/gateway/student/lesson` returning 404. Root cause: the generated `.mbti` interface file was stale — `student_lesson` function was added to `gateway_agent.mbt` but `moon info` was never run to regenerate the `.mbti`. Fixed by running `moon info` before `golem build` to ensure generated stubs match the actual source. The build pipeline (`golem build` → `golem-sdk-tools agents` → `moon build`) regenerates `golem_agents.mbt` etc. but does NOT regenerate `.mbti` files, so `moon info` must be run manually after adding new endpoint functions. Also: Gateway HTTP API is on port **9006** (not 9881 which is the Golem management API), and `golem deploy --reset` deletes all agent state requiring re-initialization.

## Most Recent Fix — Class-Subject Dropdown Empty (Session 2026-05-31)

**Root cause:** Admin Agent was running revision 1 (old code without `get_available_class_subjects`). After `golem deploy --reset`, a new revision 2 agent was created. The SQL and SurrealDB query were correct all along.

**Additional finding:** Fresh Agent instances have a first-call issue where `@json.parse()` in MoonBit WASM fails with "parse response failed" on the first `surreal_query` response (returns `[]` silently). Subsequent calls work correctly. Added a one-time retry in `get_available_class_subjects` — if `parse_result_array` fails, it re-queries SurrealDB and retries the parse.

**Fix applied:**
1. Deployed agents with `golem deploy --reset -Y` (component revision 2, later 4)
2. Added retry for `parse_result_array` in `AdminAgent.get_available_class_subjects` (`admin_agent.mbt:202-212`)
3. Verified gateway returns 98 class-subject pairs: `curl /gateway/admin/class-subjects` → `200 OK` with full data
4. Verdict: **No class-subject data missing** — stale agent instance was the culprit

## Important Notes for Next Session

- Gateway HTTP API port: **9006** (agents.localhost:9006), NOT 9881 (Golem management API)
- After adding new endpoint functions to any agent: run `moon info && moon fmt` before `golem build` to keep `.mbti` files in sync
- `golem deploy --reset` destroys all agent state — re-init is always required
- `LessonContent` content fields are JSON strings (`String?`) — frontend `JSON.parse()`s them
- **Surreal Cloud runs surrealdb-2.6.5** — `INSERT INTO ... VALUES ... ON DUPLICATE KEY UPDATE` works syntax-wise but returns non-array `result`; prefer simple `INSERT` + duplicate-key error handling
- **Curl to Surreal Cloud `/sql` endpoint returns 415 for any SQL body containing keywords like `FROM`, `INSERT`, `DEFINE`** — only `SELECT N`-style queries pass through. The agent's WASM HTTP client does NOT have this issue (receives proper responses). Suspect proxy/WAF layer limitation.
- **`ON DUPLICATE KEY UPDATE` is SurrealDB 1.x terminology** — in 2.x the same syntax exists for `INSERT INTO ... VALUES` but not for `CREATE ... CONTENT`
- **`INSERT INTO ... VALUES ...` (no upsert clause) + check error string for "Duplicate"/"unique"/"already exists"** is the working idempotent init pattern

## Next Steps (Session Bootstrap)

After context reset or new session:
1. Re-run `db/schema-v2.surql` in Surrealist
2. Verify lesson count = 1919, arrays populated
3. Deploy agents: `golem deploy --reset -Y` (from `agents/` dir)
4. Re-init admin: `golem agent invoke 'GatewayAgent()' initialize_admin '"dev-auth-key-change-in-production"' '"725d7fe9-2999-410d-8281-bd3016931a1f"' '"725d7fe9-2999-410d-8281-bd3016931a1f"' '"admin"' 'None'`
5. Re-init student: `golem agent invoke 'GatewayAgent()' initialize_admin '"dev-auth-key-change-in-production"' '"725d7fe9-2999-410d-8281-bd3016931a1f"' '"725d7fe9-2999-410d-8281-bd3016931a1f"' '"student"' 'Some("JSS_3")'`
6. Verify: `golem agent invoke 'StudentAgent("725d7fe9-2999-410d-8281-bd3016931a1f")' get_subjects`
7. Verify lesson detail API: `curl "http://agents.localhost:9006/gateway/student/lesson?user_id=725d7fe9-2999-410d-8281-bd3016931a1f&lesson_id=lessons:s48v5um2fyzq6ad5lplu" -H "X-Golem-Auth-Key: dev-auth-key-change-in-production"`
8. Verify lesson detail navigation: click a lesson card on `/lms/[subjectId]/[termId]/` → loads lesson detail page with objectives, content sections, key points

## Session 2026-05-30 — Optimizations

### Initialization: merged 2 SurrealQL queries into 1 dot-traversal + edge cache pre-population

- **Before:** `initialize()` ran 2 sequential queries: (1) `SELECT VALUE id FROM class_levels WHERE name = $class_level` → parse JSON → extract cl_id, (2) `SELECT out... FROM has_subject WHERE in = <cl_id>` with string interpolation
- **After:** Single query `SELECT id AS edge_id, out.id AS id, out.name AS name, out.code AS code FROM has_subject WHERE in.name = $class_level AND active = true ORDER BY out.name ASC`
- **Eliminates:** 1 SQL round-trip, 1 JSON parse of 19-line nested pattern match, class_level string interpolation into SQL
- **Uses dot-traversal** `in.name = $class_level` on `class_levels(name)` via `idx_cl_name` UNIQUE index (O(1))
- **Side effect:** Pre-populates `edge_cache[subject_id] = EdgeCacheEntry{ edge_id, fetched_at }` for every subject during init
- **Lesson page impact:** `get_lessons()` now always hits the trivial `WHERE class_subject = $hs_id AND term = $term_id` indexed query — **no dot-traversal path ever** after init

### `get_subjects`: subquery → dot-traversal

- **Before:** `WHERE in IN (SELECT VALUE id FROM class_levels WHERE name = $class_level LIMIT 1)`
- **After:** `WHERE in.name = $class_level` — consistent with init query, uses `idx_cl_name`

### `get_terms`: removed unused binding

- Removed `"class_level_id": cl` from bindings dict (SQL never referenced `$class_level_id`)

### Subject code badge on cards

- Added `<span>` badge in `+page.svelte` card headers — small mono font, muted color, rounded, shrink-0 (`bg-primary-100`, `px-1.5 py-0.5`, `font-mono`, `text-xs`)
- Displays when `subject.code` is non-null: e.g. `Mathematics [MTH 101]`

### Subject code badge — wrap below name when card is narrow
- Changed `CardTitle` from `flex` to `flex flex-wrap` so the badge drops to a new line when the card is too narrow
- Added `min-h-[4.5rem]` on `CardHeader` to ensure consistent card heights regardless of badge wrapping

### LMS sidebar nav item + default landing
- Added "LMS" as primary nav item in sidebar (under Navigation group, before Users section), linking to `/`
- Auth callback already redirects to `/`, making LMS the default landing page for all users
- Visible to all roles

### Cleanup: removed obsolete migration scripts
- Deleted `db/fix-ids.surql` — one-time UUID→custom-ID migration; `schema-v2.surql` now creates custom IDs directly
- Deleted `db/normalize-schema.surql` — pre-v2 schema; all functionality superseded by `schema-v2.surql`

### Context files synced with latest architecture
- **`architecture.md`**: Added `idx_cl_name` index to indexes table; updated content field types to `FLEXIBLE TYPE array<object>`; fixed Student Agent struct fields to match real code (`subject_cache`, `terms_cache`, `lessons_cache`, `edge_cache`); flattened monorepo structure (removed `(auth)/` route group); corrected Agent Memory Cache (no background refresh — simple TTL); added dot-traversal and edge-caching patterns to Key Design Patterns table
- **`code-standards.md`**: Removed duplicate content block (L44-100 was an exact copy); flattened directory structure (removed `(auth)/` route group)
- **`project-overview.md`**: Updated Core User Flow to reflect LMS as default landing page with sidebar tab; renamed "Dashboard Access" → "LMS Access"

### Fixes (same session — documentation consistency)
- **`db/schema-v2.surql` term slug generation:** `string::lowercase($t)` → `string::lowercase(string::replace($t, ' ', '_'))` — now consistent with subject slug pattern (lines 68-69)
- **`docs/specs/17-student-lms-term-lesson-browsing.md`:** All 4 `class_subject_id` references → `subject_id` (routes, proxy calls). Clarified `[subjectId]` param is subject record ID (e.g., `subjects:basic_science`), resolved to edge ID via `edge_cache`.
- **`docs/architecture.md`:** Removed 3 stale-while-revalidate references — cache section (line 374: "schedules a background refresh… stale-while-revalidate" → simple TTL with pre-populated edge cache), design patterns table (line 451: "Stale-While-Revalidate Caching" → "Simple TTL Caching"), and content caching subsection (line 372-374). All consistent with Agent Memory Cache description on line 295.
- **`docs/code-standards.md`:** "stale-while-revalidate" → "Cache TTL with synchronous refresh. No background refresh — edge cache pre-populated during init."

### Build
- Golem agents built + deployed (revision 8, `golem deploy --reset -Y`)
- `moon check --target wasm` — 0 errors
- `moon build` — 0 errors
- `pnpm build` — 0 errors

- Unit 15: Student Dashboard — Subject Cards — Replaced generic dashboard for students with a responsive subject card grid. Added 12-skeleton loading state during navigation, "No Subjects Assigned" empty state with info icon, and destructive Alert error state with Retry button. Cards are clickable (linking to `/lms/{id}`, 404 until Unit 17) with hover effects. Admin and teacher users continue to see the existing generic dashboard. Fixed role group check: changed `user.roles.includes('student')` → `'students'` to match Authentik's plural group naming. (`pnpm build` zero errors, `pnpm check` 0 errors 3 warnings — same baseline.)
- Unit 14: Auth Refresh Fixes — Race Condition, Client-Side 401, Cookie Cleanup — Fixed five issues in the token refresh strategy. (1) Module-level `inflightRefresh` promise in `hooks.server.ts` deduplicates concurrent refresh calls across parallel requests, preventing OIDC token rotation races from logging users out. (2) New `apiFetch` wrapper at `frontend/src/lib/client/api.ts` catches client-side 401s, calls `POST /api/auth/refresh` silently, retries on success, redirects to `/?error=session_expired` on failure. (3) Cookie `maxAge` aligned to real JWT `exp` in hooks.server.ts, callback, and refresh route — removed the `Math.max(..., 60)` floor; if `maxAge` is 0, no cookie is written. (4) Removed unused `accessToken` from `TokenResponse` interface and destructured out in both `handleCallback` and `refreshTokens`. (5) Standardised `SECURE` constant from `process.env.NODE_ENV === 'production'` to `!dev` (SvelteKit compile-time constant) in callback and refresh routes. Exported `TokenResponse` and `JwtClaims` types from `authentik.ts` for use in hooks. (`pnpm build` zero errors, `pnpm check` 0 errors 3 benign warnings — same baseline as Unit 13.)

- Unit 13: Routing Refactor — Direct Authentik Redirect — Deleted `/login` route, `/api/auth/login` endpoint, and static landing page. Created root `+layout.server.ts` with direct Authentik OIDC redirect (server-side 302 with PKCE). Elevated sidebar layout from `(auth)/+layout.svelte` to root `+layout.svelte`. Moved dashboard from `/dashboard` to `/` (root `+page.server.ts` + `+page.svelte`). Moved admin routes from `(auth)/admin/` to `admin/`. Deleted `(auth)` route group. Updated callback redirects from `/dashboard` to `/` and from `/login?...` to `/?error=...`. Updated `getEndSessionUrl` post_logout_redirect_uri from `/login` to `/`. (`pnpm build` zero errors.)

- Unit 12: User CRUD — Create and Delete Users — Added `createUser` and `deleteUser` functions to `authentik.ts`. Created `POST /api/admin/users/+server.ts` (create user in Authentik with auto-assign to role group) and `DELETE /api/admin/users/[pk]/+server.ts` (delete user from Authentik). Updated `UserTable.svelte`: "Create {Role}" button above table with `Dialog` form (username, name, email, password, activate toggle), `handleCreateUser` pushes result to users array; "Delete User" button in expanded Manage panel with `AlertDialog` confirmation, `handleDeleteUser` removes from users and initMap. Added `groupPk` bindable prop, passed from all three role pages (`students`, `teachers`, `admin-role`). Installed shadcn-svelte dialog, alert-dialog, label components. Fixed password not set on create (added `resetPassword` call after `createUser`). Replaced all `error()` calls in API routes with consistent JSON `{ error: { code, message } }` responses so SvelteKit HttpError format doesn't mask real error messages. Fixed `!targetPk` validation to use `isNaN(targetPk) || targetPk < 1` throughout. Split shared `actionStates` into `initStates`, `authStates`, `pwResetStates` so loading indicators are per-action-type (Initialize/Activate/ResetPassword no longer show each other's spinner). Fixed class-level `<select>` placeholder: initialized `selectedClassLevels[pk] = ''` on expand, added `disabled` to placeholder `<option>` so it can't be re-selected. (`pnpm build` zero errors, `pnpm check` zero errors.)

- Unit 11: Architecture Refactor — Activation → Initialization Split — Refactored the conflated "activation" concept: Admin Agent renamed `activate_user`→`initialize_user`, `is_user_active`→`is_user_initialized` (returns bool), `get_all_activations`→`get_all_initialized`, `deactivate_user` removed. `ActivationStatus` enum and `UserActivation` struct replaced by `UserInitialization` (no status field). Gateway Agent: `NOT_ACTIVATED`→`NOT_INITIALIZED`, renamed `check_activation`→`check_initialization`, `activate_admin`→`initialize_admin`, removed `deactivate_admin`, `list_activations`→`list_initializations` (returns JSON array). SvelteKit: `golem.ts` updated with `NOT_INITIALIZED`, `parseActivations` removed. `authentik.ts` extended with `is_active` field, 5 new functions (`activateUser`, `deactivateUser`, `resetPassword`, `addUserToGroup`, `removeUserFromGroup`). Created 5 new API routes (activate-authentik, deactivate-authentik, reset-password, add-group, remove-group). Renamed `activate`→`initialize`, deleted `deactivate`, renamed `activations`→`initializations`. Updated `auth/status` and dashboard. Restructured sidebar: "Users" section with Students, Teachers, Admin sub-pages. Created `UserTable.svelte` with two status columns, Initialize/Activate/Deactivate/ResetPassword/GroupManagement actions, class-level dropdown for students. Three role-based sub-pages (`/admin/users/students`, `/admin/users/teachers`, `/admin/users/admin-role`). Context files updated: `project-overview.md`, `architecture.md`, `code-standards.md`, `00-build-plan.md` (Unit 11 inserted, renumbered 12-24). Agent stubs regenerated. (`moon check --target wasm` zero errors, `pnpm check` zero errors.)
- Unit 10: Student Agent — Initialization and Subject List — Per-student durable `StudentAgent` with `student_id` constructor param, `initialize(class_level)` and `get_subjects()` methods querying SurrealDB. `SubjectInfo` and `StudentProfile` types with `#derive.golem_schema`. Admin Agent updated: gains `@config.Config[SurrealConfig]`, `get_class_levels()`, and fire-and-forgets `StudentAgentClient::scoped(user_id, fn(c) { c.trigger_initialize(cl) })` in `activate_user`. Gateway Agent: `/gateway/student/subjects`, `/gateway/admin/class-levels`, updated `/gateway/db-test?user_id=`, updated `/gateway/admin/activate` with `class_level` param. SvelteKit: `/api/student/subjects`, `/api/admin/class-levels` proxy routes; updated `POST /api/admin/users/[uuid]/activate` accepts `class_level` body; admin users page adds class-level dropdown fetched from `/api/admin/class-levels`. Uses `moonbitlang/core/json` with `@json.parse` + pattern matching for SurrealDB response parsing. (`golem build`, `pnpm build`, `pnpm check` all pass with zero errors.)
- Unit 9: SurrealDB Connection & Schema Normalization — `db/normalize-schema.surql` migration (7 steps). Shared `SurrealConfig` (5 `@config.Secret[String]` fields: `host`, `ns`, `database`, `username`, `password`) used by StudentAgent/TeacherAgent via `@config.Config[SurrealConfig]`. `surreal_client.mbt` with `surreal_query(config, sql)` using WASI HTTP + Basic Auth (`@base64.encode`), `surreal-ns`/`surreal-db` headers, `/sql` path, `Accept: application/json` header, `match`-based error handling. Gateway Agent `/gateway/db-test` calls `StudentAgentClient::scoped(fn(student) { student.test_db() })` via typed RPC. SvelteKit `/api/db-test` proxy route. Env var templates in `golem.yaml` secretDefaults. Verified live: `"OK: [{\"result\":[1],\"status\":\"OK\",\"time\":\"92.053µs\"}]"` via `curl /gateway/db-test`. (`golem build`, `pnpm build`, `pnpm check` all pass with zero errors.)
- Unit 1: Frontend Foundation — SvelteKit configured with Tailwind v4, shadcn-svelte Button, design tokens from ui-context.md applied in `src/app.css`, Inter font loaded. Static landing page at `/` with branded heading and primary-blue button.
- Unit 6: Admin User List Page — `/admin/users` route with role-based guard (`locals.user.roles.includes('admin')`). `authentik.ts` extended with `fetchAllUsers()` (Bearer token auth, paginated, filters to internal users in admin/students/teachers groups). shadcn-svelte Table with Name, Email, "Pending" Status, empty Actions columns. Four states: loading skeletons, error Alert + Retry, empty guidance, data table. Sidebar conditional "Admin > Users" nav item using `child` snippet pattern. (`pnpm build` and `svelte-check` pass with zero errors.)
- Unit 8: Admin Portal — Activation Actions — Admin Agent adds `deactivate_user(user_id)` and `get_all_activations()`. Gateway Agent adds 4 new endpoints: `check-activation`, `admin/activate`, `admin/deactivate`, `admin/activations`. SvelteKit gains 4 new API routes: `/api/auth/status`, `/api/admin/activations`, `/api/admin/users/[pk]/activate`, `/api/admin/users/[pk]/deactivate`. Dashboard shows "Account Not Activated" error for inactive users (server load check via `/api/auth/status`). Admin users page fetches real activation statuses, shows dynamic Badge (Active/Deactivated/Pending), and Activate/Deactivate buttons with optimistic updates and rollback on error. `proxyToGateway` extended with optional `extraParams`. `parseActivations` helper added. (`golem build`, `pnpm build`, `pnpm check` all pass with zero errors.)
- Unit 7: Admin Agent Activation Methods — Admin Agent gains `activate_user(user_id, role, class_level?) -> Result[String, String]` and `is_user_active(user_id) -> ActivationStatus` using `#derive.golem_schema` types and Golem durable memory (agent struct fields). `ActivationStatus` enum: `NotFound`, `Active`, `Suspended`, `Deactivated`. Gateway Agent `/gateway/ping` gains `user_id` query param; checks activation before proxying, returns `"NOT_ACTIVATED"` for inactive users. `proxyToGateway` in `golem.ts` handles `NOT_ACTIVATED` string, returns structured `403` error. Context files updated: storage model changed from SQLite to agent struct fields. (`moon build --target wasm`, `pnpm build`, `pnpm check` all pass with zero errors.)
- Unit 2: Authentik Authentication — Stateless OIDC with Authentik as sole signing authority. Removed Better Auth, Drizzle ORM, SQLite, and all demo routes. Built OIDC helper module (`src/lib/server/authentik.ts`) with PKCE, JWKS verification, silent token refresh, and RP-Initiated Logout. Created `/login`, `/api/auth/login`, `/api/auth/callback`, `/api/auth/logout`, `/api/auth/refresh`, and `/dashboard` routes. CSRF protection on logout. (`pnpm build` and `svelte-check` pass with zero errors.)
- Unit 3: Dashboard Layout Shell — Protected `(auth)` route group with collapsible shadcn-svelte Sidebar, top navbar with SidebarTrigger + breadcrumb placeholder + avatar dropdown with logout, and content area. Dashboard page migrated into the group. Sidebar state persisted in localStorage. (`pnpm build` and `svelte-check` pass with zero errors.)
- Unit 4: Golem Agent Scaffolding — Consolidated from 4 separate WASM components into a single `app:agents` component (`app-agents/`). All four agent types defined: AdminAgent (durable singleton, RPC-only, `ping` → `"admin online"`), GatewayAgent (ephemeral, mount `/gateway`, `ping` → calls `AdminAgent.ping` via typed `AdminAgentClient::scoped(...)`), StudentAgent (durable, placeholder), TeacherAgent (durable, placeholder). Demo agents deleted. `curl /gateway/ping` returns `"admin online"`; `/admin/ping` returns 404.
- Unit 5: SvelteKit → Golem Proxy — Created `/api/ping` proxy route in SvelteKit (`src/routes/api/ping/+server.ts`). Shared proxy helper `src/lib/server/golem.ts` with `proxyToGateway(path, userId)` and `X-Golem-Auth-Key` auth. Gateway Agent updated with `#derive.config` + `@config.Secret[String]` for auth key verification (rejects unauthorized requests before AdminAgent RPC). `secretDefaults` in `golem.yaml` for local dev. Dashboard "Connection Status" card with "Test Connection" button. Extension method `AgentError::to_string` added for generated code compatibility.



## Recent Specs

- `docs/specs/15-student-dashboard-subject-cards.md` — Student dashboard subject cards with clickable Card grid, Skeleton loading, empty and error states.
- `docs/specs/14-auth-refresh-fixes.md` — Fix race condition, client-side 401, cookie maxAge, accessToken removal, SECURE standardisation.
- `docs/specs/13-routing-refactor-direct-authentik-redirect.md` — Eliminate `/login` page, redirect unauthenticated users directly to Authentik, move dashboard to `/`, remove `(auth)` route group.
- `docs/specs/12-user-crud-create-delete.md` — Admin create/delete user UI and API routes via Authentik Admin API. Create dialog with form fields, delete AlertDialog in Manage panel, auto-group-assignment by page role.
- `docs/specs/11-architecture-refactor-activation-split.md` — Architecture refactor: split activation into Golem-side initialization and Authentik-side activation. Admin Agent renamed methods, gateway returns NOT_INITIALIZED, sidebar Users section with role-based sub-pages.
- `docs/specs/10-student-agent-initialization.md` — Per-student durable Student Agent with `initialize` and `get_subjects`, SurrealDB subject querying, class-level dropdown in admin activation UI.
- `docs/specs/03-dashboard-layout-shell.md` — Protected auth layout with collapsible shadcn-svelte Sidebar, navbar with breadcrumb + avatar dropdown, migrated dashboard page.
- `docs/specs/05-sveltekit-golem-proxy.md` — SvelteKit → Golem proxy with shared auth secret via Golem secrets.
- `docs/specs/06-admin-user-list-page.md` — Admin user list page with Authentik API via Bearer token, shadcn-svelte Table, role-based sidebar nav, group-based filtering.
- `docs/specs/07-admin-agent-activation-methods.md` — Admin Agent `activateUser` and `isUserActive` methods, Gateway Agent activation gate, proxy NOT_ACTIVATED handling.
- `docs/specs/08-admin-activation-actions.md` — Admin portal activate/deactivate buttons, dynamic status badges, optimistic updates, dashboard not-activated error page.

## Open Questions

- None.

## Architecture Decisions

- Dashboard layout uses shadcn-svelte Sidebar compound component (collapsible sidebar using Sheet on mobile). Sidebar open/close state persisted via localStorage.
- The `(auth)` route group pattern used for all protected routes — shared layout with auth guard ensures consistent authentication check and user data availability.
- `DropdownMenuTrigger` uses bits-ui's snippet-based child composition (`{#snippet child({ props })}`) rather than the deprecated `asChild` prop.
- All agents live in a single WASM component (`app:agents`, dir `app-agents/`). This enables typed intra-component RPC using `<AgentName>Client::scoped(...)` instead of raw `@rpc.AgentClient`. The `golem-sdk-tools agents` build step generates typed client stubs for all `#derive.agent` structs within the component.
- GatewayAgent uses `AdminAgentClient::scoped(fn(admin) { admin.ping() })` — the `scoped` pattern automatically handles client resource cleanup via `defer`, eliminating manual `drop()` calls.
- Empty structs in MoonBit use `StructName::{}` syntax — e.g., `fn AdminAgent::new() -> AdminAgent { AdminAgent::{} }`.
- Gateway Agent auth: `#derive.config` struct with `@config.Secret[String]` for the auth key, set via `secretDefaults` in `golem.yaml` (local) or `golem secret create` (production). The `#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")` annotation binds the HTTP header to a method parameter. The agent verifies the header against the resolved secret before any RPC.
- `golem-sdk-tools` 0.5.2 generates `e.to_string()` on `AgentError` types that lack `to_string()` — fixed by adding an extension method in `gateway_agent.mbt`.
- `proxyToGateway()` helper in `src/lib/server/golem.ts` is the single entry point for all SvelteKit-to-Golem proxy calls. Every future proxy route should use it.
- Custom types used in agent method signatures use `#derive.golem_schema` (dot syntax, not parentheses). The `golem-sdk-tools agents` command generates `HasElementSchema`, `FromExtractor`, `FromElementValue`, and `ToElementValue` trait implementations for these types automatically.
- `Result[Unit, String]` cannot be used as an RPC return type because `Unit` does not implement Golem schema traits and the orphan rule prevents adding them from a foreign package. Use `Result[String, String]` instead, with `Ok("ok")` as success value.
- **Authentik admin API uses Bearer token (not OAuth2 Client Credentials):** The service account token is generated in Authentik and sent as `Authorization: Bearer <token>`. No username needed, no token caching/refresh logic — the token is self-contained.
- **Admin user list filters by group membership:** Users must belong to at least one of `admin`, `students`, or `teachers` groups (by name) to appear in the admin table. Group PKs are fetched from `GET /api/v3/core/groups/` and cross-referenced against each user's `groups` array.
- **`SidebarMenuButton` uses `child` snippet pattern instead of `asChild`:** The shadcn-svelte component accepts `{#snippet child({ props })}` for wrapping custom elements like `<a>`, mirroring the `DropdownMenuTrigger` pattern.
- **SurrealDB uses HTTP Basic Auth with shared `SurrealConfig` (5 secrets):** Auth uses `username:password` base64-encoded via `@base64.encode()` from `moonbitlang/core/encoding/base64`. Namespace and database are sent as `surreal-ns` / `surreal-db` headers (SurrealDB SDK convention), not `NS` / `DB`. A single `SurrealConfig` struct (all 5 fields as `@config.Secret[String]`) is shared by all agents via `@config.Config[SurrealConfig]`, eliminating per-agent config duplication (`StudentConfig`, `TeacherConfig` removed). The `surreal_query(config, sql)` function takes the injected config directly — caller never resolves secrets manually. All WASI HTTP operations use `match`-based error handling, never `.unwrap()` on network calls. Gateway Agent never holds SurrealDB credentials — it routes via typed RPC to `StudentAgent.test_db()`. Env vars are substituted via `{{ VAR }}` template syntax in `secretDefaults`.
- **Use `golem deploy --reset` for development updates:** When the Golem server reports "UP-TO-DATE" despite code changes, `golem deploy --reset` forces the new WASM binary through. This is needed because the deploy's hash comparison may consider staging vs. deployed as identical during rapid iteration cycles.
- **Golem HTTP gateway wraps String returns in JSON quotes:** All `String` return values from agent methods are serialized as JSON strings (e.g., `"OK"` not `OK`). The `proxyToGateway` helper must `JSON.parse` the raw response before comparing against known strings like `"unauthorized"`, `"NOT_INITIALIZED"`, etc.
- **Authentik JWT `sub` must match API `uuid`:** User initialization and activation are keyed by UUID. The JWT `sub` claim (used as `event.locals.user.id`) must match the Authentik API `user.uuid`. Fix: set Authentik OIDC provider `sub` expression to `user.uuid`.
- **Admin Agent tracks initialization only (no Golem-level activation):** `AdminAgent.initialized_users` stores user metadata (role, class_level, initialized_at). No status enum. `is_user_initialized` returns bool. `deactivate_user` removed — deactivation is handled by Authentik API calls from SvelteKit.
- **Gateway returns `NOT_INITIALIZED` for uninitialized users:** Replaces the old `NOT_ACTIVATED` error. User-facing endpoints check `AdminAgent.is_user_initialized` before proxying. Admin endpoints (`/gateway/admin/*`) skip init check and use SvelteKit role guard.
- **Admin user pages split by role with sidebar section:** Three sub-pages under `/admin/users/students`, `/admin/users/teachers`, `/admin/users/admin-role` grouped under a "Users" sidebar header. Each filters Authentik users by group membership.
- **Init status and Authentik status are separate columns:** Admin table shows "Authentik Status" (Active/Inactive from `is_active`) and "Init Status" (Initialized/Pending from Admin Agent). Activate/Deactivate buttons call Authentik API directly; Initialize button calls Admin Agent.
- **User creation is Authentik-only with auto-group assignment:** `POST /api/admin/users` creates the user in Authentik via `POST /api/v3/core/users/` and auto-assigns them to the page's role group via `group_pk` param. No Golem initialization happens during create — that's a separate action.
- **User deletion is Authentik-only:** `DELETE /api/admin/users/[uuid]` removes the user from Authentik. If the user was initialized in Golem, the initMap entry is removed from the UI, but no Golem-side deinitialization occurs. The durable agent remains orphaned but inaccessible.
- **Create dialog and delete dialog are shadcn-svelte patterns:** Create uses a `Dialog` with controlled `open` state and a `<form>` with `onsubmit`. Delete uses `AlertDialog` with the `child` snippet pattern for the trigger button (bits-ui v2, no `asChild` prop). The create dialog is rendered at the component level; the delete dialog is inside the `{#each}` loop per row.

- `src/app.css` is the canonical CSS entry point. shadcn-svelte's generated `layout.css` was deleted and its contents merged into `app.css`.
- Better Auth was removed in favor of stateless OIDC with Authentik as the sole signing authority. JWT validation uses `jose` with Authentik's JWKS endpoint. No server-side sessions, no database in the frontend layer.
- Drizzle ORM and SQLite were removed entirely from the frontend; SvelteKit no longer has any database access.

## Session Notes

- Unit 17 completed (final fixes). Branch: N/A (no branch — direct fixes to main after earlier merge). Key work: (F) Root-caused `get_subjects` bug — name string vs record ID. (G) Created `db/fix-ids.surql` — converted lookup tables to custom human-readable record IDs (`class_levels:jss_1`, `subjects:basic_science`, `terms:first`). Rebuilt edges (98 class_subjects + 98 has_subject). (H) Fixed lessons migration (`LET` inside `IF` doesn't persist in SurrealDB). Migrated all 1919 lesson_content records to `lessons` table in 3 batches. (I) Confirmed indexes already exist. (J) Agents rebuilt (revision 5), deployed, test user re-initialized. Verified end-to-end: subjects return correct custom IDs, terms return 3 terms, lessons return 10 per subject-term combo. All queries < 2ms. Key discovery: `INFORMATION_SCHEMA.INDEXES` returning `[]` was a query format issue, not missing indexes. `pnpm build` and `pnpm check` both pass (0 errors, 3 pre-existing warnings). `golem deploy --reset -Y` destroys agent state — re-initialization required after every deploy with `--reset`. Branch: `feat/unit-16-hotfix-01-schema-v2`. PR #17 → main. Merged Unit 16 student term/lesson lists with Hotfix 01 SurrealDB schema v2 refactor. Key schema changes: `class_subjects` → `has_subject TYPE RELATION`, `lesson_content` → `lessons` SCHEMAFULL, `week_number` → `week`, global terms. Migration script `db/schema-v2.surql` (idempotent with existence checks). Student agent SQL rewritten for graph traversal. `golem build`, `pnpm build`, `svelte-check` all pass with zero errors. (`pp.diff` reviewed: LessonInfo struct field `week` → `week_number` to match generated Golem schema; `schema-v2.surql` migration steps wrapped in `IF $existing == NONE` guards for true idempotency.)
- Unit 13 completed. Branch: `feat/13-routing-refactor-direct-authentik-redirect`. Deleted static landing page, `/login` route, and `/api/auth/login` endpoint. Created root `+layout.server.ts` with direct Authentik OIDC redirect using `import { dev }` pattern. Elevated sidebar layout to root `+layout.svelte`. Dashboard moved to root `+page.svelte`. Admin routes moved from `(auth)/admin/` to `admin/`. Deleted `(auth)` route group. Updated callback/logout redirect targets. Logout fallback URL changed to `/`. Cleaned up: removed unused `deleteTarget`, added rollback to `handleAddGroup`, fixed a11y on remove-group button, added `res.ok` check to `loadClassLevels`, optimized group lookups (local `find` instead of API call), fixed `state_referenced_locally` warnings in role pages via prop destructuring. (`pnpm build` zero errors, `svelte-check` 0 errors 3 benign warnings.)
- Unit 12 completed. Branch: `feat/12-user-crud-create-delete`. Added `createUser` and `deleteUser` to `authentik.ts`. Created `POST /api/admin/users` and `DELETE /api/admin/users/[pk]` API routes. Updated `UserTable.svelte` with Create dialog (username, name, email, password, activate) and Delete AlertDialog in Manage panel. Passed `groupPk` from all three role pages. Installed shadcn-svelte dialog, alert-dialog, label. Fixed password not set on create (added `resetPassword` after `createUser`). Fixed password auto-generation and show/hide toggle. Renamed route dir `[uuid]` → `[pk]`. Replaced all `error()` calls in API routes with consistent JSON error responses. Fixed `!targetPk` validation to use `isNaN(targetPk) || targetPk < 1`. Split shared `actionStates` into per-action-type maps (`initStates`, `authStates`, `pwResetStates`) so loading indicators don't leak between buttons. Fixed class-level `<select>` placeholder (initialize on expand, `disabled` option). (`pnpm build` zero errors, `pnpm check` zero errors.)

- Unit 11 implemented. Branch: `feat/11-architecture-refactor-activation-split`. Refactored Admin/Gateway agents, removed ActivationStatus enum/deactivate_user, renamed activate→initialize. Regenerated golem stubs via `golem-sdk-tools`. Updated `golem.ts` (NOT_INITIALIZED, removed parseActivations). Extended `authentik.ts` (is_active, 5 functions). Created 5 new Authentik API routes. Renamed activate→initialize, deleted deactivate, renamed activations→initializations. Updated `/api/auth/status` and dashboard. Restructured sidebar with Users section (Students/Teachers/Admin sub-items). Created `UserTable.svelte` component with two status columns and full action set. Three role-based sub-pages. Updated all context files. (`moon check --target wasm` zero errors, `pnpm check` zero errors.) Fixed MoonBit syntax: tuple destructuring in closures uses `for` loop, `String::replace` uses labeled args `old=`, `new=`. Golem build has pre-existing `moon.mod` vs `moon.mod.json` issue with local deps — not a regression.
- Unit 10 implemented. Branch: `feat/10-student-agent-initialization`. Per-student `StudentAgent` with `student_id` identity. `SubjectInfo`/`StudentProfile` types with `#derive.golem_schema`. `initialize(class_level)` resolves class_level to SurrealDB record ID, queries `class_subjects`, parses JSON with `@json.parse` and pattern matching. `get_subjects()` returns JSON array string. Admin Agent gains `@config.Config[SurrealConfig]`, `get_class_levels()`, and fires `StudentAgentClient::scoped(user_id, ...)` in `activate_user`. Gateway Agent: 2 new endpoints + 2 updated (`db_test` and `activate_admin`). SvelteKit: 2 new proxy routes, activate endpoint extended, admin users page gets class-level `<select>` fetched from `/api/admin/class-levels`. MoonBit `String.replace` uses labeled args (`old=`, `new=`). Mutable struct fields use `mut` keyword. Generated clients correctly updated with `StudentAgentClient::scoped(student_id, ...)`. (`golem build`, `pnpm build`, `pnpm check` all pass.)
- Unit 9 refactored: Switched from Bearer token to HTTP Basic Auth via `@base64.encode()`. Shared `SurrealConfig` (5 secrets: `host`, `ns`, `database`, `username`, `password`) replaces duplicate `StudentConfig`/`TeacherConfig`. `surreal_query(config, sql)` takes injected config directly — caller never resolves secrets. `surreal-ns`/`surreal-db` headers, `/sql` path. All WASI HTTP operations use `match` error handling, no `.unwrap()` on network calls. Gateway Agent `/gateway/db-test` calls `StudentAgentClient::scoped(fn(student) { student.test_db() })` via RPC. `GatewayConfig` has only `auth_key`. (`golem build`, `pnpm build`, `pnpm check` all pass.)
- Unit 9 implemented. Branch: `feat/09-surreal-connection-normalization`. `db/normalize-schema.surql` creates subjects, class_levels, terms, class_subjects tables; adds FK fields to lesson_content; populates from existing data. `surreal_client.mbt` with `surreal_query(config, sql)` using WASI HTTP + Basic Auth. Shared `SurrealConfig` (5 secrets) eliminates per-agent configs. Gateway `/gateway/db-test` via StudentAgent RPC. SvelteKit `/api/db-test` proxy route. `.env` with env var templates. (`golem build`, `pnpm build`, `pnpm check` all pass.)
- Unit 3 implemented. Branch: `feat/03-dashboard-layout-shell`. All shadcn-svelte components (sidebar, avatar, dropdown-menu, breadcrumb, separator, sheet, tooltip, input, skeleton, card) installed. Old `src/routes/dashboard/` deleted.
- Unit 6 implemented. Branch: `feat/06-admin-user-list-page`. shadcn-svelte table, badge, alert installed. Authentik auth refactored from OAuth2 Client Credentials → Bearer token, then Basic auth → Bearer token. Group membership filter added (admin/students/teachers). Spec updated to reflect all changes.
- Unit 8 implemented. Branch: `feat/08-admin-activation-actions`. Admin Agent gains `deactivate_user` and `get_all_activations`. Gateway Agent gains 4 endpoints (admin activation check removed to avoid bootstrapping). 4 new SvelteKit API routes built. Dashboard not-activated state added. Admin page shows dynamic status badges and Activate/Deactivate buttons with optimistic updates. `proxyToGateway` extended with `extraParams` and `JSON.parse` for Golem's quoted-string responses. `parseActivations` helper added. Activation keyed by Authentik UUID (requires JWT `sub` = `user.uuid` in OIDC provider). (`golem build`, `pnpm build`, `pnpm check` all pass.)
