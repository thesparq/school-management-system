//|
/// Durable per-student agent.
/// Owns all student state: class, subjects, lesson cache,
/// assignments, submissions, and grades.

///|
#derive.agent
struct StudentAgent {
  config : @config.Config[SurrealConfig]
}

///|
fn StudentAgent::new(config : @config.Config[SurrealConfig]) -> StudentAgent {
  { config, }
}

///|
/// Tests SurrealDB connectivity via internal query helper.
/// Called by Gateway Agent via typed RPC for end-to-end verification.
pub fn StudentAgent::test_db(self : Self) -> String {
  match surreal_query(self.config, "SELECT * FROM 1") {
    Ok(body) => "OK: " + body
    Err(e) => "ERROR: " + e
  }
}
