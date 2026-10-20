# Throwaway database for the admin check: the prod profile tables (SCHEMAFULL, same fields and
# assertions), the school's eleven class levels with the stage each one belongs to, and the small
# curriculum the list-order checks read.
#
# Self-contained: creates the namespace and database too, so a fresh server accepts it in one pass.
DEFINE NAMESPACE IF NOT EXISTS main;
USE NS main;
DEFINE DATABASE IF NOT EXISTS lessons;
USE DB lessons;

DEFINE TABLE class_levels SCHEMAFULL PERMISSIONS FULL;
DEFINE FIELD name ON class_levels TYPE string;
DEFINE FIELD code ON class_levels TYPE string;
DEFINE FIELD age_range ON class_levels TYPE none | string;
DEFINE FIELD active ON class_levels TYPE bool DEFAULT true;
# The stage of school, from `db/schema-v13-class-tier.surql` (prod has it): what the admin and staff
# class lists are ordered by — the primary years, then the junior school, then the senior school —
# and what lesson generation reads. Optional: a level nobody has staged yet is NONE.
DEFINE FIELD tier ON class_levels TYPE option<string> ASSERT $value IN [NONE, "primary", "junior", "senior"];

DEFINE TABLE terms SCHEMAFULL PERMISSIONS FULL;
DEFINE FIELD name ON terms TYPE string;
DEFINE FIELD sort_order ON terms TYPE int;
DEFINE FIELD active ON terms TYPE bool DEFAULT true;

DEFINE TABLE subjects SCHEMAFULL PERMISSIONS FULL;
DEFINE FIELD name ON subjects TYPE string;
DEFINE FIELD code ON subjects TYPE string;
DEFINE FIELD active ON subjects TYPE bool DEFAULT true;

# Prod keeps names unique on all three lookup tables; mirror it so a duplicate create answers with
# the database's own message instead of silently adding a second "Noel Term".
DEFINE INDEX idx_terms_name ON terms COLUMNS name UNIQUE;
DEFINE INDEX idx_cl_name ON class_levels COLUMNS name UNIQUE;
DEFINE INDEX idx_subjects_name ON subjects COLUMNS name UNIQUE;

# The academic-period table the config hub's Session Terms section reads and writes (prod schema).
DEFINE TABLE session_term SCHEMAFULL PERMISSIONS FULL;
DEFINE FIELD session_name ON session_term TYPE string;
DEFINE FIELD term ON session_term TYPE record<terms>;
DEFINE FIELD active ON session_term TYPE bool DEFAULT false;
DEFINE FIELD created_at ON session_term TYPE datetime DEFAULT time::now();
DEFINE FIELD deleted_at ON session_term TYPE option<datetime>;
DEFINE INDEX idx_st_combo ON session_term COLUMNS session_name, term UNIQUE;

DEFINE TABLE credentials SCHEMAFULL PERMISSIONS FULL;
DEFINE FIELD name ON credentials TYPE string ASSERT $value != NONE;
DEFINE FIELD active ON credentials TYPE bool DEFAULT true;
# Prod's unique-name index (db/schema-v2.surql): the catalog can hold one row per qualification
# name, like the other lookup tables' unique names.
DEFINE INDEX idx_credentials_name ON credentials COLUMNS name UNIQUE;

# The school-number counters (same statements as `db/schema-v8-ids.surql`): one row per series, and
# the two rows are seeded with `UPSERT … SET type = …` rather than a bare `current_value = 0`, so
# re-applying this fixture cannot reset a counter the suites have already drawn from. Teachers and
# admins share `staff`, so one person's number survives a role change.
DEFINE TABLE id_sequences SCHEMAFULL PERMISSIONS FULL;
DEFINE FIELD type ON id_sequences TYPE string ASSERT $value IN ['student', 'staff'];
DEFINE FIELD current_value ON id_sequences TYPE int DEFAULT 0;
DEFINE FIELD created_at ON id_sequences TYPE datetime DEFAULT time::now();
DEFINE INDEX idx_id_seq_type ON id_sequences COLUMNS type UNIQUE;
UPSERT id_sequences:student SET type = 'student';
UPSERT id_sequences:staff SET type = 'staff';

DEFINE TABLE student_profile SCHEMAFULL PERMISSIONS FULL;
# The student's school number (`db/schema-v8-ids.surql`): the integer the backend allocates from
# `id_sequences:student` inside the write that makes the row, rendered `JES-000001` by the backend.
# Optional, and unique across the table; a row without one — the seeded `dev_user`, say — is fine.
DEFINE FIELD admission_number ON student_profile TYPE option<int>;
DEFINE INDEX idx_student_admission ON student_profile COLUMNS admission_number UNIQUE;
DEFINE FIELD class_enrolled ON student_profile TYPE record<class_levels> ASSERT $value != NONE;
DEFINE FIELD created_at ON student_profile TYPE datetime DEFAULT time::now();
DEFINE FIELD current_class ON student_profile TYPE record<class_levels> ASSERT $value != NONE;
DEFINE FIELD date_of_birth ON student_profile TYPE datetime ASSERT $value != NONE;
DEFINE FIELD deleted_at ON student_profile TYPE none | datetime;
DEFINE FIELD display_name ON student_profile TYPE string ASSERT $value != NONE;
DEFINE FIELD first_name ON student_profile TYPE string ASSERT $value != NONE;
DEFINE FIELD middle_name ON student_profile TYPE none | string;
DEFINE FIELD passport ON student_profile TYPE string ASSERT $value != NONE AND $value != '';
DEFINE FIELD surname ON student_profile TYPE string ASSERT $value != NONE;
DEFINE FIELD updated_at ON student_profile TYPE none | datetime;

DEFINE TABLE teacher_profile SCHEMAFULL PERMISSIONS FULL;
DEFINE FIELD created_at ON teacher_profile TYPE datetime DEFAULT time::now();
DEFINE FIELD date_employed ON teacher_profile TYPE none | datetime;
DEFINE FIELD deleted_at ON teacher_profile TYPE none | datetime;
DEFINE FIELD display_name ON teacher_profile TYPE string ASSERT $value != NONE;
DEFINE FIELD first_name ON teacher_profile TYPE string ASSERT $value != NONE;
DEFINE FIELD middle_name ON teacher_profile TYPE none | string;
DEFINE FIELD passport ON teacher_profile TYPE string ASSERT $value != NONE AND $value != '';
DEFINE FIELD qualifications ON teacher_profile TYPE none | array<record<credentials>>;
# The teacher's staff number (`db/schema-v8-ids.surql`), from `id_sequences:staff`, rendered
# `EMP-000001` by the backend. A pk that is already an admin reuses their number instead of drawing
# a second one, which is what the backend's read of both staff tables is for.
DEFINE FIELD staff_id ON teacher_profile TYPE option<int>;
DEFINE INDEX idx_teacher_staff_id ON teacher_profile COLUMNS staff_id UNIQUE;
DEFINE FIELD surname ON teacher_profile TYPE string ASSERT $value != NONE;
DEFINE FIELD updated_at ON teacher_profile TYPE none | datetime;

DEFINE TABLE admin_profile SCHEMAFULL PERMISSIONS FULL;
DEFINE FIELD created_at ON admin_profile TYPE datetime DEFAULT time::now();
DEFINE FIELD deleted_at ON admin_profile TYPE none | datetime;
DEFINE FIELD display_name ON admin_profile TYPE string ASSERT $value != NONE;
DEFINE FIELD first_name ON admin_profile TYPE string ASSERT $value != NONE;
DEFINE FIELD middle_name ON admin_profile TYPE none | string;
DEFINE FIELD passport ON admin_profile TYPE string ASSERT $value != NONE AND $value != '';
DEFINE FIELD role_title ON admin_profile TYPE none | string;
# What the admin may actually do (`db/schema-v14-admin-permissions.surql`, applied to prod on
# 2026-10-20): the type is the school's label and the ticks are what the backend enforces. The fixture
# declares them so a *fresh* sandbox can run the admin-permission flows — without them every admin write
# answers "Found field 'admin_type', but no such field exists for table 'admin_profile'".
DEFINE FIELD admin_type ON admin_profile TYPE option<string>;
DEFINE FIELD permissions ON admin_profile TYPE array<string> DEFAULT [];
# The admin's staff number, out of the same `id_sequences:staff` series as a teacher's
# (`db/schema-v8-ids.surql`).
DEFINE FIELD staff_id ON admin_profile TYPE option<int>;
DEFINE INDEX idx_admin_staff_id ON admin_profile COLUMNS staff_id UNIQUE;
DEFINE FIELD surname ON admin_profile TYPE string ASSERT $value != NONE;
DEFINE FIELD updated_at ON admin_profile TYPE none | datetime;

DEFINE TABLE parent_profile SCHEMAFULL PERMISSIONS FULL;
DEFINE FIELD created_at ON parent_profile TYPE datetime DEFAULT time::now();
DEFINE FIELD deleted_at ON parent_profile TYPE none | datetime;
DEFINE FIELD display_name ON parent_profile TYPE string ASSERT $value != NONE;
DEFINE FIELD name ON parent_profile TYPE string ASSERT $value != NONE;
DEFINE FIELD passport ON parent_profile TYPE string ASSERT $value != NONE AND $value != '';
DEFINE FIELD students ON parent_profile TYPE none | array<record<student_profile>> DEFAULT [];
DEFINE FIELD updated_at ON parent_profile TYPE none | datetime;

DEFINE TABLE lessons SCHEMAFULL PERMISSIONS FULL;
DEFINE FIELD active ON lessons TYPE bool DEFAULT true;
DEFINE FIELD content ON lessons TYPE none | object FLEXIBLE;
-- Prod's own field, and the one the scheme's per-week content cell goes into: the outline the lesson
-- generator reads as its `context` argument (every prod lesson carries one).
DEFINE FIELD context ON lessons TYPE none | string;
DEFINE FIELD deleted_at ON lessons TYPE none | datetime;
DEFINE FIELD duration_mins ON lessons TYPE int;
-- Whether the generator has filled `content` yet, and how many times it has (prod's fields).
DEFINE FIELD generated ON lessons TYPE bool DEFAULT false;
DEFINE FIELD has_subject ON lessons TYPE record<has_subject>;
DEFINE FIELD slug ON lessons TYPE string;
DEFINE FIELD term ON lessons TYPE record<terms>;
DEFINE FIELD topic_title ON lessons TYPE string;
DEFINE FIELD updated_at ON lessons TYPE none | datetime;
DEFINE FIELD version ON lessons TYPE int DEFAULT 1;
DEFINE FIELD week ON lessons TYPE int;
-- Prod's own lessons indexes (see db/schema-v10-lesson-indexes.surql): without these a sandbox would
-- enforce neither the slug nor the one-lesson-per-edge-term-week rule that prod enforces, so a bug
-- that duplicates a week would look fine here.
DEFINE INDEX idx_lessons_unique ON lessons COLUMNS has_subject, term, week UNIQUE;
DEFINE INDEX idx_lessons_slug ON lessons COLUMNS slug UNIQUE;

DEFINE TABLE lesson_assessments SCHEMAFULL PERMISSIONS FULL;
DEFINE FIELD active ON lesson_assessments TYPE bool DEFAULT false;
DEFINE FIELD created_at ON lesson_assessments TYPE datetime DEFAULT time::now();
DEFINE FIELD created_by ON lesson_assessments TYPE record<teacher_profile>;
DEFINE FIELD deadline ON lesson_assessments TYPE none | datetime;
DEFINE FIELD deleted_at ON lesson_assessments TYPE none | datetime;
DEFINE FIELD description ON lesson_assessments TYPE none | string;
DEFINE FIELD lesson ON lesson_assessments TYPE record<lessons> ASSERT $value != NONE;
DEFINE FIELD max_resubmissions ON lesson_assessments TYPE int DEFAULT 0;
# `array<object>` implies `questions.*`, so no explicit sub-field definition is needed here
# (prod carries one anyway).
DEFINE FIELD questions ON lesson_assessments TYPE array<object>;

# Strict question shapes, mirroring what prod now has (db/schema-v3.surql). Without these,
# this SurrealDB generation rejects question objects: only an empty array is storable.
DEFINE FIELD questions.*.type ON lesson_assessments TYPE string ASSERT $value INSIDE ['mcq', 'boolean', 'short_answer', 'essay'];
DEFINE FIELD questions.*.question ON lesson_assessments TYPE string;
DEFINE FIELD questions.*.options ON lesson_assessments TYPE option<array<string>>;
DEFINE FIELD questions.*.answer ON lesson_assessments TYPE string;
DEFINE FIELD questions.*.explanation ON lesson_assessments TYPE option<string>;
DEFINE FIELD questions.*.marks ON lesson_assessments TYPE option<number>;
DEFINE FIELD scheduled_at ON lesson_assessments TYPE none | datetime;
DEFINE FIELD title ON lesson_assessments TYPE string ASSERT $value != NONE;
DEFINE FIELD total_mark ON lesson_assessments TYPE int;
DEFINE FIELD updated_at ON lesson_assessments TYPE none | datetime;

# General assessments: a term/subject weighted assessment with its own questions (prod schema).
DEFINE TABLE general_assessments SCHEMAFULL PERMISSIONS FULL;
DEFINE FIELD active ON general_assessments TYPE bool DEFAULT false;
DEFINE FIELD created_at ON general_assessments TYPE datetime DEFAULT time::now();
DEFINE FIELD created_by ON general_assessments TYPE record<teacher_profile>;
DEFINE FIELD deadline ON general_assessments TYPE none | datetime;
DEFINE FIELD deleted_at ON general_assessments TYPE none | datetime;
DEFINE FIELD description ON general_assessments TYPE none | string;
DEFINE FIELD max_resubmissions ON general_assessments TYPE int DEFAULT 0;
DEFINE FIELD percentage_weight ON general_assessments TYPE int;
DEFINE FIELD questions ON general_assessments TYPE none | array<object>;
# (`array<object>` implies `questions.*`, and prod's explicit definition of it says the same thing.)
# Prod declares nothing under `questions.*`, so a question object is rejected there; db/schema-v3.surql
# declares the six sub-fields below and the implementation writes exactly that shape. Apply v3's
# general_assessments statements to prod before the feature can store questions there.
DEFINE FIELD questions.*.type ON general_assessments TYPE string ASSERT $value INSIDE ['mcq', 'boolean', 'short_answer', 'essay'];
DEFINE FIELD questions.*.question ON general_assessments TYPE string;
DEFINE FIELD questions.*.options ON general_assessments TYPE option<array<string>>;
DEFINE FIELD questions.*.answer ON general_assessments TYPE string;
DEFINE FIELD questions.*.explanation ON general_assessments TYPE option<string>;
DEFINE FIELD questions.*.marks ON general_assessments TYPE option<number>;
DEFINE FIELD scheduled_at ON general_assessments TYPE none | datetime;
DEFINE FIELD session_term ON general_assessments TYPE record<session_term> ASSERT $value != NONE;
DEFINE FIELD subject ON general_assessments TYPE record<subjects> ASSERT $value != NONE;
DEFINE FIELD title ON general_assessments TYPE string ASSERT $value != NONE;
DEFINE FIELD total_mark ON general_assessments TYPE int;
DEFINE FIELD updated_at ON general_assessments TYPE none | datetime;
DEFINE INDEX idx_ga_st_subj ON general_assessments FIELDS session_term, subject;

# The general_assessment -> lesson_assessment weights join table (prod schema). Kept here so the
# fixture matches prod field-for-field; the implementation neither reads nor writes it.
DEFINE TABLE compositions SCHEMAFULL PERMISSIONS FULL;
DEFINE FIELD created_at ON compositions TYPE datetime DEFAULT time::now();
DEFINE FIELD general_assessment ON compositions TYPE record<general_assessments> ASSERT $value != NONE;
DEFINE FIELD lesson_assessment ON compositions TYPE record<lesson_assessments> ASSERT $value != NONE;
DEFINE FIELD weight_pct ON compositions TYPE float;
DEFINE INDEX idx_comp_ga ON compositions FIELDS general_assessment;

DEFINE TABLE submissions SCHEMAFULL PERMISSIONS FULL;
# `array<object>` implies `answers.*`, as above.
DEFINE FIELD answers ON submissions TYPE array<object>;
# The answer objects themselves need their sub-fields declared or a SCHEMAFULL table rejects every
# one of them; same statements as `db/schema-v7-submission-answers.surql`, which prod has.
DEFINE FIELD answers.*.question_index ON submissions TYPE int;
DEFINE FIELD answers.*.answer_type ON submissions TYPE string;
DEFINE FIELD answers.*.answer_text ON submissions TYPE string;
DEFINE FIELD answers.*.allocated_mark ON submissions TYPE int;
DEFINE FIELD assessment_id ON submissions TYPE string;
DEFINE FIELD assessment_type ON submissions TYPE string;
DEFINE FIELD grade_released_at ON submissions TYPE none | datetime;
DEFINE FIELD iteration ON submissions TYPE int DEFAULT 0;
DEFINE FIELD scored_mark ON submissions TYPE none | int;
DEFINE FIELD status ON submissions TYPE string;
DEFINE FIELD student ON submissions TYPE record<student_profile> ASSERT $value != NONE;
DEFINE FIELD submitted_at ON submissions TYPE datetime DEFAULT time::now();
DEFINE FIELD total_mark ON submissions TYPE int;

CREATE class_levels:year_1 SET name = 'Year 1', code = 'year_1', age_range = '5-6 years', active = true, tier = 'primary';
CREATE class_levels:year_2 SET name = 'Year 2', code = 'year_2', age_range = '6-7 years', active = true, tier = 'primary';
CREATE class_levels:year_3 SET name = 'Year 3', code = 'year_3', age_range = '7-8 years', active = true, tier = 'primary';
CREATE class_levels:year_4 SET name = 'Year 4', code = 'year_4', age_range = '8-9 years', active = true, tier = 'primary';
CREATE class_levels:year_5 SET name = 'Year 5', code = 'year_5', age_range = '9-10 years', active = true, tier = 'primary';
CREATE class_levels:jss_1 SET name = 'JSS 1', code = 'jss_1', age_range = '10-11 years', active = true, tier = 'junior';
CREATE class_levels:jss_2 SET name = 'JSS 2', code = 'jss_2', age_range = '11-12 years', active = true, tier = 'junior';
CREATE class_levels:jss_3 SET name = 'JSS 3', code = 'jss_3', age_range = '12-13 years', active = true, tier = 'junior';
# v13's own senior rows, age ranges included (the school has yet to confirm those three).
CREATE class_levels:sss_1 SET name = 'SSS 1', code = 'sss_1', age_range = '14-15 years', active = true, tier = 'senior';
CREATE class_levels:sss_2 SET name = 'SSS 2', code = 'sss_2', age_range = '15-16 years', active = true, tier = 'senior';
CREATE class_levels:sss_3 SET name = 'SSS 3', code = 'sss_3', age_range = '16-17 years', active = true, tier = 'senior';
CREATE terms:noel_term SET name = 'Noel Term', sort_order = 1, active = true;
CREATE terms:calvary_term SET name = 'Calvary Term', sort_order = 2, active = true;
CREATE subjects:agricultural_science SET name = 'Agricultural Science', code = 'AGR', active = true;
CREATE subjects:basic_science SET name = 'Basic Science', code = 'BSC', active = true;
CREATE subjects:english_language SET name = 'English Language', code = 'ENG', active = true;
CREATE subjects:general_mathematics SET name = 'General Mathematics', code = 'MTH', active = true;
CREATE session_term:session_2026_2027 SET session_name = '2026/2027', term = terms:noel_term, active = true, created_at = time::now();

# The class_levels -> subjects edge students drill through, and one lesson hanging off it.
# Relations are created with RELATE; CREATE on a relation table is rejected. The (in, out) index
# mirrors prod, so linking the same pair twice answers with the database's own message.
DEFINE TABLE has_subject TYPE RELATION IN class_levels OUT subjects SCHEMALESS PERMISSIONS FULL;
DEFINE INDEX idx_hs_unique ON has_subject COLUMNS in, out UNIQUE;
RELATE class_levels:jss_1->has_subject:test_edge->subjects:agricultural_science SET active = true;
# The rest of the seeded curriculum: JSS 1 teaches the four seeded subjects (which is the list its
# student and staff pages show, in the school's order), and Year 1 and SSS 1 hold two pairs each so
# a list that groups classes by stage has rows in more than one stage to group.
RELATE class_levels:jss_1->has_subject:jss1_basic_science->subjects:basic_science SET active = true;
RELATE class_levels:jss_1->has_subject:jss1_english_language->subjects:english_language SET active = true;
RELATE class_levels:jss_1->has_subject:jss1_general_mathematics->subjects:general_mathematics SET active = true;
RELATE class_levels:year_1->has_subject:year1_basic_science->subjects:basic_science SET active = true;
RELATE class_levels:year_1->has_subject:year1_general_mathematics->subjects:general_mathematics SET active = true;
RELATE class_levels:sss_1->has_subject:sss1_english_language->subjects:english_language SET active = true;
RELATE class_levels:sss_1->has_subject:sss1_general_mathematics->subjects:general_mathematics SET active = true;
CREATE lessons:test_lesson SET topic_title = 'Packaging Criteria for Farm Produce', week = 1, term = terms:noel_term, has_subject = has_subject:test_edge, active = true, duration_mins = 40, slug = 'test-lesson', content = {
  introduction: 'Packaging protects farm produce.',
  objectives: [{ objective: 'Define packaging of farm produce.' }],
  content_sections: [{ header: 'WHAT IS PACKAGING?', body: 'Putting produce into containers.', sub_points: [{ text: 'Protection' }] }],
  key_points: ['Packaging protects produce.'],
  conclusion: 'In summary, packaging matters.',
  mcq_questions: [
    { question: 'What does packaging mean in agriculture?', option_a: 'Cooking produce', option_b: 'Putting produce into containers', option_c: 'Planting seeds', correct_answer: 'b', explanation: 'It means putting produce into containers.' },
    { question: 'Which material suits tomatoes?', option_a: 'Ventilated crate', option_b: 'Sealed sack', option_c: 'Open basket', correct_answer: 'a', explanation: 'Tomatoes need ventilation.' }
  ],
  theoretical_questions: [
    { question: 'Define packaging of farm produce.', model_answer: 'Putting harvested crops into containers for storage or sale.', marking_scheme: '5 marks for a complete definition.' }
  ]
};

# The dev-skip token identifies the caller as `dev_user`, so give that caller a student profile:
# submission rows then resolve a display name instead of showing a bare id.
CREATE student_profile:dev_user SET first_name = 'Test', surname = 'Student', display_name = 'Test Student', date_of_birth = <datetime> '2012-05-01', current_class = type::record('class_levels', 'jss_1'), class_enrolled = type::record('class_levels', 'jss_1'), passport = 'https://example.com/dev.jpg', created_at = time::now();

-- --- V9: the two-system write journal (see db/schema-v9-pending-ops.surql) ---
DEFINE TABLE IF NOT EXISTS pending_ops SCHEMAFULL PERMISSIONS NONE;
DEFINE FIELD IF NOT EXISTS kind ON pending_ops TYPE string ASSERT $value IN ["create_user", "delete_user"];
DEFINE FIELD IF NOT EXISTS state ON pending_ops TYPE string ASSERT $value IN ["running", "done", "failed"];
DEFINE FIELD IF NOT EXISTS step ON pending_ops TYPE option<string>;
DEFINE FIELD IF NOT EXISTS email ON pending_ops TYPE option<string>;
DEFINE FIELD IF NOT EXISTS pk ON pending_ops TYPE option<string>;
DEFINE FIELD IF NOT EXISTS payload ON pending_ops TYPE option<string>;
DEFINE FIELD IF NOT EXISTS message ON pending_ops TYPE option<string>;
DEFINE FIELD IF NOT EXISTS created_at ON pending_ops TYPE datetime DEFAULT time::now();
DEFINE FIELD IF NOT EXISTS updated_at ON pending_ops TYPE option<datetime>;
DEFINE INDEX IF NOT EXISTS idx_pending_state ON pending_ops COLUMNS state;

-- --- Teacher class-subject assignments (db/schema-v2.surql, mirrored field-for-field) ---
-- One row per (teacher, has_subject edge, session_term): the pairs an admin assigns a teacher,
-- which is what gates the teacher's lesson access. Soft-deleted; the save endpoint hides the
-- teacher's current rows and creates one per pair, scoped to the active session term.
DEFINE TABLE IF NOT EXISTS teacher_assignment SCHEMAFULL PERMISSIONS FULL;
DEFINE FIELD IF NOT EXISTS teacher_id ON teacher_assignment TYPE record<teacher_profile>;
DEFINE FIELD IF NOT EXISTS has_subject ON teacher_assignment TYPE record<has_subject>;
DEFINE FIELD IF NOT EXISTS session_term ON teacher_assignment TYPE record<session_term>;
DEFINE FIELD IF NOT EXISTS assigned_at ON teacher_assignment TYPE datetime DEFAULT time::now();
DEFINE FIELD IF NOT EXISTS deleted_at ON teacher_assignment TYPE none | datetime;
DEFINE INDEX IF NOT EXISTS idx_ta_teacher_hs_st ON teacher_assignment FIELDS teacher_id, has_subject, session_term UNIQUE;

-- v3's graph edge, which prod has (the whole v3 file was applied there). Kept only so the fixture
-- matches prod table-for-table; the implementation reads and writes teacher_assignment alone, so
-- nothing populates this one.
DEFINE TABLE IF NOT EXISTS teaches TYPE RELATION IN teacher_profile OUT has_subject PERMISSIONS FULL;
DEFINE FIELD IF NOT EXISTS session_term ON teaches TYPE record<session_term>;
DEFINE FIELD IF NOT EXISTS assigned_at ON teaches TYPE datetime DEFAULT time::now();
DEFINE FIELD IF NOT EXISTS deleted_at ON teaches TYPE none | datetime;
DEFINE INDEX IF NOT EXISTS idx_teaches_unique ON teaches COLUMNS in, out, session_term UNIQUE;

-- --- V12: the token cache (db/schema-v12-token-cache.surql, statement for statement) ---
-- What the backend keeps of an account it has just validated a token for, so a page's burst of calls
-- costs one Authentik round trip instead of a dozen. Mirrored here so a sandbox caches like prod
-- does: without the table every request validates against the mock and nothing can observe a hit.
DEFINE TABLE IF NOT EXISTS token_cache SCHEMAFULL PERMISSIONS NONE;
DEFINE FIELD IF NOT EXISTS subject ON token_cache TYPE string;
DEFINE FIELD IF NOT EXISTS identity ON token_cache TYPE string;
DEFINE FIELD IF NOT EXISTS expires_at ON token_cache TYPE datetime;
DEFINE FIELD IF NOT EXISTS created_at ON token_cache TYPE datetime DEFAULT time::now();
DEFINE INDEX IF NOT EXISTS idx_token_cache_subject ON token_cache COLUMNS subject;
DEFINE INDEX IF NOT EXISTS idx_token_cache_expiry ON token_cache COLUMNS expires_at;

-- --- V15: the password-change requirement (db/schema-v15-password-state.surql, statement for statement) ---
-- A login whose password an administrator chose has to replace it before doing anything: the backend
-- refuses every other route until it is met (see `password_change_cleared!` in main.roc). Mirrored here so
-- a fresh sandbox can run the create-with-password and reset flows — without the table, the gate reads
-- "nothing pending" and the requirement silently does not exist.
DEFINE TABLE IF NOT EXISTS password_state SCHEMAFULL PERMISSIONS FULL;
DEFINE FIELD IF NOT EXISTS required_at ON password_state TYPE datetime DEFAULT time::now();
DEFINE FIELD IF NOT EXISTS reason ON password_state TYPE string DEFAULT 'created';
DEFINE FIELD IF NOT EXISTS changed_at ON password_state TYPE none | datetime;
