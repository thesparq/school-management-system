-- Schema V5: admission numbers and staff ids — NOT APPLIED TO PROD, and not safe to apply as it stands.
--
-- Prod never ran this file: `student_profile` there has eleven fields and no `admission_number`, its
-- `teacher_profile` and `admin_profile` have no `staff_id`, and there is no `id_sequences` table. The backend
-- (`roc-backend/main.roc`) writes none of those columns either, yet they are declared here as required
-- non-empty strings with unique indexes — so a fresh database with this file applied refuses `POST /api/users`
-- for a Student/Teacher/Admin ("Couldn't coerce value for field `admission_number` of `student_profile:…`:
-- Expected `string` but found `NONE`"), and the login is rolled back. The `permissions` array at the end of
-- this file is unread and unwritten by the app too, but it has a default, so it does not break a write.
--
-- Reconcile before replaying the lineage: the code writes the columns, or this file is retired.
-- `db/schema-v8-ids.surql` supersedes this file: the numbers are written now, as integers (`option<int>`,
-- seeded with `UPSERT`, and no `DELETE`), by that shape — the backend and the sandbox fixture follow v8.
-- `docs/architecture.md` ("Storage model") carries the same note.

DEFINE TABLE IF NOT EXISTS id_sequences SCHEMAFULL;
DEFINE FIELD IF NOT EXISTS type ON id_sequences TYPE string ASSERT $value IN ["student", "staff", "admin"];
DEFINE FIELD IF NOT EXISTS prefix ON id_sequences TYPE string;
DEFINE FIELD IF NOT EXISTS current_value ON id_sequences TYPE int DEFAULT 0;
DEFINE FIELD IF NOT EXISTS created_at ON id_sequences TYPE datetime DEFAULT time::now();
DEFINE INDEX IF NOT EXISTS idx_id_seq_type ON id_sequences COLUMNS type UNIQUE;

-- We specify the record ID manually so it acts as an UPSERT automatically
UPDATE id_sequences:student SET type = "student", prefix = "JES", current_value = 0 WHERE current_value = NONE;
UPDATE id_sequences:staff SET type = "staff", prefix = "EMP", current_value = 0 WHERE current_value = NONE;
UPDATE id_sequences:admin SET type = "admin", prefix = "ADM", current_value = 0 WHERE current_value = NONE;

DEFINE FIELD IF NOT EXISTS admission_number ON student_profile TYPE string ASSERT $value != NONE AND $value != "";
DEFINE INDEX IF NOT EXISTS idx_student_admission ON student_profile COLUMNS admission_number UNIQUE;

DEFINE FIELD IF NOT EXISTS staff_id ON teacher_profile TYPE string ASSERT $value != NONE AND $value != "";
DEFINE INDEX IF NOT EXISTS idx_teacher_staffid ON teacher_profile COLUMNS staff_id UNIQUE;

DEFINE FIELD IF NOT EXISTS staff_id ON admin_profile TYPE string ASSERT $value != NONE AND $value != "";
DEFINE INDEX IF NOT EXISTS idx_admin_staffid ON admin_profile COLUMNS staff_id UNIQUE;

DEFINE FIELD IF NOT EXISTS permissions ON admin_profile TYPE array<string> DEFAULT [];
