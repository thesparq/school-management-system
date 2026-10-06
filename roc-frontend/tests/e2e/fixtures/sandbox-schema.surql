# Throwaway database for the admin check: the prod profile tables (SCHEMAFULL, same fields and
# assertions) plus the class levels the create path validates against.
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
DEFINE FIELD duration_mins ON lessons TYPE int;
DEFINE FIELD has_subject ON lessons TYPE record<has_subject>;
DEFINE FIELD slug ON lessons TYPE string;
DEFINE FIELD term ON lessons TYPE record<terms>;
DEFINE FIELD topic_title ON lessons TYPE string;
DEFINE FIELD week ON lessons TYPE int;

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

CREATE class_levels:jss_1 SET name = 'JSS 1', code = 'jss_1', age_range = '10-11 years', active = true;
CREATE class_levels:jss_2 SET name = 'JSS 2', code = 'jss_2', age_range = '11-12 years', active = true;
CREATE class_levels:jss_3 SET name = 'JSS 3', code = 'jss_3', age_range = '12-13 years', active = true;
CREATE class_levels:year_1 SET name = 'Year 1', code = 'year_1', age_range = '5-6 years', active = true;
CREATE terms:noel_term SET name = 'Noel Term', sort_order = 1, active = true;
CREATE terms:calvary_term SET name = 'Calvary Term', sort_order = 2, active = true;
CREATE subjects:agricultural_science SET name = 'Agricultural Science', code = 'AGR', active = true;
CREATE session_term:session_2026_2027 SET session_name = '2026/2027', term = terms:noel_term, active = true, created_at = time::now();

# The class_levels -> subjects edge students drill through, and one lesson hanging off it.
# Relations are created with RELATE; CREATE on a relation table is rejected. The (in, out) index
# mirrors prod, so linking the same pair twice answers with the database's own message.
DEFINE TABLE has_subject TYPE RELATION IN class_levels OUT subjects SCHEMALESS PERMISSIONS FULL;
DEFINE INDEX idx_hs_unique ON has_subject COLUMNS in, out UNIQUE;
RELATE class_levels:jss_1->has_subject:test_edge->subjects:agricultural_science SET active = true;
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
