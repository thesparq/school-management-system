## Hotfix

**HF-01. SurrealDB Schema v2 — Idiomatic Refactor**
*What it builds:* Replaces the relational-style normalization (FK columns, `class_subjects` junction table) with an idiomatic SurrealDB schema using `TYPE RELATION` graph edges (`has_subject`) and a properly `SCHEMAFULL`-typed `lessons` table. All `lesson_content` records migrate to `lessons`; the old table is preserved for legacy systems. Agent SQL queries, MoonBit types, frontend types, and docs update in lockstep.
*Dependencies:* SurrealDB staging instance with existing `lesson_content` data.

**HF-02. GatewayAgent Removal — Per-User Agent Architecture**
*What it builds:* Eliminates the Ephemeral Gateway Agent. Migrates all four agent types to direct HTTP mounts with path-based worker ID extraction (`#derive.mount("/student/{student_id}")`, etc.). Adds SuperAdminAgent (durable singleton) for bootstrap only — creates first admin's `user_profile` with no init check. AdminAgent becomes per-admin-user (`#derive.mount("/admin/{admin_id}")`). Adds typed RPC invalidation methods (`invalidate_subject_cache`, `invalidate_class_groups`, `invalidate_all`) with `invalidated` flags on all cache structs (TTL + explicit invalidation). Consolidates config into a single `SharedConfig` (auth_key + SurrealDB). Removes `initialize()` from Student/Teacher agents — lazy refresh via `invalidate()` is sufficient. Rewrites SvelteKit proxy layer from `proxyToGateway()` to per-role helpers (`proxyStudent`, `proxyTeacher`, `proxyAdmin`, `proxySuperAdmin`). Simplifies all proxy `+server.ts` routes.
*Dependencies:* Unit 20 (DB-backed architecture), Golem 1.5.3+ with mount path variable support.

**HF-03. User CRUD — Error Handling, Saga Pattern & Config Refactor**
*What it builds:* Complete rewrite of user CRUD layer with structured `AppError` types (replaces vague string errors), saga-pattern compensation for multi-step Authentik+SurrealDB operations (create/edit/delete/activate-deactivate), config split (`SharedConfig` with pre-fixed fields), shared `http_client.mbt` deduplication, group PK resolution moved to backend, `class_level` schema fix (`string` → `record<class_levels>`), `teacher_assignment` schema upgrade (`class_level_id`+`subject_id` → `record<has_subject>` + `session_term`), and unified group names (`"student"`/`"teacher"` singular). Reactive cache redesign: unified `caches : Map[String, CacheItem]` per agent, no negative caching, `get_class_level()` reactive gatekeeper replaces `ensure_initialized()`, parent-child invalidation via backbone keys, 7 structured error codes, all raw strings replaced with `AppError`. Frontend: `golem.ts` rewritten (structured error parsing), `StatusCard` component (info/warning/error), `NOT_INITIALIZED` → info card, assign-modal search ordering fix, session term field.
*Dependencies:* HF-02 (per-user agent architecture, `#derive.endpoint` HTTP mounts).
*Spec:* `docs/specs/hotfix-03-user-crud-error-handling-refactor.md`
*Status:* **Complete.** All user CRUD operations working with saga-pattern compensation. Reactive cache redesign done (unified `caches` map, no negative caching, parent-child invalidation). Schema updated (class_level record link, teacher_assignment with has_subject + session_term). 7 AppError codes replacing all raw strings. golem.ts rewritten for structured error parsing. StatusCard component (info/warning/error) used uniformly across dashboard + my-classes routes. Teacher dashboard + full lesson browsing flow working end-to-end. Group names unified to singular across Authentik, backend, and frontend. Proxy routes use mapErrorCodeToHttpStatus. Teacher agent cache (class_groups + active_session_term) follow reactive pattern. Dead code removed (invalidated field, ensure_initialized, edge cache). Context files synced to current architecture.

**HF-04. Session Term Management (Admin Configuration)**
*What it builds:* Admin Configuration sidebar group with Session Terms management page. Backend: 4 new AdminAgent endpoints (`GET /terms`, `GET /session-terms`, `POST /create-session-term`, `POST /activate-session-term`) with `"active_session_term"` cache invalidation. Frontend: table with session/term/active badge/created date/activate button, create dialog with term dropdown + active checkbox, non-blocking terms fetch with degraded fallback. Global toast notification system: `addToast()` store, 4 variants (success/info/warning/error), progress bar timer with pause-on-hover, fade-in/fade-out animations, integrated in UserTable (6 CRUD ops), session terms page, and dashboard error effects.
*Dependencies:* HF-03 (session_term table schema, `get_active_st()` helper, StatusCard component, reactive cache pattern, structured error handling).
*Spec:* `docs/specs/hotfix-04-session-term-management.md`
*Status:* **Complete.**

## Build Units
**1. Frontend Foundation**  
*What it builds:* SvelteKit project with Tailwind v4 and shadcn‑svelte fully configured. Design tokens from `ui-context.md` applied in `app.css`. A single static page showing “School Management” with a primary‑blue button.  
*Dependencies:* Scaffolded monorepo (`frontend/` exists, `pnpm` ready).

**2. Authentik Authentication**  
*What it builds:* Better Auth integration with Authentik OIDC. `hooks.server.ts` that validates JWTs and populates `locals.user`. A login route that redirects to Authentik. A minimal protected dashboard page (`/dashboard`) displaying “Hello, {user.name}”.  
*Dependencies:* Unit 1 (working SvelteKit app).

**3. Dashboard Layout Shell**  
*What it builds:* Protected layout `(auth)/+layout.svelte` with collapsible sidebar (empty nav list), top navbar (breadcrumb placeholder + profile avatar + logout button), and `<slot/>` content area. Sidebar collapse/expand works. Logout button calls `auth.signOut()`.  
*Dependencies:* Unit 2 (auth so user can log in).

**4. Golem Agent Scaffolding (Code‑First)**  
*What it builds:* ~~Minimal **Admin Agent** (durable) and **Gateway Agent** (ephemeral)~~  
**Status: Built / Superseded by HF-02.** Gateway Agent removed; all agents now expose direct HTTP endpoints via `#derive.endpoint` with path-based worker ID extraction. AdminAgent, StudentAgent, TeacherAgent are the current production agent types.  
*Dependencies:* `agents/` directory exists; Golem CLI authenticated. MoonBit compiler with Golem SDK installed.

**5. SvelteKit → Golem Proxy**  
*What it builds:* ~~A single SvelteKit API route (`/api/ping`) that proxies to the Gateway Agent~~  
**Status: Built / Superseded by HF-02.** SvelteKit proxies directly to per-agent HTTP endpoints via `proxyToAdmin`, `proxyToStudent`, `proxyToTeacher` helpers in `golem.ts`. The proxy gateways the `X-Golem-Auth-Key` header and parses structured `AppError` responses.  
*Dependencies:* Unit 4 (agents deployed), Unit 2 (auth provides `locals.user`).

**6. Admin User List Page**  
*What it builds:* An admin‑only route `/admin/users` that fetches all users from Authentik’s API (server‑side service account) and renders them in a `Table`. Columns: name, email, status (always “pending”). Protected by role check (`locals.user.role === 'admin'`).  
*Dependencies:* Unit 3 (layout shell), Unit 2 (auth).

**7. Admin Agent – Activation Methods**  
*What it builds:* ~~activation methods in agent struct fields~~  
**Status: Built / Superseded by HF-03.** User activation/deactivation now flows through the Admin Agent's Authentik client (`authentik_set_active`). Activation state is stored in Authentik, not in Golem agent state. The `is_user_active` check is an Authentik API call, and `NOT_INITIALIZED` is handled by the reactive cache gatekeeper (`get_class_level()`).  
*Dependencies:* Unit 4 (agents), Unit 5 (proxy pattern).

**8. Admin Portal – Activation Actions**  
*What it builds:* ~~Activate/Deactivate buttons~~  
**Status: Built / Superseded by HF-03.** Activation/deactivation is now handled inline on the user table rows (activate/deactivate buttons in `UserTable.svelte`), using admin proxy → agent → Authentik API. No separate "Manage" panel. User CRUD (create, edit, delete) follows the same pattern.  
*Dependencies:* Unit 7 (activation methods), Unit 6 (user list).

**9. SurrealDB Connection & Normalization**  
*What it builds:* ~~connect and normalize `lesson_content`~~  
**Status: Built / Superseded by HF-01.** The production `schema-v2.surql` replaces `class_subjects` with `has_subject` TYPE RELATION edges, defines `topics` + `lessons` tables with proper record links, and migrates all `lesson_content` data. Agents query `has_subject` edges with dot-traversal (`topic.has_subject.in`, `topic.has_subject.out`, `topic.term`).
*Dependencies:* SurrealDB instance running with existing lesson data. No code dependencies.

**10. Student Agent – Initialization and Subject List**  
*What it builds:* ~~Student Agent with `initialize(classLevel)` and agent durable state~~  
**Status: Built / Superseded by HF-03.** Student Agent now uses a reactive cache pattern — `get_class_level()` is the gatekeeper that lazily fetches from `user_profile` on first data access. Subject list queried from `has_subject` edges via `WHERE in = $class_level`. No `initialize()` method. Webhooks added for cache invalidation.  
*Dependencies:* Unit 8 (activation flow), Unit 9 (normalised SurrealDB).

**11. Architecture Refactor – Activation → Initialization Split**  
*What it builds:* ~~refactoring conflated activation concept~~  
**Status: Built / Superseded by HF-02 + HF-03.** Activation/initialization split is now realized as: (1) Authentik user lifecycle (create/edit/activate/deactivate) via Admin Agent → Authentik API, and (2) SurrealDB profile (`user_profile` table) populated during user creation. The reactive gatekeeper (`get_class_level()`) handles `NOT_INITIALIZED` — no Gateway needed. Admin users page uses role-based tabs (Students, Teachers, Admin) under `/admin/users`.  
*Dependencies:* Unit 10 (Student Agent subjects), Unit 8 (admin portal activation flow).

**12. User CRUD – Create and Delete Users**  
*What it builds:* ~~direct Authentik API calls from frontend~~  
**Status: Built / Superseded by HF-03.** User CRUD now flows through the Admin Agent: `create_user_in_authentik` (saga pattern — create Authentik user → set password → save SurrealDB profile, with compensation on failure), `edit_user_in_authentik`, `delete_user_in_authentik` (soft-delete SurrealDB first → delete Authentik → undo soft-delete on failure). Group PK resolution happens in the backend agent, not the frontend. `UserTable.svelte` handles the form/dialog UI.  
*Dependencies:* Unit 11 (admin users page, UserTable, Authentik API routes).

**13. Routing Refactor – Direct Authentik Redirect**  
*What it builds:* Eliminates the intermediate `/login` page by redirecting unauthenticated users directly to Authentik's OIDC authorization URL. The static landing page at `/` is removed; the dashboard moves from `/dashboard` to `/`. The `/login` route is deleted. The auth guard in `hooks.server.ts` redirects to Authentik's authorize endpoint instead of `/login`. The sidebar/navbar layout moves from `(auth)/+layout.svelte` to the root `+layout.svelte` (conditional on authenticated user). The `(auth)` group still wraps admin and lms routes. Logout callback redirects to Authentik logout directly.  
*Dependencies:* Unit 2 (Authentik OIDC flow, hooks.server.ts auth guard), Unit 3 (dashboard layout shell, sidebar, navbar).

**14. Auth Refresh Fixes – Race Condition, Client-Side 401, and Cookie Cleanup**  
*What it builds:* Fixes multiple issues in the token refresh strategy. (1) Module-level `inflightRefresh` promise in `hooks.server.ts` deduplicates concurrent refresh calls across parallel tab navigations, preventing OIDC token rotation races from logging users out. (2) Client-side 401 interception via `+layout.svelte` `onMount` — patches `window.fetch` to catch 401 responses from protected API calls, sets `oauth_redirect` cookie, and hard-redirects to Authentik login via `window.location.href`. (3) Cookie `maxAge` aligned to real JWT `exp`. (4) Removed unused `accessToken` from `TokenResponse`. (5) Standardised `SECURE` constant to `!dev` (SvelteKit compile-time constant).
*Dependencies:* Unit 13 (routing refactor — dashboard at `/`, auth guard in root layout), Unit 2 (Authentik OIDC flow, hooks.server.ts, refresh endpoint).

**15. Student Dashboard – Subject Cards**  
*What it builds:* Student dashboard at `/` calls `/api/student/subjects` (via SvelteKit proxy to StudentAgent) and renders a grid of subject cards (shadcn‑svelte `Card`). Empty state: `StatusCard(variant="error")`. Loading state: skeleton cards. Subjects queried from `has_subject` graph edges.  
*Dependencies:* Unit 11 (architecture refactor), Unit 10 (Student Agent subjects), Unit 3 (layout).

**16. Student Agent – Term & Lesson Lists**  
*What it builds:* Student Agent methods `getTerms()` and `getLessons(subjectId, termId)`. Both query SurrealDB with dot-traversal via `topic.has_subject` and `topic.term`, filtering by `active = true`. Results cached in the agent's unified `caches` map (TTL 600s). Proxy routes added.  
*Dependencies:* Unit 10 (Student Agent exists), Unit 9 (normalised schema with term active flags).

**17. Student LMS – Term & Lesson Browsing**  
*What it builds:* Frontend: clicking a subject navigates to `/lms/[subject]`, which calls `getTerms` and displays term buttons (Noel Term, Calvary Term, Summer Term). Clicking a term navigates to `/lms/[subject]/[term]`, which calls `getLessons` and shows a numbered lesson list. Active/inactive items are visually distinct. Breadcrumb: `LMS > Basic Science > Noel Term`.  
*Dependencies:* Unit 16 (agent methods), Unit 15 (subject grid).

**18. Student Agent – Lesson Content (Student View)**  
*What it builds:* Student Agent method `getLesson(lessonId)`. Fetches lesson from SurrealDB via `topic.has_subject.out.name`/`topic.term.name` dot-traversal. Cached with TTL; returns student‑visible fields: `objectives`, `content_sections`, `key_points`. Proxy route added.  
*Dependencies:* Unit 15 (Student Agent queries SurrealDB), Unit 9 (SurrealDB normalised).

**19. Lesson Content Page with Side Navigation**  
*What it builds:* Frontend lesson page at `/lms/[subject]/[term]/[lesson]`. Renders content sections, key points, objectives, and assignment section (if any). Side navigation panel (hover to reveal section headings, click to scroll). Breadcrumb updated.  
*Dependencies:* Unit 18 (lesson data available), Unit 17 (browsing flow).

**20. Teacher Agent – Initialization & Dashboard (DB-Backed Architecture)**  
*What it builds:* ~~7-phase DB-backed architecture implementation~~  
**Status: Built / Superseded by HF-02 + HF-03.** Architecture Rules 1-10 are now the production baseline: `user_profile` and `teacher_assignment` (now `record<has_subject>`) tables in SurrealDB. Teacher Agent uses reactive cache (`caches` map, `fetch_class_groups` populates `"class_groups"` with dot-traversal query). No `trigger_initialize` — first request lazily populates cache. Admin assignment UI with search+badge pattern for class-subject pairs. GatewayAgent removed (direct HTTP endpoints). Teacher dashboard renders "My Classes" card grid.  
*Dependencies:* Unit 19 (lesson content page), Unit 9 (SurrealDB connection).

**21. Teacher Agent – Term & Lesson Toggle**  

*What it builds:* Teacher Agent methods to toggle `active` flags on `terms` or `lessons` in SurrealDB, with fire‑and‑forget push to affected Student Agents (discovered via `user_profile` table query by class_level). Student Agent method to update local lesson status cache. Teacher UI shows toggle switches.  
*Dependencies:* Unit 20 (Teacher Agent, reactive `"class_groups"` cache), Unit 9 (SurrealDB terms table with active flag).

**22. Teacher Assignment Creation**  
*What it builds:* Teacher Agent method `configureAssignment(lessonId, selectedQuestionIds, deadline)`. Assignment definitions stored in a new SurrealDB table (not agent durable state — Rule 1). Pushes to students via `StudentAgent.addOrUpdateAssignment`. Teacher's lesson detail page shows **all** lesson fields plus checkboxes for questions, deadline picker, and "Create Assignment" button.  
*Dependencies:* Unit 20 (Teacher Agent, class_groups cache), Unit 17 (Student Agent can receive assignment config).

**23. Student Assignment Display**  
*What it builds:* Student Agent serves the active assignment's questions when loading a lesson (queried from DB-backed assignment table). Frontend lesson page now shows an "Assignment" section with MCQ radio buttons, theoretical text areas, and deadline countdown. No submission yet.  
*Dependencies:* Unit 22 (assignment config in DB), Unit 19 (lesson page).

**24. Student Assignment Submission**  
*What it builds:* Student Agent method `submitAssignment(assignmentId, answers)`. Local deadline check, teacher discovery via `user_profile`/`teacher_assignment` DB tables (not AdminAgent RPC — Rule 7), direct RPC to `TeacherAgent.receiveSubmission`. Teacher Agent inbox stores submission. Frontend: "Submit" button with confirmation.  
*Dependencies:* Unit 22 (assignment visible), Unit 20 (DB-backed teacher_assignment table).

**25. Teacher Grading**  
*What it builds:* Teacher Agent inbox view, grading method `gradeSubmission` that writes grade to a DB-backed grades table (SurrealDB) and pushes to `StudentAgent.receiveGrade`. Student Agent stores grade in its `caches` map (TTL) and displays it on the assignment. Frontend: grading form in teacher's assignment page; grade view in student's lesson.  
*Dependencies:* Unit 24 (submissions exist), Unit 22 (assignment exists).

**26. Admin Class & Teacher Management**  
*What it builds:* Admin portal UI to assign teachers to class-subject pairs (writes to `teacher_assignment` table with `record<has_subject>` FK, invalidates TeacherAgent `"class_groups"` cache) and to move students between classes (updates `user_profile.class_level`, invalidates StudentAgent `"profile"` cache which cascades to all dependent caches).  
*Dependencies:* Unit 20 (DB-backed architecture), Unit 10 (Student Agent), Unit 8 (admin portal).

**27. Polish – Loading, Error, Empty States & Dark Mode**  
*What it builds:* Skeleton loaders on all data‑driven pages. `StatusCard` component (info/warning/error variants) for all error and empty states. Dark mode toggle in the navbar using `mode‑watcher`; all components respond to `dark:` variant. Responsive sidebar collapse on small screens.  
*Dependencies:* All previous units; can be implemented incrementally but finalised as the last pass.