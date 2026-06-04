# Feature Test Checklist

Report which test number fails and we'll dig in.

---

## Auth Flow

| # | Test | How | Expected |
|---|------|-----|----------|
| 1 | Normal login | Visit `/` → redirected to Authentik → log in | Land on dashboard with user info |
| 2 | JWT expiry + valid refresh | Wait for JWT to expire (or set Authentik token lifetime to 1 min) → click anywhere | Refresh happens silently, still authenticated |
| 3 | Full session expiry | Revoke Authentik session or wait until refresh token expires → click any link | Redirected to Authentik login (no inline "Not authenticated" error) |
| 4 | Logout | Click "Sign out" in avatar dropdown | Redirected to Authentik end-session → back to `/` → Authentik login |
| 5 | Unauthenticated user | Clear cookies, visit any page | Redirected to Authentik login |

---

## Admin (login as user with admin role)

| # | Test | How | Expected |
|---|------|-----|----------|
| 6 | Home loads | Visit `/` | Dashboard page with content |
| 7 | DB connection test | Click "Test Connection" button on home page | Green success with agent response |
| 8 | Student user list | Navigate to `/admin/users/students` | Table with Name, Email, Init Status, Auth Status columns |
| 9 | Teacher user list | Navigate to `/admin/users/teachers` | Teachers table filtered by teacher group |
| 10 | Admin user list | Navigate to `/admin/users/admin-role` | Admin users table filtered by admin group |
| 11 | Create a student with class level | Click "Create Student" → fill form (username, name, email, password, class level) → submit | User in Authentik + SurrealDB with class_level; student dashboard shows subjects for that class |
| 12 | Activate user | Click "Activate" on a user's row | User's `is_active` toggles to true in Authentik; badge updates |
| 13 | Deactivate user | Click "Deactivate" on a user's row | User's `is_active` toggles to false in Authentik |
| 14 | Edit user | Click "Edit" on a user → modify fields (name, email, username, password, class_level) → save | Changes in both Authentik and SurrealDB; cache invalidated on target agent |
| 15 | Delete user | Click "Edit" → "Delete" → confirm | User removed from Authentik, profile soft-deleted in SurrealDB |
| 16 | Assign teacher subjects | Click "Assign" on a teacher → search/select class-subject pairs → save | Assigned subjects persist on reload; teacher dashboard shows classes |
| 17 | Teacher subject list | Open a teacher's assign modal | Shows currently assigned subjects from DB |
| 18 | Create teacher | Click "Create Teacher" → fill form → submit | New user in Authentik + SurrealDB, appears in teachers table |
| 19 | Session terms page | Navigate to Configuration > Session Terms | Table with Session, Term, Active, Created At columns |
| 20 | Create session term | Click "Create Session Term" → fill session + select term → submit | New row appears at top; toast confirms success |
| 21 | Activate session term | Click "Activate" on inactive row → confirm | Row shows active badge; all others deactivated; toast confirms |
| 22 | No active term warning | Ensure no active ST exists → visit page | StatusCard(warning) shown above table |
| 23 | Toast on CRUD | Create/Edit/Delete a user | Success toast appears top-right; error toast on failure |
| 24 | Toast hover pause | Hover over toast during countdown | Progress bar stops; resumes on mouse leave |

---

## Student (login as initialized student)

| # | Test | How | Expected |
|---|------|-----|----------|
| 22 | Home shows subjects | Visit `/` | Card grid of assigned subjects |
| 23 | "LMS" sidebar link | Check sidebar | "LMS" nav link visible and active |
| 24 | Drill into subject | Click a subject card at `/` | Terms listing at `/lms/{subjectId}` |
| 25 | Drill into term | Click a term | Lesson list at `/lms/{subjectId}/{termId}` |
| 26 | View lesson | Click a lesson | Tabbed page: Lesson tab (full content, side nav), Assessments tab (placeholder) |
| 27 | Content side navigation | Hover dots column on lesson page | Section headings pop up; click to scroll (Lesson tab only) |
| 28 | Mobile TOC | Narrow viewport on lesson page | Floating TOC button at bottom-right |
| 29 | Empty state (no subjects) | Login as student with class level that has no active has_subject edges | `StatusCard(variant="error")` with "No subjects are assigned to your class yet." |
| 30 | Not initialized | Login as student with no profile row in SurrealDB | `StatusCard(variant="info")` with "Account Not Initialized" message |
| 31 | Error/retry | Kill Golem agent → click any LMS link | `StatusCard(variant="error")` with Retry button |

---

## Teacher (login as teacher with assignments)

| # | Test | How | Expected |
|---|------|-----|----------|
| 32 | Home shows "My Classes" | Visit `/` | Card grid of assigned class levels |
| 33 | "My Classes" sidebar | Check sidebar | Nav link visible |
| 34 | Drill into class | Click a card | Subjects for that class |
| 35 | Drill into subject | Click a subject | Terms list |
| 36 | Drill into term | Click a term | Lesson list |
| 37 | Drill into lesson | Click a lesson | 3-tab page: Lesson (full content, side nav, no assignments), Assessments (list + Create Assessment button), Grading (submission placeholders) |
| 38 | Create Assessment modal | Click "Create Assessment" button in Assessments tab | Dialog opens with title input + MCQ accordion (collapsed) + Theoretical accordion (collapsed); questions from lesson data with checkboxes |
| 39 | Create button disabled | Leave title empty in create modal | "Create" button greyed out; becomes enabled when title is non-empty |
| 40 | Grading view | Click Grading tab | Placeholder accordion rows with student names, submission status badges, and Grade buttons |
| 41 | Inactive terms/lessons | Navigate to term/lesson selection | Inactive items shown with opacity-50, lock icon, not clickable |
| 42 | Student breadcrumb | Navigate deep as student | Breadcrumb trail starts at "Subjects" (no "LMS" prefix) |
| 43 | Student 2-tab lesson | Click lesson as student | 2 tabs: Lesson, Assessments (no Grading tab, no Create button) |
| 44 | AppButton spinner | Trigger an async action (Save, Create, Delete) | Button shows spinning SVG icon, disables, shows gerund text (e.g. "Saving...") |
| 45 | AlertDialog activation | Click "Activate" on session term row | AlertDialog opens with "Activate Session Term" title + "will deactivate all others" description; Cancel/Action buttons |
| 46 | AlertDialog delete | Click "Delete User" in edit dialog | AlertDialog opens with user name in title; danger description; Cancel/Action buttons |
| 47 | Assign modal non-blocking | Click "Assign" on teacher row | Modal opens immediately; session term shows "Loading session term..." indicator until fetch completes |
| 48 | Delete double-click guard | Rapidly click "Delete" twice | Only one DELETE request sent; second click silently ignored |

---

## General UI

| # | Test | How | Expected |
|---|------|-----|----------|
| 49 | Sidebar collapse | Click sidebar toggle | Sidebar collapses; state persists on reload |
| 50 | Breadcrumbs | Navigate deep (Subject → Term → Lesson) | Breadcrumb trail updates correctly |
| 51 | Loading skeletons | Visit a slow page | Skeleton loading states, not blank/spinner |
| 52 | Responsive layout | Resize browser to tablet width | Sidebar becomes sheet overlay |

---

## Auth Fix — Testing Guide

**Most realistic test:** Set Authentik's access token lifetime to **1 minute** in the Authentik admin UI under **Providers → your OAuth2 provider → Advanced protocol settings → Access Token Validity**.

1. Log in normally
2. Wait 1 minute (JWT expires)
3. Click around the admin users page (which fires many parallel fetch calls)
4. Should see **no "Not authenticated" error** — the refresh should happen silently
5. To test full expiry: revoke the session in Authentik admin → next click should **redirect to Authentik login** instead of showing an inline error
