# Hotfix-11: Frontend User Management Rework

## Goal

Refactor the monolithic `UserTable.svelte` (997 lines) into four role-specific table components with shared sub-components, update all create/edit forms to match the new backend profile fields (name parts, passport, DOB, qualifications, role title, students array), implement passport upload with preview via presigned R2 URLs, fix parent page layout, and unify all error/empty/loading states behind the `StatusCard` component.

## Design

**Separation of concerns:** Each user role gets its own table component containing role-specific columns, create dialog, edit dialog, and delete confirmation. Shared form logic extracted to reusable sub-components. This mirrors the backend's `handler`/`agent`/`db` layer separation.

**StatusCard everywhere:** All error, empty, and info states across user pages use the existing `<StatusCard>` component. No raw `<Alert>`, no inline `<div>` icon blocks.

**Passport upload flow:**
1. User selects file → client-side validates JPEG/PNG ≤5MB → preview thumbnail shown
2. On form submit → `POST /api/admin/generate-passport-upload-url` → `PUT` file to R2 presigned URL → include `publicUrl` in form payload
3. Edit dialog pre-loads existing `passport_url` and shows thumbnail preview
4. On create failure → SvelteKit API route handles saga compensation (`deleteR2Object`)

**Display name computation:** `display_name` is computed on the frontend as `surname + " " + first_name + (middle_name ? " " + middle_name : "")` and sent as a field to the backend (no longer sending `name`).

## Implementation

### 1. Fix Authentik Parent Group Fetch

**File:** `frontend/src/lib/server/authentik.ts:251`

Add `'parent'` to `getTargetGroupPks()` target names.

### 2. Update Frontend Type Definitions

**File:** `frontend/src/lib/types/user.ts` — replace `UserRow` with role-specific interfaces:

```typescript
interface BaseUser {
  pk: number;
  uuid: string;
  username: string;
  email: string;
  groups: string[];
  is_active: boolean;
}

interface StudentUser extends BaseUser {
  surname: string;
  first_name: string;
  middle_name?: string;
  display_name: string;
  date_of_birth: string;
  class_enrolled: string;
  current_class: string;
  passport: string;
}

interface TeacherUser extends BaseUser {
  surname: string;
  first_name: string;
  middle_name?: string;
  display_name: string;
  qualifications?: string[];
  date_employed?: string;
  passport: string;
}

interface AdminUser extends BaseUser {
  surname: string;
  first_name: string;
  middle_name?: string;
  display_name: string;
  role_title?: string;
  passport: string;
}

interface ParentUser extends BaseUser {
  name: string;
  display_name: string;
  students: string[];
  passport: string;
}
```

**File:** `frontend/src/lib/types.ts` — add:
```typescript
export interface CredentialInfo { id: string; name: string; active: boolean; }
export interface StudentListItem { id: string; display_name: string; }
```

### 3. Create Shared Components

#### `users-shared/PassportUpload.svelte` — NEW

Props: `currentUrl: string | null`, `disabled: boolean`
Emits: `passportPublicUrl: string | null`, `passportContentType: string | null`

States:
- Empty: dashed border drop zone with "Click or drag passport photo" + JPEG/PNG ≤5MB label
- Preview: 200x200 thumbnail with "Remove" button (shows currentUrl or local preview)
- Uploading: spinner overlay on thumbnail
- Error: red border + "File must be JPEG/PNG and under 5MB"

Client-side validates type (JPEG/PNG) and size (≤5MB) on file select. Does NOT upload on select — parent form's submit handler calls upload flow. Exposes publicUrl + contentType to parent via emits.

#### `users-shared/NameFields.svelte` — NEW

Props: `bind:surname`, `bind:first_name`, `bind:middle_name`
Three labeled inputs in responsive grid (1 col on mobile, 3 cols on desktop).

#### `users-shared/CredentialsSelect.svelte` — NEW

Props: `bind:selected: string[]` (credential record IDs)
Multi-select searchable dropdown (same pattern as teacher subject-assign combo). Selected credentials shown as removable badges. Fetches from `GET /api/admin/credentials` on mount.

### 4. Create Role-Specific Table Components

Each table component follows this template:

```
<script>
  - Imports: Table, StatusCard, AppButton, Badge, Dialog, AlertDialog,
    PassportUpload, NameFields, CredentialsSelect (teacher only), toast
  - Props: bind:users, allGroups, groupPk, bind:showCreateDialog,
    isLoading, hasError, errorMessage
  - State: authStates, createForm, editForm, editDialogOpen,
    deleteTarget, deleteDialogOpen, create/delete loading
  - Role-specific state: classLevels (student), credentials (teacher),
    studentList (parent)
  - Handlers: handleCreate, handleEdit, handleDelete, handleActivate,
    handleDeactivate, openEditDialog
  - onMount: fetch classLevels / credentials / studentList as needed
</script>

{#if isLoading}
  <Skeleton rows=5 />
{:else if hasError}
  <StatusCard variant="error" title="Failed to load users"
    description={errorMessage} onRetry={handleRetry} />
{:else if !hasUsers}
  <StatusCard variant="info" title="No {role} users yet"
    description="Create the first {role} to get started." />
{:else}
  <Table> <!-- role-specific columns --> </Table>
{/if}

<!-- Create Dialog — role-specific fields -->
<!-- Edit Dialog — role-specific fields, pre-loads profile -->
<!-- Delete Dialog — AlertDialog -->
```

#### `students/StudentUserTable.svelte` — NEW

**Table columns:** Name (display_name), Email, Class (current_class), Auth Status, Activate, Edit, Delete

**Create dialog fields:** Username, Surname, First Name, Middle Name, Email, Password, Date of Birth, Class Level (select from `/api/admin/class-levels`), Passport (PassportUpload), Activate checkbox

**Create payload:** `{ username, surname, first_name, middle_name, display_name, email, password, is_active, group_pk, role: 'student', class_level, date_of_birth, passport_url }`

**Edit dialog:** Same as create minus password (optional). Class Level updates `current_class` only (not `class_enrolled`). Pre-loads profile from `GET /api/admin/users/{uuid}/profile?role=student`.

#### `teachers/TeacherUserTable.svelte` — NEW

**Table columns:** Name (display_name), Email, Auth Status, Activate, Edit, Assign, Delete

**Create dialog fields:** Username, Surname, First Name, Middle Name, Email, Password, Date Employed, Qualifications (CredentialsSelect), Passport, Activate checkbox

**Edit dialog:** Pre-loads from `GET /api/admin/users/{uuid}/profile?role=teacher`.

**Class Assign dialog:** Preserved from old UserTable — active session term, current subject pairs, search/add dropdown.

#### `admin-role/AdminUserTable.svelte` — NEW

**Table columns:** Name (display_name), Email, Role Title, Auth Status, Activate, Edit, Delete

**Create dialog fields:** Username, Surname, First Name, Middle Name, Email, Password, Role Title, Passport, Activate checkbox

**Edit dialog:** Pre-loads from `GET /api/admin/users/{uuid}/profile?role=admin`.

#### `parents/ParentUserTable.svelte` — NEW

**Table columns:** Name (display_name), Email, Students (#), Auth Status, Activate, Edit, Delete

**Create dialog fields:** Username, Name (single field, no split), Email, Password, Students (multi-select from `/api/admin/students/list`, ≥1 required), Passport, Activate checkbox

**Students multi-select:** Searchable dropdown listing all students by display_name with removable badges.

**Edit dialog:** Pre-loads from `GET /api/admin/users/{uuid}/profile?role=parent`.

### 5. Update Page Components

**`students/+page.svelte`** — import `StudentUserTable` instead of `UserTable`

**`teachers/+page.svelte`** — import `TeacherUserTable` instead of `UserTable`

**`admin-role/+page.svelte`** — import `AdminUserTable` instead of `UserTable`

**`parents/+page.svelte`** — full rewrite with header + create button + ParentUserTable

### 6. Delete Old UserTable

Delete `frontend/src/routes/admin/users/UserTable.svelte`.

### 7. Dialog-Specific Logic

**Passport upload in submit handlers:**
1. Validate form fields
2. If passport file selected: POST /api/admin/generate-passport-upload-url → PUT file to uploadUrl → set passportPublicUrl
3. Compute display_name from name parts
4. POST /api/admin/users with all fields + passport_url + display_name
5. On success: toast, close dialog, push user to list
6. On error: toast, show inline error

**Edit dialog profile pre-load:**
1. Set editForm with basic fields
2. Fetch profile from /api/admin/users/{uuid}/profile?role={role}
3. Populate role-specific fields from profile response
4. Set passportUpload.currentUrl = profile.passport
5. Open dialog

**Delete handler:** Existing AlertDialog pattern — no changes needed.

**Activate/Deactivate:** Existing pattern — no changes needed.

### 8. File Structure After Rework

```
admin/users/
├── UserTable.svelte              → DELETED
├── users-shared/
│   ├── PassportUpload.svelte     → NEW
│   ├── NameFields.svelte         → NEW
│   └── CredentialsSelect.svelte  → NEW
├── students/
│   ├── +page.svelte              → UPDATED
│   ├── +page.server.ts           → unchanged
│   └── StudentUserTable.svelte   → NEW
├── teachers/
│   ├── +page.svelte              → UPDATED
│   ├── +page.server.ts           → unchanged
│   └── TeacherUserTable.svelte   → NEW
├── admin-role/
│   ├── +page.svelte              → UPDATED
│   ├── +page.server.ts           → unchanged
│   └── AdminUserTable.svelte     → NEW
└── parents/
    ├── +page.svelte              → REWRITTEN
    ├── +page.server.ts           → unchanged
    └── ParentUserTable.svelte    → NEW
```

## Dependencies

No new packages required.

## Verification Checklist

- [ ] `pnpm check` 0 errors
- [ ] `pnpm build` passes
- [ ] Parent group users appear on `/admin/users/parents` page
- [ ] Parent page has header ("Parent Users") and "Create Parent" button
- [ ] Create student: all fields present (username, surname, first_name, middle_name, email, password, DOB, class level, passport, activate)
- [ ] Create student: `display_name` computed correctly and sent to backend
- [ ] Create teacher: qualifications multi-select fetches from `/api/admin/credentials`
- [ ] Create admin: role_title field present
- [ ] Create parent: students multi-select fetches from `/api/admin/students/list`, requires ≥1
- [ ] Passport upload: file selection shows preview, uploads to R2, URL stored in profile
- [ ] Passport upload: JPEG/PNG validation, size validation
- [ ] Edit student: form pre-fills with surname, first_name, middle_name, DOB, class_level, passport preview
- [ ] Edit student: `class_level` updates `current_class` but `class_enrolled` is not shown
- [ ] Edit student: passport can be changed (new upload replaces old)
- [ ] Edit teacher: qualifications pre-filled, date_employed pre-filled, passport preview
- [ ] Edit parent: students pre-filled, name pre-filled, passport preview
- [ ] Delete: all 4 roles, AlertDialog confirmation, user removed from list
- [ ] Activate/Deactivate: toggle works for all 4 roles
- [ ] Error state: all 4 pages show StatusCard with retry on load failure
- [ ] Empty state: all 4 pages show StatusCard info when no users
- [ ] Loading: skeleton rows shown during data fetch
- [ ] Toast: success/info/error toasts fire for all CRUD operations
- [ ] Teacher class assignment still works (no regression)
- [ ] No leftover references to deleted `UserTable.svelte`
