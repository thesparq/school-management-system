//|

///|
#derive.golem_schema
enum ActivationStatus {
  NotFound
  Active
  Suspended
  Deactivated
} derive(Eq)

//|

///|
#derive.golem_schema
struct UserActivation {
  user_id : String
  role : String
  status : ActivationStatus
  class_level : String?
  activated_at : UInt64
}

//|

///|
/// Central registry agent - durable singleton.
/// Authority for user activation, class-subject-teacher assignments,
/// and class rosters.
#derive.agent
struct AdminAgent {
  activated_users : Map[String, UserActivation]
  config : @config.Config[SurrealConfig]
}

//|

///|
fn AdminAgent::new(config : @config.Config[SurrealConfig]) -> AdminAgent {
  { activated_users: Map::new(), config }
}

//|

///|
/// Health-check method. Returns admin online.
pub fn AdminAgent::ping(self : Self) -> String {
  "admin online"
}

//|

///|
/// Activates a user by storing their activation record in durable state.
/// For students with a class_level, fire-and-forget initializes the
/// Student Agent (best-effort; does not fail activation).
pub fn AdminAgent::activate_user(
  self : Self,
  user_id : String,
  role : String,
  class_level : String?,
) -> Result[String, String] {
  if !["admin", "teacher", "student"].contains(role) {
    return Err("invalid role: \{role}")
  }
  let now = @wallClock.now()
  let record = UserActivation::{
    user_id,
    role,
    status: Active,
    class_level,
    activated_at: now.seconds,
  }
  self.activated_users.set(user_id, record)

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
/// Checks whether a user is active.
/// Returns NotFound if not in registry, otherwise the stored status.
pub fn AdminAgent::is_user_active(
  self : Self,
  user_id : String,
) -> ActivationStatus {
  match self.activated_users.get(user_id) {
    None => NotFound
    Some(record) => record.status
  }
}

///|
/// Deactivates a previously activated user.
/// Returns Err if the user is not in the registry.
pub fn AdminAgent::deactivate_user(
  self : Self,
  user_id : String,
) -> Result[String, String] {
  match self.activated_users.get(user_id) {
    None => Err("user not found: \{user_id}")
    Some(record) => {
      let updated = UserActivation::{ ..record, status: Deactivated }
      self.activated_users.set(user_id, updated)
      Ok("ok")
    }
  }
}

///|
/// Returns all activation records as an array of (user_id, status) tuples.
pub fn AdminAgent::get_all_activations(
  self : Self,
) -> Array[(String, ActivationStatus)] {
  self.activated_users
  .iter()
  .map(fn(pair) { (pair.0, pair.1.status) })
  .collect()
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
