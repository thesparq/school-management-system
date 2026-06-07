# Project Overview: School Management System – LMS MVP

A robust, multi-tenant school management platform with a built‑in Learning Management System. The MVP focuses on displaying AI‑generated lesson content and handling teacher‑curated assignments with submission and grading. Teachers, students, administrators (bursar, receptionist), and parents will be able to log in through Authentik. A SvelteKit frontend (with MoonBit logic) serves as the sole authentication proxy and UI layer, forwarding all business requests to a Golem Cloud backend composed of durable, per‑user agents and a central administration agent. The system is designed to be secure, scalable, and fully event‑driven, with no direct database access from the frontend.

## Goals

1. Provide a secure, role‑based portal where students can view AI‑generated lessons and complete assignments.
2. Allow teachers to curate assessment questions from a question bank, set deadlines, and grade student submissions.
3. Let administrators initialize users, manage class‑subject‑teacher assignments, and oversee content through a central admin portal.
4. Guarantee that only pre‑initialized users can interact with their durable agent, preventing implicit resource creation.
5. Maintain a clean separation of concerns: SvelteKit handles auth and UI; Golem agents own all business logic and state.
6. Keep the system simple and idiomatic to Golem’s durable execution model (actor‑based, event‑sourced state, explicit RPCs).
7. Use a calm, accessible UI with light mode (and optional dark mode) built with Tailwind CSS v4 and shadcn‑svelte.
8. Support multiple assignments per lesson, each with its own deadline and question selection.
9. Ensure data integrity and durability using Golem's durable execution (agent struct fields) and SurrealDB for lesson content.

## Core User Flow (step‑by‑step)

1. **Login**  
   - User navigates to the SvelteKit portal → redirected to Authentik for authentication.  
   - Authentik returns a JWT; SvelteKit validates it server‑side and stores it in an HTTP‑only cookie.

2. **LMS Access**  
   - On any subsequent request, SvelteKit extracts the internal user ID from the JWT and proxies directly to the user's durable agent (Student, Teacher, or Admin Agent) via its HTTP endpoint.  
   - Each agent fetches the user profile reactively from SurrealDB when data is needed (lazy, not on every request).  
   - If no `user_profile` record exists → return "Account not initialized; please contact admin."  
   - The root page `/` is the default landing — students see the LMS subject list; admins see a dashboard.

3. **Student LMS Flow**  
   - Student logs in and lands on the LMS page (root `/`) with the "LMS" sidebar tab active.  
   - Root page displays subject cards for the student's class (cached in Student Agent).  
   - Clicking a subject → list of terms (First, Second, Third); disabled terms appear greyed out.  
   - Clicking a term → list of lessons; disabled lessons greyed out.  
   - Clicking a lesson → tabbed lesson page (Lesson tab: full content with objectives, sections, key points, side navigation; Assessments tab: assigned assessments placeholder).  
   - Student views assigned assessments in the Assessments tab (placeholder — wired in later units).

4. **Teacher LMS & Grading Flow**  
   - Teacher first sees a list of classes they teach → subjects for that class → terms → lessons.  
   - Within a lesson, teacher sees a 3-tab page: Lesson (full content, side navigation, no assignment section), Assessments (assessment list + "Create Assessment" button → modal with MCQ/theoretical question checkboxes selected from the lesson's question bank), and Grading (submission list with per-student grading rows).  
   - Assessments and grading tabs are UI placeholders for now — backend wiring for assignment creation, submission, and grading comes in later units.  
   - Teacher selects questions, sets a deadline, and creates an assignment (multiple assignments per lesson allowed).  
   - Teacher Agent stores assignment config, pushes it to all students in the class via fire‑and‑forget RPCs.  
   - Teacher opens the grading view for an assignment → sees submissions received in its inbox (lazy refresh with "data may be stale" message).  
   - Teacher grades a submission; grade and feedback are pushed to the Student Agent via RPC.

5. **Admin Operations**  
   - Admin accesses user management page grouped by role (Students, Teachers, Admin tabs).  
   - Admin initializes a user → Admin Agent records initialization, creates the user's durable agent with class, subjects, etc.  
   - Admin can activate/deactivate users in Authentik (login permission) via dedicated API routes.  
   - Admin can manage password resets and group membership directly via Authentik API.  
   - Admin can assign teachers to classes/subjects; Admin Agent updates relationships and pushes rosters to affected agents.  
   - Admin can manage session terms (e.g., "2024 Summer Term") through a Configuration panel — scoping teacher assignments, assessments, fees, and results to an academic period. Only one session term can be active at a time.  
   - Content management (AI generation/regeneration) available later.

## Features Breakdown

### Student Features
- View subjects, terms, and lessons for own class only.
- Disabled terms and lessons are visually indicated (greyed out, lock icon).
- Lesson page with breadcrumbs, 2-tab layout (Lesson: full content with side navigation; Assessments: assigned assessments placeholder).
- Assignment: objective (MCQ) and theoretical (text) questions; file uploads deferred.
- Submission with local deadline check; resubmission allowed until deadline.
- View own grades and feedback after teacher grading.

### Teacher Features
- View classes taught, subjects, terms, lessons (including inactive — shown greyed out with lock icon).
- Toggle lesson/term active status (deactivate for students).
- 3-tab lesson page: Lesson (full content), Assessments (list + create-assessment modal with question checkboxes from lesson bank), Grading (submission list).
- Create assignments: select questions from lesson's bank, set deadline (UTC).
- Multiple assignments per lesson (active simultaneously until deadline/closure).
- Grading inbox with student submissions; lazy refresh and manual refresh button.
- Grade submissions (score + feedback) pushed back to student.

### Admin Features
- User management: role-based tabs (Students, Teachers, Parents, Admin), list from Authentik, initialize/activate/deactivate users.
- Four role-specialized profile tables: student (surname, first_name, middle_name, DOB, class_enrolled, current_class, passport), teacher (qualifications, date_employed), admin (role_title), parent (name, linked students).
- Passport photo upload per user via Cloudflare R2 presigned URLs with preview.
- Credentials management: create/update qualification entries for teacher profiles.
- Golem initialization creates durable agent; Authentik activation/deactivation controls login permission.
- Reset passwords and manage group membership via Authentik API.
- Manage teacher‑class‑subject assignments; updates rosters in real time.
- Session term management: create and activate session terms (session + academic term pairs) via Configuration panel.
- Term toggle: activate/deactivate curriculum terms with cascading cache invalidation.
- (Future) AI content generation/regeneration.

### Parent Features
- Login to portal and see linked students (from parent profile's `students` array).
- Click any linked student to access full student LMS mirror (subjects → terms → lessons → lesson content).
- Submit assignments on behalf of a student (write mirror via RPC to StudentAgent).
- Read-only access enforced per student — cannot access unlinked students.

### General Features
- Light mode (default) with professional blue‑amber palette; dark mode toggle with system preference detection and sync `<script>` in `app.html` preventing flash on load/navigation.
- School branding: actual school photo as `logo.jpg` in sidebar header (and top bar when sidebar collapses), `favicon.png` for favicon and collapsed-state icon.
- Responsive layout: collapsible sidebar (offcanvas on mobile, shrink-to-icon on desktop), breadcrumb navigation, mobile-friendly tables and forms.
- Collapsed sidebar: full logo transitions into the top bar (between sidebar trigger and breadcrumb) with smooth opacity+scale animation.
- Sidebar: Navigation group (LMS, My Classes — teachers, My Children — parents), Configuration group (Session Terms, Terms — admin only), Users group (Students, Teachers, Parents, Admin — admin only). Mobile sidebar auto-closes on navigation.
- All data access via agents; SvelteKit never touches databases directly.
- JWT‑based authentication, no server‑side sessions.
- Agent durable memory (unified `caches` map per agent) for cached data; SurrealDB for canonical entity data.
- All UI uses shadcn semantic CSS tokens (`text-foreground`, `bg-background`, `border-border`, `text-destructive`, etc.) from `app.css` `@theme inline` block — no raw Tailwind color classes.
- Top loading bar (`h-0.5 bg-secondary-400/500`) appears on navigation as secondary indicator; PageSkeleton component (list/grid/card layouts) as primary per-page loading state.
- Toast notifications for transient operation feedback (success, info, warning, error).
- StatusCard component for all persistent page-level states (error, empty, info, warning).
- PageHeader component for consistent page heading + action layout across all pages.
- PageSkeleton component for consistent loading states: `list` (table placeholder rows), `grid` (card skeleton grid), `card` (single card skeleton).
- Edit dialogs lazy-load profile data: dialog opens immediately with spinner + "Loading profile data..." and disabled Save button until data arrives.
- Global cursor-pointer CSS on all clickable elements (buttons, links, checkboxes, radio buttons, selects); `cursor-not-allowed` on disabled elements.

## In Scope (MVP)

- Authentik integration (OIDC) with JWT validation in SvelteKit.
- SvelteKit as auth proxy and UI server; MoonBit for shared logic.
- Golem Cloud backend with:
  - Durable Admin Agent (central registry, role-specialized user CRUD, credentials, relationships, HTTP-accessible).
  - Durable User Agents (student, teacher, admin, parent) with TTL-cached state, each HTTP-accessible.
- Cloudflare R2 passport photo storage via presigned URLs with saga compensation on create failure.
- Parent portal: multi-student read-only LMS mirror with write proxy for assignment submission.
- Display AI‑generated lesson content from SurrealDB.
- Teacher selection of assessment questions and creation of assignments with deadlines.
- Student submission of answers (text‑only).
- Teacher grading and feedback pushed to student.
- Admin user initialization, activation, deactivation, password reset, group management.
- Class‑subject‑teacher assignment management.
- Session term management for scoping assignments to academic periods.
- Toast notification system for transient operation feedback.
- Basic UI with dashboard, sidebar, breadcrumbs, loading/empty/error states (StatusCard component).
- Multiple assignments per lesson, active until deadline/closure.

## Out of Scope (MVP)

- Automatic lesson generation or AI integration (content already in DB).
- File uploads for assignment submissions (e.g., essays, attachments).
- Real‑time collaboration or streaming (WebSockets/SSE).
- Comprehensive reporting or analytics.
- Billing, payments, or school fee management.
- Attendance tracking, timetable, or other non‑LMS modules.
- Full multi‑tenancy across different schools (single school deployment).
- Native mobile apps.

## Success Criteria

1. A teacher can create an assignment from a lesson’s question bank, students can submit answers before the deadline, and the teacher can grade those submissions.
2. A student sees only lessons and assignments for their own class, with disabled items correctly hidden or greyed out.
3. An admin can activate a new student, assign them to a class, and the student’s agent immediately shows the correct subjects.
4. A deactivated (Authentik) or uninitialized user cannot reach their agent; any request returns a clear error.
5. All state survives agent restarts and platform faults (durability), with automatic state recovery on agent restart.
6. The UI is usable on a standard school desktop/tablet, with clear navigation, loading skeletons, and error messages.
7. Lesson content is fetched from SurrealDB and cached in agents, with a stale‑while‑revalidate strategy.
8. The system handles at least 1,000 concurrent student agents without performance degradation.
