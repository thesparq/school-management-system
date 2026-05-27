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
  initialized_users : Map[String, UserInitialization]
  config : @config.Config[SurrealConfig]
}

//|

///|
fn AdminAgent::new(config : @config.Config[SurrealConfig]) -> AdminAgent {
  { initialized_users: Map::new(), config }
}

//|

///|
/// Health-check method. Returns admin online.
pub fn AdminAgent::ping(self : Self) -> String {
  "admin online"
}

//|

///|
/// Initializes a user by storing their initialization record in durable state.
/// For students with a class_level, fire-and-forget initializes the
/// Student Agent (best-effort; does not fail initialization).
pub fn AdminAgent::initialize_user(
  self : Self,
  user_id : String,
  role : String,
  class_level : String?,
) -> Result[String, String] {
  if !["admin", "teacher", "student"].contains(role) {
    return Err("invalid role: \{role}")
  }
  let now = @wallClock.now()
  let record = UserInitialization::{
    user_id,
    role,
    class_level,
    initialized_at: now.seconds,
  }
  self.initialized_users.set(user_id, record)

  if role == "student" {
    match class_level {
      Some(cl) => {
        let _ = StudentAgentClient::scoped(user_id, fn(
          client,
        ) raise @common.AgentError {
          client.trigger_initialize(cl)
        }) catch {
          _ => ()
        }
      }
      None => ()
    }
  }

  Ok("ok")
}

//|

///|
/// Checks whether a user has been initialized.
/// Returns false if not in registry, true otherwise.
/// Admin users are always considered initialized — the Admin Agent
/// singleton is ready from the moment it is created.
pub fn AdminAgent::is_user_initialized(self : Self, user_id : String) -> Bool {
  self.initialized_users.contains(user_id)
}

///|
/// Returns true for all admin users. The Admin Agent singleton
/// is always running — no per-user initialization needed.
pub fn AdminAgent::is_admin_initialized(self : Self) -> Bool {
  true
}

//|

///|
/// Returns all initialized users as an array of (user_id, role) tuples.
pub fn AdminAgent::get_all_initialized(self : Self) -> Array[(String, String)] {
  self.initialized_users
  .iter()
  .map(fn(pair) { (pair.0, pair.1.role) })
  .collect()
}

//|

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
  let sql = "SELECT id, name FROM class_levels WHERE active = true ORDER BY name ASC"
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
