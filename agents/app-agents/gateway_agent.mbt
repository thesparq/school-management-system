//|

///|
/// Stateless gatekeeper - ephemeral, fresh instance per HTTP request.
/// Checks the incoming X-Golem-Auth-Key header against the configured
/// secret before forwarding requests to internal agents.
#derive.agent("ephemeral")
#derive.mount("/gateway")
struct GatewayAgent {
  config : @config.Config[GatewayConfig]
}

//|

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
  let expected = try self.config.value.auth_key.get() catch { _ => return Some("auth error") }
  if incoming_key != expected { return Some("unauthorized") }
  None
}

///|
/// Proxies a ping to the Admin Agent via typed RPC.
/// Requires the correct X-Golem-Auth-Key header.
/// Returns admin online on success, admin unreachable on RPC failure.
#derive.endpoint(get="/ping")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn GatewayAgent::ping(self : Self, incoming_key : String) -> String {
  match self.check_auth(incoming_key) {
    Some(msg) => return msg
    None => ()
  }

  try {
    AdminAgentClient::scoped(fn(admin) raise @common.AgentError {
      admin.ping()
    })
  } catch {
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
