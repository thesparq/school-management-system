-- ============================================================
-- HF-01 — SurrealDB Schema v2
-- Idiomatic graph/document schema for lesson + topics data.
-- Idempotent: safe to re-run.
-- Does NOT modify or remove lesson_content (deprecated).
--
-- Workflow:
--   1. Run this schema once (creates staging table, populates
--      subjects/class_levels/terms/edges/lessons from lesson_content)
--   2. Import CSVs into topics_staging using Surrealist or CLI
--   3. Run this schema again — topics_staging data is preserved,
--      everything else is rebuilt with proper record links
-- ============================================================

----------------
-- Step 0: Remove all tables (schemas drop with data)
-- Order matters: child records before referenced records.
-- topics_staging is NOT removed — it survives re-runs.
----------------

REMOVE TABLE session_term;
REMOVE TABLE teacher_assignment;
REMOVE TABLE user_profile;
REMOVE TABLE topics;
REMOVE TABLE lessons;
REMOVE TABLE has_subject;
REMOVE TABLE class_levels;
REMOVE TABLE subjects;
REMOVE TABLE terms;

----------------
-- Step 1a: Define lookup table schemas
-- Schemas are defined before population.
----------------

DEFINE TABLE subjects SCHEMAFULL
  PERMISSIONS FOR select, create, update, delete NONE;
DEFINE FIELD name   ON subjects TYPE string;
DEFINE FIELD code   ON subjects TYPE string;
DEFINE FIELD active ON subjects TYPE bool DEFAULT true;
DEFINE INDEX idx_subjects_name ON subjects COLUMNS name UNIQUE;

DEFINE TABLE class_levels SCHEMAFULL
  PERMISSIONS FOR select, create, update, delete NONE;
DEFINE FIELD name   ON class_levels TYPE string;
DEFINE FIELD code   ON class_levels TYPE string;
DEFINE FIELD active ON class_levels TYPE bool DEFAULT true;
DEFINE INDEX idx_cl_name ON class_levels COLUMNS name UNIQUE;

DEFINE TABLE terms SCHEMAFULL
  PERMISSIONS FOR select, create, update, delete NONE;
DEFINE FIELD name       ON terms TYPE string;
DEFINE FIELD sort_order ON terms TYPE int;
DEFINE FIELD active     ON terms TYPE bool DEFAULT true;
DEFINE INDEX idx_terms_name ON terms COLUMNS name UNIQUE;

----------------
-- Step 1b: Populate subjects from topics_staging
----------------

LET $subjects = array::distinct((SELECT VALUE subject FROM topics_staging));
FOR $s IN $subjects {
    LET $slug = string::lowercase(string::replace($s, ' ', '_'));
    CREATE type::thing("subjects", $slug) CONTENT { name: $s, code: $slug, active: true };
};

----------------
-- Step 1c: Populate class_levels from topics_staging
----------------

LET $staging_classes = array::distinct((SELECT VALUE class FROM topics_staging));
FOR $c IN $staging_classes {
    LET $cl_name = string::replace($c, 'Jss', 'JSS');
    LET $slug = string::lowercase(string::replace($cl_name, ' ', '_'));
    CREATE type::thing("class_levels", $slug) CONTENT { name: $cl_name, code: $slug, active: true };
};

----------------
-- Step 1d: Populate terms (hardcoded — only three terms exist)
----------------

CREATE type::thing("terms", "noel_term") CONTENT { name: "Noel Term", sort_order: 1, active: true };
CREATE type::thing("terms", "calvary_term") CONTENT { name: "Calvary Term", sort_order: 2, active: true };
CREATE type::thing("terms", "summer_term") CONTENT { name: "Summer Term", sort_order: 3, active: true };

----------------
-- Step 2: Create has_subject graph edge
-- Sources exclusively from topics_staging (covers all class+subject pairs)
----------------

DEFINE TABLE has_subject TYPE RELATION FROM class_levels TO subjects;
DEFINE FIELD active ON has_subject TYPE bool DEFAULT true;
DEFINE INDEX idx_hs_unique ON has_subject COLUMNS in, out UNIQUE;
DEFINE INDEX idx_hs_in ON has_subject COLUMNS in;

-- Edges from topics_staging (covers all class+subject combinations)
LET $staging_pairs = array::distinct(SELECT class, subject FROM topics_staging);
FOR $sp IN $staging_pairs {
    -- Normalize mixed-case class names (staging has "Jss N", class_levels has "JSS N")
    LET $cl_name = string::replace($sp.class, 'Jss', 'JSS');
    LET $cl_id = (SELECT VALUE id FROM class_levels WHERE name = $cl_name LIMIT 1)[0];
    LET $s_id = (SELECT VALUE id FROM subjects WHERE name = $sp.subject LIMIT 1)[0];
    IF $cl_id != NONE AND $s_id != NONE {
        RELATE $cl_id -> has_subject -> $s_id CONTENT { active: true };
    };
};

----------------
-- Step 2a: topics table — canonical curriculum reference
-- Populated from topics_staging with typed record links
----------------

DEFINE TABLE topics SCHEMAFULL
  PERMISSIONS FOR select, create, update, delete NONE;

DEFINE FIELD has_subject ON topics TYPE record<has_subject>;
DEFINE FIELD term        ON topics TYPE record<terms>;
DEFINE FIELD week        ON topics TYPE int;
DEFINE FIELD topic_title ON topics TYPE string;
DEFINE FIELD context     ON topics TYPE option<string>;
DEFINE FIELD generated   ON topics TYPE bool DEFAULT false;
DEFINE FIELD deleted_at  ON topics TYPE option<datetime>;

DEFINE INDEX idx_topics_unique ON topics COLUMNS has_subject, term, week UNIQUE;

-- Populate from topics_staging (fetch all rows once)
LET $all_staging = (SELECT * FROM topics_staging);
FOR $s IN $all_staging {
    -- Normalize mixed-case class names (staging has "Jss N", class_levels has "JSS N")
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

----------------
-- Step 3: Create lessons table — one per topic, with full content
----------------

DEFINE TABLE lessons SCHEMAFULL;

DEFINE FIELD topic        ON lessons TYPE record<topics> ASSERT $value != NONE;
DEFINE FIELD topic_title  ON lessons TYPE string               ASSERT $value != NONE;
DEFINE FIELD week         ON lessons TYPE int                  ASSERT $value >= 1;
DEFINE FIELD active        ON lessons TYPE bool DEFAULT true;
DEFINE FIELD deleted_at    ON lessons TYPE option<datetime>;
DEFINE FIELD duration_mins ON lessons TYPE int;

DEFINE FIELD objectives           ON lessons FLEXIBLE TYPE array<object>;
DEFINE FIELD content_sections     ON lessons FLEXIBLE TYPE array<object>;
DEFINE FIELD key_points           ON lessons FLEXIBLE TYPE array;
DEFINE FIELD lesson_steps         ON lessons FLEXIBLE TYPE array<object>;
DEFINE FIELD mcq_questions        ON lessons FLEXIBLE TYPE array<object>;
DEFINE FIELD theoretical_questions ON lessons FLEXIBLE TYPE array<object>;
DEFINE FIELD materials            ON lessons FLEXIBLE TYPE array;
DEFINE FIELD prior_knowledge      ON lessons FLEXIBLE TYPE array;
DEFINE FIELD success_criteria     ON lessons FLEXIBLE TYPE array;
DEFINE FIELD extension_activities ON lessons FLEXIBLE TYPE array;
DEFINE FIELD textbook_references  ON lessons FLEXIBLE TYPE array;
DEFINE FIELD primary_sources      ON lessons FLEXIBLE TYPE array;

DEFINE FIELD introduction          ON lessons TYPE string;
DEFINE FIELD conclusion            ON lessons TYPE string;
DEFINE FIELD formative_assessment  ON lessons TYPE string;
DEFINE FIELD summative_assessment  ON lessons TYPE string;
DEFINE FIELD remediation           ON lessons TYPE string;
DEFINE FIELD teacher_tips          ON lessons TYPE string;

DEFINE INDEX idx_lessons_topic ON lessons COLUMNS topic UNIQUE;

----------------
-- Step 4: Pre-populate has_subject on lesson_content
-- Resolves class_level + subject → has_subject edge and writes it
-- directly onto each lesson_content row, so Step 5 mirrors Step 2a.
----------------

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

----------------
-- Step 5: Migrate lesson_content → lessons
-- Mirror of Step 2a: has_subject is already resolved on each row.
-- Resolve term_id, lookup topics via idx_topics_unique, CREATE.
----------------

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

----------------
-- Verification queries
----------------

SELECT count() FROM topics GROUP ALL;
SELECT count() FROM lessons GROUP ALL;
SELECT count() FROM has_subject GROUP ALL;

-- Lessons with topic details
SELECT id, topic.has_subject.in.name AS class_name,
       topic.has_subject.out.name AS subject_name,
       topic.term.name AS term_name,
       week,
       topic_title,
       topic.topic_title AS topic_title
FROM lessons
LIMIT 10;

-- Check topic coverage vs staging
LET $topic_count = (SELECT VALUE count() FROM topics)[0];
LET $staging_count = (SELECT VALUE count() FROM topics_staging)[0];
RETURN { topics: $topic_count, staging: $staging_count };

SELECT math::min(week) AS min_week, math::max(week) AS max_week
FROM lessons
GROUP ALL;

SELECT count() FROM lesson_content GROUP ALL;

----------------
-- Step 6: user_profile table (replaces AdminAgent.initialized_users + StudentAgent.profile)

DEFINE TABLE user_profile SCHEMAFULL
  PERMISSIONS FOR select, create, update, delete NONE;

DEFINE FIELD IF NOT EXISTS auth_id      ON user_profile TYPE string;
DEFINE FIELD IF NOT EXISTS role         ON user_profile TYPE string
  ASSERT $value IN ["admin", "teacher", "student"];
DEFINE FIELD IF NOT EXISTS class_level  ON user_profile TYPE option<string>;
DEFINE FIELD IF NOT EXISTS created_at   ON user_profile TYPE datetime;
DEFINE FIELD IF NOT EXISTS updated_at   ON user_profile TYPE option<datetime>;
DEFINE FIELD IF NOT EXISTS deleted_at   ON user_profile TYPE option<datetime>;

DEFINE INDEX IF NOT EXISTS idx_user_profile_auth_id
  ON user_profile COLUMNS auth_id UNIQUE;

----------------
-- Step 7: session_term table — school period unit
-- Every result, assignment, fee, payment, etc. references this.

DEFINE TABLE session_term SCHEMAFULL
  PERMISSIONS FOR select, create, update, delete NONE;

DEFINE FIELD session     ON session_term TYPE string;
DEFINE FIELD term        ON session_term TYPE record<terms>;
DEFINE FIELD active      ON session_term TYPE bool DEFAULT false;
DEFINE FIELD created_at  ON session_term TYPE datetime;
DEFINE FIELD deleted_at  ON session_term TYPE option<datetime>;

DEFINE INDEX idx_st_combo ON session_term COLUMNS session, term UNIQUE;

----------------
-- Step 8: teacher_assignment table (replaces AdminAgent.teacher_assignments)
-- Uses string IDs for class_level and subject for simple writes.
-- session_term will be added in a later phase.

DEFINE TABLE teacher_assignment SCHEMAFULL
  PERMISSIONS FOR select, create, update, delete NONE;

DEFINE FIELD teacher_id       ON teacher_assignment TYPE string;
DEFINE FIELD class_level_id   ON teacher_assignment TYPE string;
DEFINE FIELD subject_id       ON teacher_assignment TYPE string;
DEFINE FIELD assigned_at      ON teacher_assignment TYPE datetime;
DEFINE FIELD deleted_at       ON teacher_assignment TYPE option<datetime>;

DEFINE INDEX idx_ta_teacher_cl_subj
  ON teacher_assignment COLUMNS teacher_id, class_level_id, subject_id UNIQUE;
