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
