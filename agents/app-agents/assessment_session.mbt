//|
///|
#derive.agent
#derive.mount("/assessment-session/{worker_id}")
struct AssessmentSession {
  worker_id : String
  config : @config.Config[SharedConfig]
}

///|
fn AssessmentSession::new(
  worker_id : String,
  config : @config.Config[SharedConfig],
) -> AssessmentSession {
  { worker_id, config }
}

///|
#derive.endpoint(get="/ping")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AssessmentSession::ping(self : Self, incoming_key : String) -> String {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return e.to_json_string()
    Ok(_) => ()
  }
  "assessment session online"
}

///|
#derive.endpoint(post="/submit?student_id={student_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AssessmentSession::submit(
  self : Self,
  incoming_key : String,
  student_id : String,
  body_json : String,
) -> Result[SubmissionInfo, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match
    assessment_session_submit(self.config.value, student_id, body_json) {
    Ok(r) => Ok(r)
    Err(e) => Err(e.to_json_string())
  }
}
