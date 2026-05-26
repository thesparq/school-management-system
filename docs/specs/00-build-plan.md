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
*What it builds:* Extends Admin Agent with `activateUser(userId, role, class?)` (writes to SQLite, status `active`) and `isUserActive(userId)`. Gateway Agent extended: every incoming request now calls `AdminAgent.isUserActive`; if false, returns `403 { code: "NOT_ACTIVATED" }`. Testable via ping proxy for inactive vs active users.  
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
*What it builds:* Student Agent with `initialize(classLevel)` – it queries SurrealDB for subjects assigned to that class (from `class_subjects`) and stores them in its SQLite. Exposes `getSubjects()`. Admin Agent: during `activateUser` for a student, calls `StudentAgent.initialize`. A proxy route `/api/student/subjects` added.  
*Dependencies:* Unit 8 (activation flow), Unit 9 (normalised SurrealDB).

**11. Student Dashboard – Subject Cards**  
*What it builds:* Student dashboard (`/dashboard`) calls `/api/student/subjects` (via SvelteKit load) and renders a grid of subject cards (shadcn‑svelte `Card`). Empty state: “No subjects assigned.” Loading state: skeleton cards.  
*Dependencies:* Unit 10 (Student Agent subjects), Unit 3 (layout).

**12. Student Agent – Term & Lesson Lists**  
*What it builds:* Student Agent methods `getTerms(subjectId)` and `getLessons(subjectId, termId)`. Both query SurrealDB’s normalised `terms` and `lessons` tables, filtering by `active = true`. Terms that have no active lessons are excluded (or greyed out) based on the `active` flag on the term record itself (set during normalisation). Results cached in SQLite. Proxy routes added.  
*Dependencies:* Unit 10 (Student Agent exists), Unit 9 (normalised schema with term active flags).

**13. Student LMS – Term & Lesson Browsing**  
*What it builds:* Frontend: clicking a subject navigates to `/lms/[subject]`, which calls `getTerms` and displays term buttons (First, Second, Third). Clicking a term navigates to `/lms/[subject]/[term]`, which calls `getLessons` and shows a numbered lesson list. Active/inactive items are visually distinct. Breadcrumb: `LMS > Basic Science > Second Term`.  
*Dependencies:* Unit 12 (agent methods), Unit 11 (subject grid).

**14. Student Agent – Lesson Content (Student View)**  
*What it builds:* Student Agent method `getLesson(lessonId)`. Fetches the lesson from SurrealDB (cache with TTL) but returns **only** the student‑visible fields: `objectives`, `content_sections`, `key_points`, plus any active assignment questions. No full teacher‑only fields. Proxy route added.  
*Dependencies:* Unit 12 (Student Agent queries SurrealDB), Unit 9 (SurrealDB normalised).

**15. Lesson Content Page with Side Navigation**  
*What it builds:* Frontend lesson page at `/lms/[subject]/[term]/[lesson]`. Renders content sections, key points, objectives, and assignment section (if any). Side navigation panel (hover to reveal section headings, click to scroll). Breadcrumb updated.  
*Dependencies:* Unit 14 (lesson data available), Unit 13 (browsing flow).

**16. Teacher Agent – Initialization & Dashboard**  
*What it builds:* Teacher Agent with `initialize(teacherId)` – queries Admin Agent for assigned classes/subjects (stored during teacher activation) and stores in SQLite. Exposes `getMyClasses()`. Teacher dashboard: after login, teacher sees their classes, clicks into a class → subjects → terms → lessons. Reuses existing lesson list components; lesson detail view (next unit) will show all fields.  
*Dependencies:* Unit 8 (activation sets teacher assignments), Unit 13 (lesson list components), Unit 14 (need full lesson view – see Unit 18).

**17. Teacher Agent – Term & Lesson Toggle (with Normalised Term Table)**  
*What it builds:* Teacher Agent methods `toggleTermActive(subjectId, termId, active)` and `toggleLessonActive(lessonId, active)`. These update the `active` flag on the `terms` or `lessons` table in SurrealDB and fire‑and‑forget push status changes to all Student Agents in the class. Student Agent method `updateLessonStatus(lessonId, active)` updates local cache. Teacher UI shows toggle switches that work end‑to‑end.  
*Dependencies:* Unit 16 (Teacher Agent, roster), Unit 9 (normalised terms with active flag).

**18. Teacher Assignment Creation**  
*What it builds:* Teacher Agent method `configureAssignment(lessonId, selectedQuestionIds, deadline)`. Stores assignment definition in SQLite, then pushes to all students via `StudentAgent.addOrUpdateAssignment`. Teacher’s lesson detail page (built here) shows **all** lesson fields (full record) plus checkboxes for questions, deadline picker, and “Create Assignment” button.  
*Dependencies:* Unit 16 (Teacher Agent, roster), Unit 14 (Student Agent can receive assignment config).

**19. Student Assignment Display**  
*What it builds:* Student Agent serves the active assignment’s questions when loading a lesson. Frontend lesson page now shows an “Assignment” section with MCQ radio buttons, theoretical text areas, and deadline countdown. No submission yet.  
*Dependencies:* Unit 18 (assignment config exists in Student Agent), Unit 15 (lesson page).

**20. Student Assignment Submission**  
*What it builds:* Student Agent method `submitAssignment(assignmentId, answers)`. Local deadline check, teacher discovery via Admin Agent, direct RPC to `TeacherAgent.receiveSubmission`. Teacher Agent inbox stores submission. Frontend: “Submit” button with confirmation.  
*Dependencies:* Unit 19 (assignment visible), Unit 8 (Admin Agent receptionist).

**21. Teacher Grading**  
*What it builds:* Teacher Agent inbox view, grading method `gradeSubmission` that stores grade and pushes to `StudentAgent.receiveGrade`. Student Agent stores grade and displays it on the assignment. Frontend: grading form in teacher’s assignment page; grade view in student’s lesson.  
*Dependencies:* Unit 20 (submissions exist), Unit 18 (assignment exists).

**22. Admin Class & Teacher Management**  
*What it builds:* Admin portal UI to assign teachers to classes/subjects (updates Admin Agent relationships and pushes to agents) and to move students between classes.  
*Dependencies:* Unit 16 (Teacher Agent), Unit 10 (Student Agent), Unit 8 (admin portal).

**23. Polish – Loading, Error, Empty States, Stale Data Indicators & Dark Mode**  
*What it builds:* Skeleton loaders and empty states on all data‑driven pages. Error boundaries with retry buttons. **Stale data indicators on every page that displays cached content** (lesson lists, lesson content, assignment views) with manual refresh buttons. Dark mode toggle in the navbar using `mode‑watcher`; all components respond to `dark:` variant. Responsive sidebar collapse on small screens.  
*Dependencies:* All previous units; can be implemented incrementally but finalised as the last pass.
