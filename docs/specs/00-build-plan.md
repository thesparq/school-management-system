## Hotfix

**HF-01. SurrealDB Schema v2 — Idiomatic Refactor**
*What it builds:* Replaces the relational-style normalization (FK columns, `class_subjects` junction table) with an idiomatic SurrealDB schema using `TYPE RELATION` graph edges (`has_subject`) and a properly `SCHEMAFULL`-typed `lessons` table. All `lesson_content` records migrate to `lessons`; the old table is preserved for legacy systems. Agent SQL queries, MoonBit types, frontend types, and docs update in lockstep.
*Dependencies:* SurrealDB staging instance with existing `lesson_content` data.

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
*What it builds:* Minimal **Admin Agent** (durable) and **Gateway Agent** (ephemeral) using Golem’s current code‑first pattern. Each agent is a struct with annotations (cors, routing, etc.). The Admin Agent exposes a `ping` method returning `"admin online"`. The Gateway Agent exposes an endpoint that calls `AdminAgent.ping` via RPC and returns the result. Deployed to Golem Cloud and tested via `curl`.  
*Dependencies:* `agents/` directory exists; Golem CLI authenticated. MoonBit compiler with Golem SDK installed.

**5. SvelteKit → Golem Proxy**  
*What it builds:* A single SvelteKit API route (`/api/ping`) that proxies to the Gateway Agent’s ping endpoint. The route reads `user_id` from `locals.user` and passes it. A button on the dashboard calls this route and shows the result.  
*Dependencies:* Unit 4 (agents deployed), Unit 2 (auth provides `locals.user`).

**6. Admin User List Page**  
*What it builds:* An admin‑only route `/admin/users` that fetches all users from Authentik’s API (server‑side service account) and renders them in a `Table`. Columns: name, email, status (always “pending”). Protected by role check (`locals.user.role === 'admin'`).  
*Dependencies:* Unit 3 (layout shell), Unit 2 (auth).

**7. Admin Agent – Activation Methods**  
*What it builds:* Extends Admin Agent with `activateUser(userId, role, class?)` (stores in agent struct fields, status `active`) and `isUserActive(userId)`. Gateway Agent extended: every incoming request now calls `AdminAgent.isUserActive`; if false, returns `403 { code: "NOT_ACTIVATED" }`. Testable via ping proxy for inactive vs active users.  
*Dependencies:* Unit 4 (agents), Unit 5 (proxy pattern).

**8. Admin Portal – Activation Actions**  
*What it builds:* Activate/Deactivate buttons on the admin user list page. Clicking “Activate” calls a new SvelteKit API route that proxies to `AdminAgent.activateUser`. The table row updates optimistically. An inactive user logging in sees a clear “Account not activated” error page.  
*Dependencies:* Unit 7 (activation methods), Unit 6 (user list).

**9. SurrealDB Connection & Normalization**  
*What it builds:* Connect the production SurrealDB instance (already containing AI‑generated lesson records) to the project. Verify connectivity and run a one‑time normalisation migration:
- Extract `subject`, `class_level`, `term`, `week` into separate tables (`subjects`, `class_levels`, `terms`) with `active` fields where needed.
- Update `lesson_content` records to reference these new tables via foreign IDs.
- Create a `class_subjects` mapping table to define which subjects belong to a class.
- Ensure all agents can query the normalised schema via HTTP.
*Dependencies:* SurrealDB instance running with existing lesson data. No code dependencies.

**10. Student Agent – Initialization and Subject List**  
*What it builds:* Student Agent with `initialize(classLevel)` – it queries SurrealDB for subjects assigned to that class (from `class_subjects`) and stores them in its durable state. Exposes `getSubjects()`. Admin Agent: during `activateUser` for a student, calls `StudentAgent.initialize`. A proxy route `/api/student/subjects` added.  
*Dependencies:* Unit 8 (activation flow), Unit 9 (normalised SurrealDB).

**11. Architecture Refactor – Activation → Initialization Split**  
*What it builds:* Refactors the conflated "activation" concept into two independent concerns: initialization (Golem-side agent creation) and activation (Authentik-side login permission). Admin Agent renamed from `activated_users`/`UserActivation` to `initialized_users`/`UserInitialization`. Gateway returns `NOT_INITIALIZED`. Deactivation removed from Golem — handled by SvelteKit via Authentik Admin API. Admin users page restructured into role-based tabs (Students, Teachers, Admin) under a "Users" sidebar section. Adds 5 new Authentik API routes (activate, deactivate, reset password, add/remove group) and a reusable UserTable component with two status columns.  
*Dependencies:* Unit 10 (Student Agent subjects), Unit 8 (admin portal activation flow).

**12. User CRUD – Create and Delete Users**  
*What it builds:* Admin UI to create new users (username, email, password, role/group assignment) and delete existing users directly from the admin users page. Both operations call the Authentik Admin API (`POST /api/v3/core/users/` for create, `DELETE /api/v3/core/users/{pk}/` for delete). New user creation includes optional group assignment and `is_active` flag. Deletion removes the user from Authentik entirely. Server-side API routes and frontend form/dialog UI added to the expandable row pattern in UserTable.  
*Dependencies:* Unit 11 (admin users page, UserTable, Authentik API routes).

**13. Routing Refactor – Direct Authentik Redirect**  
*What it builds:* Eliminates the intermediate `/login` page by redirecting unauthenticated users directly to Authentik's OIDC authorization URL. The static landing page at `/` is removed; the dashboard moves from `/dashboard` to `/`. The `/login` route is deleted. The auth guard in `hooks.server.ts` redirects to Authentik's authorize endpoint instead of `/login`. The sidebar/navbar layout moves from `(auth)/+layout.svelte` to the root `+layout.svelte` (conditional on authenticated user). The `(auth)` group still wraps admin and lms routes. Logout callback redirects to Authentik logout directly.  
*Dependencies:* Unit 2 (Authentik OIDC flow, hooks.server.ts auth guard), Unit 3 (dashboard layout shell, sidebar, navbar).

**14. Auth Refresh Fixes – Race Condition, Client-Side 401, and Cookie Cleanup**  
*What it builds:* Fixes five concrete issues in the token refresh strategy. (1) Module-level `inflightRefresh` promise in `hooks.server.ts` deduplicates concurrent refresh calls across parallel tab navigations, preventing OIDC token rotation races from logging users out. (2) New `apiFetch` wrapper in `frontend/src/lib/client/api.ts` catches client-side 401s, calls `POST /api/auth/refresh` silently, retries the original request on success, and redirects to `/?error=session_expired` on failure. (3) Cookie `maxAge` is aligned to real JWT `exp` (removes the `Math.max(..., 60)` floor) in hooks.server.ts, callback, and refresh route — if the token expires in 5s, the cookie lives 5s, not 60s. (4) Removes unused `accessToken` from `TokenResponse`. (5) Standardises `SECURE` constant from `process.env.NODE_ENV === 'production'` to `!dev` (SvelteKit compile-time constant) in callback and refresh routes.
*Dependencies:* Unit 13 (routing refactor — dashboard at `/`, auth guard in root layout), Unit 2 (Authentik OIDC flow, hooks.server.ts, refresh endpoint).

**15. Student Dashboard – Subject Cards**  
*What it builds:* Student dashboard at `/` calls `/api/student/subjects` (via SvelteKit load) and renders a grid of subject cards (shadcn‑svelte `Card`). Empty state: “No subjects assigned.” Loading state: skeleton cards.  
*Dependencies:* Unit 11 (architecture refactor), Unit 10 (Student Agent subjects), Unit 3 (layout).

**16. Student Agent – Term & Lesson Lists**  
*What it builds:* Student Agent methods `getTerms(subjectId)` and `getLessons(subjectId, termId)`. Both query SurrealDB’s normalised `terms` and `lessons` tables, filtering by `active = true`. Terms that have no active lessons are excluded (or greyed out) based on the `active` flag on the term record itself (set during normalisation). Results cached in memory (agent struct fields). Proxy routes added.  
*Dependencies:* Unit 10 (Student Agent exists), Unit 9 (normalised schema with term active flags).

**17. Student LMS – Term & Lesson Browsing**  
*What it builds:* Frontend: clicking a subject navigates to `/lms/[subject]`, which calls `getTerms` and displays term buttons (First, Second, Third). Clicking a term navigates to `/lms/[subject]/[term]`, which calls `getLessons` and shows a numbered lesson list. Active/inactive items are visually distinct. Breadcrumb: `LMS > Basic Science > Second Term`.  
*Dependencies:* Unit 16 (agent methods), Unit 15 (subject grid).

**18. Student Agent – Lesson Content (Student View)**  
*What it builds:* Student Agent method `getLesson(lessonId)`. Fetches the lesson from SurrealDB (cache with TTL) but returns **only** the student‑visible fields: `objectives`, `content_sections`, `key_points`, plus any active assignment questions. No full teacher‑only fields. Proxy route added.  
*Dependencies:* Unit 15 (Student Agent queries SurrealDB), Unit 9 (SurrealDB normalised).

**19. Lesson Content Page with Side Navigation**  
*What it builds:* Frontend lesson page at `/lms/[subject]/[term]/[lesson]`. Renders content sections, key points, objectives, and assignment section (if any). Side navigation panel (hover to reveal section headings, click to scroll). Breadcrumb updated.  
*Dependencies:* Unit 18 (lesson data available), Unit 17 (browsing flow).

**20. Teacher Agent – Initialization & Dashboard (DB-Backed Architecture)**  
*What it builds:* Architecture Rules 1-10 implementation (see `docs/architecture.md`). SurrealDB-backed `user_profile` and `teacher_assignment` tables replace agent durable state for entity data. Admin Agent refactored: `initialized_users`/`teacher_assignments` maps removed, all reads/writes go to DB tables. Teacher Agent `trigger_initialize` reads from `teacher_assignment` table directly (not AdminAgent RPC). `class_groups` becomes a Push-Invalidation cache (Rule 4A). Admin Agent uses `with_atomic_operation` for atomic DB-write + fan-out (Rule 2). Gateway endpoints for teacher subjects with ID-only payloads. Teacher dashboard with "My Classes" card grid, admin assignment UI with search+badge pattern filtering already-assigned pairs. 7 phases: Schema migration → SurrealDB client retry wrapper → AdminAgent → TeacherAgent → StudentAgent profile → GatewayAgent → Frontend (filtered dropdown, init guard, ID-only save).  
*Branch:* `feat/20-teacher-db-backed-state`  
*Dependencies:* Unit 19 (lesson content page), Unit 9 (SurrealDB connection).

**21. Teacher Agent – Term & Lesson Toggle (with Normalised Term Table)**  

*What it builds:* Teacher Agent methods `toggleTermActive(subjectId, termId, active)` and `toggleLessonActive(lessonId, active)`. These update the `active` flag on the `terms` or `lessons` table in SurrealDB and fire‑and‑forget push status changes to all Student Agents in the class (discovering students via `user_profile` table query). Student Agent method `updateLessonStatus(lessonId, active)` updates local cache. Teacher UI shows toggle switches that work end‑to‑end.  
*Dependencies:* Unit 20 (Teacher Agent, class_groups cache), Unit 9 (normalised terms with active flag).

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
*What it builds:* Teacher Agent inbox view, grading method `gradeSubmission` that writes grade to a DB-backed grades table and pushes to `StudentAgent.receiveGrade`. Student Agent stores grade (cache) and displays it on the assignment. Frontend: grading form in teacher's assignment page; grade view in student's lesson.  
*Dependencies:* Unit 24 (submissions exist), Unit 22 (assignment exists).

**26. Admin Class & Teacher Management**  
*What it builds:* Admin portal UI to assign teachers to classes/subjects (writes to `teacher_assignment` table, invalidates TeacherAgent caches) and to move students between classes (updates `user_profile.class_level`).  
*Dependencies:* Unit 20 (DB-backed architecture), Unit 10 (Student Agent), Unit 8 (admin portal).

**27. Polish – Loading, Error, Empty States, Stale Data Indicators & Dark Mode**  
*What it builds:* Skeleton loaders and empty states on all data‑driven pages. Error boundaries with retry buttons. **Stale data indicators on every page that displays cached content** (lesson lists, lesson content, assignment views) with manual refresh buttons. Dark mode toggle in the navbar using `mode‑watcher`; all components respond to `dark:` variant. Responsive sidebar collapse on small screens.  
*Dependencies:* All previous units; can be implemented incrementally but finalised as the last pass.