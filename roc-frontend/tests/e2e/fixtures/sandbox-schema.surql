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

CREATE class_levels:jss_1 SET name = 'JSS 1', code = 'jss_1', age_range = '10-11 years', active = true;
CREATE class_levels:jss_2 SET name = 'JSS 2', code = 'jss_2', age_range = '11-12 years', active = true;
CREATE class_levels:jss_3 SET name = 'JSS 3', code = 'jss_3', age_range = '12-13 years', active = true;
CREATE class_levels:year_1 SET name = 'Year 1', code = 'year_1', age_range = '5-6 years', active = true;
CREATE terms:noel_term SET name = 'Noel Term', sort_order = 1, active = true;
CREATE terms:calvary_term SET name = 'Calvary Term', sort_order = 2, active = true;
CREATE subjects:agricultural_science SET name = 'Agricultural Science', code = 'AGR', active = true;
