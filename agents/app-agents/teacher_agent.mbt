//|
/// Durable per-teacher agent.
/// Owns all teacher state: assigned classes, rosters,
/// assignment definitions, submission inbox, and grading.

///|
#derive.agent
struct TeacherAgent {
  config : @config.Config[SurrealConfig]
}

///|
fn TeacherAgent::new(config : @config.Config[SurrealConfig]) -> TeacherAgent {
  { config, }
}

///|
/// Tests SurrealDB connectivity via internal query helper.
/// Called by Gateway Agent via typed RPC for end-to-end verification.
pub fn TeacherAgent::test_db(self : Self) -> String {
  match surreal_query(self.config, "SELECT 1") {
    Ok(body) => "OK: " + body
    Err(e) => "ERROR: " + e
  }
}
