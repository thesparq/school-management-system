-- Schema V6: Class Terms

DEFINE TABLE class_terms SCHEMAFULL PERMISSIONS FULL;

DEFINE FIELD class_level ON class_terms TYPE record<class_levels> ASSERT $value != NONE;
DEFINE FIELD session_term ON class_terms TYPE record<session_term> ASSERT $value != NONE;
DEFINE FIELD class_teacher ON class_terms TYPE option<record<teacher_profile>>;
DEFINE FIELD created_at ON class_terms TYPE datetime DEFAULT time::now();
DEFINE FIELD updated_at ON class_terms TYPE datetime DEFAULT time::now();

DEFINE INDEX idx_class_session_term ON class_terms COLUMNS class_level, session_term UNIQUE;
