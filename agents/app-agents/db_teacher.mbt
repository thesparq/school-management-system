///|
pub fn db_teacher_fetch_class_groups(
  config : SharedConfig,
  teacher_id : String,
  active_st : String,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "SELECT in AS teacher_id, out.id AS edge_id, out.in.id AS class_level_id, out.in.name AS class_level_name, out.out.id AS subject_id, out.out.name AS subject_name, out.out.code AS subject_code FROM type::record('teacher_profile', $teacher_id)->teaches WHERE session_term = $active_st AND deleted_at IS NONE ORDER BY class_level_name ASC, subject_name ASC",
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
    "SELECT id, topic_title, week, active, class_subject.out.name AS subject_name, term.name AS term_name FROM lessons WHERE class_subject.in = $class_level_id AND class_subject.out = $subject_id AND class_subject.active = true AND term = $term_id ORDER BY week ASC",
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
  let active_lit = if active { "true" } else { "false" }
  match
    surreal_query(config, "UPDATE $record_id SET active = " + active_lit, bindings={
      "record_id": record_id,
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
    "SELECT VALUE out.in FROM type::record('teacher_profile', $teacher_id)->teaches WHERE session_term = $active_st AND deleted_at IS NONE",
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
    "SELECT class_subject.in AS class_level_id, class_subject.out AS subject_id, term AS term_id FROM ONLY lessons WHERE id = $lesson_id",
    bindings={ "lesson_id": lesson_id },
  )
}
