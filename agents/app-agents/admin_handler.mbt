///|
pub fn admin_fetch_class_levels(
  config : SharedConfig,
) -> Result[Array[ClassLevelInfo], AppError] {
  let arr = match db_admin_fetch_class_levels(config) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  let items : Array[ClassLevelInfo] = []
  for item in arr {
    match item {
      Object(o) =>
        items.push(ClassLevelInfo::{
          id: match o.get("id") {
            Some(String(s)) => s
            _ => continue
          },
          name: match o.get("name") {
            Some(String(s)) => s
            _ => continue
          },
        })
      _ => ()
    }
  }
  Ok(items)
}

///|
pub fn admin_fetch_class_subjects(
  config : SharedConfig,
) -> Result[Array[TeacherSubjectPair], AppError] {
  let cl_arr = match db_admin_fetch_class_levels(config) {
    Ok(arr) => arr
    Err(e) => return Err(e)
  }
  let pairs : Array[TeacherSubjectPair] = []
  for cl_item in cl_arr {
    let cl_id = match cl_item {
      Object(obj) =>
        match obj.get("id") {
          Some(String(s)) => s
          _ => continue
        }
      _ => continue
    }
    let cl_name = match cl_item {
      Object(obj) =>
        match obj.get("name") {
          Some(String(s)) => s
          _ => continue
        }
      _ => continue
    }
    let subj_arr = match db_admin_fetch_has_subject_for_class(config, cl_id) {
      Ok(arr) => arr
      Err(_) => continue
    }
    for subj_item in subj_arr {
      match subj_item {
        Object(obj) =>
          pairs.push(TeacherSubjectPair::{
            edge_id: match obj.get("edge_id") {
              Some(String(s)) => s
              _ => continue
            },
            class_level_id: cl_id,
            class_level_name: cl_name,
            subject_id: match obj.get("subject_id") {
              Some(String(s)) => s
              _ => continue
            },
            subject_name: match obj.get("subject_name") {
              Some(String(s)) => s
              _ => continue
            },
            subject_code: match obj.get("subject_code") {
              Some(String(s)) => Some(s)
              _ => None
            },
          })
        _ => ()
      }
    }
  }
  Ok(pairs)
}

///|
pub fn admin_fetch_teacher_subjects(
  config : SharedConfig,
  target_teacher_id : String,
) -> Result[Array[TeacherSubjectPair], AppError] {
  let result_arr = match
    db_admin_fetch_teacher_subjects(config, target_teacher_id) {
    Ok(arr) => arr
    Err(e) => return Err(e)
  }
  let pairs : Array[TeacherSubjectPair] = []
  for item in result_arr {
    match item {
      Object(obj) =>
        pairs.push(TeacherSubjectPair::{
          edge_id: match obj.get("edge_id") {
            Some(String(s)) => s
            _ => continue
          },
          class_level_id: match obj.get("class_level_id") {
            Some(String(s)) => s
            _ => continue
          },
          class_level_name: match obj.get("class_level_name") {
            Some(String(s)) => s
            _ => continue
          },
          subject_id: match obj.get("subject_id") {
            Some(String(s)) => s
            _ => continue
          },
          subject_name: match obj.get("subject_name") {
            Some(String(s)) => s
            _ => continue
          },
          subject_code: match obj.get("subject_code") {
            Some(String(s)) => Some(s)
            _ => None
          },
        })
      _ => ()
    }
  }
  Ok(pairs)
}

///|
pub fn admin_fetch_profile(
  config : SharedConfig,
  target_user_id : String,
) -> Result[UserProfileInfo, AppError] {
  let arr = match db_admin_fetch_profile(config, target_user_id) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  if arr.length() > 0 {
    match arr[0] {
      Object(obj) =>
        Ok(UserProfileInfo::{
          auth_id: match obj.get("auth_id") {
            Some(String(s)) => s
            _ => ""
          },
          role: match obj.get("role") {
            Some(String(s)) => s
            _ => ""
          },
          class_level: match obj.get("class_level") {
            Some(String(s)) => s
            _ => ""
          },
          created_at: match obj.get("created_at") {
            Some(String(s)) => s
            _ => ""
          },
        })
      _ => Err(not_found_error("Profile"))
    }
  } else {
    Err(not_found_error("Profile"))
  }
}

///|
pub fn admin_soft_delete_profile(
  config : SharedConfig,
  target_user_id : String,
) -> Result[Unit, AppError] {
  db_admin_soft_delete_user(config, target_user_id)
}

///|
pub fn admin_fetch_active_session_term(
  cache : CacheSystem,
  config : SharedConfig,
  now : UInt64,
) -> Result[String, AppError] {
  let cache_key = "active_session_term"
  match cache.get(cache_key, now) {
    Some(id) => Ok(id)
    None => {
      let arr = match db_admin_fetch_active_session_term(config) {
        Ok(a) => a
        Err(e) => return Err(e)
      }
      if arr.length() > 0 {
        match arr[0] {
          String(id) => {
            cache.set(cache_key, id, 600UL, [], now)
            Ok(id)
          }
          _ => Err(not_found_error("Active session term"))
        }
      } else {
        Err(not_found_error("Active session term"))
      }
    }
  }
}

///|
pub fn admin_fetch_active_session_term_detail(
  config : SharedConfig,
) -> Result[String, AppError] {
  let arr = match db_admin_fetch_active_session_term_detail(config) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  if arr.length() > 0 {
    match arr[0] {
      Object(obj) =>
        Ok(
          "{\"id\":\"" +
          escape_json_string(
            match obj.get("id") {
              Some(String(s)) => s
              _ => ""
            },
          ) +
          "\",\"session\":\"" +
          escape_json_string(
            match obj.get("session") {
              Some(String(s)) => s
              _ => ""
            },
          ) +
          "\",\"term_name\":\"" +
          escape_json_string(
            match obj.get("term_name") {
              Some(String(s)) => s
              _ => ""
            },
          ) +
          "\"}",
        )
      _ => Ok("{}")
    }
  } else {
    Ok("{}")
  }
}

///|
pub fn admin_fetch_terms(config : SharedConfig) -> Result[String, AppError] {
  let arr = match db_admin_fetch_terms(config) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  Ok(
    "[" +
    arr
    .map(fn(item) {
      match item {
        Object(o) =>
          "{\"id\":\"" +
          escape_json_string(
            match o.get("id") {
              Some(String(s)) => s
              _ => ""
            },
          ) +
          "\",\"name\":\"" +
          escape_json_string(
            match o.get("name") {
              Some(String(s)) => s
              _ => ""
            },
          ) +
          "\"}"
        _ => "null"
      }
    })
    .join(",") +
    "]",
  )
}

///|
pub fn admin_fetch_session_terms(
  cache : CacheSystem,
  config : SharedConfig,
  now : UInt64,
) -> Result[String, AppError] {
  let cache_key = "session_terms"
  match cache.get(cache_key, now) {
    Some(json) => Ok(json)
    None => {
      let arr = match db_admin_fetch_session_terms(config) {
        Ok(a) => a
        Err(e) => return Err(e)
      }
      let json = "[" +
        arr
        .map(fn(item) {
          match item {
            Object(o) => {
              let is_active = match o.get("active") {
                Some(True) => true
                _ => false
              }
              "{\"id\":\"" +
              escape_json_string(
                match o.get("id") {
                  Some(String(s)) => s
                  _ => ""
                },
              ) +
              "\",\"session\":\"" +
              escape_json_string(
                match o.get("session") {
                  Some(String(s)) => s
                  _ => ""
                },
              ) +
              "\",\"term_name\":\"" +
              escape_json_string(
                match o.get("term_name") {
                  Some(String(s)) => s
                  _ => ""
                },
              ) +
              "\",\"active\":" +
              (if is_active { "true" } else { "false" }) +
              ",\"created_at\":\"" +
              escape_json_string(
                match o.get("created_at") {
                  Some(String(s)) => s
                  _ => ""
                },
              ) +
              "\"}"
            }
            _ => "null"
          }
        })
        .join(",") +
        "]"
      cache.set(cache_key, json, 600UL, [], now)
      Ok(json)
    }
  }
}

///|
pub fn admin_create_session_term(
  cache : CacheSystem,
  config : SharedConfig,
  body_json : String,
) -> Result[String, AppError] {
  let val = @json.parse(body_json) catch {
    _ => return Err(validation_error("Invalid JSON body"))
  }
  let obj = match val {
    Object(o) => o
    _ => return Err(validation_error("Body must be an object"))
  }
  let session = match obj.get("session") {
    Some(String(s)) => s
    _ => return Err(validation_error("Session is required"))
  }
  let term_id = match obj.get("term_id") {
    Some(String(s)) => s
    _ => return Err(validation_error("term_id is required"))
  }
  let active = match obj.get("active") {
    Some(True) => true
    _ => false
  }
  cache.invalidate("active_session_term")
  cache.invalidate("session_terms")
  if active {
    match db_admin_deactivate_all_session_terms(config) {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
  }
  let arr = match
    db_admin_create_session_term(config, session, term_id, active) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  if arr.length() > 0 {
    match arr[0] {
      Object(o) =>
        Ok(
          "{\"id\":\"" +
          escape_json_string(
            match o.get("id") {
              Some(String(s)) => s
              _ => ""
            },
          ) +
          "\",\"session\":\"" +
          escape_json_string(session) +
          "\",\"active\":" +
          (if active { "true" } else { "false" }) +
          "}",
        )
      _ => Err(validation_error("Failed to create session term"))
    }
  } else {
    Err(validation_error("Failed to create session term"))
  }
}

///|
pub fn admin_activate_session_term(
  cache : CacheSystem,
  config : SharedConfig,
  session_term_id : String,
) -> Result[Unit, AppError] {
  cache.invalidate("active_session_term")
  cache.invalidate("session_terms")
  match db_admin_deactivate_all_session_terms(config) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  db_admin_activate_session_term(config, session_term_id)
}

///|
pub fn admin_set_teacher_subjects(
  cache : CacheSystem,
  config : SharedConfig,
  target_teacher_id : String,
  pairs_json : String,
  now : UInt64,
) -> Result[String, AppError] {
  let pairs : Array[TeacherSubjectPair] = []
  let val = @json.parse(pairs_json) catch {
    _ => return Err(validation_error("Invalid JSON body"))
  }
  match val {
    Array(arr) =>
      for item in arr {
        match item {
          Object(obj) =>
            pairs.push(TeacherSubjectPair::{
              edge_id: match obj.get("has_subject_id") {
                Some(String(s)) => s
                _ => continue
              },
              class_level_id: match obj.get("class_level_id") {
                Some(String(s)) => s
                _ => continue
              },
              class_level_name: match obj.get("class_level_name") {
                Some(String(s)) => s
                _ => ""
              },
              subject_id: match obj.get("subject_id") {
                Some(String(s)) => s
                _ => continue
              },
              subject_name: match obj.get("subject_name") {
                Some(String(s)) => s
                _ => ""
              },
              subject_code: match obj.get("subject_code") {
                Some(String(s)) => Some(s)
                _ => None
              },
            })
          _ => ()
        }
      }
    _ => return Err(validation_error("Invalid JSON body"))
  }
  let _ = match
    db_admin_soft_delete_teacher_assignments(config, target_teacher_id) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  if pairs.length() > 0 {
    let active_st = match admin_fetch_active_session_term(cache, config, now) {
      Ok(id) => id
      Err(e) => return Err(e)
    }
    let create_sql = StringBuilder::new()
    for pair in pairs {
      create_sql.write_string("CREATE teacher_assignment SET teacher_id = '")
      create_sql.write_string(escape_surreal_string(target_teacher_id))
      create_sql.write_string("', has_subject = ")
      create_sql.write_string(escape_surreal_string(pair.edge_id))
      if active_st != "" {
        create_sql.write_string(", session_term = ")
        create_sql.write_string(active_st)
      }
      create_sql.write_string(", assigned_at = time::now();")
    }
    match surreal_query(config, create_sql.to_string()) {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
  }
  let ak = config.auth_key.get() catch { _ => "" }
  if ak != "" {
    let _ = TeacherAgentClient::scoped(target_teacher_id, fn(c) raise @common.AgentError {
      c.trigger_invalidate_cache(ak, "class_groups")
    }) catch { _ => () }
  }
  Ok("ok")
}

///|
pub fn admin_create_user(
  config : SharedConfig,
  body_json : String,
) -> Result[CreateUserResponse, AppError] {
  let val = @json.parse(body_json) catch {
    _ => return Err(validation_error("Invalid JSON body"))
  }
  let obj = match val {
    Object(o) => o
    _ => return Err(validation_error("Body must be an object"))
  }
  let username = match obj.get("username") {
    Some(String(s)) => s
    _ => return Err(validation_error("Username is required"))
  }
  let name = match obj.get("name") {
    Some(String(s)) => s
    _ => return Err(validation_error("Name is required"))
  }
  let email = match obj.get("email") {
    Some(String(s)) => s
    _ => return Err(validation_error("Email is required"))
  }
  let password = match obj.get("password") {
    Some(String(s)) => s
    _ => return Err(validation_error("Password is required"))
  }
  let is_active = match obj.get("is_active") {
    Some(True) => true
    Some(False) => false
    _ => true
  }
  let group_pk = match obj.get("group_pk") {
    Some(String(s)) => s
    _ => ""
  }
  let role = match obj.get("role") {
    Some(String(s)) => s
    _ => return Err(validation_error("Role is required"))
  }
  let class_level = match obj.get("class_level") {
    Some(String(s)) => if s == "" { None } else { Some(s) }
    _ => None
  }
  match validate_username(username) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match validate_name(name) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match validate_email(email) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match validate_password(password) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match validate_role(role) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  if class_level is Some(cl) {
    match validate_class_level_exists(config, cl) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
  }
  let (pk, uuid) = match
    authentik_create_user(
      config, username, name, email, password, is_active, group_pk,
    ) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  match authentik_set_password(config, pk, password) {
    Ok(_) => ()
    Err(_) => {
      let _ = authentik_delete_user(config, pk)
      return Err(validation_error("Failed to set password. User rolled back."))
    }
  }
  match db_admin_save_profile(config, uuid, role, class_level) {
    Ok(_) => ()
    Err(e) => {
      let _ = authentik_delete_user(config, pk)
      return Err(e)
    }
  }
  if role == "student" {
    match class_level {
      Some(_) => {
        let ak = config.auth_key.get() catch { _ => "" }
        if ak != "" {
          let _ = StudentAgentClient::scoped(uuid, fn(
            c,
          ) raise @common.AgentError {
            c.trigger_invalidate_cache(ak, "profile")
          }) catch { _ => () }
        }
      }
      None => ()
    }
  }
  if role == "teacher" {
    let ak = config.auth_key.get() catch { _ => "" }
    if ak != "" {
      let _ = TeacherAgentClient::scoped(uuid, fn(c) raise @common.AgentError {
        c.trigger_invalidate_cache(ak, "class_groups")
      }) catch { _ => () }
    }
  }
  let groups = if group_pk != "" { [group_pk] } else { [] }
  Ok(CreateUserResponse::{ pk, uuid, username, name, email, is_active, groups })
}

///|
pub fn admin_edit_user(
  config : SharedConfig,
  body_json : String,
) -> Result[Unit, AppError] {
  let val = @json.parse(body_json) catch {
    _ => return Err(validation_error("Invalid JSON body"))
  }
  let obj = match val {
    Object(o) => o
    _ => return Err(validation_error("Body must be an object"))
  }
  let target_user_id = match obj.get("target_user_id") {
    Some(String(s)) => s
    _ => return Err(validation_error("target_user_id is required"))
  }
  let authentik_pk = match obj.get("authentik_pk") {
    Some(Number(n, ..)) => n.to_int()
    _ => return Err(validation_error("authentik_pk is required"))
  }
  let password = match obj.get("password") {
    Some(String(s)) => if s == "" { None } else { Some(s) }
    _ => None
  }
  let role = match obj.get("role") {
    Some(String(s)) => s
    _ => return Err(validation_error("Role is required"))
  }
  let class_level = match obj.get("class_level") {
    Some(String(s)) => if s == "" { None } else { Some(s) }
    _ => None
  }
  let username = match obj.get("username") {
    Some(String(s)) => s
    _ => return Err(validation_error("Username is required"))
  }
  let name = match obj.get("name") {
    Some(String(s)) => s
    _ => return Err(validation_error("Name is required"))
  }
  let email = match obj.get("email") {
    Some(String(s)) => s
    _ => return Err(validation_error("Email is required"))
  }
  match validate_username(username) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match validate_name(name) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match validate_email(email) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match validate_role(role) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  if class_level is Some(cl) {
    match validate_class_level_exists(config, cl) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
  }
  let target_group_pk = match authentik_get_group_pk_by_name(config, role) {
    Ok(pk) => pk
    Err(e) => return Err(e)
  }
  match authentik_update_profile(config, authentik_pk, username, name, email) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  match password {
    Some(pw) => {
      match validate_password(pw) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      match authentik_set_password(config, authentik_pk, pw) {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
    }
    None => ()
  }
  let remove_group_pks = match obj.get("remove_group_pks") {
    Some(Array(arr)) => {
      let pks : Array[String] = []
      for item in arr {
        match item {
          String(s) => pks.push(s)
          _ => ()
        }
      }
      pks
    }
    _ => []
  }
  for remove_pk in remove_group_pks {
    if remove_pk != target_group_pk {
      let _ = authentik_remove_from_group(config, remove_pk, authentik_pk)
    }
  }
  match authentik_add_to_group(config, target_group_pk, authentik_pk) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  match db_admin_save_profile(config, target_user_id, role, class_level) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  if role == "student" {
    match class_level {
      Some(_) => {
        let ak = config.auth_key.get() catch { _ => "" }
        if ak != "" {
          let _ = StudentAgentClient::scoped(target_user_id, fn(
            c,
          ) raise @common.AgentError {
            c.trigger_invalidate_cache(ak, "profile")
          }) catch { _ => () }
        }
      }
      None => ()
    }
  }
  if role == "teacher" {
    let ak = config.auth_key.get() catch { _ => "" }
    if ak != "" {
      let _ = TeacherAgentClient::scoped(target_user_id, fn(
        c,
      ) raise @common.AgentError {
        c.trigger_invalidate_cache(ak, "class_groups")
      }) catch { _ => () }
    }
  }
  Ok(())
}

///|
pub fn admin_delete_user(
  config : SharedConfig,
  body_json : String,
) -> Result[Unit, AppError] {
  let val = @json.parse(body_json) catch {
    _ => return Err(validation_error("Invalid JSON body"))
  }
  let obj = match val {
    Object(o) => o
    _ => return Err(validation_error("Body must be an object"))
  }
  let authentik_pk = match obj.get("authentik_pk") {
    Some(Number(n, ..)) => n.to_int()
    _ => return Err(validation_error("authentik_pk is required"))
  }
  let target_user_id = match obj.get("target_user_id") {
    Some(String(s)) => s
    _ => return Err(validation_error("target_user_id is required"))
  }
  match db_admin_soft_delete_user(config, target_user_id) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  match authentik_delete_user(config, authentik_pk) {
    Ok(_) => Ok(())
    Err(e) => {
      let _ = db_admin_undo_soft_delete(config, target_user_id)
      Err(e)
    }
  }
}

///|
pub fn admin_set_user_active(
  config : SharedConfig,
  body_json : String,
) -> Result[Unit, AppError] {
  let val = @json.parse(body_json) catch {
    _ => return Err(validation_error("Invalid JSON body"))
  }
  let obj = match val {
    Object(o) => o
    _ => return Err(validation_error("Body must be an object"))
  }
  let authentik_pk = match obj.get("authentik_pk") {
    Some(Number(n, ..)) => n.to_int()
    _ => return Err(validation_error("authentik_pk is required"))
  }
  let is_active = match obj.get("is_active") {
    Some(True) => true
    Some(False) => false
    _ => return Err(validation_error("is_active is required"))
  }
  authentik_set_active(config, authentik_pk, is_active)
}
