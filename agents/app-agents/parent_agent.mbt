///|
#derive.agent
#derive.mount("/parent/{parent_id}")
struct ParentAgent {
  parent_id : String
  config : @config.Config[SharedConfig]
  cache : CacheSystem
}

///|
fn ParentAgent::new(
  parent_id : String,
  config : @config.Config[SharedConfig],
) -> ParentAgent {
  { parent_id, config, cache: CacheSystem::new() }
}

///|
#derive.endpoint(get="/ping")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn ParentAgent::ping(self : Self, incoming_key : String) -> String {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return e.to_json_string()
    Ok(_) => ()
  }
  "parent online"
}

///|
#derive.endpoint(get="/my-students")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn ParentAgent::my_students(
  self : Self,
  incoming_key : String,
) -> Result[Array[ParentStudentInfo], String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  let now = @wallClock.now().seconds
  match
    parent_fetch_my_students(self.cache, self.config.value, self.parent_id, now) {
    Ok(items) => Ok(items)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/student-subjects?student_id={student_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn ParentAgent::student_subjects(
  self : Self,
  incoming_key : String,
  student_id : String,
) -> Result[Array[SubjectInfo], String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match
    parent_fetch_student_subjects(self.config.value, self.parent_id, student_id) {
    Ok(items) => Ok(items)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/student-terms?student_id={student_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn ParentAgent::student_terms(
  self : Self,
  incoming_key : String,
  student_id : String,
) -> Result[Array[TermInfo], String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match
    parent_fetch_student_terms(self.config.value, self.parent_id, student_id) {
    Ok(items) => Ok(items)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/student-lessons?student_id={student_id}&subject_id={subject_id}&term_id={term_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn ParentAgent::student_lessons(
  self : Self,
  incoming_key : String,
  student_id : String,
  subject_id : String,
  term_id : String,
) -> Result[Array[LessonInfo], String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match
    parent_fetch_student_lessons(
      self.config.value,
      self.parent_id,
      student_id,
      subject_id,
      term_id,
    ) {
    Ok(items) => Ok(items)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/student-lesson?student_id={student_id}&lesson_id={lesson_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn ParentAgent::student_lesson(
  self : Self,
  incoming_key : String,
  student_id : String,
  lesson_id : String,
) -> Result[LessonContent, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match
    parent_fetch_student_lesson(
      self.config.value,
      self.parent_id,
      student_id,
      lesson_id,
    ) {
    Ok(content) => Ok(content)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(post="/invalidate-cache?key={key}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn ParentAgent::invalidate_cache(
  self : Self,
  incoming_key : String,
  key : String,
) -> String {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return e.to_json_string()
    Ok(_) => ()
  }
  if key == "all" || key == "linked_students" {
    self.cache.invalidate_all()
  } else {
    self.cache.invalidate(key)
  }
  "OK"
}
