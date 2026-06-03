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

///|
fn main {

}
