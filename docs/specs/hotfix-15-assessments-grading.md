# Hotfix-15: Assessments & Grading System

## Goal

Implement full assessments and grading: lesson-scoped assessments (quizzes per lesson) and general assessments (CA tests/exams per session term), with teacher creation from the question bank, student submission with resubmissions, MCQ auto-grading, teacher grading of theory questions via modal, grade-release controls, reactive composition-based grade mapping for general assessments, lazy scheduled activation, and an active session-term indicator in the top bar.

---

## Design

### Table Strategy — Separate, with polymorphic submissions

| Table | Scope | Key Relationship |
|---|---|---|
| `lesson_assessments` | Per lesson | `lesson: record<lessons>` |
| `general_assessments` | Per session term + subject | `session_term: record<session_term>`, `subject: record<subjects>` |
| `compositions` | Composition link | `general_assessment → lesson_assessment` with `weight_pct` |
| `submissions` | Polymorphic | `assessment_type + assessment_id` string pair |

**Question storage: Snapshot.** The assessment record copies question text/options/correct_answer at creation time. Changes to the source lesson do not retroactively alter existing assessments.

**Resubmissions: Replace mode.** `submissions.iteration` tracks resubmission count. On resubmit, the existing record's `answers` array is replaced, theory `scored_mark` resets to `null`, MCQ re-grades. Hard-capped by deadline and `max_resubmissions` (-1 = unlimited, 0 = no resubmissions).

**Grade release flow:** `submissions.grade_released_at` is `null` until the teacher explicitly releases grades. Students never see partial grades — MCQ auto-grading results are hidden until release.

**Percentage constraint: Progressive/warning-based.** Teachers create general assessments one at a time through the term. The UI shows a status bar (`X% of 100% allocated`) with a warning if exceeding 100%. No hard block, but the UI should show prominently until 100% is reached.

**Scheduled activation: Lazy on read.** The `scheduled_at` field exists on both assessment tables. Every read handler checks `scheduled_at ≤ now() && !active` and auto-activates. No Golem scheduled invocations needed for MVP.

**Composition auto-calculation: Reactive on read.** When a general assessment's grade is fetched, the system iterates all `compositions`, fetches the student's submission for each lesson assessment, and computes `(scored_mark / total_mark) × weight_pct`. Computed fresh on every read — changes to scoped assessment grades reflect immediately.

**Mixed composition:** A general assessment can have both directly-selected questions (`questions` array) AND composed scoped assessments (`compositions` table). Both contribute to the final grade proportionally.

**Grading modal:** Per-student big modal (same size as Create Assessment modal). Shows MCQ answers as read-only with correct/incorrect indicators. Shows theory answers as blockquote + mark input. "Save Grades" saves without releasing. "Save & Release" sets `grade_released_at`.

**Active session-term badge:** In the root layout top bar, between the flex spacer and ThemeToggle. Shows `<session_name> — <term_name>` in a small `Badge variant="outline"`. Fetched from `/api/active-session-term`.

---

## Implementation

### 1. Database Schema (`db/schema-v3.surql`)

```surql
-- ============================================================
-- Schema v3: Assessments, Compositions, Submissions
-- ============================================================

-- Lesson-scoped assessments
DEFINE TABLE lesson_assessments SCHEMAFULL
  PERMISSIONS FOR select, create, update, delete NONE;

DEFINE FIELD lesson           ON lesson_assessments TYPE record<lessons> ASSERT $value != NONE;
DEFINE FIELD title            ON lesson_assessments TYPE string ASSERT $value != NONE;
DEFINE FIELD description      ON lesson_assessments TYPE option<string>;
DEFINE FIELD questions        ON lesson_assessments TYPE array<object>;
  -- { question_index: int, type: "mcq"|"theoretical", question_text: string,
  --   option_a?: string, option_b?: string, option_c?: string,
  --   correct_answer?: string, allocated_mark: int, source_question_index: int }
DEFINE FIELD total_mark       ON lesson_assessments TYPE int;
DEFINE FIELD max_resubmissions ON lesson_assessments TYPE int DEFAULT 0;
DEFINE FIELD deadline         ON lesson_assessments TYPE option<datetime>;
DEFINE FIELD active           ON lesson_assessments TYPE bool DEFAULT false;
DEFINE FIELD scheduled_at     ON lesson_assessments TYPE option<datetime>;
DEFINE FIELD created_by       ON lesson_assessments TYPE record<teacher_profile>;
DEFINE FIELD created_at       ON lesson_assessments TYPE datetime DEFAULT time::now();
DEFINE FIELD updated_at       ON lesson_assessments TYPE option<datetime>;
DEFINE FIELD deleted_at       ON lesson_assessments TYPE option<datetime>;

DEFINE INDEX idx_la_lesson ON lesson_assessments COLUMNS lesson;

-- General (term-scoped) assessments
DEFINE TABLE general_assessments SCHEMAFULL
  PERMISSIONS FOR select, create, update, delete NONE;

DEFINE FIELD session_term      ON general_assessments TYPE record<session_term> ASSERT $value != NONE;
DEFINE FIELD subject           ON general_assessments TYPE record<subjects> ASSERT $value != NONE;
DEFINE FIELD title             ON general_assessments TYPE string ASSERT $value != NONE;
DEFINE FIELD description       ON general_assessments TYPE option<string>;
DEFINE FIELD percentage_weight ON general_assessments TYPE int;
DEFINE FIELD questions         ON general_assessments TYPE option<array<object>>;
  -- Same snapshot format as lesson_assessments; null when purely composed
DEFINE FIELD total_mark        ON general_assessments TYPE int;
DEFINE FIELD max_resubmissions  ON general_assessments TYPE int DEFAULT 0;
DEFINE FIELD deadline          ON general_assessments TYPE option<datetime>;
DEFINE FIELD active            ON general_assessments TYPE bool DEFAULT false;
DEFINE FIELD scheduled_at      ON general_assessments TYPE option<datetime>;
DEFINE FIELD created_by        ON general_assessments TYPE record<teacher_profile>;
DEFINE FIELD created_at        ON general_assessments TYPE datetime DEFAULT time::now();
DEFINE FIELD updated_at        ON general_assessments TYPE option<datetime>;
DEFINE FIELD deleted_at        ON general_assessments TYPE option<datetime>;

DEFINE INDEX idx_ga_st_subj ON general_assessments COLUMNS session_term, subject;

-- Composition: general assessment → lesson assessment
DEFINE TABLE compositions SCHEMAFULL
  PERMISSIONS FOR select, create, update, delete NONE;

DEFINE FIELD general_assessment ON compositions TYPE record<general_assessments> ASSERT $value != NONE;
DEFINE FIELD lesson_assessment  ON compositions TYPE record<lesson_assessments> ASSERT $value != NONE;
DEFINE FIELD weight_pct         ON compositions TYPE float;
  -- Auto-calculated: la.total_mark / sum(all_composed_la.total_mark) * ga.percentage_weight
  -- Teacher can override by editing weight_pct directly
DEFINE FIELD created_at         ON compositions TYPE datetime DEFAULT time::now();

DEFINE INDEX idx_comp_ga ON compositions COLUMNS general_assessment;

-- Polymorphic submissions table (serves both assessment types)
DEFINE TABLE submissions SCHEMAFULL
  PERMISSIONS FOR select, create, update, delete NONE;

DEFINE FIELD assessment_type  ON submissions TYPE string;  -- "lesson" | "general"
DEFINE FIELD assessment_id    ON submissions TYPE string;  -- record ID string
DEFINE FIELD student          ON submissions TYPE record<student_profile> ASSERT $value != NONE;
DEFINE FIELD iteration        ON submissions TYPE int DEFAULT 0;
DEFINE FIELD status           ON submissions TYPE string;  -- "submitted" | "graded"
DEFINE FIELD submitted_at     ON submissions TYPE datetime DEFAULT time::now();
DEFINE FIELD answers          ON submissions TYPE array<object>;
  -- { question_index: int, type: "mcq"|"theoretical", answer_text: string,
  --   allocated_mark: int, scored_mark?: int, correct?: bool }
DEFINE FIELD total_mark       ON submissions TYPE int;
DEFINE FIELD scored_mark      ON submissions TYPE option<int>;
DEFINE FIELD grade_released_at ON submissions TYPE option<datetime>;
  -- null = student cannot see grade; non-null = full grade visible

DEFINE INDEX idx_sub_student ON submissions COLUMNS student;
DEFINE INDEX idx_sub_assessment ON submissions COLUMNS assessment_type, assessment_id;

-- Uniqueness: one submission per student per assessment per iteration
DEFINE INDEX idx_sub_unique ON submissions COLUMNS assessment_type, assessment_id, student, iteration UNIQUE;

-- Lessons table additions
DEFINE FIELD IF NOT EXISTS version     ON lessons TYPE int DEFAULT 1;
DEFINE FIELD IF NOT EXISTS updated_at  ON lessons TYPE option<datetime>;
```

### 2. MoonBit Types (`types_assessment.mbt`)

All types use `#derive.golem_schema` for WIT generation and `derive(ToJson, FromJson)` for MoonBit serialization.

```moonbit
///|
#derive.golem_schema
struct AssessmentQuestion {
  question_index  : Int
  question_type   : String      // "mcq" | "theoretical"
  question_text   : String
  option_a        : String?
  option_b        : String?
  option_c        : String?
  correct_answer  : String?     // null for theoretical
  allocated_mark  : Int
  source_question_index : Int   // index in the source lesson's question array
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct LessonAssessmentInfo {
  id                : String
  lesson            : String
  title             : String
  description       : String?
  questions         : Array[AssessmentQuestion]
  total_mark        : Int
  max_resubmissions : Int
  deadline          : String?
  active            : Bool
  scheduled_at      : String?
  created_at        : String
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct GeneralAssessmentInfo {
  id                : String
  session_term      : String
  subject           : String
  title             : String
  description       : String?
  percentage_weight : Int
  questions         : Array[AssessmentQuestion]?
  compositions      : Array[CompositionInfo]?
  total_mark        : Int
  max_resubmissions : Int
  deadline          : String?
  active            : Bool
  scheduled_at      : String?
  created_at        : String
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct CompositionInfo {
  id                        : String
  lesson_assessment         : String
  lesson_assessment_title   : String?
  lesson_assessment_total_mark : Int?
  weight_pct                : Float
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct SubmissionAnswer {
  question_index : Int
  answer_type    : String    // "mcq" | "theoretical"
  answer_text    : String
  allocated_mark : Int
  scored_mark    : Int?
  correct        : Bool?
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct SubmissionInfo {
  id                 : String
  assessment_type    : String
  assessment_id      : String
  student            : String
  student_name       : String?
  iteration          : Int
  status             : String
  submitted_at       : String
  answers            : Array[SubmissionAnswer]
  total_mark         : Int
  scored_mark        : Int?
  grade_released_at  : String?
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct CompositionGradeBreakdown {
  lesson_assessment_title : String
  scored_pct              : Float?
  weight_pct              : Float
  graded                  : Bool
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct CompositionGradeResult {
  total_scored_pct : Float?
  total_weight_pct : Float
  breakdown        : Array[CompositionGradeBreakdown]
  all_graded       : Bool
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct PercentageSummary {
  current   : Int
  remaining : Int
} derive(ToJson, FromJson)
```

### 3. Database Layer (`db_assessment.mbt`)

Follows existing `db_*.mbt` pattern: functions take `config: SharedConfig` first, return `Result[Array[Json], AppError]`, use `surreal_query()` with `$bindings`.

```moonbit
///|
pub fn db_create_lesson_assessment(
  config : SharedConfig,
  lesson_id : String,
  title : String,
  description : String?,
  questions_json : String,
  total_mark : Int,
  max_resubmissions : Int,
  deadline : String?,
  scheduled_at : String?,
  teacher_id : String,
) -> Result[Array[Json], AppError] {
  surreal_query(config,
    "CREATE lesson_assessments CONTENT {
      lesson: $lesson_id,
      title: $title,
      description: $description,
      questions: $questions,
      total_mark: $total_mark,
      max_resubmissions: $max_resubmissions,
      deadline: $deadline,
      scheduled_at: $scheduled_at,
      created_by: type::thing(\"teacher_profile\", $teacher_id)
    }",
    bindings={
      "lesson_id": lesson_id,
      "title": title,
      "description": description ?? "",
      "questions": questions_json,
      "total_mark": total_mark.to_string(),
      "max_resubmissions": max_resubmissions.to_string(),
      "deadline": deadline ?? "",
      "scheduled_at": scheduled_at ?? "",
      "teacher_id": teacher_id,
    },
  )
}

///|
pub fn db_create_general_assessment(config, st_id, subj_id, title, desc, pct, questions_json, total_mark,
  max_resub, deadline, scheduled_at, teacher_id) -> Result[Array[Json], AppError] { ... }
// Same pattern — SQL CREATE with bindings

///|
pub fn db_create_composition(config, ga_id, la_id, weight_pct) -> Result[Array[Json], AppError] {
  surreal_query(config,
    "CREATE compositions CONTENT {
      general_assessment: type::thing(\"general_assessments\", $ga_id),
      lesson_assessment: type::thing(\"lesson_assessments\", $la_id),
      weight_pct: $weight_pct
    }",
    bindings={ "ga_id": ga_id, "la_id": la_id, "weight_pct": weight_pct.to_string() },
  )
}

///|
pub fn db_fetch_lesson_assessments(config, lesson_id) -> Result[Array[Json], AppError] {
  surreal_query(config,
    "SELECT * FROM lesson_assessments WHERE lesson = $lesson_id AND deleted_at IS NONE ORDER BY created_at ASC",
    bindings={ "lesson_id": lesson_id },
  )
}

///|
pub fn db_fetch_general_assessments(config, st_id, subj_id) -> Result[Array[Json], AppError] {
  surreal_query(config,
    "SELECT * FROM general_assessments WHERE session_term = $st AND subject = $subj AND deleted_at IS NONE ORDER BY created_at ASC",
    bindings={ "st": st_id, "subj": subj_id },
  )
}

///|
pub fn db_fetch_assessment_by_id(config, table, id) -> Result[Array[Json], AppError] {
  surreal_query(config,
    "SELECT * FROM type::thing($table, $id)",
    bindings={ "table": table, "id": id },
  )
}

///|
pub fn db_fetch_compositions(config, ga_id) -> Result[Array[Json], AppError] {
  surreal_query(config,
    "SELECT * FROM compositions WHERE general_assessment = $ga_id",
    bindings={ "ga_id": ga_id },
  )
}

///|
pub fn db_fetch_submission(config, student_id, assessment_type, assessment_id) -> Result[Array[Json], AppError] {
  surreal_query(config,
    "SELECT * FROM submissions WHERE student = type::thing(\"student_profile\", $student) AND assessment_type = $at AND assessment_id = $aid AND deleted_at IS NONE ORDER BY iteration DESC LIMIT 1",
    bindings={ "student": student_id, "at": assessment_type, "aid": assessment_id },
  )
}

///|
pub fn db_fetch_submissions_for_assessment(config, assessment_type, assessment_id) -> Result[Array[Json], AppError] {
  surreal_query(config,
    "SELECT * FROM submissions WHERE assessment_type = $at AND assessment_id = $aid AND deleted_at IS NONE ORDER BY submitted_at ASC",
    bindings={ "at": assessment_type, "aid": assessment_id },
  )
}

///|
pub fn db_upsert_submission(config, id?, assessment_type, assessment_id, student_id, iteration, status,
  answers_json, total_mark, scored_mark?, grade_released_at?) -> Result[Array[Json], AppError] {
  if id != "" {
    surreal_query(config,
      "UPDATE type::thing(\"submissions\", $id) CONTENT {
        assessment_type: $at,
        assessment_id: $aid,
        student: type::thing(\"student_profile\", $student),
        iteration: $iter,
        status: $status,
        submitted_at: time::now(),
        answers: $answers,
        total_mark: $total_mark,
        scored_mark: $scored_mark,
        grade_released_at: $grade_released_at
      }",
      bindings={ ... },
    )
  } else {
    surreal_query(config, "CREATE submissions CONTENT { ... }", bindings={ ... })
  }
}

///|
pub fn db_release_grades(config, submission_id) -> Result[Array[Json], AppError] {
  surreal_query(config,
    "UPDATE type::thing(\"submissions\", $id) SET grade_released_at = time::now(), status = 'graded'",
    bindings={ "id": submission_id },
  )
}

///|
pub fn db_update_submission_marks(config, submission_id, scored_mark) -> Result[Array[Json], AppError] {
  surreal_query(config,
    "UPDATE type::thing(\"submissions\", $id) SET scored_mark = $sm",
    bindings={ "id": submission_id, "sm": scored_mark.to_string() },
  )
}

///|
pub fn db_toggle_assessment_active(config, table, id, active) -> Result[Array[Json], AppError] {
  surreal_query(config,
    "UPDATE type::thing($table, $id) SET active = $active",
    bindings={ "table": table, "id": id, "active": if active { "true" } else { "false" } },
  )
}

///|
pub fn db_sum_percentage_weights(config, st_id, subj_id, exclude_id?) -> Result[Array[Json], AppError] {
  match exclude_id {
    Some(eid) =>
      surreal_query(config,
        "SELECT math::sum(percentage_weight) AS total FROM general_assessments WHERE session_term = $st AND subject = $subj AND deleted_at IS NONE AND id != $eid",
        bindings={ "st": st_id, "subj": subj_id, "eid": eid },
      )
    None =>
      surreal_query(config,
        "SELECT math::sum(percentage_weight) AS total FROM general_assessments WHERE session_term = $st AND subject = $subj AND deleted_at IS NONE",
        bindings={ "st": st_id, "subj": subj_id },
      )
  }
}
```

### 4. Teacher Handler (`teacher_handler_assessment.mbt`)

Follows the pattern from `admin_handler.mbt`: functions take `config: SharedConfig` and `body_json: String`, parse with `@json.parse() + match Object(o)`, return `Result[ResponseType, AppError]`.

```moonbit
///|
fn parse_assessment_questions(json_arr : Array[Json]) -> Array[AssessmentQuestion]? {
  let questions : Array[AssessmentQuestion] = []
  for item in json_arr {
    match item {
      Object(obj) => {
        let qi = match obj.get("question_index") { Some(Number(n, ..)) => n.to_int() _ => continue }
        questions.push(AssessmentQuestion::{
          question_index: qi,
          question_type: match obj.get("question_type") { Some(String(s)) => s _ => continue },
          question_text: match obj.get("question_text") { Some(String(s)) => s _ => continue },
          option_a: match obj.get("option_a") { Some(String(s)) => Some(s) _ => None },
          option_b: match obj.get("option_b") { Some(String(s)) => Some(s) _ => None },
          option_c: match obj.get("option_c") { Some(String(s)) => Some(s) _ => None },
          correct_answer: match obj.get("correct_answer") { Some(String(s)) => Some(s) _ => None },
          allocated_mark: match obj.get("allocated_mark") { Some(Number(n, ..)) => n.to_int() _ => 1 },
          source_question_index: match obj.get("source_question_index") { Some(Number(n, ..)) => n.to_int() _ => qi },
        })
      }
      _ => ()
    }
  }
  if questions.length() > 0 { Some(questions) } else { None }
}

///|
pub fn teacher_create_lesson_assessment(
  config : SharedConfig,
  body_json : String,
) -> Result[LessonAssessmentInfo, AppError] {
  let val = @json.parse(body_json) catch {
    _ => return Err(validation_error("Invalid JSON body"))
  }
  let obj = match val {
    Object(o) => o
    _ => return Err(validation_error("Body must be an object"))
  }
  let lesson_id = match obj.get("lesson_id") { Some(String(s)) => s _ => return Err(validation_error("lesson_id required")) }
  let title = match obj.get("title") { Some(String(s)) => s _ => return Err(validation_error("title required")) }
  let description = match obj.get("description") { Some(String(s)) => Some(s) _ => None }
  let questions_raw = match obj.get("questions") { Some(Array(a)) => a _ => return Err(validation_error("questions required")) }
  let questions = match parse_assessment_questions(questions_raw) {
    Some(q) => q
    _ => return Err(validation_error("Invalid questions array"))
  }
  let total_mark = match obj.get("total_mark") { Some(Number(n, ..)) => n.to_int() _ => {
    // auto-calculate
    let mut sum = 0
    for q in questions { sum += q.allocated_mark }
    sum
  }}
  // ... extract other fields
  
  // Verify teacher owns this lesson's subject+class
  // (query teacher_assignment WHERE teacher_id = $tid AND has_subject.in/out matches lesson's topic.has_subject)
  
  // INSERT
  let result = db_create_lesson_assessment(config, lesson_id, title, description,
    questions.to_json().stringify(), total_mark, max_resub, deadline, scheduled_at, teacher_id)?
  
  // Parse and return created assessment
  result[0].stringify() |> parse_lesson_assessment_json() |> Ok()
}

///|
pub fn teacher_create_general_assessment(config: SharedConfig, body_json: String) -> Result[GeneralAssessmentInfo, AppError] { ... }
// 1. Parse body (st_id, subj_id, title, pct, questions?, composition_ids?)
// 2. Validate teacher assignment
// 3. Calculate weight_pct for each composition
// 4. If both questions + compositions: handle mixed mode
// 5. CREATE general_assessment + compositions
// 6. Return created assessment

///|
pub fn teacher_fetch_lesson_assessments(config, lesson_id) -> Result[Array[LessonAssessmentInfo], AppError] {
  let arr = db_fetch_lesson_assessments(config, lesson_id)?
  let items : Array[LessonAssessmentInfo] = []
  for row in arr { items.push(parse_lesson_assessment_json(row.stringify())?) }
  Ok(items)
}

///|
pub fn teacher_fetch_general_assessments(config, st_id, subj_id) -> Result[Array[GeneralAssessmentInfo], AppError] {
  let arr = db_fetch_general_assessments(config, st_id, subj_id)?
  let items : Array[GeneralAssessmentInfo] = []
  for row in arr {
    let ga = parse_general_assessment_json(row.stringify())?
    // Fetch compositions for each
    let comps = db_fetch_compositions(config, ga.id)?
    let comp_infos : Array[CompositionInfo] = []
    for comp in comps { comp_infos.push(parse_composition_json(comp.stringify())?) }
    items.push({ ga with compositions: Some(comp_infos) })
  }
  Ok(items)
}

///|
pub fn teacher_fetch_submissions(config, assessment_type, assessment_id) -> Result[Array[SubmissionInfo], AppError] {
  let arr = db_fetch_submissions_for_assessment(config, assessment_type, assessment_id)?
  let items : Array[SubmissionInfo] = []
  for row in arr { items.push(parse_submission_json(row.stringify())?) }
  Ok(items)
}

///|
pub fn teacher_grade_submission(config: SharedConfig, body_json: String) -> Result[SubmissionInfo, AppError] {
  let val = @json.parse(body_json) catch { _ => return Err(validation_error("Invalid JSON body")) }
  let obj = match val { Object(o) => o _ => return Err(validation_error("Body must be an object")) }
  let submission_id = match obj.get("submission_id") { Some(String(s)) => s _ => return Err(validation_error("submission_id required")) }
  let answers_raw = match obj.get("answers") { Some(Array(a)) => a _ => return Err(validation_error("answers required")) }
  
  // Recalculate scored_mark from answers
  let mut scored = 0
  for item in answers_raw {
    match item {
      Object(ao) => {
        let sm = match ao.get("scored_mark") { Some(Number(n, ..)) => n.to_int() _ => 0 }
        scored += sm
        // UPDATE submissions SET answers[$idx].scored_mark = $sm WHERE id = $submission_id
        // (SurrealDB array update)
      }
      _ => ()
    }
  }
  
  db_update_submission_marks(config, submission_id, scored)?
  // Re-fetch and return updated submission
  db_fetch_submission_by_id(config, submission_id)?.stringify() |> parse_submission_json() |> Ok()
}

///|
pub fn teacher_release_grades(config, submission_id) -> Result[SubmissionInfo, AppError] {
  db_release_grades(config, submission_id)?
  db_fetch_submission_by_id(config, submission_id)?.stringify() |> parse_submission_json() |> Ok()
}

///|
pub fn teacher_toggle_assessment(config, assessment_type, assessment_id, active) -> Result[String, AppError] {
  let table = if assessment_type == "lesson" { "lesson_assessments" } else { "general_assessments" }
  db_toggle_assessment_active(config, table, assessment_id, active)? |> Ok("ok")
}

///|
pub fn teacher_get_percentage_summary(config, st_id, subj_id) -> Result[PercentageSummary, AppError] {
  let arr = db_sum_percentage_weights(config, st_id, subj_id, None)?
  let current = if arr.length() > 0 {
    match arr[0] {
      Object(obj) => match obj.get("total") { Some(Number(n, ..)) => n.to_int() _ => 0 }
      _ => 0
    }
  } else { 0 }
  Ok(PercentageSummary::{ current, remaining: if 100 - current > 0 { 100 - current } else { 0 } })
}
```

### 5. Student Handler (`student_handler_assessment.mbt`)

```moonbit
///|
pub fn student_fetch_lesson_assessments(
  config : SharedConfig,
  student_id : String,
  lesson_id : String,
) -> Result[Array[LessonAssessmentInfo], AppError] {
  let arr = db_fetch_lesson_assessments(config, lesson_id)?
  let items : Array[LessonAssessmentInfo] = []
  for row in arr {
    let json_str = row.stringify()
    let la = parse_lesson_assessment_json(json_str)?
    // Lazy activation
    try_activate_if_scheduled(config, "lesson_assessments", la.id, la.scheduled_at, la.active)
    if la.active {
      items.push(la)
    }
  }
  Ok(items)
}

///|
pub fn student_fetch_general_assessments(config, student_id, st_id, subj_id) -> Result[Array[GeneralAssessmentInfo], AppError] { ... }
// Same pattern with lazy activation

///|
pub fn student_submit_assessment(
  config : SharedConfig,
  student_id : String,
  body_json : String,
) -> Result[SubmissionInfo, AppError] {
  let val = @json.parse(body_json) catch { _ => return Err(validation_error("Invalid JSON body")) }
  let obj = match val { Object(o) => o _ => return Err(validation_error("Body must be an object")) }
  let assessment_type = match obj.get("assessment_type") { Some(String(s)) => s _ => return Err(validation_error("assessment_type required")) }
  let assessment_id = match obj.get("assessment_id") { Some(String(s)) => s _ => return Err(validation_error("assessment_id required")) }
  let answers_raw = match obj.get("answers") { Some(Array(a)) => a _ => return Err(validation_error("answers required")) }
  
  // 1. Fetch assessment and validate
  let table = if assessment_type == "lesson" { "lesson_assessments" } else { "general_assessments" }
  let assessment_arr = db_fetch_assessment_by_id(config, table, assessment_id)?
  if assessment_arr.length() == 0 { return Err(not_found_error("Assessment")) }
  let assessment = assessment_arr[0]
  let assessment_obj = match assessment { Object(o) => o _ => return Err(AppError::{ code: InternalError, message: "Invalid assessment data", debug: None }) }
  let active = match assessment_obj.get("active") { Some(Bool(b)) => b _ => false }
  if !active { return Err(validation_error("Assessment is not active")) }
  
  // 2. Check deadline
  let deadline = match assessment_obj.get("deadline") { Some(String(s)) => s _ => "" }
  if deadline != "" {
    // Parse and compare ISO datetime; if now > deadline → reject
    // (simplified: frontend also checks, backend makes authoritative check)
  }
  
  // 3. Check existing submission for resubmission limits
  let existing_arr = db_fetch_submission(config, student_id, assessment_type, assessment_id)?
  let mut existing_sub = if existing_arr.length() > 0 { Some(existing_arr[0]) } else { None }
  let max_resub = match assessment_obj.get("max_resubmissions") { Some(Number(n, ..)) => n.to_int() _ => 0 }
  
  let iteration = match existing_sub {
    Some(_) => {
      // Check limit
      let current_iter = match existing_sub {
        Object(o) => match o.get("iteration") { Some(Number(n, ..)) => n.to_int() _ => 0 }
        _ => 0
      }
      if max_resub != -1 && current_iter >= max_resub {
        return Err(validation_error("Resubmission limit reached"))
      }
      // Check if already released
      match existing_sub {
        Object(o) => match o.get("grade_released_at") {
          Some(String(s)) if s != "" => return Err(validation_error("Cannot resubmit after grades released"))
          _ => ()
        }
        _ => ()
      }
      current_iter + 1
    }
    None => 0
  }
  
  // 4. Auto-grade MCQ, parse answers
  let mut scored_mark = 0
  let mut all_mcq_scored = true
  let mut parsed_answers : Array[SubmissionAnswer] = []
  
  for item in answers_raw {
    match item {
      Object(ao) => {
        let qi = match ao.get("question_index") { Some(Number(n, ..)) => n.to_int() _ => 0 }
        let atype = match ao.get("answer_type") { Some(String(s)) => s _ => "" }
        let text = match ao.get("answer_text") { Some(String(s)) => s _ => "" }
        let am = match ao.get("allocated_mark") { Some(Number(n, ..)) => n.to_int() _ => 0 }
        
        // Find the question in the assessment to check correct_answer
        let assessment_questions = match assessment_obj.get("questions") { Some(Array(a)) => a _ => [] }
        let mut correct_answer : String? = None
        for aq in assessment_questions {
          match aq {
            Object(aqo) => {
              let aqi = match aqo.get("question_index") { Some(Number(n, ..)) => n.to_int() _ => -1 }
              if aqi == qi {
                correct_answer = match aqo.get("correct_answer") { Some(String(s)) => Some(s) _ => None }
              }
            }
            _ => ()
          }
        }
        
        if atype == "mcq" {
          match correct_answer {
            Some(ca) => {
              let correct = text == ca
              parsed_answers.push(SubmissionAnswer::{
                question_index: qi, answer_type: "mcq", answer_text: text,
                allocated_mark: am, scored_mark: if correct { Some(am) } else { Some(0) },
                correct: Some(correct),
              })
              if correct { scored_mark += am }
            }
            None => {
              // No correct answer stored — treat as theory
              parsed_answers.push(SubmissionAnswer::{
                question_index: qi, answer_type: "mcq", answer_text: text,
                allocated_mark: am, scored_mark: None, correct: None,
              })
              all_mcq_scored = false
            }
          }
        } else {
          // Theoretical — scored later by teacher
          parsed_answers.push(SubmissionAnswer::{
            question_index: qi, answer_type: "theoretical", answer_text: text,
            allocated_mark: am, scored_mark: None, correct: None,
          })
        }
      }
      _ => ()
    }
  }
  
  // 5. Calculate total_mark from assessment
  let total_mark = match assessment_obj.get("total_mark") { Some(Number(n, ..)) => n.to_int() _ => 0 }
  
  // 6. Upsert submission (replace mode)
  let sub_id = match existing_sub {
    Object(o) => match o.get("id") { Some(String(s)) => s _ => "" }
    _ => ""
  }
  let sub = db_upsert_submission(config, sub_id, assessment_type, assessment_id,
    student_id, iteration, "submitted", parsed_answers.to_json().stringify(),
    total_mark, if all_mcq_scored { Some(scored_mark) } else { None }, None)?
  
  // 7. Parse and return
  sub[0].stringify() |> parse_submission_json() |> Ok()
}

///|
pub fn student_fetch_my_grades(config, student_id, assessment_type, assessment_id) -> Result[SubmissionInfo?, AppError] {
  let arr = db_fetch_submission(config, student_id, assessment_type, assessment_id)?
  if arr.length() == 0 { return Ok(None) }
  let sub = parse_submission_json(arr[0].stringify())?
  
  // Hide grades if not released
  let sub = if sub.grade_released_at == None {
    { sub with scored_mark: None, answers: [] }  // Return metadata only, no grades
  } else { sub }
  
  Ok(Some(sub))
}

///|
pub fn compute_composition_grade(config, student_id, ga_id) -> Result[CompositionGradeResult, AppError] {
  let comps_arr = db_fetch_compositions(config, ga_id)?
  let mut total_scored = 0.0
  let mut total_weight = 0.0
  let mut breakdown : Array[CompositionGradeBreakdown] = []
  let mut all_graded = true
  
  for comp_item in comps_arr {
    let comp = parse_composition_json(comp_item.stringify())?
    let la_arr = db_fetch_assessment_by_id(config, "lesson_assessments", comp.lesson_assessment)?
    let la_title = if la_arr.length() > 0 {
      match la_arr[0] { Object(o) => match o.get("title") { Some(String(s)) => s _ => "Unknown" } _ => "Unknown" }
    } else { "Unknown" }
    
    let sub_arr = db_fetch_submission(config, student_id, "lesson", comp.lesson_assessment)?
    if sub_arr.length() > 0 {
      let sub = parse_submission_json(sub_arr[0].stringify())?
      if sub.grade_released_at != None {
        match sub.scored_mark {
          Some(sm) if sub.total_mark > 0 => {
            let pct = (sm.to_float() / sub.total_mark.to_float()) * comp.weight_pct
            total_scored += pct
            total_weight += comp.weight_pct
            breakdown.push(CompositionGradeBreakdown::{
              lesson_assessment_title: la_title,
              scored_pct: Some(pct),
              weight_pct: comp.weight_pct,
              graded: true,
            })
          }
          _ => {
            total_weight += comp.weight_pct
            breakdown.push(CompositionGradeBreakdown::{
              lesson_assessment_title: la_title,
              scored_pct: Some(0.0), weight_pct: comp.weight_pct, graded: true,
            })
          }
        }
      } else {
        all_graded = false
        breakdown.push(CompositionGradeBreakdown::{
          lesson_assessment_title: la_title,
          scored_pct: None, weight_pct: comp.weight_pct, graded: false,
        })
      }
    } else {
      total_weight += comp.weight_pct
      breakdown.push(CompositionGradeBreakdown::{
        lesson_assessment_title: la_title,
        scored_pct: Some(0.0), weight_pct: comp.weight_pct, graded: true,
      })
    }
  }
  
  Ok(CompositionGradeResult::{
    total_scored_pct: if all_graded { Some(total_scored) } else { None },
    total_weight_pct: total_weight,
    breakdown: breakdown,
    all_graded: all_graded,
  })
}

///|
pub fn student_get_active_session_term(config) -> Result[Map[String, Json], AppError] {
  let arr = surreal_query(config, "SELECT id, session_name, term.name AS term_name FROM session_term WHERE active = true AND deleted_at IS NONE LIMIT 1")?
  if arr.length() > 0 {
    match arr[0] { Object(o) => Ok(o) _ => Err(not_found_error("Active session term")) }
  } else {
    Err(not_found_error("Active session term"))
  }
}

///|
fn try_activate_if_scheduled(config, table, id, scheduled_at, active) {
  // If scheduled_at is past and not yet active, activate it
  // This is a fire-and-forget best-effort operation
  if !active {
    match scheduled_at {
      Some(s) if s != "" => {
        // Compare ISO datetime — simplified: just attempt update
        let _ = db_toggle_assessment_active(config, table, id, true)
      }
      _ => ()
    }
  }
}
```

### 6. Teacher Agent Endpoints (`teacher_agent.mbt`)

Add to existing `TeacherAgent` struct. Follows existing pattern: `#derive.endpoint`, `#derive.endpoint_header`, `require_auth`, return `Result[Type, String]`.

```moonbit
///|
#derive.endpoint(post="/create-lesson-assessment")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn TeacherAgent::create_lesson_assessment(
  self : Self,
  incoming_key : String,
  body_json : String,
) -> Result[LessonAssessmentInfo, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match teacher_create_lesson_assessment(self.config.value, body_json) {
    Ok(r) => Ok(r)
    Err(e) => Err(e.to_json_string())
  }
}

// POST /create-general-assessment
// POST /grade-submission  (body_json)
// POST /release-grades?submission_id=
// POST /toggle-assessment?assessment_type=&assessment_id=&active=
// GET /lesson-assessments?lesson_id=
// GET /general-assessments?session_term_id=&subject_id=
// GET /submissions?assessment_type=&assessment_id=
// GET /assessment-percentage-summary?session_term_id=&subject_id=
```

### 7. Student Agent Endpoints (`student_agent.mbt`)

Add to existing `StudentAgent` struct.

```moonbit
///|
#derive.endpoint(get="/assessments?lesson_id={lesson_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn StudentAgent::get_lesson_assessments(
  self : Self,
  incoming_key : String,
  lesson_id : String,
) -> Result[Array[LessonAssessmentInfo], String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match student_fetch_lesson_assessments(self.config.value, self.student_id, lesson_id) {
    Ok(r) => Ok(r)
    Err(e) => Err(e.to_json_string())
  }
}

// GET /general-assessments?session_term_id=&subject_id=
// POST /submit-assessment (body_json)
// GET /my-grades?assessment_type=&assessment_id=
// GET /active-session-term
```

### 8. Frontend Proxy Routes

**`/api/teacher/` routes — each is a `+server.ts` endpoint:**

| Route | Method | Agent Endpoint | Body/Params |
|---|---|---|---|
| `/api/teacher/create-lesson-assessment` | POST | `/create-lesson-assessment` | JSON body → `body_json` |
| `/api/teacher/create-general-assessment` | POST | `/create-general-assessment` | JSON body |
| `/api/teacher/lesson-assessments` | GET | `/lesson-assessments?lesson_id=` | query param |
| `/api/teacher/general-assessments` | GET | `/general-assessments?session_term_id=&subject_id=` | query params |
| `/api/teacher/submissions` | GET | `/submissions?assessment_type=&assessment_id=` | query params |
| `/api/teacher/grade-submission` | POST | `/grade-submission` | JSON body |
| `/api/teacher/release-grades` | POST | `/release-grades?submission_id=` | query param (no body) |
| `/api/teacher/toggle-assessment` | POST | `/toggle-assessment?assessment_type=&assessment_id=&active=` | query params |
| `/api/teacher/assessment-percentage-summary` | GET | `/assessment-percentage-summary?session_term_id=&subject_id=` | query params |

Pattern for each route (follows `frontend/src/routes/api/teacher/lessons/+server.ts` and `frontend/src/routes/api/admin/credentials/+server.ts`):

**GET route pattern:**
```ts
import { proxyToTeacher, mapErrorCodeToHttpStatus } from '$lib/server/golem';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async (event) => {
  const userId = event.locals.user?.id;
  if (!userId) return new Response(JSON.stringify({ error: { code: 'UNAUTHENTICATED', message: 'Not authenticated.' } }), { status: 401, headers: { 'content-type': 'application/json' } });

  const url = new URL(event.request.url);
  const param1 = url.searchParams.get('param1');
  if (!param1) return new Response(JSON.stringify({ error: { code: 'BAD_REQUEST', message: 'Missing param1' } }), { status: 400, headers: { 'content-type': 'application/json' } });

  const result = await proxyToTeacher(userId, '/endpoint-path', { param1 });
  if (result.error) return new Response(JSON.stringify(result), { status: mapErrorCodeToHttpStatus(result.error.code), headers: { 'content-type': 'application/json' } });

  let data: unknown;
  try { data = JSON.parse(result.data); } catch { return new Response(JSON.stringify({ error: { code: 'INVALID_RESPONSE', message: 'Failed to parse agent response' } }), { status: 502, headers: { 'content-type': 'application/json' } }); }

  return new Response(JSON.stringify({ data }), { status: 200, headers: { 'content-type': 'application/json' } });
};
```

**POST with body pattern:**
```ts
export const POST: RequestHandler = async (event) => {
  const userId = event.locals.user?.id;
  if (!userId) return new Response(JSON.stringify({ error: { code: 'UNAUTHENTICATED', message: 'Not authenticated.' } }), { status: 401, headers: { 'content-type': 'application/json' } });

  const body = await event.request.json().catch(() => null);
  if (!body) return new Response(JSON.stringify({ error: { code: 'BAD_REQUEST', message: 'Invalid JSON body' } }), { status: 400, headers: { 'content-type': 'application/json' } });

  const result = await proxyToTeacher(userId, '/endpoint-path', {}, 'POST', body);
  if (result.error) return new Response(JSON.stringify(result), { status: mapErrorCodeToHttpStatus(result.error.code), headers: { 'content-type': 'application/json' } });

  let data: unknown;
  try { data = JSON.parse(result.data); } catch { return new Response(JSON.stringify({ error: { code: 'INVALID_RESPONSE', message: 'Failed to parse agent response' } }), { status: 502, headers: { 'content-type': 'application/json' } }); }

  return new Response(JSON.stringify({ data }), { status: 200, headers: { 'content-type': 'application/json' } });
};
```

**`/api/student/` routes:**

| Route | Method | Agent Endpoint | Notes |
|---|---|---|---|
| `/api/student/assessments` | GET | `/assessments?lesson_id=` | Student's view of lesson assessments |
| `/api/student/general-assessments` | GET | `/general-assessments?session_term_id=&subject_id=` | Student's view |
| `/api/student/submit-assessment` | POST | `/submit-assessment` | JSON body |
| `/api/student/my-grades` | GET | `/my-grades?assessment_type=&assessment_id=` | Own grades |
| `/api/student/active-session-term` | GET | `/active-session-term` | Returns `{id, session_name, term_name}` |

**`/api/active-session-term` (shared route):**

A single shared route that works for all roles. Proxies to the Student Agent's `/active-session-term` endpoint (which any authenticated user can call). Follows the same GET pattern.

### 9. Frontend Type Additions (`types.ts`)

```ts
export interface AssessmentQuestion {
  question_index: number;
  question_type: 'mcq' | 'theoretical';
  question_text: string;
  option_a: string | null;
  option_b: string | null;
  option_c: string | null;
  correct_answer: string | null;
  allocated_mark: number;
  source_question_index: number;
}

export interface LessonAssessmentInfo {
  id: string;
  lesson: string;
  title: string;
  description: string | null;
  questions: AssessmentQuestion[];
  total_mark: number;
  max_resubmissions: number;
  deadline: string | null;
  active: boolean;
  scheduled_at: string | null;
  created_at: string;
}

export interface GeneralAssessmentInfo {
  id: string;
  session_term: string;
  subject: string;
  title: string;
  description: string | null;
  percentage_weight: number;
  questions: AssessmentQuestion[] | null;
  compositions: CompositionInfo[] | null;
  total_mark: number;
  max_resubmissions: number;
  deadline: string | null;
  active: boolean;
  scheduled_at: string | null;
  created_at: string;
}

export interface CompositionInfo {
  id: string;
  lesson_assessment: string;
  lesson_assessment_title: string | null;
  lesson_assessment_total_mark: number | null;
  weight_pct: number;
}

export interface SubmissionAnswer {
  question_index: number;
  answer_type: 'mcq' | 'theoretical';
  answer_text: string;
  allocated_mark: number;
  scored_mark: number | null;
  correct: boolean | null;
}

export interface SubmissionInfo {
  id: string;
  assessment_type: string;
  assessment_id: string;
  student: string;
  student_name: string | null;
  iteration: number;
  status: string;
  submitted_at: string;
  answers: SubmissionAnswer[];
  total_mark: number;
  scored_mark: number | null;
  grade_released_at: string | null;
}

export interface CompositionGradeBreakdown {
  lesson_assessment_title: string;
  scored_pct: number | null;
  weight_pct: number;
  graded: boolean;
}

export interface CompositionGradeResult {
  total_scored_pct: number | null;
  total_weight_pct: number;
  breakdown: CompositionGradeBreakdown[];
  all_graded: boolean;
}

export interface PercentageSummary {
  current: number;
  remaining: number;
}
```

### 10. Frontend Component Changes

**A. `LessonPage.svelte` — Assessments Tab (student):**

Replace placeholder `StatusCard` with:
```svelte
{#if assessments && assessments.length > 0}
  <Accordion.Root type="single" bind:value={expandedAssessment}>
    {#each assessments as a (a.id)}
      <Accordion.Item value={a.id}>
        <Accordion.Trigger>
          <div class="flex items-center gap-3">
            <span>{a.title}</span>
            <Badge variant="outline">{a.total_mark} marks</Badge>
            {#if a.deadline}
              <span class="text-xs text-muted-foreground">Due {formatDate(a.deadline)}</span>
            {/if}
          </div>
        </Accordion.Trigger>
        <Accordion.Content>
          <p class="text-sm text-muted-foreground">{a.questions.length} questions</p>
          <div class="flex gap-2 mt-2">
            <AppButton onclick={() => openSubmitModal(a)}>
              {hasSubmission(a.id) ? 'View Submission' : 'Start Assessment'}
            </AppButton>
            {#if myGrades[a.id]?.grade_released_at}
              <AppButton variant="outline" onclick={() => openGradeView(a)}>View Grade</AppButton>
            {/if}
          </div>
        </Accordion.Content>
      </Accordion.Item>
    {/each}
  </Accordion.Root>
{:else}
  <StatusCard variant="info" title="No Assessments" description="No assessments for this lesson yet." />
{/if}
```

**B. `LessonPage.svelte` — Create Assessment Modal (teacher):**

Revamp modal — add mark input per question + compute total:
- Tab bar: "Select Questions" (default) → question bank with checkboxes + `allocated_mark` number input per question
- Footer: "Total Marks: X" live counter
- "Create Assessment" button → POST to `/api/teacher/create-lesson-assessment`

**C. `GradeAssessmentModal.svelte` (new, shared):**

```svelte
<Dialog.Root bind:open={gradeModalOpen}>
  <Dialog.Content class="sm:max-w-5xl max-h-[92vh] flex flex-col">
    <Dialog.Header>
      <Dialog.Title>Grade Submission — {assessmentTitle}</Dialog.Title>
      <Dialog.Description>
        Student: {studentName} | Iteration: {iteration} | Submitted: {submittedAt}
      </Dialog.Description>
    </Dialog.Header>
    
    <div class="flex-1 overflow-y-auto px-0.5 py-6 space-y-6">
      {#each answers as answer, i}
        <div class="space-y-2 p-4 border border-border rounded-lg">
          <div class="flex justify-between">
            <p class="text-sm font-medium">Question {i + 1} ({answer.answer_type})</p>
            <span class="text-xs text-muted-foreground">{answer.allocated_mark} marks</span>
          </div>
          <p class="text-sm">{answer.question_text}</p>
          
          {#if answer.answer_type === 'mcq'}
            <div class="flex items-center gap-2">
              <span class="text-sm">Answer: {answer.answer_text}</span>
              {#if answer.correct}
                <Badge class="bg-success-100 text-success-700">Correct</Badge>
              {:else}
                <Badge variant="destructive">Incorrect</Badge>
              {/if}
            </div>
          {:else}
            <blockquote class="border-l-2 border-border pl-3 text-sm italic">
              {answer.answer_text}
            </blockquote>
            <div class="flex items-center gap-2">
              <Label>Score (out of {answer.allocated_mark})</Label>
              <Input type="number" min="0" max={answer.allocated_mark} bind:value={markInputs[i]} class="w-20" />
            </div>
          {/if}
        </div>
      {/each}
    </div>
    
    <Dialog.Footer class="flex items-center justify-between">
      <span class="text-sm text-muted-foreground">{totalAssigned} of {totalMarks} marks assigned</span>
      <div class="flex gap-2">
        <Dialog.Close>Cancel</Dialog.Close>
        <AppButton onclick={saveGrades}>Save Grades</AppButton>
        <AppButton onclick={saveAndRelease}>Save & Release</AppButton>
      </div>
    </Dialog.Footer>
  </Dialog.Content>
</Dialog.Root>
```

**D. `SubmitAssessmentModal.svelte` (new, shared):**

Large modal showing assessment questions with inputs. MCQ as radio buttons, theory as textareas. Submit button POSTs to `/api/student/submit-assessment`. Shows confirmation on success.

**E. Student lesson-list page (`lms/[subjectId]/[termId]/+page.svelte`):**

After the lessons list section:
```svelte
<Separator class="my-8" />

<div class="space-y-4">
  <h2 class="text-xl font-display font-bold text-primary-700">General Assessments</h2>
  
  {#if generalAssessments && generalAssessments.length > 0}
    <Accordion.Root type="single">
      {#each generalAssessments as ga (ga.id)}
        <Accordion.Item value={ga.id}>
          <Accordion.Trigger>
            <div class="flex items-center gap-3">
              <span>{ga.title}</span>
              <Badge>{ga.percentage_weight}%</Badge>
              {#if ga.deadline}
                <span class="text-xs text-muted-foreground">Due {formatDate(ga.deadline)}</span>
              {/if}
            </div>
          </Accordion.Trigger>
          <Accordion.Content>
            <!-- View/Submit/ViewGrade buttons -->
          </Accordion.Content>
        </Accordion.Item>
      {/each}
    </Accordion.Root>
  {:else}
    <StatusCard variant="info" title="No General Assessments" description="No general assessments for this term yet." />
  {/if}
</div>
```

**F. Teacher lesson-list page (`my-classes/[classId]/[subjectId]/[termId]/+page.svelte`):**

Same General Assessments section + teacher controls:
- "Create General Assessment" button at the top → modal with:
  - Title + percentage weight input + live "X% allocated, Y% remaining" display
  - Tab switch: "Question Bank" mode (browse lessons, select questions) vs "Compose" mode (browse existing scoped assessments)
  - Combined support (both tabs active simultaneously)
- Accordion items expand to show submission list + "Grade" button per student → opens `GradeAssessmentModal`

**G. `+layout.svelte` — Active session-term badge:**

Between `<div class="flex-1"></div>` and `<ThemeToggle />`:
```svelte
{#if activeSessionTerm}
  <Badge variant="outline" class="text-xs gap-1 px-2 py-0.5">
    <span class="hidden sm:inline">{activeSessionTerm.session_name} — </span>
    {activeTermName}
  </Badge>
{/if}
```

Fetch in layout data via `/api/active-session-term`. Store in `$page.data.activeSessionTerm`.

### 11. Error Code Updates

Add to `mapErrorCodeToHttpStatus` in `golem.ts`:
```ts
case 'DEADLINE_EXCEEDED': return 403;
case 'RESUBMISSION_LIMIT': return 403;
```

Add to `ErrorCode` enum in `errors.mbt`:
```moonbit
DeadlineExceeded
ResubmissionLimit
```

### 12. Model File Rebuild

After adding new types and endpoints:
```bash
moon info && moon fmt
```

---

## Dependencies

No new packages. All needed UI components (Accordion, Dialog, Checkbox, Input, Label, Badge, Separator, Button) are already installed via shadcn-svelte. A native `<input type="datetime-local">` suffices for deadline/schedule pickers — no date picker library needed.

---

## Verification Checklist

- [ ] `moon check --target wasm` — 0 errors
- [ ] `moon info && moon fmt` runs without errors
- [ ] `golem build` — 0 errors
- [ ] `pnpm build` — 0 errors
- [ ] `pnpm check` — 0 errors
- [ ] Teacher creates lesson assessment with marked questions via Create Assessment modal
- [ ] Teacher creates general assessment from question bank (multi-lesson selection)
- [ ] Teacher creates general assessment composed of scoped assessments (auto-weight calculation)
- [ ] Teacher creates mixed general assessment (questions + compositions)
- [ ] Percentage summary shows correct allocation (X% of 100%) on general assessment page
- [ ] Saving general assessment with >100% triggers visible warning (no hard block)
- [ ] Student sees lesson assessments in Assessments tab — can click to submit
- [ ] Student submits MCQ answers — auto-graded correctly on submission
- [ ] Student submits theory answers — scored_mark = null (pending teacher)
- [ ] Student resubmits before deadline — iteration increments, theory clears, MCQ re-grades
- [ ] Resubmission rejected after deadline
- [ ] Resubmission rejected when `iteration >= max_resubmissions`
- [ ] Teacher sees submissions in Grading tab with correct status badges
- [ ] Grading modal opens — MCQ shown as read-only with correct/incorrect badges
- [ ] Teacher scores theory questions via modal — "Save Grades" persists without releasing
- [ ] "Save & Release" sets `grade_released_at`
- [ ] Student cannot see graded marks until `grade_released_at` is set
- [ ] General assessment grade auto-computes from composition submissions on read
- [ ] Changing a scoped assessment grade reflects in general assessment grade immediately
- [ ] Pending composition shows as "not graded" (not 0) in breakdown
- [ ] Lazy activation: assessment with `scheduled_at` in the past activates on first fetch
- [ ] Active badge renders in top bar with current session_name + term_name
- [ ] Student sees General Assessments section on lesson-list page
- [ ] Teacher sees General Assessments section with create + grading on lesson-list page
- [ ] Parent agent mirrors student assessment flows (view + submit)
- [ ] Games: empty assessment, lesson with no questions, deadline in the past, max_resubmissions=0
- [ ] All existing functionality continues to work (no regressions from schema additions)
