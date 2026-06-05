-- ============================================================
-- HF-10 — SurrealDB Schema v3
-- Role-specialized profile tables + credentials lookup.
-- Record IDs = {table}:{auth_uuid} — no separate auth_id field.
-- Idempotent: safe to re-run (uses IF NOT EXISTS).
-- Run AFTER schema-v2.surql (depends on class_levels table).
-- ============================================================

---------------
-- Step 0: Clean up old monolithic user_profile table
---------------

REMOVE TABLE user_profile;

---------------
-- Step 1: student_profile
-- Record ID: student_profile:{auth_uuid}
---------------

DEFINE TABLE IF NOT EXISTS student_profile SCHEMAFULL
  PERMISSIONS FOR select, create, update, delete NONE;

DEFINE FIELD IF NOT EXISTS surname        ON student_profile TYPE string
  ASSERT $value != NONE;
DEFINE FIELD IF NOT EXISTS first_name     ON student_profile TYPE string
  ASSERT $value != NONE;
DEFINE FIELD IF NOT EXISTS middle_name    ON student_profile TYPE option<string>;
DEFINE FIELD IF NOT EXISTS display_name   ON student_profile TYPE string
  ASSERT $value != NONE;
DEFINE FIELD IF NOT EXISTS date_of_birth  ON student_profile TYPE datetime
  ASSERT $value != NONE;
DEFINE FIELD IF NOT EXISTS class_enrolled ON student_profile TYPE record<class_levels>
  ASSERT $value != NONE;
DEFINE FIELD IF NOT EXISTS current_class  ON student_profile TYPE record<class_levels>
  ASSERT $value != NONE;
DEFINE FIELD IF NOT EXISTS passport       ON student_profile TYPE string
  ASSERT $value != NONE;
DEFINE FIELD IF NOT EXISTS created_at     ON student_profile TYPE datetime DEFAULT time::now();
DEFINE FIELD IF NOT EXISTS updated_at     ON student_profile TYPE option<datetime>;
DEFINE FIELD IF NOT EXISTS deleted_at     ON student_profile TYPE option<datetime>;

---------------
-- Step 2: teacher_profile
-- Record ID: teacher_profile:{auth_uuid}
---------------

DEFINE TABLE IF NOT EXISTS teacher_profile SCHEMAFULL
  PERMISSIONS FOR select, create, update, delete NONE;

DEFINE FIELD IF NOT EXISTS surname       ON teacher_profile TYPE string
  ASSERT $value != NONE;
DEFINE FIELD IF NOT EXISTS first_name    ON teacher_profile TYPE string
  ASSERT $value != NONE;
DEFINE FIELD IF NOT EXISTS middle_name   ON teacher_profile TYPE option<string>;
DEFINE FIELD IF NOT EXISTS display_name  ON teacher_profile TYPE string
  ASSERT $value != NONE;
DEFINE FIELD IF NOT EXISTS qualifications ON teacher_profile TYPE option<array<record<credentials>>>;
DEFINE FIELD IF NOT EXISTS date_employed ON teacher_profile TYPE option<datetime>;
DEFINE FIELD IF NOT EXISTS passport      ON teacher_profile TYPE string
  ASSERT $value != NONE;
DEFINE FIELD IF NOT EXISTS created_at    ON teacher_profile TYPE datetime DEFAULT time::now();
DEFINE FIELD IF NOT EXISTS updated_at    ON teacher_profile TYPE option<datetime>;
DEFINE FIELD IF NOT EXISTS deleted_at    ON teacher_profile TYPE option<datetime>;

---------------
-- Step 3: admin_profile
-- Record ID: admin_profile:{auth_uuid}
---------------

DEFINE TABLE IF NOT EXISTS admin_profile SCHEMAFULL
  PERMISSIONS FOR select, create, update, delete NONE;

DEFINE FIELD IF NOT EXISTS surname      ON admin_profile TYPE string
  ASSERT $value != NONE;
DEFINE FIELD IF NOT EXISTS first_name   ON admin_profile TYPE string
  ASSERT $value != NONE;
DEFINE FIELD IF NOT EXISTS middle_name  ON admin_profile TYPE option<string>;
DEFINE FIELD IF NOT EXISTS display_name ON admin_profile TYPE string
  ASSERT $value != NONE;
DEFINE FIELD IF NOT EXISTS role_title   ON admin_profile TYPE option<string>;
DEFINE FIELD IF NOT EXISTS passport     ON admin_profile TYPE string
  ASSERT $value != NONE;
DEFINE FIELD IF NOT EXISTS created_at   ON admin_profile TYPE datetime DEFAULT time::now();
DEFINE FIELD IF NOT EXISTS updated_at   ON admin_profile TYPE option<datetime>;
DEFINE FIELD IF NOT EXISTS deleted_at   ON admin_profile TYPE option<datetime>;

---------------
-- Step 4: parent_profile
-- Record ID: parent_profile:{auth_uuid}
---------------

DEFINE TABLE IF NOT EXISTS parent_profile SCHEMAFULL
  PERMISSIONS FOR select, create, update, delete NONE;

DEFINE FIELD IF NOT EXISTS name         ON parent_profile TYPE string
  ASSERT $value != NONE;
DEFINE FIELD IF NOT EXISTS display_name ON parent_profile TYPE string
  ASSERT $value != NONE;
DEFINE FIELD IF NOT EXISTS students     ON parent_profile TYPE array<record<student_profile>>
  ASSERT array::len($value) > 0;
DEFINE FIELD IF NOT EXISTS passport     ON parent_profile TYPE string
  ASSERT $value != NONE;
DEFINE FIELD IF NOT EXISTS created_at   ON parent_profile TYPE datetime DEFAULT time::now();
DEFINE FIELD IF NOT EXISTS updated_at   ON parent_profile TYPE option<datetime>;
DEFINE FIELD IF NOT EXISTS deleted_at   ON parent_profile TYPE option<datetime>;

---------------
-- Step 5: credentials — teacher qualification lookup table
-- Record ID: credentials:{slug}
---------------

DEFINE TABLE IF NOT EXISTS credentials SCHEMAFULL
  PERMISSIONS FOR select, create, update, delete NONE;

DEFINE FIELD IF NOT EXISTS name   ON credentials TYPE string
  ASSERT $value != NONE;
DEFINE FIELD IF NOT EXISTS active ON credentials TYPE bool DEFAULT true;

DEFINE INDEX IF NOT EXISTS idx_credentials_name ON credentials COLUMNS name UNIQUE;

---------------
-- Verification
---------------

SELECT count() FROM student_profile GROUP ALL;
SELECT count() FROM teacher_profile GROUP ALL;
SELECT count() FROM admin_profile GROUP ALL;
SELECT count() FROM parent_profile GROUP ALL;
SELECT count() FROM credentials GROUP ALL;
