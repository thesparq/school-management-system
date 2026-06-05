///|
pub fn db_admin_fetch_student_profile(config : SharedConfig, user_id : String) -> Result[Array[Json], AppError] {
  surreal_query(config, "SELECT *, meta::id(id) AS id FROM type::thing('student_profile', $user_id) WHERE deleted_at IS NONE", bindings={ "user_id": user_id })
}
pub fn db_admin_fetch_teacher_profile(config : SharedConfig, user_id : String) -> Result[Array[Json], AppError] {
  surreal_query(config, "SELECT *, meta::id(id) AS id FROM type::thing('teacher_profile', $user_id) WHERE deleted_at IS NONE", bindings={ "user_id": user_id })
}
pub fn db_admin_fetch_admin_profile(config : SharedConfig, user_id : String) -> Result[Array[Json], AppError] {
  surreal_query(config, "SELECT *, meta::id(id) AS id FROM type::thing('admin_profile', $user_id) WHERE deleted_at IS NONE", bindings={ "user_id": user_id })
}
pub fn db_admin_fetch_parent_profile(config : SharedConfig, user_id : String) -> Result[Array[Json], AppError] {
  surreal_query(config, "SELECT *, meta::id(id) AS id FROM type::thing('parent_profile', $user_id) WHERE deleted_at IS NONE", bindings={ "user_id": user_id })
}

pub fn db_admin_create_student_profile(config : SharedConfig, user_id : String, surname : String, first_name : String, middle_name : String?, display_name : String, dob : String, class_level_id : String, passport_url : String) -> Result[Unit, AppError] {
  let b = match middle_name {
    Some(_) => { "user_id": user_id, "surname": surname, "first_name": first_name, "middle_name": middle_name.unwrap(), "display_name": display_name, "dob": dob, "cl": class_level_id, "passport": passport_url }
    None => { "user_id": user_id, "surname": surname, "first_name": first_name, "display_name": display_name, "dob": dob, "cl": class_level_id, "passport": passport_url }
  }
  let sql = if middle_name.is_some() {
    "CREATE type::thing('student_profile', $user_id) SET surname = $surname, first_name = $first_name, middle_name = $middle_name, display_name = $display_name, date_of_birth = $dob, class_enrolled = type::thing('class_levels', $cl), current_class = type::thing('class_levels', $cl), passport = $passport, created_at = time::now()"
  } else {
    "CREATE type::thing('student_profile', $user_id) SET surname = $surname, first_name = $first_name, display_name = $display_name, date_of_birth = $dob, class_enrolled = type::thing('class_levels', $cl), current_class = type::thing('class_levels', $cl), passport = $passport, created_at = time::now()"
  }
  match surreal_query(config, sql, bindings=b) { Ok(_) => Ok(()); Err(e) => Err(e) }
}
pub fn db_admin_update_student_profile(config : SharedConfig, user_id : String, surname : String, first_name : String, middle_name : String?, display_name : String, dob : String, class_level_id : String, passport_url : String) -> Result[Unit, AppError] {
  let b = match middle_name {
    Some(_) => { "user_id": user_id, "surname": surname, "first_name": first_name, "middle_name": middle_name.unwrap(), "display_name": display_name, "dob": dob, "cl": class_level_id, "passport": passport_url }
    None => { "user_id": user_id, "surname": surname, "first_name": first_name, "display_name": display_name, "dob": dob, "cl": class_level_id, "passport": passport_url }
  }
  let sql = if middle_name.is_some() {
    "UPDATE type::thing('student_profile', $user_id) SET surname = $surname, first_name = $first_name, middle_name = $middle_name, display_name = $display_name, date_of_birth = $dob, current_class = type::thing('class_levels', $cl), passport = $passport, updated_at = time::now()"
  } else {
    "UPDATE type::thing('student_profile', $user_id) SET surname = $surname, first_name = $first_name, display_name = $display_name, date_of_birth = $dob, current_class = type::thing('class_levels', $cl), passport = $passport, updated_at = time::now()"
  }
  match surreal_query(config, sql, bindings=b) { Ok(_) => Ok(()); Err(e) => Err(e) }
}

pub fn db_admin_create_teacher_profile(config : SharedConfig, user_id : String, surname : String, first_name : String, middle_name : String?, display_name : String, qualifications : Array[String]?, date_employed : String?, passport_url : String) -> Result[Unit, AppError] {
  let sql = "CREATE type::thing('teacher_profile', $user_id) SET surname = $surname, first_name = $first_name, display_name = $display_name, passport = $passport, created_at = time::now()"
  let b : Map[String, String] = { "user_id": user_id, "surname": surname, "first_name": first_name, "display_name": display_name, "passport": passport_url }
  match surreal_query(config, sql, bindings=b) { Ok(_) => Ok(()); Err(e) => Err(e) }
}
pub fn db_admin_update_teacher_profile(config : SharedConfig, user_id : String, surname : String, first_name : String, middle_name : String?, display_name : String, qualifications : Array[String]?, date_employed : String?, passport_url : String) -> Result[Unit, AppError] {
  let sql = "UPDATE type::thing('teacher_profile', $user_id) SET surname = $surname, first_name = $first_name, display_name = $display_name, passport = $passport, updated_at = time::now()"
  let b : Map[String, String] = { "user_id": user_id, "surname": surname, "first_name": first_name, "display_name": display_name, "passport": passport_url }
  match surreal_query(config, sql, bindings=b) { Ok(_) => Ok(()); Err(e) => Err(e) }
}

pub fn db_admin_create_admin_profile(config : SharedConfig, user_id : String, surname : String, first_name : String, middle_name : String?, display_name : String, role_title : String?, passport_url : String) -> Result[Unit, AppError] {
  let sql = "CREATE type::thing('admin_profile', $user_id) SET surname = $surname, first_name = $first_name, display_name = $display_name, passport = $passport, created_at = time::now()"
  let b : Map[String, String] = { "user_id": user_id, "surname": surname, "first_name": first_name, "display_name": display_name, "passport": passport_url }
  match surreal_query(config, sql, bindings=b) { Ok(_) => Ok(()); Err(e) => Err(e) }
}
pub fn db_admin_update_admin_profile(config : SharedConfig, user_id : String, surname : String, first_name : String, middle_name : String?, display_name : String, role_title : String?, passport_url : String) -> Result[Unit, AppError] {
  let sql = "UPDATE type::thing('admin_profile', $user_id) SET surname = $surname, first_name = $first_name, display_name = $display_name, passport = $passport, updated_at = time::now()"
  let b : Map[String, String] = { "user_id": user_id, "surname": surname, "first_name": first_name, "display_name": display_name, "passport": passport_url }
  match surreal_query(config, sql, bindings=b) { Ok(_) => Ok(()); Err(e) => Err(e) }
}

pub fn db_admin_create_parent_profile(config : SharedConfig, user_id : String, name : String, passport_url : String) -> Result[Unit, AppError] {
  let sql = "CREATE type::thing('parent_profile', $user_id) SET name = $name, display_name = $name, students = [], passport = $passport, created_at = time::now()"
  match surreal_query(config, sql, bindings={ "user_id": user_id, "name": name, "passport": passport_url }) { Ok(_) => Ok(()); Err(e) => Err(e) }
}
pub fn db_admin_update_parent_profile(config : SharedConfig, user_id : String, name : String, passport_url : String) -> Result[Unit, AppError] {
  let sql = "UPDATE type::thing('parent_profile', $user_id) SET name = $name, display_name = $name, passport = $passport, updated_at = time::now()"
  match surreal_query(config, sql, bindings={ "user_id": user_id, "name": name, "passport": passport_url }) { Ok(_) => Ok(()); Err(e) => Err(e) }
}

pub fn db_admin_soft_delete_student_profile(config : SharedConfig, user_id : String) -> Result[Unit, AppError] {
  match surreal_query(config, "UPDATE type::thing('student_profile', $user_id) SET deleted_at = time::now() WHERE deleted_at IS NONE", bindings={ "user_id": user_id }) { Ok(_) => Ok(()); Err(e) => Err(e) }
}
pub fn db_admin_undo_soft_delete_student_profile(config : SharedConfig, user_id : String) -> Result[Unit, AppError] {
  match surreal_query(config, "UPDATE type::thing('student_profile', $user_id) SET deleted_at = NONE", bindings={ "user_id": user_id }) { Ok(_) => Ok(()); Err(e) => Err(e) }
}
pub fn db_admin_soft_delete_teacher_profile(config : SharedConfig, user_id : String) -> Result[Unit, AppError] {
  match surreal_query(config, "UPDATE type::thing('teacher_profile', $user_id) SET deleted_at = time::now() WHERE deleted_at IS NONE", bindings={ "user_id": user_id }) { Ok(_) => Ok(()); Err(e) => Err(e) }
}
pub fn db_admin_undo_soft_delete_teacher_profile(config : SharedConfig, user_id : String) -> Result[Unit, AppError] {
  match surreal_query(config, "UPDATE type::thing('teacher_profile', $user_id) SET deleted_at = NONE", bindings={ "user_id": user_id }) { Ok(_) => Ok(()); Err(e) => Err(e) }
}
pub fn db_admin_soft_delete_admin_profile(config : SharedConfig, user_id : String) -> Result[Unit, AppError] {
  match surreal_query(config, "UPDATE type::thing('admin_profile', $user_id) SET deleted_at = time::now() WHERE deleted_at IS NONE", bindings={ "user_id": user_id }) { Ok(_) => Ok(()); Err(e) => Err(e) }
}
pub fn db_admin_undo_soft_delete_admin_profile(config : SharedConfig, user_id : String) -> Result[Unit, AppError] {
  match surreal_query(config, "UPDATE type::thing('admin_profile', $user_id) SET deleted_at = NONE", bindings={ "user_id": user_id }) { Ok(_) => Ok(()); Err(e) => Err(e) }
}
pub fn db_admin_soft_delete_parent_profile(config : SharedConfig, user_id : String) -> Result[Unit, AppError] {
  match surreal_query(config, "UPDATE type::thing('parent_profile', $user_id) SET deleted_at = time::now() WHERE deleted_at IS NONE", bindings={ "user_id": user_id }) { Ok(_) => Ok(()); Err(e) => Err(e) }
}
pub fn db_admin_undo_soft_delete_parent_profile(config : SharedConfig, user_id : String) -> Result[Unit, AppError] {
  match surreal_query(config, "UPDATE type::thing('parent_profile', $user_id) SET deleted_at = NONE", bindings={ "user_id": user_id }) { Ok(_) => Ok(()); Err(e) => Err(e) }
}

pub fn db_admin_fetch_students_by_class_level(config : SharedConfig, class_level_id : String) -> Result[Array[Json], AppError] {
  surreal_query(config, "SELECT meta::id(id) AS id FROM student_profile WHERE current_class = $class_level_id AND deleted_at IS NONE", bindings={ "class_level_id": class_level_id })
}

pub fn db_admin_fetch_users_by_role(config : SharedConfig, role : String) -> Result[Array[Json], AppError] {
  let table = match role {
    "student" => "student_profile"
    "teacher" => "teacher_profile"
    "admin" => "admin_profile"
    "parent" => "parent_profile"
    _ => return Err(validation_error("Unknown role: " + role))
  }
  surreal_query(config, "SELECT meta::id(id) AS id FROM " + table + " WHERE deleted_at IS NONE")
}

pub fn db_admin_fetch_credentials(config : SharedConfig) -> Result[Array[Json], AppError] {
  surreal_query(config, "SELECT meta::id(id) AS id, name, active FROM credentials WHERE active = true ORDER BY name ASC")
}

pub fn db_admin_create_credential(config : SharedConfig, name : String) -> Result[Array[Json], AppError] {
  let slug = string::lowercase(string::replace(name, ' ', '_'))
  surreal_query(config, "CREATE type::thing('credentials', $slug) SET name = $name, active = true", bindings={ "slug": slug, "name": name })
}

pub fn db_admin_fetch_all_student_profiles(config : SharedConfig) -> Result[Array[Json], AppError] {
  surreal_query(config, "SELECT meta::id(id) AS id, display_name FROM student_profile WHERE deleted_at IS NONE ORDER BY display_name ASC")
}

pub fn db_admin_fetch_student_exists(config : SharedConfig, student_id : String) -> Result[Bool, AppError] {
  match surreal_query(config, "SELECT meta::id(id) AS id FROM type::thing('student_profile', $student_id) WHERE deleted_at IS NONE LIMIT 1", bindings={ "student_id": student_id }) {
    Ok(arr) => Ok(arr.length() > 0)
    Err(e) => Err(e)
  }
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
  surreal_query(config, "SELECT id, name, sort_order, active FROM terms ORDER BY sort_order ASC")
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
pub fn db_admin_fetch_students_by_class_levels(config : SharedConfig, class_level_ids : Array[String]) -> Result[Array[Json], AppError] {
  if class_level_ids.length() == 0 { return Ok([]) }
  for id in class_level_ids {
    if !id.starts_with("class_levels:") {
      return Err(validation_error("Invalid class level ID format: " + id))
    }
  }
  let cl_in = "[" + class_level_ids.map(fn(cl) { escape_surreal_string(cl) }).join(", ") + "]"
  surreal_query(config, "SELECT meta::id(id) AS id, current_class FROM student_profile WHERE current_class IN " + cl_in + " AND deleted_at IS NONE")
}

pub fn db_admin_fetch_class_level_by_name(config : SharedConfig, class_level : String) -> Result[Array[Json], AppError] {
  surreal_query(config, "SELECT id FROM class_levels WHERE name = $name LIMIT 1", bindings={ "name": class_level })
}

pub fn db_admin_create_teacher_assignments(config : SharedConfig, teacher_id : String, pairs : Array[TeacherSubjectPair], active_st : String) -> Result[Unit, AppError] {
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
