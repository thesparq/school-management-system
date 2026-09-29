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
