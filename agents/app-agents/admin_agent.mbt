///|
#derive.golem_schema
struct ClassLevelInfo {
  id : String
  name : String
}

///|
#derive.golem_schema
struct UserProfileInfo {
  auth_id : String
  role : String
  class_level : String
  created_at : String
}

///|
#derive.golem_schema
struct CreateUserResponse {
  pk : Int
  uuid : String
  username : String
  name : String
  email : String
  is_active : Bool
  groups : Array[String]
}

///|
#derive.agent
#derive.mount("/admin/{admin_id}")
struct AdminAgent {
  admin_id : String
  config : @config.Config[SharedConfig]
  mut caches : Map[String, CacheItem]
}

///|
fn AdminAgent::new(
  admin_id : String,
  config : @config.Config[SharedConfig],
) -> AdminAgent {
  { admin_id, config, caches: Map::new() }
}

///|
#derive.endpoint(get="/ping")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::ping(self : Self, incoming_key : String) -> String {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return e.to_json_string()
    Ok(_) => ()
  }
  "admin online"
}

///|
#derive.endpoint(get="/get-profile?target_user_id={target_user_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::get_profile(
  self : Self,
  incoming_key : String,
  target_user_id : String,
) -> Result[UserProfileInfo, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  let sql = "SELECT auth_id, role, class_level.name AS class_level, created_at FROM user_profile WHERE " +
    "auth_id = '" +
    escape_surreal_string(target_user_id) +
    "' AND deleted_at IS NONE LIMIT 1"
  match surreal_query(self.config.value, sql) {
    Ok(arr) =>
      if arr.length() > 0 {
        match arr[0] {
          Object(obj) => {
            let auth_id = match obj.get("auth_id") {
              Some(String(s)) => s
              _ => ""
            }
            let role = match obj.get("role") {
              Some(String(s)) => s
              _ => ""
            }
            let class_level = match obj.get("class_level") {
              Some(String(s)) => s
              _ => ""
            }
            let created_at = match obj.get("created_at") {
              Some(String(s)) => s
              _ => ""
            }
            Ok(UserProfileInfo::{ auth_id, role, class_level, created_at })
          }
          _ =>
            Err(
              AppError::{ code: NotFound, message: "Profile not found", detail: None }
              .to_json_string(),
            )
        }
      } else {
        Err(
          AppError::{ code: NotFound, message: "Profile not found", detail: None }.to_json_string(),
        )
      }
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(post="/soft-delete-profile?target_user_id={target_user_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::soft_delete_profile(
  self : Self,
  incoming_key : String,
  target_user_id : String,
) -> Result[String, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match surreal_soft_delete_user(self.config.value, target_user_id) {
    Ok(_) => Ok("ok")
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/class-levels")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::get_class_levels(
  self : Self,
  incoming_key : String,
) -> Result[Array[ClassLevelInfo], String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  let sql = "SELECT id, name FROM class_levels ORDER BY name ASC"
  match surreal_query(self.config.value, sql) {
    Ok(arr) => {
      let items : Array[ClassLevelInfo] = []
      for item in arr {
        match item {
          Object(o) => {
            let id = match o.get("id") {
              Some(v) =>
                match v {
                  String(s) => s
                  _ => continue
                }
              None => continue
            }
            let name = match o.get("name") {
              Some(v) =>
                match v {
                  String(s) => s
                  _ => continue
                }
              None => continue
            }
            items.push(ClassLevelInfo::{ id, name })
          }
          _ => ()
        }
      }
      Ok(items)
    }
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/class-subjects")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::get_available_class_subjects(
  self : Self,
  incoming_key : String,
) -> Result[Array[TeacherSubjectPair], String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  let cl_arr = match
    surreal_query(
      self.config.value,
      "SELECT id, name FROM class_levels ORDER BY name ASC",
    ) {
    Ok(arr) => arr
    Err(e) => return Err(e.to_json_string())
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
    let subj_sql = "SELECT id AS edge_id, out.id AS subject_id, out.name AS subject_name, " +
      "out.code AS subject_code FROM has_subject " +
      "WHERE in = type::thing(\"class_levels\", " +
      escape_surreal_string(cl_id) +
      ") AND active = true ORDER BY out.name ASC"
    let subj_arr = match surreal_query(self.config.value, subj_sql) {
      Ok(arr) => arr
      Err(_) => continue
    }
    for subj_item in subj_arr {
      match subj_item {
        Object(obj) => {
          let edge_id = match obj.get("edge_id") {
            Some(String(s)) => s
            _ => continue
          }
          let subject_id = match obj.get("subject_id") {
            Some(String(s)) => s
            _ => continue
          }
          let subject_name = match obj.get("subject_name") {
            Some(String(s)) => s
            _ => continue
          }
          let subject_code = match obj.get("subject_code") {
            Some(String(s)) => Some(s)
            _ => None
          }
          pairs.push(TeacherSubjectPair::{
            edge_id,
            class_level_id: cl_id,
            class_level_name: cl_name,
            subject_id,
            subject_name,
            subject_code,
          })
        }
        _ => ()
      }
    }
  }
  Ok(pairs)
}

///|
#derive.endpoint(get="/teacher/subjects?target_teacher_id={target_teacher_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::get_teacher_subjects(
  self : Self,
  incoming_key : String,
  target_teacher_id : String,
) -> Result[Array[TeacherSubjectPair], String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  let sql = "SELECT teacher_id, " +
    "has_subject.id AS edge_id, " +
    "has_subject.in.id AS class_level_id, " +
    "has_subject.in.name AS class_level_name, " +
    "has_subject.out.id AS subject_id, " +
    "has_subject.out.name AS subject_name, " +
    "has_subject.out.code AS subject_code " +
    "FROM teacher_assignment WHERE teacher_id = '" +
    escape_surreal_string(target_teacher_id) +
    "' AND deleted_at IS NONE ORDER BY class_level_name ASC, subject_name ASC"
  let result_arr = match surreal_query(self.config.value, sql) {
    Ok(arr) => arr
    Err(e) => return Err(e.to_json_string())
  }
  let pairs : Array[TeacherSubjectPair] = []
  for item in result_arr {
    match item {
      Object(obj) => {
        let edge_id = match obj.get("edge_id") {
          Some(String(s)) => s
          _ => continue
        }
        let class_level_id = match obj.get("class_level_id") {
          Some(String(s)) => s
          _ => continue
        }
        let class_level_name = match obj.get("class_level_name") {
          Some(String(s)) => s
          _ => continue
        }
        let subject_id = match obj.get("subject_id") {
          Some(String(s)) => s
          _ => continue
        }
        let subject_name = match obj.get("subject_name") {
          Some(String(s)) => s
          _ => continue
        }
        let subject_code = match obj.get("subject_code") {
          Some(String(s)) => Some(s)
          _ => None
        }
        pairs.push(TeacherSubjectPair::{
          edge_id,
          class_level_id,
          class_level_name,
          subject_id,
          subject_name,
          subject_code,
        })
      }
      _ => ()
    }
  }
  Ok(pairs)
}

///|
#derive.endpoint(post="/teacher/subjects?target_teacher_id={target_teacher_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
#derive.endpoint_body("pairs_json")
pub fn AdminAgent::set_teacher_subjects(
  self : Self,
  incoming_key : String,
  target_teacher_id : String,
  pairs_json : String,
) -> Result[String, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  let pairs : Array[TeacherSubjectPair] = []
  let val = @json.parse(pairs_json) catch {
    _ =>
      return Err(
        AppError::{
          code: ValidationError,
          message: "Invalid JSON body",
          detail: None,
        }.to_json_string(),
      )
  }
  match val {
    Array(arr) =>
      for item in arr {
        match item {
          Object(obj) => {
            let edge_id = match obj.get("has_subject_id") {
              Some(String(s)) => s
              _ => continue
            }
            let class_level_id = match obj.get("class_level_id") {
              Some(String(s)) => s
              _ => continue
            }
            let class_level_name = match obj.get("class_level_name") {
              Some(String(s)) => s
              _ => ""
            }
            let subject_id = match obj.get("subject_id") {
              Some(String(s)) => s
              _ => continue
            }
            let subject_name = match obj.get("subject_name") {
              Some(String(s)) => s
              _ => ""
            }
            let subject_code = match obj.get("subject_code") {
              Some(String(s)) => Some(s)
              _ => None
            }
            pairs.push(TeacherSubjectPair::{
              edge_id,
              class_level_id,
              class_level_name,
              subject_id,
              subject_name,
              subject_code,
            })
          }
          _ => ()
        }
      }
    _ =>
      return Err(
        AppError::{
          code: ValidationError,
          message: "Invalid JSON body",
          detail: None,
        }.to_json_string(),
      )
  }
  let soft_delete_sql = "UPDATE teacher_assignment SET deleted_at = time::now() WHERE teacher_id = '" +
    escape_surreal_string(target_teacher_id) +
    "' AND deleted_at IS NONE"
  match surreal_query(self.config.value, soft_delete_sql) {
    Ok(_) => ()
    Err(e) => return Err(e.to_json_string())
  }
  if pairs.length() > 0 {
    let active_st = match self.get_active_st() {
      Ok(id) => id
      Err(e) => return Err(e.to_json_string())
    }
    let create_sql = StringBuilder::new()
    for pair in pairs {
      create_sql.write_string("CREATE teacher_assignment SET teacher_id = '")
      create_sql.write_string(escape_surreal_string(target_teacher_id))
      create_sql.write_string("', has_subject = ")
      create_sql.write_string(pair.edge_id)
      if active_st != "" {
        create_sql.write_string(", session_term = ")
        create_sql.write_string(active_st)
      }
      create_sql.write_string(", assigned_at = time::now();")
    }
    match surreal_query(self.config.value, create_sql.to_string()) {
      Ok(_) => ()
      Err(e) => return Err(e.to_json_string())
    }
  }
  let ak = self.config.value.auth_key.get() catch { _ => "error" }
  let _ = TeacherAgentClient::scoped(target_teacher_id, fn(
    client,
  ) raise @common.AgentError {
    client.invalidate_cache(ak, "class_groups")
  }) catch {
    _ => "error"
  }
  Ok("ok")
}

///|
fn AdminAgent::get_active_st(self : Self) -> Result[String, AppError] {
  let now = @wallClock.now().seconds
  match self.caches.get("active_session_term") {
    Some(item) if now - item.fetched_at < CACHE_TTL =>
      match item.data {
        ActiveSessionTerm(id) => return Ok(id)
        _ => ()
      }
    _ => ()
  }
  match
    surreal_query(
      self.config.value,
      "SELECT VALUE id FROM session_term WHERE active = true LIMIT 1",
    ) {
    Ok(arr) =>
      if arr.length() > 0 {
        match arr[0] {
          String(id) => {
            self.caches.set("active_session_term", CacheItem::{
              data: ActiveSessionTerm(id),
              fetched_at: now,
            })
            Ok(id)
          }
          _ =>
            Err(
              AppError::{
                code: NotFound,
                message: "No active session term found.",
                detail: None,
              },
            )
        }
      } else {
        Err(
          AppError::{
            code: NotFound,
            message: "No active session term found.",
            detail: None,
          },
        )
      }
    Err(_) =>
      Err(
        AppError::{
          code: SurrealDBError,
          message: "Failed to query active session term.",
          detail: None,
        },
      )
  }
}

///|
#derive.endpoint(get="/active-session-term")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::get_active_session_term(
  self : Self,
  incoming_key : String,
) -> Result[String, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  let sql = "SELECT id, session, term.name AS term_name FROM session_term WHERE active = true LIMIT 1"
  match surreal_query(self.config.value, sql) {
    Ok(arr) =>
      if arr.length() > 0 {
        match arr[0] {
          Object(obj) => {
            let id = match obj.get("id") {
              Some(String(s)) => s
              _ => ""
            }
            let session = match obj.get("session") {
              Some(String(s)) => s
              _ => ""
            }
            let term_name = match obj.get("term_name") {
              Some(String(s)) => s
              _ => ""
            }
            Ok(
              "{\"id\":\"" +
              escape_json_string(id) +
              "\",\"session\":\"" +
              escape_json_string(session) +
              "\",\"term_name\":\"" +
              escape_json_string(term_name) +
              "\"}",
            )
          }
          _ => Ok("{}")
        }
      } else {
        Ok("{}")
      }
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/terms")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::get_terms(
  self : Self,
  incoming_key : String,
) -> Result[String, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  let sql = "SELECT id, name, sort_order FROM terms ORDER BY sort_order ASC"
  match surreal_query(self.config.value, sql) {
    Ok(arr) => {
      let items = arr.map(fn(item) {
        match item {
          Object(o) => {
            let id = match o.get("id") {
              Some(v) =>
                match v {
                  String(s) => s
                  _ => ""
                }
              None => ""
            }
            let name = match o.get("name") {
              Some(v) =>
                match v {
                  String(s) => s
                  _ => ""
                }
              None => ""
            }
            "{\"id\":\"" + escape_json_string(id) + "\",\"name\":\"" + escape_json_string(name) + "\"}"
          }
          _ => "null"
        }
      })
      Ok("[" + items.join(",") + "]")
    }
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/session-terms")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::get_session_terms(
  self : Self,
  incoming_key : String,
) -> Result[String, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  let sql = "SELECT id, session, term.name AS term_name, active, created_at " +
    "FROM session_term ORDER BY created_at DESC"
  match surreal_query(self.config.value, sql) {
    Ok(arr) => {
      let items = arr.map(fn(item) {
        match item {
          Object(o) => {
            let id = match o.get("id") {
              Some(v) =>
                match v {
                  String(s) => s
                  _ => ""
                }
              None => ""
            }
            let session = match o.get("session") {
              Some(v) =>
                match v {
                  String(s) => s
                  _ => ""
                }
              None => ""
            }
            let term_name = match o.get("term_name") {
              Some(v) =>
                match v {
                  String(s) => s
                  _ => ""
                }
              None => ""
            }
            let active = match o.get("active") {
              Some(True) => true
              _ => false
            }
            let created_at = match o.get("created_at") {
              Some(v) =>
                match v {
                  String(s) => s
                  _ => ""
                }
              None => ""
            }
            "{\"id\":\"" + escape_json_string(id) +
            "\",\"session\":\"" + escape_json_string(session) +
            "\",\"term_name\":\"" + escape_json_string(term_name) +
            "\",\"active\":" + (if active { "true" } else { "false" }) +
            ",\"created_at\":\"" + escape_json_string(created_at) + "\"}"
          }
          _ => "null"
        }
      })
      Ok("[" + items.join(",") + "]")
    }
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(post="/create-session-term")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
#derive.endpoint_body("body_json")
pub fn AdminAgent::create_session_term(
  self : Self,
  incoming_key : String,
  body_json : String,
) -> Result[String, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  let val = @json.parse(body_json) catch {
    _ => return Err(AppError::{ code: ValidationError, message: "Invalid JSON body", detail: None }.to_json_string())
  }
  let obj = match val {
    Object(o) => o
    _ => return Err(AppError::{ code: ValidationError, message: "Body must be an object", detail: None }.to_json_string())
  }
  let session = match obj.get("session") {
    Some(String(s)) => s
    _ => return Err(AppError::{ code: ValidationError, message: "Session is required", detail: None }.to_json_string())
  }
  let term_id = match obj.get("term_id") {
    Some(String(s)) => s
    _ => return Err(AppError::{ code: ValidationError, message: "term_id is required", detail: None }.to_json_string())
  }
  let active = match obj.get("active") {
    Some(True) => true
    _ => false
  }
  self.caches.remove("active_session_term")
  if active {
    let deactivate_sql = "UPDATE session_term SET active = false"
    match surreal_query(self.config.value, deactivate_sql) {
      Ok(_) => ()
      Err(e) => return Err(e.to_json_string())
    }
  }
  let create_sql = "CREATE session_term SET session = '" +
    escape_surreal_string(session) +
    "', term = " + term_id +
    ", active = " + (if active { "true" } else { "false" }) +
    ", created_at = time::now()"
  match surreal_query(self.config.value, create_sql) {
    Ok(arr) =>
      if arr.length() > 0 {
        match arr[0] {
          Object(o) => {
            let id = match o.get("id") {
              Some(v) =>
                match v {
                  String(s) => s
                  _ => ""
                }
              None => ""
            }
            Ok(
              "{\"id\":\"" + escape_json_string(id) +
              "\",\"session\":\"" + escape_json_string(session) +
              "\",\"active\":" + (if active { "true" } else { "false" }) +
              "}",
            )
          }
          _ => Err(AppError::{ code: InternalError, message: "Failed to create session term", detail: None }.to_json_string())
        }
      } else {
        Err(AppError::{ code: InternalError, message: "Failed to create session term", detail: None }.to_json_string())
      }
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(post="/activate-session-term?session_term_id={session_term_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::activate_session_term(
  self : Self,
  incoming_key : String,
  session_term_id : String,
) -> Result[String, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  self.caches.remove("active_session_term")
  let deactivate_sql = "UPDATE session_term SET active = false"
  match surreal_query(self.config.value, deactivate_sql) {
    Ok(_) => ()
    Err(e) => return Err(e.to_json_string())
  }
  let activate_sql = "UPDATE session_term SET active = true WHERE id = " + session_term_id
  match surreal_query(self.config.value, activate_sql) {
    Ok(_) => Ok("ok")
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(post="/invalidate-cache?key={key}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::invalidate_cache(
  self : Self,
  incoming_key : String,
  key : String,
) -> String {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return e.to_json_string()
    Ok(_) => ()
  }
  if key == "all" {
    self.caches = Map::new()
  } else {
    self.caches.remove(key)
  }
  "OK"
}

// ─────────────────────────────────────────────
// User CRUD — Saga Pattern with Compensation
// ─────────────────────────────────────────────

///|
/// Creates a user in Authentik + SurrealDB with compensation on failure.
/// Steps: validate → create user → set password → save profile
/// If step 2/3 fails, the created Authentik user is cleaned up.
#derive.endpoint(post="/create-user")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
#derive.endpoint_body("body_json")
pub fn AdminAgent::create_user_in_authentik(
  self : Self,
  incoming_key : String,
  body_json : String,
) -> Result[CreateUserResponse, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  let val = @json.parse(body_json) catch {
    _ =>
      return Err(
        AppError::{ code: ValidationError, message: "Invalid JSON body", detail: None }
        .to_json_string(),
      )
  }
  let obj = match val {
    Object(o) => o
    _ =>
      return Err(
        AppError::{ code: ValidationError, message: "Body must be an object", detail: None }
        .to_json_string(),
      )
  }
  let username = match obj.get("username") {
    Some(String(s)) => s
    _ =>
      return Err(
        AppError::{
          code: ValidationError,
          message: "Username is required",
          detail: None,
        }.to_json_string(),
      )
  }
  let name = match obj.get("name") {
    Some(String(s)) => s
    _ =>
      return Err(
        AppError::{ code: ValidationError, message: "Name is required", detail: None }
        .to_json_string(),
      )
  }
  let email = match obj.get("email") {
    Some(String(s)) => s
    _ =>
      return Err(
        AppError::{ code: ValidationError, message: "Email is required", detail: None }
        .to_json_string(),
      )
  }
  let password = match obj.get("password") {
    Some(String(s)) => s
    _ =>
      return Err(
        AppError::{
          code: ValidationError,
          message: "Password is required",
          detail: None,
        }.to_json_string(),
      )
  }
  let is_active = match obj.get("is_active") {
    Some(True) => true
    Some(False) => false
    _ => true
  }
  let group_name_or_pk = match obj.get("group_pk") {
    Some(String(s)) => s
    _ => ""
  }
  let role = match obj.get("role") {
    Some(String(s)) => s
    _ =>
      return Err(
        AppError::{ code: ValidationError, message: "Role is required", detail: None }
        .to_json_string(),
      )
  }
  let class_level = match obj.get("class_level") {
    Some(String(s)) => if s == "" { None } else { Some(s) }
    _ => None
  }

  match validate_username(username) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match validate_name(name) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match validate_email(email) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match validate_password(password) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match validate_role(role) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }

  let group_pk = if group_name_or_pk != "" {
    // Try to resolve name → PK. If it already looks like a UUID (PK), use it as-is.
    if group_name_or_pk.contains("-") && group_name_or_pk.length() > 30 {
      group_name_or_pk
    } else {
      match authentik_get_group_pk_by_name(self.config.value, group_name_or_pk) {
        Ok(pk) => pk
        Err(e) => return Err(e.to_json_string())
      }
    }
  } else {
    ""
  }

  if class_level is Some(cl) {
    match validate_class_level_exists(self.config.value, cl) {
      Err(e) => return Err(e.to_json_string())
      Ok(_) => ()
    }
  }

  let (pk, uuid) = match
    authentik_create_user(
      self.config.value,
      username,
      name,
      email,
      password,
      is_active,
      group_pk,
    ) {
    Ok(r) => r
    Err(e) => return Err(e.to_json_string())
  }

  match authentik_set_password(self.config.value, pk, password) {
    Ok(_) => ()
    Err(_) => {
      let _ = authentik_delete_user(self.config.value, pk)
      return Err(
        AppError::{
          code: AuthentikError,
          message: "Failed to set password for created user. User was rolled back.",
          detail: None,
        }.to_json_string(),
      )
    }
  }

  match surreal_save_profile(self.config.value, uuid, role, class_level) {
    Ok(_) => ()
    Err(e) => {
      let _ = authentik_delete_user(self.config.value, pk)
      return Err(
        AppError::{
          code: e.code,
          message: e.message,
          detail: e.detail,
        }.to_json_string(),
      )
    }
  }

  if role == "student" {
    match class_level {
      Some(_) => {
        let ak = self.config.value.auth_key.get() catch { _ => "error" }
        let _ = StudentAgentClient::scoped(uuid, fn(
          client,
        ) raise @common.AgentError {
          client.invalidate_cache(ak, "profile")
        }) catch {
          _ => "error"
        }
      }
      None => ()
    }
  }
  if role == "teacher" {
    let ak = self.config.value.auth_key.get() catch { _ => "error" }
    let _ = TeacherAgentClient::scoped(uuid, fn(
      client,
    ) raise @common.AgentError {
      client.invalidate_cache(ak, "class_groups")
    }) catch {
      _ => "error"
    }
  }

  let groups = if group_pk != "" { [group_pk] } else { [] }
  Ok(
    CreateUserResponse::{
      pk,
      uuid,
      username,
      name,
      email,
      is_active,
      groups,
    },
  )
}

///|
/// Edits a user in Authentik + SurrealDB.
/// Steps: validate → resolve group PK → update profile → set password (opt) →
///        remove old groups → add to target group → save profile → invalidate caches.
/// Non-critical failures (group removal) are logged but don't stop the flow.
#derive.endpoint(post="/edit-user")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
#derive.endpoint_body("body_json")
pub fn AdminAgent::edit_user_in_authentik(
  self : Self,
  incoming_key : String,
  body_json : String,
) -> Result[String, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  let val = @json.parse(body_json) catch {
    _ =>
      return Err(
        AppError::{ code: ValidationError, message: "Invalid JSON body", detail: None }
        .to_json_string(),
      )
  }
  let obj = match val {
    Object(o) => o
    _ =>
      return Err(
        AppError::{ code: ValidationError, message: "Body must be an object", detail: None }
        .to_json_string(),
      )
  }
  let target_user_id = match obj.get("target_user_id") {
    Some(String(s)) => s
    _ =>
      return Err(
        AppError::{
          code: ValidationError,
          message: "target_user_id is required",
          detail: None,
        }.to_json_string(),
      )
  }
  let authentik_pk = match obj.get("authentik_pk") {
    Some(Number(n, ..)) => n.to_int()
    _ =>
      return Err(
        AppError::{
          code: ValidationError,
          message: "authentik_pk is required",
          detail: None,
        }.to_json_string(),
      )
  }
  let password = match obj.get("password") {
    Some(String(s)) => if s == "" { None } else { Some(s) }
    _ => None
  }
  let role = match obj.get("role") {
    Some(String(s)) => s
    _ =>
      return Err(
        AppError::{ code: ValidationError, message: "Role is required", detail: None }
        .to_json_string(),
      )
  }
  let class_level = match obj.get("class_level") {
    Some(String(s)) => if s == "" { None } else { Some(s) }
    _ => None
  }
  let username = match obj.get("username") {
    Some(String(s)) => s
    _ =>
      return Err(
        AppError::{ code: ValidationError, message: "Username is required", detail: None }
        .to_json_string(),
      )
  }
  let name = match obj.get("name") {
    Some(String(s)) => s
    _ =>
      return Err(
        AppError::{ code: ValidationError, message: "Name is required", detail: None }
        .to_json_string(),
      )
  }
  let email = match obj.get("email") {
    Some(String(s)) => s
    _ =>
      return Err(
        AppError::{ code: ValidationError, message: "Email is required", detail: None }
        .to_json_string(),
      )
  }

  match validate_username(username) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match validate_name(name) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match validate_email(email) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match validate_role(role) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  if class_level is Some(cl) {
    match validate_class_level_exists(self.config.value, cl) {
      Err(e) => return Err(e.to_json_string())
      Ok(_) => ()
    }
  }

  let target_group_pk = match authentik_get_group_pk_by_name(
    self.config.value,
    role,
  ) {
    Ok(pk) => pk
    Err(e) => return Err(e.to_json_string())
  }

  match authentik_update_profile(self.config.value, authentik_pk, username, name, email) {
    Ok(_) => ()
    Err(e) => return Err(e.to_json_string())
  }

  match password {
    Some(pw) =>
      match validate_password(pw) {
        Err(e) => return Err(e.to_json_string())
        Ok(_) =>
          match authentik_set_password(self.config.value, authentik_pk, pw) {
            Ok(_) => ()
            Err(e) => return Err(e.to_json_string())
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
      let _ = authentik_remove_from_group(self.config.value, remove_pk, authentik_pk)
    }
  }

  match authentik_add_to_group(self.config.value, target_group_pk, authentik_pk) {
    Ok(_) => ()
    Err(e) => return Err(e.to_json_string())
  }

  match surreal_save_profile(self.config.value, target_user_id, role, class_level) {
    Ok(_) => ()
    Err(e) => return Err(e.to_json_string())
  }

  if role == "student" {
    match class_level {
      Some(_) => {
        let ak = self.config.value.auth_key.get() catch { _ => "error" }
        let _ = StudentAgentClient::scoped(target_user_id, fn(
          client,
        ) raise @common.AgentError {
          client.invalidate_cache(ak, "profile")
        }) catch {
          _ => "error"
        }
      }
      None => ()
    }
  }
  if role == "teacher" {
    let ak = self.config.value.auth_key.get() catch { _ => "error" }
    let _ = TeacherAgentClient::scoped(target_user_id, fn(
      client,
    ) raise @common.AgentError {
      client.invalidate_cache(ak, "class_groups")
    }) catch {
      _ => "error"
    }
  }

  Ok("ok")
}

///|
/// Deletes a user. Soft-deletes from SurrealDB first,
/// then deletes from Authentik. If Authentik deletion fails,
/// the soft-delete is undone.
#derive.endpoint(post="/delete-user")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
#derive.endpoint_body("body_json")
pub fn AdminAgent::delete_user_in_authentik(
  self : Self,
  incoming_key : String,
  body_json : String,
) -> Result[String, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  let val = @json.parse(body_json) catch {
    _ =>
      return Err(
        AppError::{ code: ValidationError, message: "Invalid JSON body", detail: None }
        .to_json_string(),
      )
  }
  let obj = match val {
    Object(o) => o
    _ =>
      return Err(
        AppError::{ code: ValidationError, message: "Body must be an object", detail: None }
        .to_json_string(),
      )
  }
  let authentik_pk = match obj.get("authentik_pk") {
    Some(Number(n, ..)) => n.to_int()
    _ =>
      return Err(
        AppError::{
          code: ValidationError,
          message: "authentik_pk is required",
          detail: None,
        }.to_json_string(),
      )
  }
  let target_user_id = match obj.get("target_user_id") {
    Some(String(s)) => s
    _ =>
      return Err(
        AppError::{
          code: ValidationError,
          message: "target_user_id is required",
          detail: None,
        }.to_json_string(),
      )
  }

  // Step 1: Soft-delete from SurrealDB
  match surreal_soft_delete_user(self.config.value, target_user_id) {
    Ok(_) => ()
    Err(e) => return Err(e.to_json_string())
  }

  // Step 2: Delete from Authentik
  match authentik_delete_user(self.config.value, authentik_pk) {
    Ok(_) => Ok("ok")
    Err(e) => {
      // COMPENSATION: undo the soft-delete
      let _ = surreal_undo_soft_delete(self.config.value, target_user_id)
      Err(e.to_json_string())
    }
  }
}

///|
/// Activates or deactivates a user in Authentik.
#derive.endpoint(post="/set-user-active")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
#derive.endpoint_body("body_json")
pub fn AdminAgent::set_user_active_status(
  self : Self,
  incoming_key : String,
  body_json : String,
) -> Result[String, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  let val = @json.parse(body_json) catch {
    _ =>
      return Err(
        AppError::{ code: ValidationError, message: "Invalid JSON body", detail: None }
        .to_json_string(),
      )
  }
  let obj = match val {
    Object(o) => o
    _ =>
      return Err(
        AppError::{ code: ValidationError, message: "Body must be an object", detail: None }
        .to_json_string(),
      )
  }
  let authentik_pk = match obj.get("authentik_pk") {
    Some(Number(n, ..)) => n.to_int()
    _ =>
      return Err(
        AppError::{
          code: ValidationError,
          message: "authentik_pk is required",
          detail: None,
        }.to_json_string(),
      )
  }
  let is_active = match obj.get("is_active") {
    Some(True) => true
    Some(False) => false
    _ =>
      return Err(
        AppError::{
          code: ValidationError,
          message: "is_active is required",
          detail: None,
        }.to_json_string(),
      )
  }
  match authentik_set_active(self.config.value, authentik_pk, is_active) {
    Ok(_) => Ok("ok")
    Err(e) => Err(e.to_json_string())
  }
}
