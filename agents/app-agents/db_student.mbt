///|
pub fn db_student_fetch_profile(
  config : SharedConfig,
  student_id : String,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "SELECT *, meta::id(id) AS id FROM type::thing('student_profile', $student_id) WHERE deleted_at IS NONE LIMIT 1",
    bindings={ "student_id": student_id },
  )
}

///|
pub fn db_student_fetch_subjects(
  config : SharedConfig,
  class_level : String,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "SELECT out.id AS id, out.name AS name, out.code AS code FROM has_subject WHERE in = $class_level AND active = true ORDER BY name ASC",
    bindings={ "class_level": class_level },
  )
}

///|
pub fn db_student_fetch_terms(
  config : SharedConfig,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config, "SELECT * FROM terms WHERE active = true ORDER BY sort_order ASC",
  )
}

///|
pub fn db_student_fetch_lessons(
  config : SharedConfig,
  class_level : String,
  subject_id : String,
  term_id : String,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "SELECT id, topic_title, week, active, topic.has_subject.out.name AS subject_name, topic.term.name AS term_name FROM lessons WHERE topic.has_subject.in = $class_level AND topic.has_subject.out = $subject_id AND topic.has_subject.active = true AND topic.term = $term_id AND active = true ORDER BY week ASC",
    bindings={
      "class_level": class_level,
      "subject_id": subject_id,
      "term_id": term_id,
    },
  )
}

///|
pub fn db_student_fetch_lesson_content(
  config : SharedConfig,
  lesson_id : String,
  class_level : String,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "SELECT id, topic_title, week, topic.has_subject.out AS subject_id, topic.has_subject.out.name AS subject_name, topic.term AS term_id, topic.term.name AS term_name, objectives, content_sections, key_points, mcq_questions, theoretical_questions FROM lessons WHERE id = $lesson_id AND topic.has_subject.in = $class_level AND active = true",
    bindings={ "lesson_id": lesson_id, "class_level": class_level },
  )
}
