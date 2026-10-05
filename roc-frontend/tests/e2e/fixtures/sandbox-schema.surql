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

DEFINE TABLE credentials SCHEMAFULL PERMISSIONS FULL;
DEFINE FIELD name ON credentials TYPE string ASSERT $value != NONE;
DEFINE FIELD active ON credentials TYPE bool DEFAULT true;

DEFINE TABLE student_profile SCHEMAFULL PERMISSIONS FULL;
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
DEFINE FIELD scheduled_at ON lesson_assessments TYPE none | datetime;
DEFINE FIELD title ON lesson_assessments TYPE string ASSERT $value != NONE;
DEFINE FIELD total_mark ON lesson_assessments TYPE int;
DEFINE FIELD updated_at ON lesson_assessments TYPE none | datetime;

DEFINE TABLE submissions SCHEMAFULL PERMISSIONS FULL;
# `array<object>` implies `answers.*`, as above.
DEFINE FIELD answers ON submissions TYPE array<object>;
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

# The class_levels -> subjects edge students drill through, and one lesson hanging off it.
# Relations are created with RELATE; CREATE on a relation table is rejected.
DEFINE TABLE has_subject TYPE RELATION IN class_levels OUT subjects SCHEMALESS PERMISSIONS FULL;
RELATE class_levels:jss_1->has_subject:test_edge->subjects:agricultural_science SET active = true;
CREATE lessons:test_lesson SET topic_title = 'Packaging Criteria for Farm Produce', week = 1, term = terms:noel_term, has_subject = has_subject:test_edge, active = true, duration_mins = 40, slug = 'test-lesson';

# The dev-skip token identifies the caller as `dev_user`, so give that caller a student profile:
# submission rows then resolve a display name instead of showing a bare id.
CREATE student_profile:dev_user SET first_name = 'Test', surname = 'Student', display_name = 'Test Student', date_of_birth = <datetime> '2012-05-01', current_class = type::record('class_levels', 'jss_1'), class_enrolled = type::record('class_levels', 'jss_1'), passport = 'https://example.com/dev.jpg', created_at = time::now();
