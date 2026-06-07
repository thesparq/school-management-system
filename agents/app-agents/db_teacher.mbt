///|
pub fn db_teacher_fetch_class_groups(
  config : SharedConfig,
  teacher_id : String,
  active_st : String,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "SELECT teacher_id, has_subject.id AS edge_id, has_subject.in.id AS class_level_id, has_subject.in.name AS class_level_name, has_subject.out.id AS subject_id, has_subject.out.name AS subject_name, has_subject.out.code AS subject_code FROM teacher_assignment WHERE teacher_id = $teacher_id AND session_term = $active_st AND deleted_at IS NONE ORDER BY class_level_name ASC, subject_name ASC",
    bindings={ "teacher_id": teacher_id, "active_st": active_st },
  )
}

///|
pub fn db_teacher_fetch_terms(
  config : SharedConfig,
) -> Result[Array[Json], AppError] {
  surreal_query(config, "SELECT * FROM terms ORDER BY sort_order ASC")
}

///|
pub fn db_teacher_fetch_lessons(
  config : SharedConfig,
  class_level_id : String,
  subject_id : String,
  term_id : String,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "SELECT id, topic_title, week, active, topic.has_subject.out.name AS subject_name, topic.term.name AS term_name FROM lessons WHERE topic.has_subject.in = $class_level_id AND topic.has_subject.out = $subject_id AND topic.has_subject.active = true AND topic.term = $term_id ORDER BY week ASC",
    bindings={
      "class_level_id": class_level_id,
      "subject_id": subject_id,
      "term_id": term_id,
    },
  )
}

///|
pub fn db_teacher_update_record_active(
  config : SharedConfig,
  record_id : String,
  active : Bool,
) -> Result[Unit, AppError] {
  match
    surreal_query(config, "UPDATE $record_id SET active = $active", bindings={
      "record_id": record_id,
      "active": if active {
        "true"
      } else {
        "false"
      },
    }) {
    Ok(_) => Ok(())
    Err(e) => Err(e)
  }
}

///|
pub fn db_teacher_fetch_class_levels_for_teacher(
  config : SharedConfig,
  teacher_id : String,
  active_st : String,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "SELECT VALUE has_subject.in FROM teacher_assignment WHERE teacher_id = $teacher_id AND session_term = $active_st AND deleted_at IS NONE",
    bindings={ "teacher_id": teacher_id, "active_st": active_st },
  )
}

///|
pub fn db_teacher_fetch_lesson_meta(
  config : SharedConfig,
  lesson_id : String,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "SELECT topic.has_subject.in AS class_level_id, topic.has_subject.out AS subject_id, topic.term AS term_id FROM ONLY lessons WHERE id = $lesson_id",
    bindings={ "lesson_id": lesson_id },
  )
}
