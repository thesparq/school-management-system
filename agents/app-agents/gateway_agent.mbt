//|

///|
/// Stateless gatekeeper - ephemeral, fresh instance per HTTP request.
/// Checks the incoming X-Golem-Auth-Key header against the configured
/// secret before forwarding requests to internal agents.
/// Also checks user initialization via Admin Agent RPC.
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
/// Requires correct X-Golem-Auth-Key header and an initialized user.
/// Returns admin online on success, NOT_INITIALIZED if user is not initialized,
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

  // 2. Check initialization via Admin Agent RPC
  let initialized = AdminAgentClient::scoped(fn(
    admin,
  ) raise @common.AgentError {
    admin.is_user_initialized(user_id)
  }) catch {
    _ => return "admin unreachable"
  }

  if !initialized {
    return "NOT_INITIALIZED"
  }

  // 3. Forward to Admin Agent ping
  AdminAgentClient::scoped(fn(admin) raise @common.AgentError { admin.ping() }) catch {
    _ => "admin unreachable"
  }
}

///|
/// Admin ping — skips the per-user initialization check.
/// The Admin Agent singleton is always ready; admin users don't need init.
#derive.endpoint(get="/admin/ping?user_id={admin_user_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::admin_ping(
  self : Self,
  incoming_key : String,
  admin_user_id : String,
) -> String {
  match self.check_auth(incoming_key) {
    Some(msg) => return msg
    None => ()
  }
  AdminAgentClient::scoped(fn(admin) raise @common.AgentError { admin.ping() }) catch {
    _ => "admin unreachable"
  }
}

///|
/// Checks whether a user is initialized.
/// Returns OK if initialized, NOT_INITIALIZED if not.
#derive.endpoint(get="/check-initialization?user_id={user_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::check_initialization(
  self : Self,
  incoming_key : String,
  user_id : String,
) -> String {
  match self.check_auth(incoming_key) {
    Some(msg) => return msg
    None => ()
  }
  let initialized = AdminAgentClient::scoped(fn(
    admin,
  ) raise @common.AgentError {
    admin.is_user_initialized(user_id)
  }) catch {
    _ => return "admin unreachable"
  }
  if !initialized {
    return "NOT_INITIALIZED"
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
/// Admin-only: initializes a target user.
/// Accepts optional class_level for student initializations.
/// Requires valid X-Golem-Auth-Key header.
#derive.endpoint(get="/admin/initialize?user_id={admin_user_id}&target_user_id={target_user_id}&role={role}&class_level={class_level}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::initialize_admin(
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
  let init_result = AdminAgentClient::scoped(fn(
    admin,
  ) raise @common.AgentError {
    admin.initialize_user(target_user_id, role, class_level)
  }) catch {
    _ => return "admin unreachable"
  }
  match init_result {
    Ok(_) => "OK"
    Err(msg) => msg
  }
}

///|
/// Returns the authenticated student's subjects as a typed array.
/// Requires initialization check.
#derive.endpoint(get="/student/subjects?user_id={user_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::student_subjects(
  self : Self,
  incoming_key : String,
  user_id : String,
) -> Result[Array[SubjectInfo], String] {
  match self.check_auth(incoming_key) {
    Some(msg) => return Err(msg)
    None => ()
  }
  let initialized = AdminAgentClient::scoped(fn(
    admin,
  ) raise @common.AgentError {
    admin.is_user_initialized(user_id)
  }) catch {
    _ => return Err("admin unreachable")
  }
  if !initialized {
    return Err("NOT_INITIALIZED")
  }

  let result = StudentAgentClient::scoped(user_id, fn(
    student,
  ) raise @common.AgentError {
    student.get_subjects()
  }) catch {
    _ => return Err("student agent unreachable")
  }
  Ok(result)
}

///|
/// Returns terms for the authenticated student's class level.
/// Requires initialization check.
#derive.endpoint(get="/student/terms?user_id={user_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::student_terms(
  self : Self,
  incoming_key : String,
  user_id : String,
) -> Result[Array[TermInfo], String] {
  match self.check_auth(incoming_key) {
    Some(msg) => return Err(msg)
    None => ()
  }
  let initialized = AdminAgentClient::scoped(fn(
    admin,
  ) raise @common.AgentError {
    admin.is_user_initialized(user_id)
  }) catch {
    _ => return Err("admin unreachable")
  }
  if !initialized {
    return Err("NOT_INITIALIZED")
  }

  let result = StudentAgentClient::scoped(user_id, fn(
    student,
  ) raise @common.AgentError {
    student.get_terms()
  }) catch {
    _ => return Err("student agent unreachable")
  }
  Ok(result)
}

///|
/// Returns lessons for a given subject + term in the student's class level.
/// Requires initialization check.
#derive.endpoint(get="/student/lessons?user_id={user_id}&subject_id={subject_id}&term_id={term_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::student_lessons(
  self : Self,
  incoming_key : String,
  user_id : String,
  subject_id : String,
  term_id : String,
) -> Result[Array[LessonInfo], String] {
  match self.check_auth(incoming_key) {
    Some(msg) => return Err(msg)
    None => ()
  }
  let initialized = AdminAgentClient::scoped(fn(
    admin,
  ) raise @common.AgentError {
    admin.is_user_initialized(user_id)
  }) catch {
    _ => return Err("admin unreachable")
  }
  if !initialized {
    return Err("NOT_INITIALIZED")
  }

  let result = StudentAgentClient::scoped(user_id, fn(
    student,
  ) raise @common.AgentError {
    student.get_lessons(subject_id, term_id)
  }) catch {
    _ => return Err("student agent unreachable")
  }
  Ok(result)
}

///|
/// Returns student-visible lesson content for a given lesson_id.
/// Requires initialization check.
#derive.endpoint(get="/student/lesson?user_id={user_id}&lesson_id={lesson_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::student_lesson(
  self : Self,
  incoming_key : String,
  user_id : String,
  lesson_id : String,
) -> Result[LessonContent?, String] {
  match self.check_auth(incoming_key) {
    Some(msg) => return Err(msg)
    None => ()
  }
  let initialized = AdminAgentClient::scoped(fn(
    admin,
  ) raise @common.AgentError {
    admin.is_user_initialized(user_id)
  }) catch {
    _ => return Err("admin unreachable")
  }
  if !initialized {
    return Err("NOT_INITIALIZED")
  }

  let result = StudentAgentClient::scoped(user_id, fn(
    student,
  ) raise @common.AgentError {
    student.get_lesson(lesson_id)
  }) catch {
    _ => return Err("student agent unreachable")
  }
  Ok(result)
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
/// Admin-only: returns all initialized users as a JSON array of [user_id, role]
/// pairs. Requires valid X-Golem-Auth-Key header.
#derive.endpoint(get="/admin/initializations?user_id={admin_user_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::list_initializations(
  self : Self,
  incoming_key : String,
  admin_user_id : String,
) -> String {
  match self.check_auth(incoming_key) {
    Some(msg) => return msg
    None => ()
  }
  let inits = AdminAgentClient::scoped(fn(admin) raise @common.AgentError {
    admin.get_all_initialized()
  }) catch {
    _ => return "admin unreachable"
  }
  let items : Array[String] = []
  for item in inits {
    let (uid, role) = item
    items.push(
      "[\"" +
      uid.replace(old="\"", new="\\\"") +
      "\",\"" +
      role.replace(old="\"", new="\\\"") +
      "\"]",
    )
  }
  "[" + items.join(",") + "]"
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
