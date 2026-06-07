///|
fn try_parse_session_terms(json_str : String) -> Array[SessionTermInfo]? {
  let val = @json.parse(json_str) catch { _ => return None }
  match val {
    Array(arr) => {
      let items : Array[SessionTermInfo] = []
      for i in arr {
        match i {
          Object(obj) =>
            items.push(SessionTermInfo::{
              id: match obj.get("id") {
                Some(String(s)) => s
                _ => continue
              },
              session: match obj.get("session") {
                Some(String(s)) => s
                _ => continue
              },
              term_name: match obj.get("term_name") {
                Some(String(s)) => s
                _ => continue
              },
              active: match obj.get("active") {
                Some(True) => true
                _ => false
              },
              created_at: match obj.get("created_at") {
                Some(String(s)) => s
                _ => ""
              },
            })
          _ => ()
        }
      }
      if items.length() > 0 {
        Some(items)
      } else {
        None
      }
    }
    _ => None
  }
}

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
pub fn admin_fetch_student_profile(
  config : SharedConfig,
  target_user_id : String,
) -> Result[StudentProfileInfo, AppError] {
  let arr = match db_admin_fetch_student_profile(config, target_user_id) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  if arr.length() > 0 {
    match arr[0] {
      Object(obj) =>
        Ok(StudentProfileInfo::{
          id: match obj.get("id") {
            Some(String(s)) => s
            _ => ""
          },
          surname: match obj.get("surname") {
            Some(String(s)) => s
            _ => ""
          },
          first_name: match obj.get("first_name") {
            Some(String(s)) => s
            _ => ""
          },
          middle_name: match obj.get("middle_name") {
            Some(String(s)) => Some(s)
            _ => None
          },
          display_name: match obj.get("display_name") {
            Some(String(s)) => s
            _ => ""
          },
          date_of_birth: match obj.get("date_of_birth") {
            Some(String(s)) => s
            _ => ""
          },
          class_enrolled: match obj.get("class_enrolled") {
            Some(String(s)) => s
            _ => ""
          },
          current_class: match obj.get("current_class") {
            Some(String(s)) => s
            _ => ""
          },
          passport: match obj.get("passport") {
            Some(String(s)) => s
            _ => ""
          },
          created_at: match obj.get("created_at") {
            Some(String(s)) => s
            _ => ""
          },
        })
      _ => Err(not_found_error("Student profile"))
    }
  } else {
    Err(not_found_error("Student profile"))
  }
}

///|
pub fn admin_fetch_teacher_profile(
  config : SharedConfig,
  target_user_id : String,
) -> Result[TeacherProfileInfo, AppError] {
  let arr = match db_admin_fetch_teacher_profile(config, target_user_id) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  if arr.length() > 0 {
    match arr[0] {
      Object(obj) =>
        Ok(TeacherProfileInfo::{
          id: match obj.get("id") {
            Some(String(s)) => s
            _ => ""
          },
          surname: match obj.get("surname") {
            Some(String(s)) => s
            _ => ""
          },
          first_name: match obj.get("first_name") {
            Some(String(s)) => s
            _ => ""
          },
          middle_name: match obj.get("middle_name") {
            Some(String(s)) => Some(s)
            _ => None
          },
          display_name: match obj.get("display_name") {
            Some(String(s)) => s
            _ => ""
          },
          qualifications: match obj.get("qualifications") {
            Some(Array(a)) => {
              let qs : Array[String] = []
              for x in a {
                match x {
                  String(s) => qs.push(s)
                  _ => ()
                }
              }
              Some(qs)
            }
            _ => None
          },
          date_employed: match obj.get("date_employed") {
            Some(String(s)) => Some(s)
            _ => None
          },
          passport: match obj.get("passport") {
            Some(String(s)) => s
            _ => ""
          },
          created_at: match obj.get("created_at") {
            Some(String(s)) => s
            _ => ""
          },
        })
      _ => Err(not_found_error("Teacher profile"))
    }
  } else {
    Err(not_found_error("Teacher profile"))
  }
}

///|
pub fn admin_fetch_admin_profile(
  config : SharedConfig,
  target_user_id : String,
) -> Result[AdminProfileInfo, AppError] {
  let arr = match db_admin_fetch_admin_profile(config, target_user_id) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  if arr.length() > 0 {
    match arr[0] {
      Object(obj) =>
        Ok(AdminProfileInfo::{
          id: match obj.get("id") {
            Some(String(s)) => s
            _ => ""
          },
          surname: match obj.get("surname") {
            Some(String(s)) => s
            _ => ""
          },
          first_name: match obj.get("first_name") {
            Some(String(s)) => s
            _ => ""
          },
          middle_name: match obj.get("middle_name") {
            Some(String(s)) => Some(s)
            _ => None
          },
          display_name: match obj.get("display_name") {
            Some(String(s)) => s
            _ => ""
          },
          role_title: match obj.get("role_title") {
            Some(String(s)) => Some(s)
            _ => None
          },
          passport: match obj.get("passport") {
            Some(String(s)) => s
            _ => ""
          },
          created_at: match obj.get("created_at") {
            Some(String(s)) => s
            _ => ""
          },
        })
      _ => Err(not_found_error("Admin profile"))
    }
  } else {
    Err(not_found_error("Admin profile"))
  }
}

///|
pub fn admin_fetch_parent_profile(
  config : SharedConfig,
  target_user_id : String,
) -> Result[ParentProfileInfo, AppError] {
  let arr = match db_admin_fetch_parent_profile(config, target_user_id) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  if arr.length() > 0 {
    match arr[0] {
      Object(obj) =>
        Ok(ParentProfileInfo::{
          id: match obj.get("id") {
            Some(String(s)) => s
            _ => ""
          },
          name: match obj.get("name") {
            Some(String(s)) => s
            _ => ""
          },
          display_name: match obj.get("display_name") {
            Some(String(s)) => s
            _ => ""
          },
          students: match obj.get("students") {
            Some(Array(a)) => {
              let sids : Array[String] = []
              for x in a {
                match x {
                  String(s) => sids.push(s)
                  _ => ()
                }
              }
              sids
            }
            _ => []
          },
          passport: match obj.get("passport") {
            Some(String(s)) => s
            _ => ""
          },
          created_at: match obj.get("created_at") {
            Some(String(s)) => s
            _ => ""
          },
        })
      _ => Err(not_found_error("Parent profile"))
    }
  } else {
    Err(not_found_error("Parent profile"))
  }
}

///|
pub fn admin_fetch_credentials(
  config : SharedConfig,
) -> Result[Array[CredentialInfo], AppError] {
  let arr = match db_admin_fetch_credentials(config) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  let items : Array[CredentialInfo] = []
  for item in arr {
    match item {
      Object(o) =>
        items.push(CredentialInfo::{
          id: match o.get("id") {
            Some(String(s)) => s
            _ => continue
          },
          name: match o.get("name") {
            Some(String(s)) => s
            _ => continue
          },
          active: match o.get("active") {
            Some(True) => true
            _ => false
          },
        })
      _ => ()
    }
  }
  Ok(items)
}

///|
pub fn admin_create_credential(
  config : SharedConfig,
  name : String,
) -> Result[CredentialInfo, AppError] {
  let arr = match db_admin_create_credential(config, name) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  if arr.length() > 0 {
    match arr[0] {
      Object(o) =>
        Ok(CredentialInfo::{
          id: match o.get("id") {
            Some(String(s)) => s
            _ => ""
          },
          name,
          active: true,
        })
      _ => Err(validation_error("Failed to create credential"))
    }
  } else {
    Err(validation_error("Failed to create credential"))
  }
}

///|
pub fn admin_delete_credential(
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
  let id = match obj.get("id") {
    Some(String(s)) => s
    _ => return Err(validation_error("id is required"))
  }
  match db_admin_delete_credential(config, id) {
    Ok(_) => Ok(())
    Err(e) => Err(e)
  }
}

///|
pub fn admin_fetch_active_session_term_id(
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
            cache.set(cache_key, id, CACHE_TTL, [], now)
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
) -> Result[SessionTermDetail, AppError] {
  let arr = match db_admin_fetch_active_session_term_detail(config) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  if arr.length() > 0 {
    match arr[0] {
      Object(obj) =>
        Ok(SessionTermDetail::{
          id: match obj.get("id") {
            Some(String(s)) => s
            _ => ""
          },
          session: match obj.get("session") {
            Some(String(s)) => s
            _ => ""
          },
          term_name: match obj.get("term_name") {
            Some(String(s)) => s
            _ => ""
          },
        })
      _ => Err(not_found_error("Active session term"))
    }
  } else {
    Err(not_found_error("Active session term"))
  }
}

///|
pub fn admin_fetch_terms(
  config : SharedConfig,
) -> Result[Array[TermSimple], AppError] {
  let arr = match db_admin_fetch_terms(config) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  let items : Array[TermSimple] = []
  for item in arr {
    match item {
      Object(o) =>
        items.push(TermSimple::{
          id: match o.get("id") {
            Some(String(s)) => s
            _ => continue
          },
          name: match o.get("name") {
            Some(String(s)) => s
            _ => continue
          },
          active: match o.get("active") {
            Some(True) => true
            _ => false
          },
          sort_order: match o.get("sort_order") {
            Some(Number(d, ..)) => d.to_int()
            _ => 0
          },
        })
      _ => ()
    }
  }
  Ok(items)
}

///|
pub fn admin_fetch_session_terms(
  cache : CacheSystem,
  config : SharedConfig,
  now : UInt64,
) -> Result[Array[SessionTermInfo], AppError] {
  let cache_key = "session_terms"
  match cache.get(cache_key, now) {
    Some(json_str) =>
      match try_parse_session_terms(json_str) {
        Some(items) => return Ok(items)
        None => ()
      }
    None => ()
  }
  let arr = match db_admin_fetch_session_terms(config) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  let items : Array[SessionTermInfo] = []
  for item in arr {
    match item {
      Object(o) =>
        items.push(SessionTermInfo::{
          id: match o.get("id") {
            Some(String(s)) => s
            _ => continue
          },
          session: match o.get("session") {
            Some(String(s)) => s
            _ => continue
          },
          term_name: match o.get("term_name") {
            Some(String(s)) => s
            _ => continue
          },
          active: match o.get("active") {
            Some(True) => true
            _ => false
          },
          created_at: match o.get("created_at") {
            Some(String(s)) => s
            _ => ""
          },
        })
      _ => ()
    }
  }
  cache.set(cache_key, items.to_json().stringify(), CACHE_TTL, [], now)
  Ok(items)
}

///|
pub fn admin_create_session_term(
  cache : CacheSystem,
  config : SharedConfig,
  body_json : String,
) -> Result[SessionTermInfo, AppError] {
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
  let arr = if active {
    match
      @api.with_atomic_operation(fn() -> Result[Array[Json], AppError] {
        match db_admin_deactivate_all_session_terms(config) {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
        db_admin_create_session_term(config, session, term_id, active)
      }) {
      Ok(a) => a
      Err(e) => return Err(e)
    }
  } else {
    match db_admin_create_session_term(config, session, term_id, false) {
      Ok(a) => a
      Err(e) => return Err(e)
    }
  }
  cache.invalidate("active_session_term")
  cache.invalidate("session_terms")
  if arr.length() > 0 {
    match arr[0] {
      Object(o) => {
        let term_name = match o.get("term_name") {
          Some(String(s)) => s
          _ => ""
        }
        let created_at_val = match o.get("created_at") {
          Some(String(s)) => s
          _ => ""
        }
        Ok(SessionTermInfo::{
          id: match o.get("id") {
            Some(String(s)) => s
            _ => ""
          },
          session,
          term_name,
          active,
          created_at: created_at_val,
        })
      }
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
  match
    @api.with_atomic_operation(fn() -> Result[Unit, AppError] {
      match db_admin_deactivate_all_session_terms(config) {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
      db_admin_activate_session_term(config, session_term_id)
    }) {
    Ok(_) => {
      cache.invalidate("active_session_term")
      cache.invalidate("session_terms")
      Ok(())
    }
    Err(e) => Err(e)
  }
}

///|
pub fn admin_toggle_term(
  config : SharedConfig,
  term_id : String,
  active : Bool,
) -> Result[Unit, AppError] {
  match db_teacher_update_record_active(config, term_id, active) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let students = match db_admin_fetch_users_by_role(config, "student") {
    Ok(a) => a
    Err(_) => []
  }
  let teachers = match db_admin_fetch_users_by_role(config, "teacher") {
    Ok(a) => a
    Err(_) => []
  }
  let ak = config.auth_key.get() catch { _ => "" }
  if ak != "" {
    for item in students {
      match item {
        Object(obj) => {
          let uid = match obj.get("id") {
            Some(String(s)) => s
            _ => continue
          }
          let _ = StudentAgentClient::scoped(uid, fn(
            c,
          ) raise @common.AgentError {
            c.trigger_invalidate_cache(ak, "all")
          }) catch {
            _ => ()
          }
        }
        _ => ()
      }
    }
    for item in teachers {
      match item {
        Object(obj) => {
          let uid = match obj.get("id") {
            Some(String(s)) => s
            _ => continue
          }
          let _ = TeacherAgentClient::scoped(uid, fn(
            c,
          ) raise @common.AgentError {
            c.trigger_invalidate_cache(ak, "all")
          }) catch {
            _ => ()
          }
        }
        _ => ()
      }
    }
  }
  Ok(())
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
  if pairs.length() > 0 {
    let active_st = match
      admin_fetch_active_session_term_id(cache, config, now) {
      Ok(id) => id
      Err(e) => return Err(e)
    }
    match
      @api.with_atomic_operation(fn() -> Result[Unit, AppError] {
        match
          db_admin_soft_delete_teacher_assignments(config, target_teacher_id) {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
        match
          db_admin_create_teacher_assignments(
            config, target_teacher_id, pairs, active_st,
          ) {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
        Ok(())
      }) {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
  } else {
    let _ = match
      db_admin_soft_delete_teacher_assignments(config, target_teacher_id) {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
  }
  let ak = config.auth_key.get() catch { _ => "" }
  if ak != "" {
    let _ = TeacherAgentClient::scoped(target_teacher_id, fn(
      c,
    ) raise @common.AgentError {
      c.trigger_invalidate_cache(ak, "class_groups")
    }) catch {
      _ => ()
    }
  }
  Ok("ok")
}

///|
fn create_user_saga(
  config : SharedConfig,
  username : String,
  display_name : String,
  email : String,
  password : String,
  is_active : Bool,
  role : String,
  group_pk : String,
) -> Result[(Int, String), AppError] {
  let mut created_pk : Int = 0
  let saga_result = @api.with_atomic_operation(fn() -> Result[
    (Int, String),
    AppError,
  ] {
    let (pk_inner, uuid_inner) = match
      authentik_create_user(
        config, username, display_name, email, password, is_active, group_pk,
      ) {
      Ok(r) => {
        created_pk = r.0
        r
      }
      Err(e) => return Err(e)
    }
    match authentik_set_password(config, pk_inner, password) {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    Ok((pk_inner, uuid_inner))
  })
  match saga_result {
    Ok(r) => Ok(r)
    Err(e) => {
      if created_pk != 0 {
        let _ = authentik_delete_user(config, created_pk)
      }
      return Err(e)
    }
  }
}

///|
fn create_user_response(
  pk : Int,
  uuid : String,
  username : String,
  display_name : String,
  email : String,
  is_active : Bool,
  group_pk : String,
) -> CreateUserResponse {
  let groups = if group_pk != "" { [group_pk] } else { [] }
  CreateUserResponse::{
    pk,
    uuid,
    username,
    name: display_name,
    email,
    is_active,
    groups,
  }
}

///|
fn invalidate_agent_cache(
  config : SharedConfig,
  role : String,
  target_id : String,
) -> Unit {
  let ak = config.auth_key.get() catch { _ => "" }
  if ak == "" {
    return ()
  }
  if role == "student" {
    let _ = StudentAgentClient::scoped(target_id, fn(
      c,
    ) raise @common.AgentError {
      c.trigger_invalidate_cache(ak, "profile")
    }) catch {
      _ => ()
    }
  }
  if role == "teacher" {
    let _ = TeacherAgentClient::scoped(target_id, fn(
      c,
    ) raise @common.AgentError {
      c.trigger_invalidate_cache(ak, "class_groups")
    }) catch {
      _ => ()
    }
  }
  if role == "parent" {
    let _ = ParentAgentClient::scoped(target_id, fn(
      c,
    ) raise @common.AgentError {
      c.trigger_invalidate_cache(ak, "linked_students")
    }) catch {
      _ => ()
    }
  }
}

///|
pub fn admin_create_student(
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
  let surname = match obj.get("surname") {
    Some(String(s)) => s
    _ => return Err(validation_error("Surname is required"))
  }
  let first_name = match obj.get("first_name") {
    Some(String(s)) => s
    _ => return Err(validation_error("First name is required"))
  }
  let middle_name = match obj.get("middle_name") {
    Some(String(s)) => if s == "" { None } else { Some(s) }
    _ => None
  }
  let display_name = match middle_name {
    Some(mn) => surname + " " + first_name + " " + mn
    None => surname + " " + first_name
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
  let class_level = match obj.get("class_level") {
    Some(String(s)) => if s == "" { None } else { Some(s) }
    _ => None
  }
  let passport_url = match obj.get("passport_url") {
    Some(String(s)) => s
    _ => return Err(validation_error("Passport is required"))
  }
  let dob = match obj.get("date_of_birth") {
    Some(String(s)) => s
    _ => return Err(validation_error("Date of birth is required"))
  }
  let group_pk = match obj.get("group_pk") {
    Some(String(s)) => s
    _ => ""
  }
  match validate_username(username) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match validate_name_part(surname, "Surname") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match validate_name_part(first_name, "First name") {
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
  match validate_role("student") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match validate_dob(dob) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match validate_passport_url(passport_url) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match class_level {
    Some(cl) =>
      match validate_class_level_exists(config, cl) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
    None => return Err(validation_error("Class level is required for students"))
  }
  let cl_id = match class_level {
    Some(cl) =>
      match db_admin_fetch_class_level_by_name(config, cl) {
        Ok(arr) =>
          if arr.length() > 0 {
            match arr[0] {
              Object(o) =>
                match o.get("id") {
                  Some(String(s)) => s
                  _ =>
                    return Err(AppError::{
                      code: SurrealDBError,
                      message: "Failed to resolve class level",
                      debug: None,
                    })
                }
              _ =>
                return Err(AppError::{
                  code: SurrealDBError,
                  message: "Unexpected response",
                  debug: None,
                })
            }
          } else {
            return Err(not_found_error("Class level"))
          }
        Err(e) => return Err(e)
      }
    None => return Err(validation_error("Class level is required"))
  }
  let (pk, uuid) = match
    create_user_saga(
      config, username, display_name, email, password, is_active, "student", group_pk,
    ) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  match
    @api.with_atomic_operation(fn() -> Result[Unit, AppError] {
      db_admin_create_student_profile(
        config, uuid, surname, first_name, middle_name, display_name, dob, cl_id,
        passport_url,
      )
    }) {
    Ok(_) => ()
    Err(e) => {
      let _ = authentik_delete_user(config, pk)
      return Err(e)
    }
  }
  invalidate_agent_cache(config, "student", uuid)
  Ok(
    create_user_response(
      pk, uuid, username, display_name, email, is_active, group_pk,
    ),
  )
}

///|
pub fn admin_create_teacher(
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
  let surname = match obj.get("surname") {
    Some(String(s)) => s
    _ => return Err(validation_error("Surname is required"))
  }
  let first_name = match obj.get("first_name") {
    Some(String(s)) => s
    _ => return Err(validation_error("First name is required"))
  }
  let middle_name = match obj.get("middle_name") {
    Some(String(s)) => if s == "" { None } else { Some(s) }
    _ => None
  }
  let display_name = match middle_name {
    Some(mn) => surname + " " + first_name + " " + mn
    None => surname + " " + first_name
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
  let passport_url = match obj.get("passport_url") {
    Some(String(s)) => s
    _ => return Err(validation_error("Passport is required"))
  }
  let group_pk = match obj.get("group_pk") {
    Some(String(s)) => s
    _ => ""
  }
  match validate_username(username) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match validate_name_part(surname, "Surname") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match validate_name_part(first_name, "First name") {
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
  match validate_role("teacher") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match validate_passport_url(passport_url) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let (pk, uuid) = match
    create_user_saga(
      config, username, display_name, email, password, is_active, "teacher", group_pk,
    ) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  match
    @api.with_atomic_operation(fn() -> Result[Unit, AppError] {
      db_admin_create_teacher_profile(
        config,
        uuid,
        surname,
        first_name,
        middle_name,
        display_name,
        None,
        None,
        passport_url,
      )
    }) {
    Ok(_) => ()
    Err(e) => {
      let _ = authentik_delete_user(config, pk)
      return Err(e)
    }
  }
  invalidate_agent_cache(config, "teacher", uuid)
  Ok(
    create_user_response(
      pk, uuid, username, display_name, email, is_active, group_pk,
    ),
  )
}

///|
pub fn admin_create_admin(
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
  let surname = match obj.get("surname") {
    Some(String(s)) => s
    _ => return Err(validation_error("Surname is required"))
  }
  let first_name = match obj.get("first_name") {
    Some(String(s)) => s
    _ => return Err(validation_error("First name is required"))
  }
  let middle_name = match obj.get("middle_name") {
    Some(String(s)) => if s == "" { None } else { Some(s) }
    _ => None
  }
  let display_name = match middle_name {
    Some(mn) => surname + " " + first_name + " " + mn
    None => surname + " " + first_name
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
  let passport_url = match obj.get("passport_url") {
    Some(String(s)) => s
    _ => return Err(validation_error("Passport is required"))
  }
  let group_pk = match obj.get("group_pk") {
    Some(String(s)) => s
    _ => ""
  }
  match validate_username(username) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match validate_name_part(surname, "Surname") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match validate_name_part(first_name, "First name") {
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
  match validate_role("admin") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match validate_passport_url(passport_url) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let (pk, uuid) = match
    create_user_saga(
      config, username, display_name, email, password, is_active, "admin", group_pk,
    ) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  match
    @api.with_atomic_operation(fn() -> Result[Unit, AppError] {
      db_admin_create_admin_profile(
        config,
        uuid,
        surname,
        first_name,
        middle_name,
        display_name,
        None,
        passport_url,
      )
    }) {
    Ok(_) => ()
    Err(e) => {
      let _ = authentik_delete_user(config, pk)
      return Err(e)
    }
  }
  Ok(
    create_user_response(
      pk, uuid, username, display_name, email, is_active, group_pk,
    ),
  )
}

///|
pub fn admin_create_parent(
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
  let passport_url = match obj.get("passport_url") {
    Some(String(s)) => s
    _ => return Err(validation_error("Passport is required"))
  }
  let group_pk = match obj.get("group_pk") {
    Some(String(s)) => s
    _ => ""
  }
  match validate_username(username) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match validate_name_part(name, "Name") {
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
  match validate_role("parent") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match validate_passport_url(passport_url) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let (pk, uuid) = match
    create_user_saga(
      config, username, name, email, password, is_active, "parent", group_pk,
    ) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  match
    @api.with_atomic_operation(fn() -> Result[Unit, AppError] {
      db_admin_create_parent_profile(config, uuid, name, passport_url)
    }) {
    Ok(_) => ()
    Err(e) => {
      let _ = authentik_delete_user(config, pk)
      return Err(e)
    }
  }
  invalidate_agent_cache(config, "parent", uuid)
  Ok(create_user_response(pk, uuid, username, name, email, is_active, group_pk))
}

///|
fn apply_edit_saga(
  config : SharedConfig,
  target_user_id : String,
  pk : Int,
  password : String?,
  username : String,
  display_name : String,
  email : String,
  old_role : String,
  new_role : String,
  remove_group_pks : Array[String],
) -> Result[Unit, AppError] {
  let target_group_pk = match authentik_get_group_pk_by_name(config, new_role) {
    Ok(pk) => pk
    Err(e) => return Err(e)
  }
  match
    @api.with_atomic_operation(fn() -> Result[Unit, AppError] {
      match
        authentik_update_profile(config, pk, username, display_name, email) {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
      match password {
        Some(pw) =>
          match authentik_set_password(config, pk, pw) {
            Ok(_) => ()
            Err(e) => return Err(e)
          }
        None => ()
      }
      for remove_pk in remove_group_pks {
        if remove_pk != target_group_pk {
          let _ = authentik_remove_from_group(config, remove_pk, pk)
        }
      }
      match authentik_add_to_group(config, target_group_pk, pk) {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
      Ok(())
    }) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  invalidate_agent_cache(config, new_role, target_user_id)
  Ok(())
}

///|
pub fn admin_edit_student(
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
  let pk = match obj.get("authentik_pk") {
    Some(Number(n, ..)) => n.to_int()
    _ => return Err(validation_error("authentik_pk is required"))
  }
  let password = match obj.get("password") {
    Some(String(s)) => if s == "" { None } else { Some(s) }
    _ => None
  }
  let username = match obj.get("username") {
    Some(String(s)) => s
    _ => return Err(validation_error("Username is required"))
  }
  let email = match obj.get("email") {
    Some(String(s)) => s
    _ => return Err(validation_error("Email is required"))
  }
  let display_name = match obj.get("display_name") {
    Some(String(s)) => s
    _ => return Err(validation_error("display_name is required"))
  }
  let remove_group_pks : Array[String] = match obj.get("remove_group_pks") {
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
  let surname = match obj.get("surname") {
    Some(String(s)) => s
    _ => return Err(validation_error("Surname is required"))
  }
  let first_name = match obj.get("first_name") {
    Some(String(s)) => s
    _ => return Err(validation_error("First name is required"))
  }
  let middle_name = match obj.get("middle_name") {
    Some(String(s)) => if s == "" { None } else { Some(s) }
    _ => None
  }
  let class_level = match obj.get("class_level") {
    Some(String(s)) => if s == "" { None } else { Some(s) }
    _ => None
  }
  let passport_url = match obj.get("passport_url") {
    Some(String(s)) => s
    _ => return Err(validation_error("Passport is required"))
  }
  let dob = match obj.get("date_of_birth") {
    Some(String(s)) => s
    _ => return Err(validation_error("Date of birth is required"))
  }
  match validate_name_part(surname, "Surname") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match validate_name_part(first_name, "First name") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match validate_dob(dob) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match validate_passport_url(passport_url) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match class_level {
    Some(cl) =>
      match validate_class_level_exists(config, cl) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
    None => return Err(validation_error("Class level is required for students"))
  }
  let cl_id = match class_level {
    Some(cl) =>
      match db_admin_fetch_class_level_by_name(config, cl) {
        Ok(arr) =>
          if arr.length() > 0 {
            match arr[0] {
              Object(o) =>
                match o.get("id") {
                  Some(String(s)) => s
                  _ =>
                    return Err(AppError::{
                      code: SurrealDBError,
                      message: "Failed to resolve class level",
                      debug: None,
                    })
                }
              _ =>
                return Err(AppError::{
                  code: SurrealDBError,
                  message: "Unexpected response",
                  debug: None,
                })
            }
          } else {
            return Err(not_found_error("Class level"))
          }
        Err(e) => return Err(e)
      }
    None => return Err(validation_error("Class level is required"))
  }
  match
    @api.with_atomic_operation(fn() -> Result[Unit, AppError] {
      db_admin_update_student_profile(
        config, target_user_id, surname, first_name, middle_name, display_name, dob,
        cl_id, passport_url,
      )
    }) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  apply_edit_saga(
    config, target_user_id, pk, password, username, display_name, email, "student",
    "student", remove_group_pks,
  )
}

///|
pub fn admin_edit_teacher(
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
  let pk = match obj.get("authentik_pk") {
    Some(Number(n, ..)) => n.to_int()
    _ => return Err(validation_error("authentik_pk is required"))
  }
  let password = match obj.get("password") {
    Some(String(s)) => if s == "" { None } else { Some(s) }
    _ => None
  }
  let username = match obj.get("username") {
    Some(String(s)) => s
    _ => return Err(validation_error("Username is required"))
  }
  let email = match obj.get("email") {
    Some(String(s)) => s
    _ => return Err(validation_error("Email is required"))
  }
  let display_name = match obj.get("display_name") {
    Some(String(s)) => s
    _ => return Err(validation_error("display_name is required"))
  }
  let remove_group_pks : Array[String] = match obj.get("remove_group_pks") {
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
  let surname = match obj.get("surname") {
    Some(String(s)) => s
    _ => return Err(validation_error("Surname is required"))
  }
  let first_name = match obj.get("first_name") {
    Some(String(s)) => s
    _ => return Err(validation_error("First name is required"))
  }
  let middle_name = match obj.get("middle_name") {
    Some(String(s)) => if s == "" { None } else { Some(s) }
    _ => None
  }
  let passport_url = match obj.get("passport_url") {
    Some(String(s)) => s
    _ => return Err(validation_error("Passport is required"))
  }
  match validate_name_part(surname, "Surname") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match validate_name_part(first_name, "First name") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match validate_passport_url(passport_url) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match
    @api.with_atomic_operation(fn() -> Result[Unit, AppError] {
      db_admin_update_teacher_profile(
        config,
        target_user_id,
        surname,
        first_name,
        middle_name,
        display_name,
        None,
        None,
        passport_url,
      )
    }) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  apply_edit_saga(
    config, target_user_id, pk, password, username, display_name, email, "teacher",
    "teacher", remove_group_pks,
  )
}

///|
pub fn admin_edit_admin(
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
  let pk = match obj.get("authentik_pk") {
    Some(Number(n, ..)) => n.to_int()
    _ => return Err(validation_error("authentik_pk is required"))
  }
  let password = match obj.get("password") {
    Some(String(s)) => if s == "" { None } else { Some(s) }
    _ => None
  }
  let username = match obj.get("username") {
    Some(String(s)) => s
    _ => return Err(validation_error("Username is required"))
  }
  let email = match obj.get("email") {
    Some(String(s)) => s
    _ => return Err(validation_error("Email is required"))
  }
  let display_name = match obj.get("display_name") {
    Some(String(s)) => s
    _ => return Err(validation_error("display_name is required"))
  }
  let remove_group_pks : Array[String] = match obj.get("remove_group_pks") {
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
  let surname = match obj.get("surname") {
    Some(String(s)) => s
    _ => return Err(validation_error("Surname is required"))
  }
  let first_name = match obj.get("first_name") {
    Some(String(s)) => s
    _ => return Err(validation_error("First name is required"))
  }
  let middle_name = match obj.get("middle_name") {
    Some(String(s)) => if s == "" { None } else { Some(s) }
    _ => None
  }
  let passport_url = match obj.get("passport_url") {
    Some(String(s)) => s
    _ => return Err(validation_error("Passport is required"))
  }
  match validate_name_part(surname, "Surname") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match validate_name_part(first_name, "First name") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match validate_passport_url(passport_url) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match
    @api.with_atomic_operation(fn() -> Result[Unit, AppError] {
      db_admin_update_admin_profile(
        config,
        target_user_id,
        surname,
        first_name,
        middle_name,
        display_name,
        None,
        passport_url,
      )
    }) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  apply_edit_saga(
    config, target_user_id, pk, password, username, display_name, email, "admin",
    "admin", remove_group_pks,
  )
}

///|
pub fn admin_edit_parent(
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
  let pk = match obj.get("authentik_pk") {
    Some(Number(n, ..)) => n.to_int()
    _ => return Err(validation_error("authentik_pk is required"))
  }
  let password = match obj.get("password") {
    Some(String(s)) => if s == "" { None } else { Some(s) }
    _ => None
  }
  let username = match obj.get("username") {
    Some(String(s)) => s
    _ => return Err(validation_error("Username is required"))
  }
  let email = match obj.get("email") {
    Some(String(s)) => s
    _ => return Err(validation_error("Email is required"))
  }
  let display_name = match obj.get("display_name") {
    Some(String(s)) => s
    _ => return Err(validation_error("display_name is required"))
  }
  let remove_group_pks : Array[String] = match obj.get("remove_group_pks") {
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
  let passport_url = match obj.get("passport_url") {
    Some(String(s)) => s
    _ => return Err(validation_error("Passport is required"))
  }
  match validate_name_part(display_name, "Name") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match validate_passport_url(passport_url) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match
    @api.with_atomic_operation(fn() -> Result[Unit, AppError] {
      db_admin_update_parent_profile(
        config, target_user_id, display_name, passport_url,
      )
    }) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  apply_edit_saga(
    config, target_user_id, pk, password, username, display_name, email, "parent",
    "parent", remove_group_pks,
  )
}

///|
fn do_delete(
  config : SharedConfig,
  pk : Int,
  user_id : String,
  role : String,
  db_delete : (SharedConfig, String) -> Result[Unit, AppError],
  db_undo : (SharedConfig, String) -> Result[Unit, AppError],
) -> Result[Unit, AppError] {
  match
    @api.with_atomic_operation(fn() -> Result[Unit, AppError] {
      match db_delete(config, user_id) {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
      match authentik_delete_user(config, pk) {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
      Ok(())
    }) {
    Ok(_) => {
      invalidate_agent_cache(config, role, user_id)
      Ok(())
    }
    Err(e) => {
      let _ = db_undo(config, user_id)
      return Err(e)
    }
  }
}

///|
pub fn admin_delete_student(
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
  let pk = match obj.get("authentik_pk") {
    Some(Number(n, ..)) => n.to_int()
    _ => return Err(validation_error("authentik_pk is required"))
  }
  let user_id = match obj.get("target_user_id") {
    Some(String(s)) => s
    _ => return Err(validation_error("target_user_id is required"))
  }
  do_delete(
    config, pk, user_id, "student", db_admin_soft_delete_student_profile, db_admin_undo_soft_delete_student_profile,
  )
}

///|
pub fn admin_delete_teacher(
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
  let pk = match obj.get("authentik_pk") {
    Some(Number(n, ..)) => n.to_int()
    _ => return Err(validation_error("authentik_pk is required"))
  }
  let user_id = match obj.get("target_user_id") {
    Some(String(s)) => s
    _ => return Err(validation_error("target_user_id is required"))
  }
  do_delete(
    config, pk, user_id, "teacher", db_admin_soft_delete_teacher_profile, db_admin_undo_soft_delete_teacher_profile,
  )
}

///|
pub fn admin_delete_admin(
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
  let pk = match obj.get("authentik_pk") {
    Some(Number(n, ..)) => n.to_int()
    _ => return Err(validation_error("authentik_pk is required"))
  }
  let user_id = match obj.get("target_user_id") {
    Some(String(s)) => s
    _ => return Err(validation_error("target_user_id is required"))
  }
  do_delete(
    config, pk, user_id, "admin", db_admin_soft_delete_admin_profile, db_admin_undo_soft_delete_admin_profile,
  )
}

///|
pub fn admin_delete_parent(
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
  let pk = match obj.get("authentik_pk") {
    Some(Number(n, ..)) => n.to_int()
    _ => return Err(validation_error("authentik_pk is required"))
  }
  let user_id = match obj.get("target_user_id") {
    Some(String(s)) => s
    _ => return Err(validation_error("target_user_id is required"))
  }
  do_delete(
    config, pk, user_id, "parent", db_admin_soft_delete_parent_profile, db_admin_undo_soft_delete_parent_profile,
  )
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
