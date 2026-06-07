-- ============================================================
-- Schema v3: Assessments, Compositions, Submissions
-- Adds to schema-v2 tables without modifying existing ones.
-- Idempotent: safe to re-run.
-- ============================================================

-- Lesson-scoped assessments
DEFINE TABLE IF NOT EXISTS lesson_assessments SCHEMAFULL
  PERMISSIONS FOR select, create, update, delete NONE;

DEFINE FIELD IF NOT EXISTS lesson           ON lesson_assessments TYPE record<lessons> ASSERT $value != NONE;
DEFINE FIELD IF NOT EXISTS title            ON lesson_assessments TYPE string ASSERT $value != NONE;
DEFINE FIELD IF NOT EXISTS description      ON lesson_assessments TYPE option<string>;
DEFINE FIELD IF NOT EXISTS questions        ON lesson_assessments TYPE array<object>;
DEFINE FIELD IF NOT EXISTS total_mark       ON lesson_assessments TYPE int;
DEFINE FIELD IF NOT EXISTS max_resubmissions ON lesson_assessments TYPE int DEFAULT 0;
DEFINE FIELD IF NOT EXISTS deadline         ON lesson_assessments TYPE option<datetime>;
DEFINE FIELD IF NOT EXISTS active           ON lesson_assessments TYPE bool DEFAULT false;
DEFINE FIELD IF NOT EXISTS scheduled_at     ON lesson_assessments TYPE option<datetime>;
DEFINE FIELD IF NOT EXISTS created_by       ON lesson_assessments TYPE record<teacher_profile>;
DEFINE FIELD IF NOT EXISTS created_at       ON lesson_assessments TYPE datetime DEFAULT time::now();
DEFINE FIELD IF NOT EXISTS updated_at       ON lesson_assessments TYPE option<datetime>;
DEFINE FIELD IF NOT EXISTS deleted_at       ON lesson_assessments TYPE option<datetime>;

DEFINE INDEX IF NOT EXISTS idx_la_lesson ON lesson_assessments COLUMNS lesson;

-- General (term-scoped) assessments
DEFINE TABLE IF NOT EXISTS general_assessments SCHEMAFULL
  PERMISSIONS FOR select, create, update, delete NONE;

DEFINE FIELD IF NOT EXISTS session_term      ON general_assessments TYPE record<session_term> ASSERT $value != NONE;
DEFINE FIELD IF NOT EXISTS subject           ON general_assessments TYPE record<subjects> ASSERT $value != NONE;
DEFINE FIELD IF NOT EXISTS title             ON general_assessments TYPE string ASSERT $value != NONE;
DEFINE FIELD IF NOT EXISTS description       ON general_assessments TYPE option<string>;
DEFINE FIELD IF NOT EXISTS percentage_weight ON general_assessments TYPE int;
DEFINE FIELD IF NOT EXISTS questions         ON general_assessments TYPE option<array<object>>;
DEFINE FIELD IF NOT EXISTS total_mark        ON general_assessments TYPE int;
DEFINE FIELD IF NOT EXISTS max_resubmissions  ON general_assessments TYPE int DEFAULT 0;
DEFINE FIELD IF NOT EXISTS deadline          ON general_assessments TYPE option<datetime>;
DEFINE FIELD IF NOT EXISTS active            ON general_assessments TYPE bool DEFAULT false;
DEFINE FIELD IF NOT EXISTS scheduled_at      ON general_assessments TYPE option<datetime>;
DEFINE FIELD IF NOT EXISTS created_by        ON general_assessments TYPE record<teacher_profile>;
DEFINE FIELD IF NOT EXISTS created_at        ON general_assessments TYPE datetime DEFAULT time::now();
DEFINE FIELD IF NOT EXISTS updated_at        ON general_assessments TYPE option<datetime>;
DEFINE FIELD IF NOT EXISTS deleted_at        ON general_assessments TYPE option<datetime>;

DEFINE INDEX IF NOT EXISTS idx_ga_st_subj ON general_assessments COLUMNS session_term, subject;

-- Composition: general assessment -> lesson assessment
DEFINE TABLE IF NOT EXISTS compositions SCHEMAFULL
  PERMISSIONS FOR select, create, update, delete NONE;

DEFINE FIELD IF NOT EXISTS general_assessment ON compositions TYPE record<general_assessments> ASSERT $value != NONE;
DEFINE FIELD IF NOT EXISTS lesson_assessment  ON compositions TYPE record<lesson_assessments> ASSERT $value != NONE;
DEFINE FIELD IF NOT EXISTS weight_pct         ON compositions TYPE float;
DEFINE FIELD IF NOT EXISTS created_at         ON compositions TYPE datetime DEFAULT time::now();

DEFINE INDEX IF NOT EXISTS idx_comp_ga ON compositions COLUMNS general_assessment;

-- Polymorphic submissions table (serves both assessment types)
DEFINE TABLE IF NOT EXISTS submissions SCHEMAFULL
  PERMISSIONS FOR select, create, update, delete NONE;

DEFINE FIELD IF NOT EXISTS assessment_type  ON submissions TYPE string;
DEFINE FIELD IF NOT EXISTS assessment_id    ON submissions TYPE string;
DEFINE FIELD IF NOT EXISTS student          ON submissions TYPE record<student_profile> ASSERT $value != NONE;
DEFINE FIELD IF NOT EXISTS iteration        ON submissions TYPE int DEFAULT 0;
DEFINE FIELD IF NOT EXISTS status           ON submissions TYPE string;
DEFINE FIELD IF NOT EXISTS submitted_at     ON submissions TYPE datetime DEFAULT time::now();
DEFINE FIELD IF NOT EXISTS answers          ON submissions TYPE array<object>;
DEFINE FIELD IF NOT EXISTS total_mark       ON submissions TYPE int;
DEFINE FIELD IF NOT EXISTS scored_mark      ON submissions TYPE option<int>;
DEFINE FIELD IF NOT EXISTS grade_released_at ON submissions TYPE option<datetime>;

DEFINE INDEX IF NOT EXISTS idx_sub_student      ON submissions COLUMNS student;
DEFINE INDEX IF NOT EXISTS idx_sub_assessment   ON submissions COLUMNS assessment_type, assessment_id;
DEFINE INDEX IF NOT EXISTS idx_sub_unique       ON submissions COLUMNS assessment_type, assessment_id, student, iteration UNIQUE;

-- Lessons table additions (idempotent)
DEFINE FIELD IF NOT EXISTS version     ON lessons TYPE int DEFAULT 1;
DEFINE FIELD IF NOT EXISTS updated_at  ON lessons TYPE option<datetime>;

-- Verification
SELECT count() FROM lesson_assessments GROUP ALL;
SELECT count() FROM general_assessments GROUP ALL;
SELECT count() FROM compositions GROUP ALL;
SELECT count() FROM submissions GROUP ALL;
