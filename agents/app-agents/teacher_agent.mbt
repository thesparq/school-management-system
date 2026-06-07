//|

///|
#derive.agent
#derive.mount("/teacher/{teacher_id}")
struct TeacherAgent {
  teacher_id : String
  config : @config.Config[SharedConfig]
  cache : CacheSystem
}

///|
fn TeacherAgent::new(
  teacher_id : String,
  config : @config.Config[SharedConfig],
) -> TeacherAgent {
  { teacher_id, config, cache: CacheSystem::new() }
}

///|
#derive.endpoint(get="/ping")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn TeacherAgent::ping(self : Self, incoming_key : String) -> String {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return e.to_json_string()
    Ok(_) => ()
  }
  "teacher online"
}

///|
#derive.endpoint(get="/classes")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn TeacherAgent::get_my_classes(
  self : Self,
  incoming_key : String,
) -> Result[Array[TeacherClassGroup], String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  let now = @wallClock.now().seconds
  match
    teacher_fetch_classes(self.cache, self.config.value, self.teacher_id, now) {
    Ok(arr) => Ok(arr)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/terms")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn TeacherAgent::get_terms(
  self : Self,
  incoming_key : String,
) -> Result[Array[TermInfo], String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  let now = @wallClock.now().seconds
  match teacher_fetch_terms(self.cache, self.config.value, now) {
    Ok(arr) => Ok(arr)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/lessons?class_level_id={class_level_id}&subject_id={subject_id}&term_id={term_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn TeacherAgent::get_lessons(
  self : Self,
  incoming_key : String,
  class_level_id : String,
  subject_id : String,
  term_id : String,
) -> Result[Array[LessonInfo], String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  let now = @wallClock.now().seconds
  match
    teacher_fetch_lessons(
      self.cache,
      self.config.value,
      class_level_id,
      subject_id,
      term_id,
      now,
    ) {
    Ok(arr) => Ok(arr)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(post="/invalidate-cache?key={key}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn TeacherAgent::invalidate_cache(
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
#derive.endpoint(post="/toggle-lesson-active?lesson_id={lesson_id}&active={active}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn TeacherAgent::toggle_lesson_active(
  self : Self,
  incoming_key : String,
  lesson_id : String,
  active : Bool,
) -> Result[String, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match
    teacher_toggle_lesson(self.cache, self.config.value, lesson_id, active) {
    Ok(_) => Ok("ok")
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(post="/create-lesson-assessment")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn TeacherAgent::create_lesson_assessment(
  self : Self,
  incoming_key : String,
  body_json : String,
) -> Result[LessonAssessmentInfo, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match teacher_create_lesson_assessment(self.config.value, body_json) {
    Ok(r) => Ok(r)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(post="/create-general-assessment")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn TeacherAgent::create_general_assessment(
  self : Self,
  incoming_key : String,
  body_json : String,
) -> Result[GeneralAssessmentInfo, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match teacher_create_general_assessment(self.config.value, body_json) {
    Ok(r) => Ok(r)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/lesson-assessments?lesson_id={lesson_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn TeacherAgent::get_lesson_assessments(
  self : Self,
  incoming_key : String,
  lesson_id : String,
) -> Result[Array[LessonAssessmentInfo], String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match teacher_fetch_lesson_assessments(self.config.value, lesson_id) {
    Ok(r) => Ok(r)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/general-assessments?session_term_id={session_term_id}&subject_id={subject_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn TeacherAgent::get_general_assessments(
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
    teacher_fetch_general_assessments(
      self.config.value,
      session_term_id,
      subject_id,
    ) {
    Ok(r) => Ok(r)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/submissions?assessment_type={assessment_type}&assessment_id={assessment_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn TeacherAgent::get_submissions(
  self : Self,
  incoming_key : String,
  assessment_type : String,
  assessment_id : String,
) -> Result[Array[SubmissionInfo], String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match
    teacher_fetch_submissions(self.config.value, assessment_type, assessment_id) {
    Ok(r) => Ok(r)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(post="/grade-submission")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn TeacherAgent::grade_submission(
  self : Self,
  incoming_key : String,
  body_json : String,
) -> Result[SubmissionInfo, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match teacher_grade_submission(self.config.value, body_json) {
    Ok(r) => Ok(r)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(post="/release-grades?submission_id={submission_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn TeacherAgent::release_grades(
  self : Self,
  incoming_key : String,
  submission_id : String,
) -> Result[SubmissionInfo, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match teacher_release_grades(self.config.value, submission_id) {
    Ok(r) => Ok(r)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(post="/toggle-assessment?assessment_type={assessment_type}&assessment_id={assessment_id}&active={active}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn TeacherAgent::toggle_assessment(
  self : Self,
  incoming_key : String,
  assessment_type : String,
  assessment_id : String,
  active : Bool,
) -> Result[String, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match
    teacher_toggle_assessment(
      self.config.value,
      assessment_type,
      assessment_id,
      active,
    ) {
    Ok(r) => Ok(r)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/assessment-percentage-summary?session_term_id={session_term_id}&subject_id={subject_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn TeacherAgent::get_percentage_summary(
  self : Self,
  incoming_key : String,
  session_term_id : String,
  subject_id : String,
) -> Result[PercentageSummary, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match
    teacher_get_percentage_summary(
      self.config.value,
      session_term_id,
      subject_id,
    ) {
    Ok(r) => Ok(r)
    Err(e) => Err(e.to_json_string())
  }
}
