//|

///|
#derive.golem_schema
struct UserInitialization {
  user_id : String
  role : String
  class_level : String?
  initialized_at : UInt64
} derive(Eq)

//|

///|
/// Central registry agent - durable singleton.
/// Authority for user initialization, class-subject-teacher assignments,
/// and class rosters.
#derive.agent
struct AdminAgent {
  config : @config.Config[SurrealConfig]
}

///|
fn AdminAgent::new(config : @config.Config[SurrealConfig]) -> AdminAgent {
  { config, }
}

///|
/// Health-check method. Returns admin online.
pub fn AdminAgent::ping(self : Self) -> String {
  "admin online"
}

///|
fn escape_surreal_string(s : String) -> String {
  s.replace(old="'", new="''")
}

///|
/// Initializes a user by writing to user_profile table in SurrealDB.
/// For students with a class_level, fire-and-forget initializes the
/// Student Agent (best-effort; does not fail initialization).
/// For teachers, fire-and-forget initializes the Teacher Agent.
pub fn AdminAgent::initialize_user(
  self : Self,
  user_id : String,
  role : String,
  class_level : String?,
) -> Result[String, String] {
  if !["admin", "teacher", "student"].contains(role) {
    return Err("invalid role: \{role}")
  }
  let cl_insert = match class_level {
    Some(cl) => "'" + escape_surreal_string(cl) + "'"
    None => "NULL"
  }
  let sql = "INSERT INTO user_profile (auth_id, role, class_level, created_at) VALUES ('" +
    escape_surreal_string(user_id) +
    "', '" +
    escape_surreal_string(role) +
    "', " +
    cl_insert +
    ", time::now())"
  match surreal_query(self.config, sql) {
    Ok(_) => ()
    Err(e) =>
      if e.contains("Duplicate") ||
        e.contains("unique") ||
        e.contains("already exists") {
        // already initialized — proceed
      } else {
        return Err(e)
      }
  }
  if role == "student" {
    match class_level {
      Some(cl) => {
        let _ = StudentAgentClient::scoped(user_id, fn(
          client,
        ) raise @common.AgentError {
          client.initialize(cl)
        }) catch {
          _ => "error"
        }
      }
      None => ()
    }
  }
  if role == "teacher" {
    let _ = TeacherAgentClient::scoped(user_id, fn(
      client,
    ) raise @common.AgentError {
      client.trigger_initialize()
    }) catch {
      _ => "error"
    }
  }
  Ok("ok")
}

///|
/// Checks whether a user has been initialized.
/// Queries user_profile table — returns false on error or no match.
/// Admin users are always considered initialized — the Admin Agent
/// singleton is ready from the moment it is created.
pub fn AdminAgent::is_user_initialized(self : Self, user_id : String) -> Bool {
  let sql = "SELECT auth_id FROM user_profile WHERE " +
    "auth_id = '" +
    escape_surreal_string(user_id) +
    "' AND deleted_at IS NONE LIMIT 1"
  match surreal_query_retry(self.config, sql, None) {
    Ok(arr) => arr.length() > 0
    Err(_) => false
  }
}

///|
/// Returns true for all admin users. The Admin Agent singleton
/// is always running — no per-user initialization needed.
pub fn AdminAgent::is_admin_initialized(self : Self) -> Bool {
  true
}

///|
/// Returns all initialized users as an array of (user_id, role) tuples.
pub fn AdminAgent::get_all_initialized(self : Self) -> Array[(String, String)] {
  let sql = "SELECT auth_id, role FROM user_profile WHERE deleted_at IS NONE"
  let result_arr = match surreal_query_retry(self.config, sql, None) {
    Ok(arr) => arr
    Err(_) => return []
  }
  let items : Array[(String, String)] = []
  for item in result_arr {
    match item {
      Object(obj) => {
        let auth_id = match obj.get("auth_id") {
          Some(String(s)) => s
          _ => continue
        }
        let role = match obj.get("role") {
          Some(String(s)) => s
          _ => continue
        }
        items.push((auth_id, role))
      }
      _ => ()
    }
  }
  items
}

///|
fn escape_json_string(s : String) -> String {
  s
  .replace(old="\\", new="\\\\")
  .replace(old="\"", new="\\\"")
  .replace(old="\n", new="\\n")
  .replace(old="\r", new="\\r")
  .replace(old="\t", new="\\t")
}

///|
/// Returns all active class levels as a JSON array string.
pub fn AdminAgent::get_class_levels(self : Self) -> String {
  let sql = "SELECT id, name FROM class_levels ORDER BY name ASC"
  let raw = match surreal_query(self.config, sql) {
    Ok(body) => body
    Err(e) => return "ERROR: " + e
  }

  let val = @json.parse(raw) catch {
    _ => return "ERROR: parse class_levels response failed"
  }
  let result_arr = match val {
    Array(a) => {
      if a.length() == 0 {
        return "[]"
      }
      match a[0] {
        Object(obj) =>
          match obj.get("result") {
            Some(r) =>
              match r {
                Array(a2) => a2
                _ => return "[]"
              }
            None => return "[]"
          }
        _ => return "[]"
      }
    }
    _ => return "[]"
  }
  let items = result_arr.map(fn(item) {
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
        "{\"id\":\"" +
        escape_json_string(id) +
        "\",\"name\":\"" +
        escape_json_string(name) +
        "\"}"
      }
      _ => "{}"
    }
  })
  "[" + items.join(",") + "]"
}

///|
/// Returns all active class-subject pairs from has_subject edges.
pub fn AdminAgent::get_available_class_subjects(
  self : Self,
) -> Array[TeacherSubjectPair] {
  let sql = "SELECT in.id AS class_level_id, " +
    "in.name AS class_level_name, " +
    "out.id AS subject_id, out.name AS subject_name, " +
    "out.code AS subject_code " +
    "FROM has_subject WHERE active = true " +
    "ORDER BY in.name ASC, out.name ASC"
  let raw = match surreal_query(self.config, sql) {
    Ok(body) => body
    Err(_) => return []
  }
  let result_arr = match parse_result_array(raw) {
    Ok(arr) => arr
    Err(_) => {
      let raw2 = match surreal_query(self.config, sql) {
        Ok(b) => b
        Err(_) => return []
      }
      match parse_result_array(raw2) {
        Ok(arr) => arr
        Err(_) => return []
      }
    }
  }
  let pairs : Array[TeacherSubjectPair] = []
  for item in result_arr {
    match item {
      Object(obj) => {
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
  pairs
  .mut_view()
  .sort_by(fn(a, b) {
    if a.class_level_name != b.class_level_name {
      if a.class_level_name > b.class_level_name {
        1
      } else {
        -1
      }
    } else if a.subject_name != b.subject_name {
      if a.subject_name > b.subject_name {
        1
      } else {
        -1
      }
    } else {
      0
    }
  })
  pairs
}

///|
/// Stores a teacher's assigned class-subject pairs in the teacher_assignment
/// table (soft-deletes existing, inserts new), then triggers Teacher Agent
/// re-initialization via fire-and-forget RPC.
pub fn AdminAgent::set_teacher_subjects(
  self : Self,
  teacher_id : String,
  pairs : Array[TeacherSubjectPair],
) -> Result[String, String] {
  let sql = StringBuilder::new()
  sql.write_string(
    "UPDATE teacher_assignment SET deleted_at = time::now() WHERE teacher_id = '",
  )
  sql.write_string(escape_surreal_string(teacher_id))
  sql.write_string("' AND deleted_at IS NONE;")
  for pair in pairs {
    sql.write_string("CREATE teacher_assignment CONTENT { teacher_id: '")
    sql.write_string(escape_surreal_string(teacher_id))
    sql.write_string("', class_level_id: '")
    sql.write_string(escape_surreal_string(pair.class_level_id))
    sql.write_string("', subject_id: '")
    sql.write_string(escape_surreal_string(pair.subject_id))
    sql.write_string("', assigned_at: time::now() };")
  }
  match surreal_query_retry(self.config, sql.to_string(), None) {
    Ok(_) => {
      let _ = TeacherAgentClient::scoped(teacher_id, fn(
        client,
      ) raise @common.AgentError {
        client.trigger_initialize()
      }) catch {
        _ => "error"
      }
      Ok("ok")
    }
    Err(e) => Err(e)
  }
}

///|
/// Returns the stored assignments for a teacher, or [] if none.
/// Resolves class_level and subject names from their respective tables.
pub fn AdminAgent::get_teacher_subjects(
  self : Self,
  teacher_id : String,
) -> Array[TeacherSubjectPair] {
  let sql = "SELECT teacher_id, class_level_id, subject_id, " +
    "(SELECT VALUE name FROM class_levels WHERE id = type::thing(\"class_levels\", class_level_id))[0] AS class_level_name, " +
    "(SELECT VALUE name FROM subjects WHERE id = type::thing(\"subjects\", subject_id))[0] AS subject_name, " +
    "(SELECT VALUE code FROM subjects WHERE id = type::thing(\"subjects\", subject_id))[0] AS subject_code " +
    "FROM teacher_assignment WHERE teacher_id = '" +
    escape_surreal_string(teacher_id) +
    "' AND deleted_at IS NONE ORDER BY class_level_name ASC, subject_name ASC"
  let result_arr = match surreal_query_retry(self.config, sql, None) {
    Ok(arr) => arr
    Err(_) => return []
  }
  let pairs : Array[TeacherSubjectPair] = []
  for item in result_arr {
    match item {
      Object(obj) => {
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
  pairs
}
