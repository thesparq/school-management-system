///|
pub fn db_parent_fetch_profile(
  config : SharedConfig,
  parent_id : String,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "SELECT *, meta::id(id) AS id FROM type::thing('parent_profile', $parent_id) WHERE deleted_at IS NONE LIMIT 1",
    bindings={ "parent_id": parent_id },
  )
}

///|
pub fn db_parent_fetch_student_profiles(
  config : SharedConfig,
  student_ids : Array[String],
) -> Result[Array[Json], AppError] {
  if student_ids.length() == 0 {
    return Ok([])
  }
  for id in student_ids {
    if !id.starts_with("student_profile:") {
      return Err(validation_error("Invalid student profile ID: " + id))
    }
  }
  let ids_list = "[" +
    student_ids.map(fn(id) { escape_surreal_string(id) }).join(", ") +
    "]"
  surreal_query(
    config,
    "SELECT meta::id(id) AS id, display_name, current_class.name AS current_class FROM student_profile WHERE meta::id(id) IN " +
    ids_list +
    " AND deleted_at IS NONE ORDER BY display_name ASC",
  )
}

///|
pub fn db_parent_count_subjects_for_class(
  config : SharedConfig,
  class_level_id : String,
) -> Result[Int, AppError] {
  match
    surreal_query(
      config,
      "SELECT count() FROM has_subject WHERE in = $class_level_id AND active = true GROUP ALL",
      bindings={ "class_level_id": class_level_id },
    ) {
    Ok(arr) =>
      if arr.length() > 0 {
        match arr[0] {
          Object(o) =>
            match o.get("count") {
              Some(Number(n, ..)) => Ok(n.to_int())
              _ => Ok(0)
            }
          _ => Ok(0)
        }
      } else {
        Ok(0)
      }
    Err(e) => Err(e)
  }
}

///|
pub fn db_parent_fetch_student_subjects(
  config : SharedConfig,
  class_level_id : String,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "SELECT out.id AS id, out.name AS name, out.code AS code FROM has_subject WHERE in = $class_level_id AND active = true ORDER BY name ASC",
    bindings={ "class_level_id": class_level_id },
  )
}

///|
pub fn db_parent_fetch_student_terms(
  config : SharedConfig,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config, "SELECT * FROM terms WHERE active = true ORDER BY sort_order ASC",
  )
}

///|
pub fn db_parent_fetch_student_lessons(
  config : SharedConfig,
  class_level_id : String,
  subject_id : String,
  term_id : String,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "SELECT id, topic_title, week, active, topic.has_subject.out.name AS subject_name, topic.term.name AS term_name FROM lessons WHERE topic.has_subject.in = $class_level_id AND topic.has_subject.out = $subject_id AND topic.has_subject.active = true AND topic.term = $term_id AND active = true ORDER BY week ASC",
    bindings={
      "class_level_id": class_level_id,
      "subject_id": subject_id,
      "term_id": term_id,
    },
  )
}

///|
pub fn db_parent_fetch_student_lesson_content(
  config : SharedConfig,
  lesson_id : String,
  class_level : String,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "SELECT id, topic_title, week, topic.has_subject.out AS subject_id, topic.has_subject.out.name AS subject_name, topic.term AS term_id, topic.term.name AS term_name, objectives, content_sections, key_points, mcq_questions, theoretical_questions FROM lessons WHERE id = $lesson_id AND topic.has_subject.in = $class_level AND topic.has_subject.active = true AND active = true",
    bindings={ "lesson_id": lesson_id, "class_level": class_level },
  )
}
