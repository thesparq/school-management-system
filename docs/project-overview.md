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
   - Student logs in and lands on the LMS page (root `/`) with the “LMS” sidebar tab active.  
   - Root page displays subject cards for the student’s class (cached in Student Agent; fetched from SurrealDB on cache miss).  
   - Clicking a subject → list of terms (First, Second, Third); disabled terms appear greyed out.  
   - Clicking a term → list of lessons; disabled lessons greyed out.  
   - Clicking a lesson → full lesson content rendered (sections, sub‑points) plus the active assignment’s questions (previously pushed by the Teacher Agent).  
   - Student answers objective (radio buttons) and theoretical (text area) questions, submits before deadline.  
   - Student Agent verifies deadline locally, discovers the teacher via Admin Agent (cached), then sends submission directly to Teacher Agent via RPC.

4. **Teacher LMS & Grading Flow**  
   - Teacher first sees a list of classes they teach → subjects for that class → terms → lessons.  
   - Within a lesson, teacher can view full content and a list of all assessment questions (MCQ + theoretical).  
   - Teacher selects questions, sets a deadline, and creates an assignment (multiple assignments per lesson allowed).  
   - Teacher Agent stores assignment config, pushes it to all students in the class via fire‑and‑forget RPCs.  
   - Teacher opens the grading view for an assignment → sees submissions received in its inbox (lazy refresh with “data may be stale” message).  
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
- Lesson page with breadcrumbs, full content, and inline assignment.
- Assignment: objective (MCQ) and theoretical (text) questions; file uploads deferred.
- Submission with local deadline check; resubmission allowed until deadline.
- View own grades and feedback after teacher grading.

### Teacher Features
- View classes taught, subjects, terms, lessons.
- Toggle lesson/term active status (deactivate for students).
- Create assignments: select questions from lesson’s bank, set deadline (UTC).
- Multiple assignments per lesson (active simultaneously until deadline/closure).
- Grading inbox with student submissions; lazy refresh and manual refresh button.
- Grade submissions (score + feedback) pushed back to student.

### Admin Features
- User management: role-based tabs (Students, Teachers, Admin), list from Authentik, initialize/activate/deactivate users.
- Golem initialization creates durable agent; Authentik activation/deactivation controls login permission.
- Reset passwords and manage group membership via Authentik API.
- Manage teacher‑class‑subject assignments; updates rosters in real time.
- Session term management: create and activate session terms (session + academic term pairs) via Configuration panel.
- (Future) AI content generation/regeneration.

### General Features
- Light mode (default) with professional blue‑amber palette; optional dark mode toggle.
- Responsive layout: collapsible sidebar, breadcrumb navigation.
- Sidebar: Navigation group (LMS, My Classes), Configuration group (Session Terms — admin only), Users group (role-based tabs).
- All data access via agents; SvelteKit never touches databases directly.
- JWT‑based authentication, no server‑side sessions.
- Agent durable memory (unified `caches` map per agent) for cached data; SurrealDB for canonical entity data.
- Toast notifications for transient operation feedback (success, info, warning, error) with progress bar and pause-on-hover.
- StatusCard component for page-level empty, error, and info states.

## In Scope (MVP)

- Authentik integration (OIDC) with JWT validation in SvelteKit.
- SvelteKit as auth proxy and UI server; MoonBit for shared logic.
- Golem Cloud backend with:
  - Durable Admin Agent (central registry, user initialization, relationships, HTTP-accessible).
  - Durable User Agents (student, teacher, admin) with TTL-cached state, each HTTP-accessible.
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
- File uploads for assignments (e.g., essays, attachments).
- Real‑time collaboration or streaming (WebSockets/SSE).
- Parent portal features beyond login (viewing grades, etc.).
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
