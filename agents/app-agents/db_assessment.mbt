///|
pub fn db_create_lesson_assessment(
  config : SharedConfig,
  lesson_id : String,
  title : String,
  description : String,
  questions_json : String,
  total_mark : Int,
  max_resubmissions : Int,
  deadline : String,
  scheduled_at : String,
  teacher_id : String,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "CREATE lesson_assessments CONTENT { lesson: type::record('lessons', $lesson_id), title: $title, description: $description, questions: json::parse($questions_json), total_mark: int::from($total_mark), max_resubmissions: int::from($max_resub), deadline: $deadline, active: false, scheduled_at: $scheduled_at, created_by: type::record('teacher_profile', $teacher_id) }",
    bindings={
      "lesson_id": lesson_id,
      "title": title,
      "description": description,
      "questions_json": questions_json,
      "total_mark": total_mark.to_string(),
      "max_resub": max_resubmissions.to_string(),
      "deadline": deadline,
      "scheduled_at": scheduled_at,
      "teacher_id": teacher_id,
    },
  )
}

///|
pub fn db_create_general_assessment(
  config : SharedConfig,
  session_term_id : String,
  subject_id : String,
  title : String,
  description : String,
  percentage_weight : Int,
  questions_json : String,
  total_mark : Int,
  max_resubmissions : Int,
  deadline : String,
  scheduled_at : String,
  teacher_id : String,
) -> Result[Array[Json], AppError] {
  let has_questions = questions_json != "" && questions_json != "[]"
  if has_questions {
    surreal_query(
      config,
      "CREATE general_assessments CONTENT { session_term: type::record('session_term', $st_id), subject: type::record('subjects', $subj_id), title: $title, description: $description, percentage_weight: int::from($pct), questions: json::parse($questions_json), total_mark: int::from($total_mark), max_resubmissions: int::from($max_resub), deadline: $deadline, active: false, scheduled_at: $scheduled_at, created_by: type::record('teacher_profile', $teacher_id) }",
      bindings={
        "st_id": session_term_id,
        "subj_id": subject_id,
        "title": title,
        "description": description,
        "pct": percentage_weight.to_string(),
        "questions_json": questions_json,
        "total_mark": total_mark.to_string(),
        "max_resub": max_resubmissions.to_string(),
        "deadline": deadline,
        "scheduled_at": scheduled_at,
        "teacher_id": teacher_id,
      },
    )
  } else {
    surreal_query(
      config,
      "CREATE general_assessments CONTENT { session_term: type::record('session_term', $st_id), subject: type::record('subjects', $subj_id), title: $title, description: $description, percentage_weight: int::from($pct), total_mark: int::from($total_mark), max_resubmissions: int::from($max_resub), deadline: $deadline, active: false, scheduled_at: $scheduled_at, created_by: type::record('teacher_profile', $teacher_id) }",
      bindings={
        "st_id": session_term_id,
        "subj_id": subject_id,
        "title": title,
        "description": description,
        "pct": percentage_weight.to_string(),
        "total_mark": total_mark.to_string(),
        "max_resub": max_resubmissions.to_string(),
        "deadline": deadline,
        "scheduled_at": scheduled_at,
        "teacher_id": teacher_id,
      },
    )
  }
}

///|
pub fn db_create_composition(
  config : SharedConfig,
  ga_id : String,
  la_id : String,
  weight_pct : Float,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "CREATE compositions CONTENT { general_assessment: type::record('general_assessments', $ga_id), lesson_assessment: type::record('lesson_assessments', $la_id), weight_pct: $weight_pct }",
    bindings={
      "ga_id": ga_id,
      "la_id": la_id,
      "weight_pct": weight_pct.to_string(),
    },
  )
}

///|
pub fn db_fetch_lesson_assessments(
  config : SharedConfig,
  lesson_id : String,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "SELECT *, meta::id(id) AS id FROM lesson_assessments WHERE lesson = $lesson_id AND deleted_at IS NONE ORDER BY created_at ASC",
    bindings={ "lesson_id": lesson_id },
  )
}

///|
pub fn db_fetch_general_assessments(
  config : SharedConfig,
  session_term_id : String,
  subject_id : String,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "SELECT *, meta::id(id) AS id FROM general_assessments WHERE session_term = $st AND subject = $subj AND deleted_at IS NONE ORDER BY created_at ASC",
    bindings={ "st": session_term_id, "subj": subject_id },
  )
}

///|
pub fn db_fetch_assessment_by_id(
  config : SharedConfig,
  table : String,
  id : String,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "SELECT *, meta::id(id) AS id FROM type::record($table, $id)",
    bindings={ "table": table, "id": id },
  )
}

///|
pub fn db_fetch_compositions(
  config : SharedConfig,
  ga_id : String,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "SELECT *, meta::id(id) AS id FROM compositions WHERE general_assessment = $ga_id",
    bindings={ "ga_id": ga_id },
  )
}

///|
pub fn db_fetch_submission(
  config : SharedConfig,
  student_id : String,
  assessment_type : String,
  assessment_id : String,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "SELECT *, meta::id(id) AS id FROM submissions WHERE student = type::record('student_profile', $student) AND assessment_type = $at AND assessment_id = $aid AND deleted_at IS NONE ORDER BY iteration DESC LIMIT 1",
    bindings={
      "student": student_id,
      "at": assessment_type,
      "aid": assessment_id,
    },
  )
}

///|
pub fn db_fetch_submissions_for_assessment(
  config : SharedConfig,
  assessment_type : String,
  assessment_id : String,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "SELECT *, meta::id(id) AS id FROM submissions WHERE assessment_type = $at AND assessment_id = $aid AND deleted_at IS NONE ORDER BY submitted_at ASC",
    bindings={ "at": assessment_type, "aid": assessment_id },
  )
}

///|
pub fn db_fetch_submission_by_id(
  config : SharedConfig,
  submission_id : String,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "SELECT *, meta::id(id) AS id FROM type::record('submissions', $id)",
    bindings={ "id": submission_id },
  )
}

///|
pub fn db_upsert_submission(
  config : SharedConfig,
  existing_id : String,
  assessment_type : String,
  assessment_id : String,
  student_id : String,
  iteration : Int,
  status : String,
  answers_json : String,
  total_mark : Int,
  scored_mark : String,
  grade_released_at : String,
) -> Result[Array[Json], AppError] {
  if existing_id != "" {
    surreal_query(
      config,
      "UPDATE type::record('submissions', $id) CONTENT { assessment_type: $at, assessment_id: $aid, student: type::record('student_profile', $student), iteration: int::from($iter), status: $status, submitted_at: time::now(), answers: json::parse($answers_json), total_mark: int::from($total_mark), scored_mark: $scored_mark, grade_released_at: $grade_released_at }",
      bindings={
        "id": existing_id,
        "at": assessment_type,
        "aid": assessment_id,
        "student": student_id,
        "iter": iteration.to_string(),
        "status": status,
        "answers_json": answers_json,
        "total_mark": total_mark.to_string(),
        "scored_mark": scored_mark,
        "grade_released_at": grade_released_at,
      },
    )
  } else {
    surreal_query(
      config,
      "CREATE submissions CONTENT { assessment_type: $at, assessment_id: $aid, student: type::record('student_profile', $student), iteration: int::from($iter), status: $status, submitted_at: time::now(), answers: json::parse($answers_json), total_mark: int::from($total_mark), scored_mark: $scored_mark, grade_released_at: $grade_released_at }",
      bindings={
        "at": assessment_type,
        "aid": assessment_id,
        "student": student_id,
        "iter": iteration.to_string(),
        "status": status,
        "answers_json": answers_json,
        "total_mark": total_mark.to_string(),
        "scored_mark": scored_mark,
        "grade_released_at": grade_released_at,
      },
    )
  }
}

///|
pub fn db_release_grades(
  config : SharedConfig,
  submission_id : String,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "UPDATE type::record('submissions', $id) SET grade_released_at = time::now(), status = 'graded'",
    bindings={ "id": submission_id },
  )
}

///|
pub fn db_update_submission_marks(
  config : SharedConfig,
  submission_id : String,
  scored_mark : Int,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "UPDATE type::record('submissions', $id) SET scored_mark = int::from($sm)",
    bindings={ "id": submission_id, "sm": scored_mark.to_string() },
  )
}

///|
pub fn db_update_submission_answers(
  config : SharedConfig,
  submission_id : String,
  answers_json : String,
  scored_mark : Int,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "UPDATE type::record('submissions', $id) SET answers = json::parse($answers_json), scored_mark = int::from($sm)",
    bindings={
      "id": submission_id,
      "answers_json": answers_json,
      "sm": scored_mark.to_string(),
    },
  )
}

///|
pub fn db_toggle_assessment_active(
  config : SharedConfig,
  table : String,
  id : String,
  active : Bool,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "UPDATE type::record($table, $id) SET active = $active",
    bindings={
      "table": table,
      "id": id,
      "active": if active {
        "true"
      } else {
        "false"
      },
    },
  )
}

///|
pub fn db_sum_percentage_weights(
  config : SharedConfig,
  session_term_id : String,
  subject_id : String,
  exclude_id : String,
) -> Result[Array[Json], AppError] {
  if exclude_id != "" {
    surreal_query(
      config,
      "SELECT math::sum(percentage_weight) AS total FROM general_assessments WHERE session_term = $st AND subject = $subj AND deleted_at IS NONE AND id != $eid",
      bindings={ "st": session_term_id, "subj": subject_id, "eid": exclude_id },
    )
  } else {
    surreal_query(
      config,
      "SELECT math::sum(percentage_weight) AS total FROM general_assessments WHERE session_term = $st AND subject = $subj AND deleted_at IS NONE",
      bindings={ "st": session_term_id, "subj": subject_id },
    )
  }
}

///|
pub fn db_fetch_active_session_term(
  config : SharedConfig,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config, "SELECT id, session_name, term.name AS term_name FROM session_term WHERE active = true AND deleted_at IS NONE LIMIT 1",
  )
}

///|
pub fn db_fetch_lesson_meta(
  config : SharedConfig,
  lesson_id : String,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "SELECT class_subject.in.id AS class_level_id, class_subject.out.id AS subject_id, term.id AS term_id FROM lessons WHERE id = $lesson_id",
    bindings={ "lesson_id": lesson_id },
  )
}
