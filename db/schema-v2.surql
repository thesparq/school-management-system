 
 
REMOVE TABLE IF EXISTS lesson_assessments; 
REMOVE TABLE IF EXISTS general_assessments; 
REMOVE TABLE IF EXISTS compositions; 
REMOVE TABLE IF EXISTS submissions; 
REMOVE TABLE IF EXISTS session_term; 
REMOVE TABLE IF EXISTS teacher_assignment; 
REMOVE TABLE IF EXISTS parent_profile; 
REMOVE TABLE IF EXISTS admin_profile; 
REMOVE TABLE IF EXISTS teacher_profile; 
REMOVE TABLE IF EXISTS student_profile; 
REMOVE TABLE IF EXISTS credentials; 
REMOVE TABLE IF EXISTS user_profile; 
REMOVE TABLE IF EXISTS topics; 
REMOVE TABLE IF EXISTS lessons; 
REMOVE TABLE IF EXISTS has_subject; 
REMOVE TABLE IF EXISTS class_levels; 
REMOVE TABLE IF EXISTS subjects; 
REMOVE TABLE IF EXISTS terms; 
 
 
DEFINE TABLE subjects SCHEMAFULL; 
  ; 
DEFINE FIELD name   ON subjects TYPE string; 
DEFINE FIELD code   ON subjects TYPE string; 
DEFINE FIELD active ON subjects TYPE bool DEFAULT true; 
DEFINE INDEX idx_subjects_name ON subjects COLUMNS name UNIQUE; 
 
DEFINE TABLE class_levels SCHEMAFULL; 
  ; 
DEFINE FIELD name   ON class_levels TYPE string; 
DEFINE FIELD code   ON class_levels TYPE string; 
DEFINE FIELD active ON class_levels TYPE bool DEFAULT true; 
DEFINE INDEX idx_cl_name ON class_levels COLUMNS name UNIQUE; 
 
DEFINE TABLE terms SCHEMAFULL; 
  ; 
DEFINE FIELD name       ON terms TYPE string; 
DEFINE FIELD sort_order ON terms TYPE int; 
DEFINE FIELD active     ON terms TYPE bool DEFAULT true; 
DEFINE INDEX idx_terms_name ON terms COLUMNS name UNIQUE; 
 
 
LET $subjects = array::distinct((SELECT VALUE subject FROM topics_staging)); 
FOR $s IN $subjects { 
    LET $slug = string::lowercase(string::replace($s, ' ', '_')); 
    CREATE type::record("subjects", $slug) CONTENT { name: $s, code: $slug, active: true }; 
}; 
 
 
LET $staging_classes = array::distinct((SELECT VALUE class FROM topics_staging)); 
FOR $c IN $staging_classes { 
    LET $cl_name = string::replace($c, 'Jss', 'JSS'); 
    LET $slug = string::lowercase(string::replace($cl_name, ' ', '_')); 
    CREATE type::record("class_levels", $slug) CONTENT { name: $cl_name, code: $slug, active: true }; 
}; 
 
 
CREATE type::record("terms", "noel_term") CONTENT { name: "Noel Term", sort_order: 1, active: true }; 
CREATE type::record("terms", "calvary_term") CONTENT { name: "Calvary Term", sort_order: 2, active: true }; 
CREATE type::record("terms", "summer_term") CONTENT { name: "Summer Term", sort_order: 3, active: true }; 
 
 
DEFINE TABLE has_subject TYPE RELATION FROM class_levels TO subjects; 
DEFINE FIELD active ON has_subject TYPE bool DEFAULT true; 
DEFINE INDEX idx_hs_unique ON has_subject COLUMNS in, out UNIQUE; 
DEFINE INDEX idx_hs_in ON has_subject COLUMNS in; 
 
LET $staging_pairs = array::distinct(SELECT class, subject FROM topics_staging); 
FOR $sp IN $staging_pairs { 

    LET $cl_name = string::replace($sp.class, 'Jss', 'JSS'); 
    LET $cl_id = (SELECT VALUE id FROM class_levels WHERE name = $cl_name LIMIT 1)[0]; 
    LET $s_id = (SELECT VALUE id FROM subjects WHERE name = $sp.subject LIMIT 1)[0]; 
    IF $cl_id != NONE AND $s_id != NONE { 
        RELATE $cl_id -> has_subject -> $s_id CONTENT { active: true }; 
    }; 
}; 
 
 
DEFINE TABLE topics SCHEMAFULL; 
  ; 
 
DEFINE FIELD has_subject ON topics TYPE record<has_subject>; 
DEFINE FIELD term        ON topics TYPE record<terms>; 
DEFINE FIELD week        ON topics TYPE int; 
DEFINE FIELD topic_title ON topics TYPE string; 
DEFINE FIELD context     ON topics TYPE option<string>; 
DEFINE FIELD generated   ON topics TYPE bool DEFAULT false; 
DEFINE FIELD deleted_at  ON topics TYPE option<datetime>; 
 
DEFINE INDEX idx_topics_unique ON topics COLUMNS has_subject, term, week UNIQUE; 
 
LET $all_staging = (SELECT * FROM topics_staging); 
FOR $s IN $all_staging { 

    LET $cl_name = string::replace($s.class, 'Jss', 'JSS'); 
    LET $cl_id = (SELECT VALUE id FROM class_levels WHERE name = $cl_name LIMIT 1)[0]; 
    LET $sb_id = (SELECT VALUE id FROM subjects WHERE name = $s.subject LIMIT 1)[0]; 
    LET $hs = (SELECT VALUE id FROM has_subject WHERE in = $cl_id AND out = $sb_id LIMIT 1)[0]; 
    LET $term_id = (SELECT VALUE id FROM terms WHERE name = $s.term LIMIT 1)[0]; 
    IF $hs != NONE AND $term_id != NONE { 
        CREATE topics CONTENT { 
            has_subject: $hs, 
            term: $term_id, 
            week: $s.week, 
            topic_title: $s.topic, 
            context: $s.context ?? "", 
            generated: $s.generated ?? false 
        }; 
    }; 
}; 
 
 
DEFINE TABLE lessons SCHEMAFULL; 
 
DEFINE FIELD topic        ON lessons TYPE record<topics> ASSERT $value != NONE; 
DEFINE FIELD topic_title  ON lessons TYPE string               ASSERT $value != NONE; 
DEFINE FIELD week         ON lessons TYPE int                  ASSERT $value >= 1; 
DEFINE FIELD active        ON lessons TYPE bool DEFAULT true; 
DEFINE FIELD deleted_at    ON lessons TYPE option<datetime>; 
DEFINE FIELD duration_mins ON lessons TYPE int; 
 
DEFINE FIELD objectives           ON lessons TYPE array; 
DEFINE FIELD content_sections     ON lessons TYPE array; 
DEFINE FIELD key_points           ON lessons TYPE array; 
DEFINE FIELD lesson_steps         ON lessons TYPE array; 
DEFINE FIELD mcq_questions        ON lessons TYPE array; 
DEFINE FIELD theoretical_questions ON lessons TYPE array; 
DEFINE FIELD materials            ON lessons TYPE array; 
DEFINE FIELD prior_knowledge      ON lessons TYPE array; 
DEFINE FIELD success_criteria     ON lessons TYPE array; 
DEFINE FIELD extension_activities ON lessons TYPE array; 
DEFINE FIELD textbook_references  ON lessons TYPE array; 
DEFINE FIELD primary_sources      ON lessons TYPE array; 
 
DEFINE FIELD introduction          ON lessons TYPE string; 
DEFINE FIELD conclusion            ON lessons TYPE string; 
DEFINE FIELD formative_assessment  ON lessons TYPE string; 
DEFINE FIELD summative_assessment  ON lessons TYPE string; 
DEFINE FIELD remediation           ON lessons TYPE string; 
DEFINE FIELD teacher_tips          ON lessons TYPE string; 
 
DEFINE INDEX idx_lessons_topic ON lessons COLUMNS topic UNIQUE; 
 
 
LET $all_lc = (SELECT id, class_level, subject FROM lesson_content); 
FOR $lc IN $all_lc { 
    LET $cl_label = IF $lc.class_level IS NONE THEN NONE 
                    ELSE IF string::starts_with($lc.class_level, 'PRIMARY_') THEN 
                        "Year " + string::replace($lc.class_level, 'PRIMARY_', '') 
                    ELSE IF string::starts_with($lc.class_level, 'JSS_') THEN 
                        string::replace($lc.class_level, '_', ' ') 
                    ELSE $lc.class_level END; 
    LET $cl_id = (SELECT VALUE id FROM class_levels WHERE name = $cl_label LIMIT 1)[0]; 
    LET $sb_name = IF $lc.subject = "Agriculture" THEN "Agricultural Science" 
                   ELSE IF $lc.subject = "Yoruba" THEN "Yoruba Language" 
                   ELSE $lc.subject END; 
    LET $sb_id = (SELECT VALUE id FROM subjects WHERE name = $sb_name LIMIT 1)[0]; 
    LET $hs = (SELECT VALUE id FROM has_subject WHERE in = $cl_id AND out = $sb_id LIMIT 1)[0]; 
    IF $hs != NONE { 
        UPDATE $lc.id SET has_subject = $hs; 
    }; 
}; 
 
 
LET $all_content = (SELECT * FROM lesson_content); 
FOR $lc IN $all_content { 
    LET $term_map = IF $lc.term = "FIRST" OR $lc.term = "First Term" OR $lc.term = "1st Term" THEN "Noel Term" 
                    ELSE IF $lc.term = "SECOND" OR $lc.term = "Second Term" THEN "Calvary Term" 
                    ELSE IF $lc.term = "THIRD" OR $lc.term = "Third Term" THEN "Summer Term" 
                    ELSE $lc.term END; 
    LET $term_id = (SELECT VALUE id FROM terms WHERE name = $term_map LIMIT 1)[0]; 
    LET $week_val = $lc.week_number ?? $lc.week ?? 1; 
    LET $topic_id = (SELECT VALUE id FROM topics WHERE 
        has_subject = $lc.has_subject AND term = $term_id AND week = $week_val LIMIT 1 
    )[0]; 
    IF $lc.has_subject != NONE AND $term_id != NONE AND $topic_id != NONE { 
        CREATE lessons CONTENT { 
            topic: $topic_id, 
            topic_title: $lc.topic_title ?? ($lc.subject ?? ""), 
            week: $week_val, 
            active: $lc.active ?? true, 
            duration_mins: $lc.duration_mins ?? 40, 
            introduction: $lc.introduction, 
            conclusion: $lc.conclusion, 
            objectives: $lc.objectives ?? [], 
            content_sections: $lc.content_sections ?? [], 
            key_points: $lc.key_points ?? [], 
            lesson_steps: $lc.lesson_steps ?? [], 
            mcq_questions: $lc.mcq_questions ?? [], 
            theoretical_questions: $lc.theoretical_questions ?? [], 
            materials: $lc.materials ?? [], 
            prior_knowledge: $lc.prior_knowledge ?? [], 
            success_criteria: $lc.success_criteria ?? [], 
            extension_activities: $lc.extension_activities ?? [], 
            textbook_references: $lc.textbook_references ?? [], 
            primary_sources: $lc.primary_sources ?? [], 
            formative_assessment: $lc.formative_assessment ?? "", 
            summative_assessment: $lc.summative_assessment ?? "", 
            remediation: $lc.remediation ?? "", 
            teacher_tips: $lc.teacher_tips ?? "" 
        }; 
    }; 
}; 
 
 
SELECT count() FROM topics GROUP ALL; 
SELECT count() FROM lessons GROUP ALL; 
SELECT count() FROM has_subject GROUP ALL; 
 
SELECT id, topic.has_subject.in.name AS class_name, 
       topic.has_subject.out.name AS subject_name, 
       topic.term.name AS term_name, 
       week, 
       topic_title, 
       topic.topic_title AS topic_title 
FROM lessons 
LIMIT 10; 
 
LET $topic_count = (SELECT VALUE count() FROM topics)[0]; 
LET $staging_count = (SELECT VALUE count() FROM topics_staging)[0]; 
RETURN { topics: $topic_count, staging: $staging_count }; 
 
SELECT math::min(week) AS min_week, math::max(week) AS max_week 
FROM lessons 
GROUP ALL; 
 
SELECT count() FROM lesson_content GROUP ALL; 
 
 
DEFINE TABLE IF NOT EXISTS student_profile SCHEMAFULL; 
  ; 
 
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
  ASSERT $value != NONE AND $value != ""; 
DEFINE FIELD IF NOT EXISTS created_at     ON student_profile TYPE datetime DEFAULT time::now(); 
DEFINE FIELD IF NOT EXISTS updated_at     ON student_profile TYPE option<datetime>; 
DEFINE FIELD IF NOT EXISTS deleted_at     ON student_profile TYPE option<datetime>; 
 
DEFINE TABLE IF NOT EXISTS teacher_profile SCHEMAFULL; 
  ; 
 
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
  ASSERT $value != NONE AND $value != ""; 
DEFINE FIELD IF NOT EXISTS created_at    ON teacher_profile TYPE datetime DEFAULT time::now(); 
DEFINE FIELD IF NOT EXISTS updated_at    ON teacher_profile TYPE option<datetime>; 
DEFINE FIELD IF NOT EXISTS deleted_at    ON teacher_profile TYPE option<datetime>; 
 
DEFINE TABLE IF NOT EXISTS admin_profile SCHEMAFULL; 
  ; 
 
DEFINE FIELD IF NOT EXISTS surname      ON admin_profile TYPE string 
  ASSERT $value != NONE; 
DEFINE FIELD IF NOT EXISTS first_name   ON admin_profile TYPE string 
  ASSERT $value != NONE; 
DEFINE FIELD IF NOT EXISTS middle_name  ON admin_profile TYPE option<string>; 
DEFINE FIELD IF NOT EXISTS display_name ON admin_profile TYPE string 
  ASSERT $value != NONE; 
DEFINE FIELD IF NOT EXISTS role_title   ON admin_profile TYPE option<string>; 
DEFINE FIELD IF NOT EXISTS passport     ON admin_profile TYPE string 
  ASSERT $value != NONE AND $value != ""; 
DEFINE FIELD IF NOT EXISTS created_at   ON admin_profile TYPE datetime DEFAULT time::now(); 
DEFINE FIELD IF NOT EXISTS updated_at   ON admin_profile TYPE option<datetime>; 
DEFINE FIELD IF NOT EXISTS deleted_at   ON admin_profile TYPE option<datetime>; 
 
DEFINE TABLE IF NOT EXISTS parent_profile SCHEMAFULL; 
  ; 
 
DEFINE FIELD IF NOT EXISTS name         ON parent_profile TYPE string 
  ASSERT $value != NONE; 
DEFINE FIELD IF NOT EXISTS display_name ON parent_profile TYPE string 
  ASSERT $value != NONE; 
DEFINE FIELD IF NOT EXISTS students     ON parent_profile TYPE option<array<record<student_profile>>> 
  DEFAULT []; 
DEFINE FIELD IF NOT EXISTS passport     ON parent_profile TYPE string 
  ASSERT $value != NONE AND $value != ""; 
DEFINE FIELD IF NOT EXISTS created_at   ON parent_profile TYPE datetime DEFAULT time::now(); 
DEFINE FIELD IF NOT EXISTS updated_at   ON parent_profile TYPE option<datetime>; 
DEFINE FIELD IF NOT EXISTS deleted_at   ON parent_profile TYPE option<datetime>; 
 
 
DEFINE TABLE IF NOT EXISTS credentials SCHEMAFULL; 
  ; 
 
DEFINE FIELD IF NOT EXISTS name   ON credentials TYPE string 
  ASSERT $value != NONE; 
DEFINE FIELD IF NOT EXISTS active ON credentials TYPE bool DEFAULT true; 
 
DEFINE INDEX IF NOT EXISTS idx_credentials_name ON credentials COLUMNS name UNIQUE; 
 
 
SELECT count() FROM student_profile GROUP ALL; 
SELECT count() FROM teacher_profile GROUP ALL; 
SELECT count() FROM admin_profile GROUP ALL; 
SELECT count() FROM parent_profile GROUP ALL; 
SELECT count() FROM credentials GROUP ALL; 
 
 
DEFINE TABLE session_term SCHEMAFULL; 
  ; 
 
DEFINE FIELD session_name ON session_term TYPE string; 
DEFINE FIELD term         ON session_term TYPE record<terms>; 
DEFINE FIELD active       ON session_term TYPE bool DEFAULT false; 
DEFINE FIELD created_at   ON session_term TYPE datetime DEFAULT time::now(); 
DEFINE FIELD deleted_at   ON session_term TYPE option<datetime>; 
 
DEFINE INDEX idx_st_combo ON session_term COLUMNS session_name, term UNIQUE; 
 
 
DEFINE TABLE teacher_assignment SCHEMAFULL; 
  ; 
 
DEFINE FIELD teacher_id   ON teacher_assignment TYPE record<teacher_profile>; 
DEFINE FIELD has_subject  ON teacher_assignment TYPE record<has_subject>; 
DEFINE FIELD session_term ON teacher_assignment TYPE record<session_term>; 
DEFINE FIELD assigned_at  ON teacher_assignment TYPE datetime DEFAULT time::now(); 
DEFINE FIELD deleted_at   ON teacher_assignment TYPE option<datetime>; 
 
DEFINE INDEX idx_ta_teacher_hs_st 
  ON teacher_assignment COLUMNS teacher_id, has_subject, session_term UNIQUE; 
 
 
 
DEFINE TABLE IF NOT EXISTS lesson_assessments SCHEMAFULL; 
  ; 
 
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
 
DEFINE TABLE IF NOT EXISTS general_assessments SCHEMAFULL; 
  ; 
 
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
 
DEFINE TABLE IF NOT EXISTS compositions SCHEMAFULL; 
  ; 
 
DEFINE FIELD IF NOT EXISTS general_assessment ON compositions TYPE record<general_assessments> ASSERT $value != NONE; 
DEFINE FIELD IF NOT EXISTS lesson_assessment  ON compositions TYPE record<lesson_assessments> ASSERT $value != NONE; 
DEFINE FIELD IF NOT EXISTS weight_pct         ON compositions TYPE float; 
DEFINE FIELD IF NOT EXISTS created_at         ON compositions TYPE datetime DEFAULT time::now(); 
 
DEFINE INDEX IF NOT EXISTS idx_comp_ga ON compositions COLUMNS general_assessment; 
 
DEFINE TABLE IF NOT EXISTS submissions SCHEMAFULL; 
  ; 
 
DEFINE FIELD IF NOT EXISTS assessment_type   ON submissions TYPE string; 
DEFINE FIELD IF NOT EXISTS assessment_id     ON submissions TYPE string; 
DEFINE FIELD IF NOT EXISTS student           ON submissions TYPE record<student_profile> ASSERT $value != NONE; 
DEFINE FIELD IF NOT EXISTS iteration         ON submissions TYPE int DEFAULT 0; 
DEFINE FIELD IF NOT EXISTS status            ON submissions TYPE string; 
DEFINE FIELD IF NOT EXISTS submitted_at      ON submissions TYPE datetime DEFAULT time::now(); 
DEFINE FIELD IF NOT EXISTS answers           ON submissions TYPE array<object>; 
DEFINE FIELD IF NOT EXISTS total_mark        ON submissions TYPE int; 
DEFINE FIELD IF NOT EXISTS scored_mark       ON submissions TYPE option<int>; 
DEFINE FIELD IF NOT EXISTS grade_released_at ON submissions TYPE option<datetime>; 
 
DEFINE INDEX IF NOT EXISTS idx_sub_student      ON submissions COLUMNS student; 
DEFINE INDEX IF NOT EXISTS idx_sub_assessment   ON submissions COLUMNS assessment_type, assessment_id; 
DEFINE INDEX IF NOT EXISTS idx_sub_unique       ON submissions COLUMNS assessment_type, assessment_id, student, iteration UNIQUE; 
 
DEFINE FIELD IF NOT EXISTS version     ON lessons TYPE int DEFAULT 1; 
DEFINE FIELD IF NOT EXISTS updated_at  ON lessons TYPE option<datetime>; 
 
SELECT count() FROM lesson_assessments GROUP ALL; 
SELECT count() FROM general_assessments GROUP ALL; 
SELECT count() FROM compositions GROUP ALL; 
SELECT count() FROM submissions GROUP ALL; 
 
DEFINE TABLE terms SCHEMAFULL;
DEFINE FIELD name ON terms TYPE string;
DEFINE FIELD sort_order ON terms TYPE number;
DEFINE FIELD active ON terms TYPE bool DEFAULT true;

DEFINE TABLE session_term SCHEMAFULL;
DEFINE FIELD session_name ON session_term TYPE string;
DEFINE FIELD term ON session_term TYPE record<terms>;
DEFINE FIELD active ON session_term TYPE bool DEFAULT true;
