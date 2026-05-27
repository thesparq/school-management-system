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
}

//|

///|
fn AdminAgent::new() -> AdminAgent {
  AdminAgent::{ activated_users: Map::new() }
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
/// Returns Ok on success, Err for invalid role.
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
