# Project Overview: School Management System – LMS MVP

A robust, multi-tenant school management platform with a built‑in Learning Management System. The MVP focuses on displaying AI‑generated lesson content and handling teacher‑curated assignments with submission and grading. Teachers, students, administrators (bursar, receptionist), and parents will be able to log in through Authentik. A SvelteKit frontend (with MoonBit logic) serves as the sole authentication proxy and UI layer, forwarding all business requests to a Golem Cloud backend composed of durable, per‑user agents and a central administration agent. The system is designed to be secure, scalable, and fully event‑driven, with no direct database access from the frontend.

## Goals

1. Provide a secure, role‑based portal where students can view AI‑generated lessons and complete assignments.
2. Allow teachers to curate assessment questions from a question bank, set deadlines, and grade student submissions.
3. Let administrators activate users, manage class‑subject‑teacher assignments, and oversee content through a central admin portal.
4. Guarantee that only pre‑activated users can interact with their durable agent, preventing implicit resource creation.
5. Maintain a clean separation of concerns: SvelteKit handles auth and UI; Golem agents own all business logic and state.
6. Keep the system simple and idiomatic to Golem’s durable execution model (actor‑based, event‑sourced state, explicit RPCs).
7. Use a calm, accessible UI with light mode (and optional dark mode) built with Tailwind CSS v4 and shadcn‑svelte.
8. Support multiple assignments per lesson, each with its own deadline and question selection.
9. Ensure data integrity and durability using agent‑local SQLite and SurrealDB for lesson content.

## Core User Flow (step‑by‑step)

1. **Login**  
   - User navigates to the SvelteKit portal → redirected to Authentik for authentication.  
   - Authentik returns a JWT; SvelteKit validates it server‑side and stores it in an HTTP‑only cookie.

2. **Dashboard Access**  
   - On any subsequent request, SvelteKit extracts the internal user ID from the JWT and calls the Golem Ephemeral Gateway Agent.  
   - Gateway checks with the durable Admin Agent whether the user is active.  
   - If inactive → error “Account not activated; please contact admin.”  
   - If active → forwards the request to the user’s durable agent (Student, Teacher, or Admin User Agent).

3. **Student LMS Flow**  
   - Student sees a sidebar with the LMS tab active by default.  
   - Dashboard displays subjects for the student’s class (cached in Student Agent; fetched from SurrealDB on cache miss).  
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
   - Admin accesses user management page (user list fetched from Authentik API).  
   - Admin activates a user → Admin Agent records activation, initialises the user’s durable agent with class, subjects, etc.  
   - Admin can assign teachers to classes/subjects; Admin Agent updates relationships and pushes rosters to affected agents.  
   - Admin can deactivate/suspend users; subsequent requests blocked by Ephemeral Gateway.  
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
- User management: list from Authentik, activate/deactivate/suspend users.
- User activation triggers durable agent initialisation.
- Manage teacher‑class‑subject assignments; updates rosters in real time.
- (Future) AI content generation/regeneration.

### General Features
- Light mode (default) with professional blue‑amber palette; optional dark mode toggle.
- Responsive layout: collapsible sidebar, breadcrumb navigation.
- All data access via agents; SvelteKit never touches databases directly.
- JWT‑based authentication, no server‑side sessions.
- Agent‑local SQLite for structured user data; SurrealDB for lesson content.

## In Scope (MVP)

- Authentik integration (OIDC) with JWT validation in SvelteKit.
- SvelteKit as auth proxy and UI server; MoonBit for shared logic.
- Golem Cloud backend with:
  - Ephemeral Gateway Agent (stateless gatekeeper).
  - Durable Admin Agent (central registry, user activation, relationships).
  - Durable User Agents (student, teacher, admin) with SQLite state.
- Display AI‑generated lesson content from SurrealDB.
- Teacher selection of assessment questions and creation of assignments with deadlines.
- Student submission of answers (text‑only).
- Teacher grading and feedback pushed to student.
- Admin user activation, deactivation, suspension.
- Class‑subject‑teacher assignment management.
- Basic UI with dashboard, sidebar, breadcrumbs, loading/empty/error states.
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
4. A suspended user cannot reach their agent; any request returns a clear “account not activated” error.
5. All state survives agent restarts and platform faults (durability), with automatic schema migrations on agent startup.
6. The UI is usable on a standard school desktop/tablet, with clear navigation, loading skeletons, and error messages.
7. Lesson content is fetched from SurrealDB and cached in agents, with a stale‑while‑revalidate strategy.
8. The system handles at least 1,000 concurrent student agents without performance degradation.
