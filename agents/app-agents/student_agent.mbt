//|

///|
#derive.agent
#derive.mount("/student/{student_id}")
struct StudentAgent {
  student_id : String
  config : @config.Config[SharedConfig]
  cache : CacheSystem
}

///|
fn StudentAgent::new(
  student_id : String,
  config : @config.Config[SharedConfig],
) -> StudentAgent {
  { student_id, config, cache: CacheSystem::new() }
}

///|
#derive.endpoint(get="/ping")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn StudentAgent::ping(self : Self, incoming_key : String) -> String {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return e.to_json_string()
    Ok(_) => ()
  }
  "student online"
}

///|
#derive.endpoint(get="/subjects")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn StudentAgent::get_subjects(
  self : Self,
  incoming_key : String,
) -> Result[Array[SubjectInfo], String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  let now = @wallClock.now().seconds
  match
    student_fetch_subjects(self.cache, self.config.value, self.student_id, now) {
    Ok(arr) => Ok(arr)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/terms")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn StudentAgent::get_terms(
  self : Self,
  incoming_key : String,
) -> Result[Array[TermInfo], String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  let now = @wallClock.now().seconds
  match
    student_fetch_terms(self.cache, self.config.value, self.student_id, now) {
    Ok(arr) => Ok(arr)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/lessons?subject_id={subject_id}&term_id={term_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn StudentAgent::get_lessons(
  self : Self,
  incoming_key : String,
  subject_id : String,
  term_id : String,
) -> Result[Array[LessonInfo], String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  let now = @wallClock.now().seconds
  match
    student_fetch_lessons(
      self.cache,
      self.config.value,
      self.student_id,
      subject_id,
      term_id,
      now,
    ) {
    Ok(arr) => Ok(arr)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/lesson?lesson_id={lesson_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn StudentAgent::get_lesson(
  self : Self,
  incoming_key : String,
  lesson_id : String,
) -> Result[LessonContent?, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  let now = @wallClock.now().seconds
  match
    student_fetch_lesson(
      self.cache,
      self.config.value,
      self.student_id,
      lesson_id,
      now,
    ) {
    Ok(lc) => Ok(lc)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(post="/invalidate-cache?key={key}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn StudentAgent::invalidate_cache(
  self : Self,
  incoming_key : String,
  key : String,
) -> String {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return e.to_json_string()
    Ok(_) => ()
  }
  if key == "all" {
    self.cache.invalidate_all()
  } else {
    self.cache.invalidate(key)
  }
  "OK"
}

///|
#derive.endpoint(get="/assessments?lesson_id={lesson_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn StudentAgent::get_lesson_assessments(
  self : Self,
  incoming_key : String,
  lesson_id : String,
) -> Result[Array[LessonAssessmentInfo], String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match
    student_fetch_lesson_assessments(
      self.config.value,
      self.student_id,
      lesson_id,
    ) {
    Ok(r) => Ok(r)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/general-assessments?session_term_id={session_term_id}&subject_id={subject_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn StudentAgent::get_general_assessments(
  self : Self,
  incoming_key : String,
  session_term_id : String,
  subject_id : String,
) -> Result[Array[GeneralAssessmentInfo], String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match
    student_fetch_general_assessments(
      self.config.value,
      self.student_id,
      session_term_id,
      subject_id,
    ) {
    Ok(r) => Ok(r)
    Err(e) => Err(e.to_json_string())
  }
}



///|
#derive.endpoint(get="/my-grades?assessment_type={assessment_type}&assessment_id={assessment_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn StudentAgent::get_my_grades(
  self : Self,
  incoming_key : String,
  assessment_type : String,
  assessment_id : String,
) -> Result[SubmissionInfo?, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match
    student_fetch_my_grades(
      self.config.value,
      self.student_id,
      assessment_type,
      assessment_id,
    ) {
    Ok(r) => Ok(r)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/active-session-term")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn StudentAgent::get_active_session_term(
  self : Self,
  incoming_key : String,
) -> Result[String, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match student_get_active_session_term(self.config.value) {
    Ok(r) => Ok(r)
    Err(e) => Err(e.to_json_string())
  }
}
