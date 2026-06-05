# Hotfix-10: User Management Refactor

## Goal

Split the monolithic `user_profile` table into four role-specialized profile tables using Authentik UUIDs as record IDs, add a Parent agent that mirrors the complete student agent for multi-student access, enrich all profiles with role-specific fields, introduce a credentials lookup table for teacher qualifications, and implement Cloudflare R2 passport storage via presigned URLs with saga compensation on create.

## Design

### Record ID Convention

All four profile tables and the credentials table use custom record IDs — no separate `id` field:

- `student_profile:{auth_uuid}` — e.g., `student_profile:a1b2c3d4-e5f6-7890-abcd-ef1234567890`
- `teacher_profile:{auth_uuid}`
- `admin_profile:{auth_uuid}`
- `parent_profile:{auth_uuid}`
- `credentials:{slug}` — e.g., `credentials:b_ed_mathematics`

Authentik UUIDs (standard RFC 4122 with hyphens) are compatible with SurrealDB record ID constraints (alphanumeric, hyphens, underscores). This eliminates the separate `auth_id` field — the record ID *is* the identifier. Parent's `students` array stores typed `record<student_profile>` references.

### Display Name

`display_name` on student, teacher, and admin profiles is computed as `"surname firstname middlename"` on create/edit. This is what gets sent to Authentik's `name` field. On the parent profile, `name` is a single field (no split into parts) and maps directly to Authentik.

### Name Format

`display_name = surname + " " + first_name + (middle_name.map(" " + _) | "")`

### Parent Agent

Durable agent, mounted at `/parent/{parent_id}`, mirrors the **complete** student agent — all reads and writes. Reads query SurrealDB directly. Writes (assignment submission, future mutations) proxy via typed RPC to the student's own agent. The parent handler verifies the requested `student_id` is in the parent's `students` array before any operation.

### Passport Storage — Presigned URL Flow (Browser → R2 Direct)

```
1. Browser: user selects file, client-side validates type (JPEG/PNG) and size (≤ 5MB)
2. Browser: POST /api/admin/generate-passport-upload-url { profileType, userId, contentType, fileSize }
3. Server: validates content type and size → generates presigned PUT URL (5-min expiry) → returns { uploadUrl, publicUrl }
4. Browser: PUT file directly to R2 using presigned URL (Content-Type baked into signature,
   mathematically enforced by AWS SigV4 — wrong type = 403)
5. Browser: includes publicUrl in create/edit form submission
6. On create failure: SvelteKit calls deleteR2Object() as saga compensation
7. On edit failure: no compensation needed (same key, retry overwrites harmlessly)
```

Security properties of presigned URLs:
- Content-Type is signature-locked — R2 rejects mismatched types
- Scoped to exact key — cannot overwrite other files
- 5-minute expiry — stale URLs are useless
- Server validates type/size before issuing — malformed requests never get a URL
- No R2 credentials exposed to browser — the presigned URL is a derived signature

---

## Implementation

### 1. Database Schema (`db/schema-v3.surql`)

All tables: `SCHEMAFULL`, `PERMISSIONS ... NONE`. Fresh start — no migration needed (testing phase). Drop `user_profile` before applying.

#### `student_profile`
| Field | Type | Notes |
|---|---|---|
| `surname` | `string` | Required |
| `first_name` | `string` | Required |
| `middle_name` | `option<string>` | Optional |
| `display_name` | `string` | Required. Computed: `"surname firstname middlename"` |
| `date_of_birth` | `datetime` | Required. Not optional. |
| `class_enrolled` | `record<class_levels>` | Required. Set on create, immutable. |
| `current_class` | `record<class_levels>` | Required. Create: = class_enrolled. Edit: updatable. |
| `passport` | `string` | Required. R2 public URL. |
| `created_at` | `datetime` | `DEFAULT time::now()` |
| `updated_at` | `option<datetime>` | |
| `deleted_at` | `option<datetime>` | Soft delete |

#### `teacher_profile`
| Field | Type | Notes |
|---|---|---|
| `surname` | `string` | Required |
| `first_name` | `string` | Required |
| `middle_name` | `option<string>` | Optional |
| `display_name` | `string` | Required. Computed. |
| `qualifications` | `option<array<record<credentials>>>` | Array of credentials record IDs |
| `date_employed` | `option<datetime>` | |
| `passport` | `string` | Required |
| `created_at` | `datetime` | `DEFAULT time::now()` |
| `updated_at` | `option<datetime>` | |
| `deleted_at` | `option<datetime>` | |

#### `admin_profile`
| Field | Type | Notes |
|---|---|---|
| `surname` | `string` | Required |
| `first_name` | `string` | Required |
| `middle_name` | `option<string>` | Optional |
| `display_name` | `string` | Required. Computed. |
| `role_title` | `option<string>` | e.g., "Bursar", "Receptionist" |
| `passport` | `string` | Required |
| `created_at` | `datetime` | `DEFAULT time::now()` |
| `updated_at` | `option<datetime>` | |
| `deleted_at` | `option<datetime>` | |

#### `parent_profile`
| Field | Type | Notes |
|---|---|---|
| `name` | `string` | Required. Single name field (no split into parts). Maps to Authentik name. |
| `display_name` | `string` | Required. Same as `name` (no parts to concatenate). |
| `students` | `array<record<student_profile>>` | Required. `ASSERT array::len($value) > 0`. Typed references. |
| `passport` | `string` | Required. R2 URL. |
| `created_at` | `datetime` | `DEFAULT time::now()` |
| `updated_at` | `option<datetime>` | |
| `deleted_at` | `option<datetime>` | |

#### `credentials` (Lookup Table)
| Field | Type | Notes |
|---|---|---|
| `name` | `string` | Required. Unique. |
| `active` | `bool` | `DEFAULT true` |

Record IDs: `credentials:b_ed_mathematics`, `credentials:m_sc_education`, etc.

Index: `idx_credentials_name` UNIQUE on `name`.

#### Indexes

No `auth_id` indexes needed — record IDs are inherently unique in SurrealDB.

### 2. Config (`config.mbt`)

No changes to `SharedConfig`. R2 secrets stay in SvelteKit `.env` only. The Golem agent never interacts with R2.

### 3. Types

#### `types_admin.mbt` — Replace `UserProfileInfo` with four structs:

```mbt
struct StudentProfileInfo {
  id : String              // "student_profile:{uuid}"
  surname : String
  first_name : String
  middle_name : String?
  display_name : String
  date_of_birth : String   // ISO 8601 datetime
  class_enrolled : String  // class_levels record ID
  current_class : String
  passport : String        // R2 URL
  created_at : String
}

struct TeacherProfileInfo {
  id : String
  surname : String
  first_name : String
  middle_name : String?
  display_name : String
  qualifications : Array[String]?  // credentials record IDs
  date_employed : String?
  passport : String
  created_at : String
}

struct AdminProfileInfo {
  id : String
  surname : String
  first_name : String
  middle_name : String?
  display_name : String
  role_title : String?
  passport : String
  created_at : String
}

struct ParentProfileInfo {
  id : String
  name : String
  display_name : String
  students : Array[String]  // student_profile record IDs, always populated
  passport : String
  created_at : String
}
```

#### `types_parent.mbt` — NEW:

```mbt
struct ParentStudentInfo {
  id : String              // student_profile:{uuid}
  display_name : String
  class_level : String     // current class name
  subject_count : Int
}
```

#### `types_student.mbt` — Updated `StudentProfile`:

```mbt
struct StudentProfile {
  surname : String
  first_name : String
  middle_name : String?
  display_name : String
  date_of_birth : String
  class_level : String       // current_class as class_levels record ID
  passport : String
}
```

### 4. Validation (`validation.mbt`)

- `validate_role` adds `"parent"` → accepts `["admin", "teacher", "student", "parent"]`
- `validate_name_part(value, field_name)` → min 1 char
- `validate_dob(value)` → valid ISO 8601 datetime, not in the future
- `validate_student_ids(ids, config)` → each ID must exist in `student_profile` with `deleted_at IS NONE`
- `validate_passport_url(value)` → must be non-empty string

### 5. DB Layer

#### `db_admin.mbt` — Replace all `user_profile` functions with role-specific variants:

| Old | New (4 variants each) |
|---|---|
| `db_admin_fetch_profile` | `db_admin_fetch_student_profile`, `_teacher_profile`, `_admin_profile`, `_parent_profile` |
| `db_admin_save_profile` | `db_admin_create_student_profile`, `db_admin_update_student_profile`, ... |
| `db_admin_soft_delete_profile` | `db_admin_soft_delete_student_profile`, ... |
| `db_admin_undo_soft_delete` | `db_admin_undo_soft_delete_student_profile`, ... |
| `db_admin_fetch_users_by_role` | Returns record IDs from the correct profile table based on role param |

**`db_admin_create_student_profile`** — creates new student record:
```sql
CREATE student_profile:{uuid} SET
  surname = $surname, first_name = $first_name, middle_name = $middle_name,
  display_name = $display_name, date_of_birth = $dob,
  class_enrolled = type::thing('class_levels', $class_level),
  current_class = type::thing('class_levels', $class_level),
  passport = $passport, created_at = time::now()
```

**`db_admin_update_student_profile`** — updates existing student (current_class only — class_enrolled immutable):
```sql
UPDATE student_profile:{uuid} SET
  surname = $surname, first_name = $first_name, middle_name = $middle_name,
  display_name = $display_name, date_of_birth = $dob,
  current_class = type::thing('class_levels', $class_level),
  passport = $passport, updated_at = time::now()
```

**`db_admin_create_teacher_profile`:**
```sql
CREATE teacher_profile:{uuid} SET
  surname = $surname, first_name = $first_name, middle_name = $middle_name,
  display_name = $display_name, qualifications = $qualifications,
  date_employed = $date_employed, passport = $passport, created_at = time::now()
```

**`db_admin_create_admin_profile`:**
```sql
CREATE admin_profile:{uuid} SET
  surname = $surname, first_name = $first_name, middle_name = $middle_name,
  display_name = $display_name, role_title = $role_title,
  passport = $passport, created_at = time::now()
```

**`db_admin_create_parent_profile`:**
```sql
CREATE parent_profile:{uuid} SET
  name = $name, display_name = $name,
  students = $students, passport = $passport, created_at = time::now()
```

#### `db_student.mbt` — Update profile queries:

- `db_student_fetch_profile(student_id)` — queries `SELECT *, meta::id(id) AS id FROM student_profile:{student_id} WHERE deleted_at IS NONE`
- All existing subject/term/lesson queries unchanged

#### `db_parent.mbt` — NEW:

- `db_parent_fetch_linked_students(parent_id)` — reads `parent_profile.students` array, fetches each `student_profile` for display_name, current_class.name, and counts subjects via `has_subject`
- `db_parent_fetch_student_subjects(class_level_id)` — same query as `db_student_fetch_subjects`
- `db_parent_fetch_student_terms(class_level_id)`, `db_parent_fetch_student_lessons(subject_id, term_id, class_level_id)`, `db_parent_fetch_student_lesson(lesson_id)` — identical queries to student variants

### 6. Authentik Client (`authentik_client.mbt`)

No structural changes. Existing functions (`authentik_create_user`, `authentik_set_password`, `authentik_update_profile`, `authentik_delete_user`, `authentik_add_to_group`, `authentik_set_active`) work as-is. `authentik_get_group_pk_by_name("parent")` resolves the parent group.

### 7. Passport Upload — Presigned URL Flow

#### `frontend/src/lib/server/r2.ts` — NEW:

```typescript
import { S3Client, PutObjectCommand, DeleteObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

const ALLOWED_TYPES = ['image/jpeg', 'image/png'];
const MAX_SIZE_BYTES = 5 * 1024 * 1024; // 5 MB

const r2 = new S3Client({
  region: 'auto',
  endpoint: process.env.R2_ENDPOINT_URL!,
  credentials: {
    accessKeyId: process.env.R2_ACCESS_KEY_ID!,
    secretAccessKey: process.env.R2_SECRET_ACCESS_KEY!,
  },
});

const BUCKET = process.env.R2_BUCKET_NAME!;
const PUBLIC_URL_BASE = process.env.R2_PUBLIC_URL!;

export function getR2Key(profileType: string, userId: string, contentType: string): { key: string; ext: string } {
  const ext = contentType === 'image/png' ? 'png' : 'jpg';
  return { key: `${profileType}/${userId}/passport.${ext}`, ext };
}

export function validateUploadRequest(contentType: string, fileSize: number): string | null {
  if (!ALLOWED_TYPES.includes(contentType)) return 'File type must be JPEG or PNG';
  if (fileSize > MAX_SIZE_BYTES) return 'File size must not exceed 5 MB';
  return null;
}

export async function generatePresignedUploadUrl(profileType: string, userId: string, contentType: string) {
  const error = validateUploadRequest(contentType, 0);
  if (error) throw new Error(error);
  const { key } = getR2Key(profileType, userId, contentType);
  const uploadUrl = await getSignedUrl(r2, new PutObjectCommand({
    Bucket: BUCKET,
    Key: key,
    ContentType: contentType,
  }), { expiresIn: 300 }); // 5 minutes
  const publicUrl = `${PUBLIC_URL_BASE}/${key}`;
  return { uploadUrl, publicUrl, key };
}

export async function deleteR2Object(profileType: string, userId: string, contentType: string) {
  const { key } = getR2Key(profileType, userId, contentType);
  await r2.send(new DeleteObjectCommand({ Bucket: BUCKET, Key: key }));
}
```

#### `POST /api/admin/generate-passport-upload-url` — NEW API route:
1. Admin auth + role check
2. Accept body: `{ profileType: "student"|"teacher"|"admin"|"parent", userId: string, contentType: string, fileSize: number }`
3. Validate `fileSize ≤ 5MB`, `contentType ∈ ['image/jpeg', 'image/png']`
4. Call `generatePresignedUploadUrl(profileType, userId, contentType)`
5. Return `{ uploadUrl, publicUrl }`

#### Create User Flow with Saga (SvelteKit API route):

```
1. Receive form body with all fields + passportPublicUrl (already uploaded to R2) + passportContentType

2. Call Golem agent: POST /admin/{admin_id}/create-{role}

3. If Golem returns ERROR:
   → deleteR2Object(profileType, userId, passportContentType)    // saga compensation
   → Return error to frontend

4. If Golem returns OK:
   → Done. Passport persists in R2.
```

#### Edit User Flow (no saga compensation):

```
1. Receive form body with all fields + passportPublicUrl, passportContentType (if new file uploaded)

2. Call Golem agent: POST /admin/{admin_id}/edit-{role}

3. If Golem returns ERROR:
   → No R2 compensation (same key, retry overwrites harmlessly)
   → Return error to frontend

4. If Golem returns OK:
   → Done.
```

#### Frontend Passport Upload Component Behavior:

```
1. User selects file → client-side validation: type (JPEG/PNG), size (≤ 5MB)
2. File preview shown in component
3. On form submit (NOT on file select):
   a. Client-side size recheck
   b. POST /api/admin/generate-passport-upload-url { profileType, userId, contentType, fileSize }
   c. PUT file directly to R2 via presigned uploadUrl (Content-Type header must match)
   d. Receive 200 OK → passport uploaded
   e. Include publicUrl in create/edit form submission
4. On edit: if no new file selected, pass existing passport URL unchanged
```

### 8. Admin Handler (`admin_handler.mbt`)

Replace 4 generic endpoints with 4×4 = 16 role-specific functions.

#### Create Variants

**`admin_create_student(input)`:**
1. Validate: username, display_name, email, password, role="student", class_level exists, dob valid, passport_url non-empty
2. Compute `display_name = surname + " " + first_name + (middle_name.map(" " + _) | "")`
3. Resolve class_level name → record ID via `db_admin_fetch_class_level_by_name`
4. Saga (`@api.with_atomic_operation`):
   a. `authentik_create_user(username, display_name, email, password, is_active, group_pk="student")` → returns (pk, uuid)
   b. `authentik_set_password(pk, password)`
   c. `db_admin_create_student_profile(uuid, surname, first_name, middle_name, display_name, dob, class_level_id, passport_url)` — class_enrolled = current_class = class_level_id
5. On saga failure: if pk > 0, compensate `authentik_delete_user(pk)`
6. Fire-and-forget: `StudentAgentClient::trigger_invalidate_cache(uuid, "profile")`
7. Return `CreateUserResponse { pk, uuid, username, name: display_name, email, is_active, groups }`

**`admin_create_teacher(input)`:**
1. Validate: username, display_name, email, password, role="teacher", qualifications valid (each must be an existing credentials record ID), passport_url
2. Compute display_name from parts
3. Saga:
   a. Authentik create user + set password
   b. `authentik_add_to_group(pk, "teacher")`
   c. `db_admin_create_teacher_profile(uuid, ..., qualifications_ids, date_employed, passport_url)`
4. On failure: compensate Authentik delete
5. Fire-and-forget: `TeacherAgentClient::trigger_invalidate_cache(uuid, "class_groups")`

**`admin_create_admin(input)`:**
1. Validate: username, display_name, email, password, role="admin", role_title if provided, passport_url
2. Same saga pattern with group="admin", `db_admin_create_admin_profile`
3. No cache invalidation (Admin agent is singleton)

**`admin_create_parent(input)`:**
1. Validate: username, name, email, password, role="parent", students array (each must be valid student_profile record with deleted_at IS NONE), passport_url
2. Saga:
   a. Authentik create user + set password
   b. `authentik_add_to_group(pk, "parent")`
   c. `db_admin_create_parent_profile(uuid, name, student_ids, passport_url)`
3. On failure: compensate Authentik delete
4. Fire-and-forget: `ParentAgentClient::trigger_invalidate_cache(uuid, "linked_students")`

#### Edit Variants

**`admin_edit_student(input)`:**
1. Validate: target_user_id, authentik_pk, class_level, passport_url
2. Resolve target group PK for role changes
3. Compute display_name from parts
4. Saga:
   a. `authentik_update_profile(pk, username, display_name, email)`
   b. If password provided: `authentik_set_password(pk, password)`
   c. Group management: remove from old groups, add to "student" group
   d. `db_admin_update_student_profile(uuid, surname, first_name, middle_name, display_name, dob, class_level_id, passport_url)` — only current_class updates, class_enrolled unchanged
5. No compensation needed (all operations idempotent)
6. Fire-and-forget invalidate student cache

**`admin_edit_teacher`, `admin_edit_admin`, `admin_edit_parent`** — same pattern with role-specific fields.

#### Delete Variants (4 total)

**`admin_delete_student(input)`:**
1. Saga:
   a. `db_admin_soft_delete_student_profile(uuid)` — UPDATE SET deleted_at = time::now()
   b. `authentik_delete_user(pk)`
2. On failure: `db_admin_undo_soft_delete_student_profile(uuid)` — UPDATE SET deleted_at = NONE
3. Fire-and-forget invalidate student cache

#### Profile Fetch Variants (4 total)

Direct record ID lookups: `SELECT *, meta::id(id) AS id FROM {role}_profile:{uuid} WHERE deleted_at IS NONE`

#### Credentials Management

**`admin_fetch_credentials()`** — `SELECT *, meta::id(id) AS id FROM credentials WHERE active = true`

**`admin_create_credential(name)`** — `CREATE credentials:{slug} SET name = $name`

### 9. Admin Agent (`admin_agent.mbt`)

Replace 4 generic user endpoints with 16 role-specific endpoints:

| Old Endpoint | New Endpoints |
|---|---|
| `POST /create-user` | `POST /create-student`, `POST /create-teacher`, `POST /create-admin`, `POST /create-parent` |
| `POST /edit-user` | `POST /edit-student`, `POST /edit-teacher`, `POST /edit-admin`, `POST /edit-parent` |
| `POST /delete-user` | `POST /delete-student`, `POST /delete-teacher`, `POST /delete-admin`, `POST /delete-parent` |
| `GET /get-profile` | `GET /get-student-profile`, `GET /get-teacher-profile`, `GET /get-admin-profile`, `GET /get-parent-profile` |

Plus new endpoints:
- `GET /credentials` — list all credentials
- `POST /create-credential` — create a new credential entry

Each endpoint remains 3-5 lines — validation and business logic in handler, thin wrapper in agent.

### 10. Parent Agent (`parent_agent.mbt`, `parent_handler.mbt`, `db_parent.mbt` — NEW)

**Agent struct:**
```mbt
struct ParentAgent {
  parent_id : String
  config : @config.Config[SharedConfig]
  cache : CacheSystem
}
```

**Mount:** `/parent/{parent_id}` — durable.

#### Endpoints

| Method | Path | Type | Implementation |
|---|---|---|---|
| `GET` | `/ping` | Read | `"parent online"` |
| `GET` | `/my-students` | Read | Query `parent_profile.students` → fetch each `student_profile` for name, class, subject count |
| `GET` | `/student-subjects?student_id=` | Read | Verify student_id in students array → query SurrealDB for subjects |
| `GET` | `/student-terms?student_id=` | Read | Verify → query SurrealDB for terms |
| `GET` | `/student-lessons?student_id=&subject_id=&term_id=` | Read | Verify → query SurrealDB for lessons |
| `GET` | `/student-lesson?student_id=&lesson_id=` | Read | Verify → query SurrealDB for lesson content |
| `POST` | `/student-submit-assignment?student_id=` | **Write** | Verify → RPC `StudentAgentClient::scoped(student_id, submit_assignment)` |
| `POST` | `/invalidate-cache?key=` | Admin | Invalidate cache |

**Verification pattern (all student endpoints):**
```
1. Fetch parent profile from cache or DB
2. Check requested student_id is in parent.students array
3. If not in array → return NOT_FOUND error
4. If in array → execute read/write operation
```

Cache: TTL 600s. Backbone key: `"linked_students"` → invalidates all. Cache keys:
- `"linked_students"` — students list
- `"student_subjects:{student_id}"` → depends on `"linked_students"`
- `"student_terms:{student_id}"` → depends on `"linked_students"`
- `"student_lessons:{student_id}|{subject_id}|{term_id}"` → depends on `"linked_students"`
- `"student_lesson:{student_id}|{lesson_id}"` → depends on `"student_lessons:..."`

### 11. Golem Config (`golem.yaml`)

Register ParentAgent in the `app-agents` component template alongside existing agents. After registration, run `golem-sdk-tools agents` to regenerate `golem_agents.mbt` and `golem_clients.mbt` with ParentAgent RPC stubs.

### 12. Student & Teacher Agent Updates

**Student Agent (`student_handler.mbt`):**
- `get_class_level()` reads from `student_profile:{student_id}` (direct record ID lookup) instead of `user_profile WHERE auth_id=`
- `StudentProfile` struct gains `surname, first_name, middle_name, display_name, date_of_birth, passport`
- Cache key `"profile"` unchanged

**Teacher Agent:** No structural changes (teacher agent doesn't read its own profile — constructs state from `teacher_assignment` table).

### 13. Frontend — Shared Components

#### `$lib/components/PassportUpload.svelte` — NEW:
- Props: `currentUrl: string | null`, `disabled: boolean`
- Emits: `passportPublicUrl: string | null`, `passportContentType: string | null`
- States: empty (drag zone with dashed border), preview (image thumbnail + "Remove" button), uploading (spinner overlay)
- Client-side validation: JPEG/PNG only, ≤ 5MB
- Upload happens in parent form's submit handler (NOT on file select)

#### `$lib/components/NameFields.svelte` — NEW:
- Props: `bind:surname`, `bind:first_name`, `bind:middle_name` (all bindable)
- Three labeled inputs in responsive grid

#### `$lib/components/CredentialsSelect.svelte` — NEW:
- Props: `bind:selected: string[]` (credentials record IDs)
- Fetches credentials list from `GET /api/admin/credentials`
- Multi-select searchable dropdown (same pattern as teacher subject-assign combo)
- Selected credentials shown as removable badges

#### Split UserTable into 4 Role-Specific Components:

| Component | Columns |
|---|---|
| `StudentUserTable.svelte` | Name, Email, Class, Auth Status, Activate, Edit, Delete |
| `TeacherUserTable.svelte` | Name, Email, Auth Status, Activate, Edit, Assign, Delete |
| `AdminUserTable.svelte` | Name, Email, Role Title, Auth Status, Activate, Edit, Delete |
| `ParentUserTable.svelte` | Name, Email, Students (#), Auth Status, Activate, Edit, Delete |

Each has its own create/edit dialog with role-specific form fields (name parts, passport upload, credentials select, student multi-select, etc.).

### 14. Frontend — Parent User Management Page

**New route:** `/admin/users/parents/`

- `+page.server.ts` — fetches all users from Authentik, filters to "parent" group
- `+page.svelte` — renders `<ParentUserTable>`

**Parent edit dialog — Students multi-select:**
- Fetches all `student_profile` records via `GET /api/admin/students/list`
- Searchable dropdown (same pattern as teacher subject-assign combo)
- Selected students appear as removable badges
- Form validates `students.length > 0` before submit

**Sidebar (`+layout.svelte`):** Add "Parents" entry in Users section, between Teachers and Admin.

### 15. Frontend — Parent LMS Flow

**New route group:** `/parent/`

| Route | Data Source | Component |
|---|---|---|
| `/parent/` | `GET /api/parent/my-students` | Student card grid (display_name, class badge, subject count) |
| `/parent/{studentId}/` | `GET /api/parent/student-subjects?student_id=` | Subject card grid (same as student LMS) |
| `/parent/{studentId}/{subjectId}/` | `GET /api/parent/student-terms?student_id=` | Term card grid |
| `/parent/{studentId}/{subjectId}/{termId}/` | `GET /api/parent/student-lessons?student_id=&subject=&term=` | Lesson numbered list |
| `/parent/{studentId}/{subjectId}/{termId}/{lessonId}/` | `GET /api/parent/student-lesson?student_id=&lesson_id=` | `LessonPage.svelte` (full 2-tab mirror including assessments) |

Breadcrumbs: `My Children > {Student Name} > {Subject} > {Term} > {Lesson}`

Parent sidebar (visible to parent role only):
```
Navigation
  └── My Children    → /parent
```

**New proxy routes** (under `routes/api/parent/`):
- `GET /api/parent/my-students`
- `GET /api/parent/student-subjects`
- `GET /api/parent/student-terms`
- `GET /api/parent/student-lessons`
- `GET /api/parent/student-lesson`
- `POST /api/parent/student-submit-assignment`

**`golem.ts`:** Add `proxyToParent(userId, path, ...)` alongside existing proxy functions.

**`hooks.server.ts` + `+layout.server.ts`:** Add parent role and `/parent/*` to allowed routes.

### 16. Frontend — Updated Admin API Routes

Replace generic admin user routes with role-specific variants:

| Old | New |
|---|---|
| `POST /api/admin/users` | `POST /api/admin/users/students`, `/teachers`, `/admin-role`, `/parents` |
| `POST .../{uuid}/edit-profile` | `POST /api/admin/users/students/{uuid}/edit-profile`, ... |
| `DELETE .../{pk}` | `DELETE /api/admin/users/students/{pk}`, ... |
| `GET .../{uuid}/profile` | `GET /api/admin/users/students/{uuid}/profile`, ... |

New routes:
- `POST /api/admin/generate-passport-upload-url` — returns presigned URL for browser → R2 upload
- `GET /api/admin/credentials` — lists all credentials
- `POST /api/admin/credentials` — creates a new credential
- `GET /api/admin/students/list` — returns all student profile IDs + names (for parent student-selection dropdown)

### 17. Docs Update

- **`architecture.md`:** Replace `user_profile` with four new tables in Storage Model. Add ParentAgent row to agent table. Add credentials table. Update sidebar structure. Update invariants (profile check now on role-specific tables). Add `parent_agent.mbt`, `parent_handler.mbt`, `db_parent.mbt`, `types_parent.mbt` to monorepo structure.
- **`project-overview.md`:** Add parent role to authorization table. Add parent features to Features Breakdown. Move parent portal from Out of Scope to In Scope.
- **`code-standards.md`:** No changes needed.
- **`progress-tracker.md`:** Record HF-10.

---

## Dependencies

### New npm Packages (frontend)
```bash
pnpm add @aws-sdk/client-s3 @aws-sdk/s3-request-presigner
```

### New MoonBit Packages (backend)
None.

### External Setup (manual, one-time)
- **Cloudflare R2:** Create bucket. Set CORS to allow PUT from frontend origin. Create API token with Object Read & Write. Set custom domain or public URL.
- **Authentik:** Create "parent" group.
- **SurrealDB:** Drop `user_profile` table before applying new schema.

### Environment Variables (SvelteKit `.env`)
```bash
R2_ACCESS_KEY_ID=
R2_SECRET_ACCESS_KEY=
R2_BUCKET_NAME=
R2_PUBLIC_URL=          # e.g., https://pub-xxx.r2.dev or custom domain
R2_ENDPOINT_URL=        # e.g., https://{account_id}.r2.cloudflarestorage.com
```

### Golem Secrets (`golem.yaml`)
No new secrets needed (R2 stays in SvelteKit).

---

## Verification Checklist

- [ ] `moon check --target wasm` — 0 errors
- [ ] `golem build` — 0 errors
- [ ] `pnpm check` — 0 errors, warning baseline unchanged
- [ ] `pnpm build` — succeeds
- [ ] Create student: profile in `student_profile` table, all fields correct, `class_enrolled == current_class`
- [ ] Edit student: `current_class` updates, `class_enrolled` unchanged
- [ ] Create teacher with qualifications array of credentials record IDs
- [ ] Create admin with role_title field
- [ ] Create parent with students array (must have ≥ 1 student)
- [ ] Parent creation rejected if students array is empty
- [ ] Parent login via Authentik → sees student list with names, classes, subject counts
- [ ] Parent clicks student → full LMS mirror (subjects → terms → lessons → lesson content, 2 tabs)
- [ ] Parent can submit assignment on behalf of student (write mirror)
- [ ] Parent denied access to student not in their `students` array
- [ ] Passport upload: presigned URL generated, file uploaded directly to R2, URL stored in profile
- [ ] Passport preview visible in edit dialog
- [ ] Passport upload rejected if type not JPEG/PNG or size > 5MB
- [ ] Create saga: if Golem agent fails after R2 upload, R2 object is deleted (compensation)
- [ ] Edit saga: no R2 compensation needed (same key, retry overwrites)
- [ ] Delete student: soft-deleted in profile, Authentik user removed, R2 passport file remains (cleanup deferred)
- [ ] Delete cascade: parent's students array should not reference deleted students (or parent profile marks stale)
- [ ] Credentials: create credential, list in teacher form, select for teacher, view in teacher edit
- [ ] Teacher subject assignment still works
- [ ] Session term management still works
- [ ] Cache invalidation fires on create/edit/delete for all roles
- [ ] All sidebar links correct for all 5 roles (admin, teacher, student, parent, unauthenticated)
- [ ] Breadcrumbs correct for all new routes
- [ ] Toast notifications for all CRUD operations
- [ ] No regressions on existing student LMS, teacher classes, admin configuration
