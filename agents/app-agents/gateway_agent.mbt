//|

///|
/// Stateless gatekeeper - ephemeral, fresh instance per HTTP request.
/// Checks the incoming X-Golem-Auth-Key header against the configured
/// secret before forwarding requests to internal agents.
/// Also checks user activation via Admin Agent RPC.
#derive.agent("ephemeral")
#derive.mount("/gateway")
struct GatewayAgent {
  config : @config.Config[GatewayConfig]
}

//|

///|
#derive.config
pub(all) struct GatewayConfig {
  auth_key : @config.Secret[String]
}

//|

///|
fn GatewayAgent::new(config : @config.Config[GatewayConfig]) -> GatewayAgent {
  { config, }
}

//|

///|
/// Shared auth check for all Gateway Agent endpoints.
/// Returns None if the key matches; Some(error_message) on failure.
fn GatewayAgent::check_auth(self : Self, incoming_key : String) -> String? {
  let expected = self.config.value.auth_key.get() catch {
    _ => return Some("auth error")
  }
  if incoming_key != expected {
    return Some("unauthorized")
  }
  None
}

///|
/// Proxies a ping to the Admin Agent via typed RPC.
/// Requires correct X-Golem-Auth-Key header and an active user.
/// Returns admin online on success, NOT_ACTIVATED if user is inactive,
/// admin unreachable on RPC failure.
#derive.endpoint(get="/ping?user_id={user_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::ping(
  self : Self,
  incoming_key : String,
  user_id : String,
) -> String {
  // 1. Check auth
  match self.check_auth(incoming_key) {
    Some(msg) => return msg
    None => ()
  }

  // 2. Check activation via Admin Agent RPC
  let status = AdminAgentClient::scoped(fn(admin) raise @common.AgentError {
    admin.is_user_active(user_id)
  }) catch {
    _ => return "admin unreachable"
  }

  if status != Active {
    return "NOT_ACTIVATED"
  }

  // 3. Forward to Admin Agent ping
  AdminAgentClient::scoped(fn(admin) raise @common.AgentError { admin.ping() }) catch {
    _ => "admin unreachable"
  }
}

//|

///|
/// Checks whether a user is activated.
/// Returns OK if active, NOT_ACTIVATED if not.
#derive.endpoint(get="/check-activation?user_id={user_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::check_activation(
  self : Self,
  incoming_key : String,
  user_id : String,
) -> String {
  match self.check_auth(incoming_key) {
    Some(msg) => return msg
    None => ()
  }
  let status = AdminAgentClient::scoped(fn(admin) raise @common.AgentError {
    admin.is_user_active(user_id)
  }) catch {
    _ => return "admin unreachable"
  }
  if status != Active {
    return "NOT_ACTIVATED"
  }
  "OK"
}

///|
/// Tests SurrealDB end-to-end via Student Agent RPC.
/// The Gateway does NOT hold DB credentials - only Student/Teacher agents do.
#derive.endpoint(get="/db-test?user_id={user_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::db_test(
  self : Self,
  incoming_key : String,
  user_id : String,
) -> String {
  match self.check_auth(incoming_key) {
    Some(msg) => return msg
    None => ()
  }
  StudentAgentClient::scoped(user_id, fn(student) raise @common.AgentError {
    student.test_db()
  }) catch {
    _ => "ERROR: student agent unreachable"
  }
}

///|
/// Admin-only: activates a target user.
/// Accepts optional class_level for student activations.
/// Requires valid X-Golem-Auth-Key header.
#derive.endpoint(get="/admin/activate?user_id={admin_user_id}&target_user_id={target_user_id}&role={role}&class_level={class_level}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::activate_admin(
  self : Self,
  incoming_key : String,
  admin_user_id : String,
  target_user_id : String,
  role : String,
  class_level : String?,
) -> String {
  match self.check_auth(incoming_key) {
    Some(msg) => return msg
    None => ()
  }
  let act_result = AdminAgentClient::scoped(fn(admin) raise @common.AgentError {
    admin.activate_user(target_user_id, role, class_level)
  }) catch {
    _ => return "admin unreachable"
  }
  match act_result {
    Ok(_) => "OK"
    Err(msg) => msg
  }
}

///|
/// Admin-only: deactivates a target user.
/// Requires valid X-Golem-Auth-Key header.
#derive.endpoint(get="/admin/deactivate?user_id={admin_user_id}&target_user_id={target_user_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::deactivate_admin(
  self : Self,
  incoming_key : String,
  admin_user_id : String,
  target_user_id : String,
) -> String {
  match self.check_auth(incoming_key) {
    Some(msg) => return msg
    None => ()
  }
  let deact_result = AdminAgentClient::scoped(fn(
    admin,
  ) raise @common.AgentError {
    admin.deactivate_user(target_user_id)
  }) catch {
    _ => return "admin unreachable"
  }
  match deact_result {
    Ok(_) => "OK"
    Err(msg) => msg
  }
}

///|
/// Returns the authenticated student's subjects as a JSON array string.
/// Requires activation check.
#derive.endpoint(get="/student/subjects?user_id={user_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::student_subjects(
  self : Self,
  incoming_key : String,
  user_id : String,
) -> String {
  match self.check_auth(incoming_key) {
    Some(msg) => return msg
    None => ()
  }
  let status = AdminAgentClient::scoped(fn(admin) raise @common.AgentError {
    admin.is_user_active(user_id)
  }) catch {
    _ => return "admin unreachable"
  }
  if status != Active {
    return "NOT_ACTIVATED"
  }

  StudentAgentClient::scoped(user_id, fn(student) raise @common.AgentError {
    student.get_subjects()
  }) catch {
    _ => "ERROR: student agent unreachable"
  }
}

///|
/// Returns all active class levels as a JSON array string.
/// Requires valid X-Golem-Auth-Key header.
#derive.endpoint(get="/admin/class-levels?user_id={admin_user_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::list_class_levels(
  self : Self,
  incoming_key : String,
  admin_user_id : String,
) -> String {
  match self.check_auth(incoming_key) {
    Some(msg) => return msg
    None => ()
  }
  AdminAgentClient::scoped(fn(admin) raise @common.AgentError {
    admin.get_class_levels()
  }) catch {
    _ => "admin unreachable"
  }
}

///|
fn activation_status_to_string(status : ActivationStatus) -> String {
  match status {
    Active => "active"
    Deactivated => "deactivated"
    Suspended => "suspended"
    NotFound => "not_found"
  }
}

///|
/// Admin-only: returns all activation records as newline-separated
/// user_id|status lines. Requires valid X-Golem-Auth-Key header.
#derive.endpoint(get="/admin/activations?user_id={admin_user_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::list_activations(
  self : Self,
  incoming_key : String,
  admin_user_id : String,
) -> String {
  match self.check_auth(incoming_key) {
    Some(msg) => return msg
    None => ()
  }
  let activations = AdminAgentClient::scoped(fn(
    admin,
  ) raise @common.AgentError {
    admin.get_all_activations()
  }) catch {
    _ => return "admin unreachable"
  }
  let mut lines = ""
  for item in activations {
    let (user_id, status) = item
    lines = lines + user_id + "|" + activation_status_to_string(status) + "\n"
  }
  lines
}

///|
/// Extension method needed by generated golem_agents.mbt.
fn @common.AgentError::to_string(self : @common.AgentError) -> String {
  match self {
    InvalidInput(msg) => msg
    InvalidMethod(msg) => msg
    InvalidType(msg) => msg
    InvalidAgentId(msg) => msg
    CustomError(_) => "CustomError"
  }
}

//|

///|
fn main {

}
