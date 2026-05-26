//|
///|
/// Stateless gatekeeper - ephemeral, fresh instance per HTTP request.
/// Checks activation status with AdminAgent via RPC before forwarding.
#derive.agent("ephemeral")
#derive.mount("/gateway")
struct GatewayAgent {}

//|

///|
fn GatewayAgent::new() -> GatewayAgent {
  GatewayAgent::{  }
}

//|

///|
/// Proxies a ping to the Admin Agent via typed RPC.
/// Returns admin online on success, admin unreachable on RPC failure.
#derive.endpoint(get="/ping")
pub fn GatewayAgent::ping(self : Self) -> String {
  try {
    AdminAgentClient::scoped(fn(admin) raise @common.AgentError {
      admin.ping()
    })
  } catch {
    _ => "admin unreachable"
  }
}
