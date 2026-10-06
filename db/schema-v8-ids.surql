-- Schema V8: School numbers — a student's admission number and a staff member's staff id
--
-- v5 declared these columns as required non-empty strings, seeded `id_sequences` with `DELETE` + a bare
-- `current_value = 0`, and was never applied to prod: it declares columns the backend did not write, so
-- a database with it applied refused every Student/Teacher/Admin create. **This file supersedes both v5
-- files**, which are NOT APPLIED to prod and are not safe to replay; the numbers are written now, as
-- integers, by this shape. `docs/architecture.md` ("Storage model") carries the rule.
--
-- What is stored is the number alone — an integer, with no prefix and no padding — one series per class
-- of member: a student's `admission_number` from `id_sequences:student`, and a staff member's `staff_id`
-- from `id_sequences:staff`, which teachers and admins share so that a role change keeps the number a
-- person already holds (a teacher made an admin reuses their `staff_id`; a student who becomes staff is
-- given a fresh staff number). The written form (`JES-000123`, `EMP-000045`) is the backend's, rendered
-- in one place (`roc-backend/main.roc`): the prefix is in no stored row and in no page.
--
-- Additive only, in the lineage's usual shape: `IF NOT EXISTS` throughout, no `REMOVE`, and the two
-- sequence rows are seeded with `UPSERT … SET type = …` so re-applying this file cannot reset a live
-- counter (v5's seed opens with `DELETE id_sequences`, which is why it cannot be replayed).
-- `roc-frontend/tests/e2e/fixtures/sandbox-schema.surql` mirrors it.

DEFINE TABLE IF NOT EXISTS id_sequences SCHEMAFULL;
-- One row per series, and the type is what names the series: the whole row is a counter, so a value
-- outside the two names would be a series nothing allocates from.
DEFINE FIELD IF NOT EXISTS type ON id_sequences TYPE string ASSERT $value IN ["student", "staff"];
DEFINE FIELD IF NOT EXISTS current_value ON id_sequences TYPE int DEFAULT 0;
DEFINE FIELD IF NOT EXISTS created_at ON id_sequences TYPE datetime DEFAULT time::now();
DEFINE INDEX IF NOT EXISTS idx_id_seq_type ON id_sequences COLUMNS type UNIQUE;

UPSERT id_sequences:student SET type = "student";
UPSERT id_sequences:staff SET type = "staff";

-- An optional integer: a row that predates the numbers (or one written by hand, as a test does) has
-- none, and the unique index allows any number of rows without one.
DEFINE FIELD IF NOT EXISTS admission_number ON student_profile TYPE option<int>;
DEFINE INDEX IF NOT EXISTS idx_student_admission ON student_profile COLUMNS admission_number UNIQUE;

DEFINE FIELD IF NOT EXISTS staff_id ON teacher_profile TYPE option<int>;
DEFINE INDEX IF NOT EXISTS idx_teacher_staff_id ON teacher_profile COLUMNS staff_id UNIQUE;

DEFINE FIELD IF NOT EXISTS staff_id ON admin_profile TYPE option<int>;
DEFINE INDEX IF NOT EXISTS idx_admin_staff_id ON admin_profile COLUMNS staff_id UNIQUE;
