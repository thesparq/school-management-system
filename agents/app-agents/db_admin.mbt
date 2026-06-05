///|
pub fn db_admin_fetch_profile(config : SharedConfig, target_user_id : String) -> Result[Array[Json], AppError] {
  surreal_query(config, "SELECT auth_id, role, class_level.name AS class_level, created_at FROM user_profile WHERE auth_id = $target_user_id AND deleted_at IS NONE LIMIT 1", bindings={ "target_user_id": target_user_id })
}
pub fn db_admin_save_profile(config : SharedConfig, target_user_id : String, role : String, class_level : String?) -> Result[Unit, AppError] {
  if !["admin", "teacher", "student"].contains(role) { return Err(validation_error("Invalid role: " + role)) }
  let cl_record = match class_level {
    Some(cl) => {
      let arr = match surreal_query(config, "SELECT id FROM class_levels WHERE name = $name LIMIT 1", bindings={ "name": cl }) { Ok(a) => a; Err(e) => return Err(AppError::{ code: SurrealDBError, message: "Failed to resolve class level", debug: e.debug }) }
      if arr.length() > 0 { match arr[0] { Object(o) => match o.get("id") { Some(String(slug)) => Some(slug); _ => None }; _ => None } } else { None }
    }
    None => None
  }
  let sql = match cl_record {
    Some(_) => "INSERT INTO user_profile (auth_id, role, class_level, created_at) VALUES ($target_user_id, $role, $class_level, time::now()) ON DUPLICATE KEY UPDATE role=$role, class_level=$class_level"
    None => "INSERT INTO user_profile (auth_id, role, created_at) VALUES ($target_user_id, $role, time::now()) ON DUPLICATE KEY UPDATE role=$role"
  }
  let b = match cl_record {
    Some(slug) => { "target_user_id": target_user_id, "role": role, "class_level": slug }
    None => { "target_user_id": target_user_id, "role": role }
  }
  match surreal_query(config, sql, bindings=b) { Ok(_) => Ok(()); Err(e) => Err(e) }
}
pub fn db_admin_soft_delete_user(config : SharedConfig, target_user_id : String) -> Result[Unit, AppError] {
  match surreal_query(config, "UPDATE user_profile SET deleted_at = time::now() WHERE auth_id = $target_user_id AND deleted_at IS NONE", bindings={ "target_user_id": target_user_id }) { Ok(_) => Ok(()); Err(e) => Err(e) }
}
pub fn db_admin_undo_soft_delete(config : SharedConfig, target_user_id : String) -> Result[Unit, AppError] {
  match surreal_query(config, "UPDATE user_profile SET deleted_at = NONE WHERE auth_id = $target_user_id", bindings={ "target_user_id": target_user_id }) { Ok(_) => Ok(()); Err(e) => Err(e) }
}
pub fn db_admin_fetch_class_levels(config : SharedConfig) -> Result[Array[Json], AppError] {
  surreal_query(config, "SELECT id, name FROM class_levels ORDER BY name ASC")
}
pub fn db_admin_fetch_has_subject_for_class(config : SharedConfig, class_level_id : String) -> Result[Array[Json], AppError] {
  surreal_query(config, "SELECT id AS edge_id, out.id AS subject_id, out.name AS subject_name, out.code AS subject_code FROM has_subject WHERE in = $class_level_id AND active = true ORDER BY out.name ASC", bindings={ "class_level_id": class_level_id })
}
pub fn db_admin_fetch_teacher_subjects(config : SharedConfig, target_teacher_id : String) -> Result[Array[Json], AppError] {
  surreal_query(config, "SELECT teacher_id, has_subject.id AS edge_id, has_subject.in.id AS class_level_id, has_subject.in.name AS class_level_name, has_subject.out.id AS subject_id, has_subject.out.name AS subject_name, has_subject.out.code AS subject_code FROM teacher_assignment WHERE teacher_id = $target_teacher_id AND deleted_at IS NONE ORDER BY class_level_name ASC, subject_name ASC", bindings={ "target_teacher_id": target_teacher_id })
}
pub fn db_admin_soft_delete_teacher_assignments(config : SharedConfig, target_teacher_id : String) -> Result[Unit, AppError] {
  match surreal_query(config, "UPDATE teacher_assignment SET deleted_at = time::now() WHERE teacher_id = $target_teacher_id AND deleted_at IS NONE", bindings={ "target_teacher_id": target_teacher_id }) { Ok(_) => Ok(()); Err(e) => Err(e) }
}
pub fn db_admin_fetch_active_session_term(config : SharedConfig) -> Result[Array[Json], AppError] {
  surreal_query(config, "SELECT VALUE id FROM session_term WHERE active = true LIMIT 1")
}
pub fn db_admin_fetch_active_session_term_detail(config : SharedConfig) -> Result[Array[Json], AppError] {
  surreal_query(config, "SELECT id, session, term.name AS term_name FROM session_term WHERE active = true LIMIT 1")
}
pub fn db_admin_fetch_terms(config : SharedConfig) -> Result[Array[Json], AppError] {
  surreal_query(config, "SELECT id, name, sort_order FROM terms ORDER BY sort_order ASC")
}
pub fn db_admin_fetch_session_terms(config : SharedConfig) -> Result[Array[Json], AppError] {
  surreal_query(config, "SELECT id, session, term.name AS term_name, active, created_at FROM session_term ORDER BY created_at DESC")
}
pub fn db_admin_deactivate_all_session_terms(config : SharedConfig) -> Result[Unit, AppError] {
  match surreal_query(config, "UPDATE session_term SET active = false") { Ok(_) => Ok(()); Err(e) => Err(e) }
}
pub fn db_admin_create_session_term(config : SharedConfig, session : String, term_id : String, active : Bool) -> Result[Array[Json], AppError] {
  surreal_query(config, "CREATE session_term SET session = $session, term = $term_id, active = $active, created_at = time::now()", bindings={ "session": session, "term_id": term_id, "active": if active { "true" } else { "false" } })
}
pub fn db_admin_activate_session_term(config : SharedConfig, session_term_id : String) -> Result[Unit, AppError] {
  match surreal_query(config, "UPDATE $session_term_id SET active = true", bindings={ "session_term_id": session_term_id }) { Ok(_) => Ok(()); Err(e) => Err(e) }
}
pub fn db_admin_fetch_students_by_class_level(config : SharedConfig, class_level_id : String) -> Result[Array[Json], AppError] {
  surreal_query(config, "SELECT auth_id FROM user_profile WHERE class_level = $class_level_id AND role = 'student' AND deleted_at IS NONE", bindings={ "class_level_id": class_level_id })
}
pub fn db_admin_fetch_students_by_class_levels(config : SharedConfig, class_level_ids : Array[String]) -> Result[Array[Json], AppError] {
  if class_level_ids.length() == 0 { return Ok([]) }
  ///|
  /// NOTE: SurrealDB $bindings do not support array parameters for IN clauses.
  /// class_level_ids are pre-validated slugs from the DB, not user input.
  /// escape_surreal_string is retained here as the only exception in the DB layer.
  let cl_in = "[" + class_level_ids.map(fn(cl) { escape_surreal_string(cl) }).join(", ") + "]"
  surreal_query(config, "SELECT auth_id, class_level FROM user_profile WHERE class_level IN " + cl_in + " AND role = 'student' AND deleted_at IS NONE")
}

///|
pub fn db_admin_fetch_class_level_by_name(
  config : SharedConfig,
  class_level : String
) -> Result[Array[Json], AppError] {
  surreal_query(config, "SELECT id FROM class_levels WHERE name = $name LIMIT 1", bindings={ "name": class_level })
}

///|
pub fn db_admin_create_teacher_assignments(
  config : SharedConfig,
  teacher_id : String,
  pairs : Array[TeacherSubjectPair],
  active_st : String
) -> Result[Unit, AppError] {
  for pair in pairs {
    let sql = if active_st != "" {
      "CREATE teacher_assignment SET teacher_id = $teacher_id, has_subject = $edge_id, session_term = $active_st, assigned_at = time::now()"
    } else {
      "CREATE teacher_assignment SET teacher_id = $teacher_id, has_subject = $edge_id, assigned_at = time::now()"
    }
    let b = if active_st != "" {
      { "teacher_id": teacher_id, "edge_id": pair.edge_id, "active_st": active_st }
    } else {
      { "teacher_id": teacher_id, "edge_id": pair.edge_id }
    }
    match surreal_query(config, sql, bindings=b) {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
  }
  Ok(())
}
