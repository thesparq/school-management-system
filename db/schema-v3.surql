-- Schema V3: Graph Edges and Strict Typing

-- 1. DEFINE the `teaches` edge table
DEFINE TABLE teaches TYPE RELATION FROM teacher_profile TO has_subject;
DEFINE FIELD session_term ON teaches TYPE record<session_term>;
DEFINE FIELD assigned_at  ON teaches TYPE datetime DEFAULT time::now();
DEFINE FIELD deleted_at   ON teaches TYPE option<datetime>;

-- Add a unique index to prevent duplicate assignments for the same term
DEFINE INDEX idx_teaches_unique ON teaches COLUMNS in, out, session_term UNIQUE;

-- 2. MIGRATE DATA from `teacher_assignment` to `teaches`
-- This reads the old linking table and creates proper graph edges
LET $assignments = (SELECT * FROM teacher_assignment);
FOR $assignment IN $assignments {
    -- We use string::contains as a safeguard to ensure it's a record link, though type::thing handles it well.
    LET $teacher = $assignment.teacher_id;
    LET $subject = $assignment.has_subject;
    IF $teacher != NONE AND $subject != NONE {
        RELATE $teacher -> teaches -> $subject CONTENT {
            session_term: $assignment.session_term,
            assigned_at: $assignment.assigned_at,
            deleted_at: $assignment.deleted_at
        };
    };
};

-- 3. REMOVE the old linking table (Optional, but good practice. We can keep it for now as a backup if needed, but the plan was to remove it)
-- REMOVE TABLE teacher_assignment;

-- 4. STRICT TYPING for AI Assessment JSON
-- We define exactly what the JSON structure of `questions` must look like in `lesson_assessments`
-- This prevents agents from storing malformed hallucinated JSON.
DEFINE FIELD IF NOT EXISTS questions ON lesson_assessments TYPE option<array<object>>;
DEFINE FIELD IF NOT EXISTS questions.*.type ON lesson_assessments TYPE string ASSERT $value INSIDE ['mcq', 'boolean', 'short_answer', 'essay'];
DEFINE FIELD IF NOT EXISTS questions.*.question ON lesson_assessments TYPE string;
DEFINE FIELD IF NOT EXISTS questions.*.options ON lesson_assessments TYPE option<array<string>>;
DEFINE FIELD IF NOT EXISTS questions.*.answer ON lesson_assessments TYPE string;
DEFINE FIELD IF NOT EXISTS questions.*.explanation ON lesson_assessments TYPE option<string>;
DEFINE FIELD IF NOT EXISTS questions.*.marks ON lesson_assessments TYPE option<number>;

-- Do the same for general_assessments
DEFINE FIELD IF NOT EXISTS questions.*.type ON general_assessments TYPE string ASSERT $value INSIDE ['mcq', 'boolean', 'short_answer', 'essay'];
DEFINE FIELD IF NOT EXISTS questions.*.question ON general_assessments TYPE string;
DEFINE FIELD IF NOT EXISTS questions.*.options ON general_assessments TYPE option<array<string>>;
DEFINE FIELD IF NOT EXISTS questions.*.answer ON general_assessments TYPE string;
DEFINE FIELD IF NOT EXISTS questions.*.explanation ON general_assessments TYPE option<string>;
DEFINE FIELD IF NOT EXISTS questions.*.marks ON general_assessments TYPE option<number>;

-- 5. ELIMINATE `credentials` table (Migrating to string arrays)
-- The `credentials` table was just an enum of strings. We can store this as an array of strings on the teacher directly.
DEFINE FIELD IF NOT EXISTS qualifications ON teacher_profile TYPE option<array<string>>;
-- Migrate data
LET $teachers = (SELECT id, qualifications FROM teacher_profile);
FOR $t IN $teachers {
    IF $t.qualifications != NONE {
        -- Map record links to their names
        LET $string_quals = (SELECT VALUE name FROM credentials WHERE id IN $t.qualifications);
        UPDATE $t.id SET qualifications = $string_quals;
    };
};
