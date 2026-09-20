//|

///|
#derive.agent
#derive.mount("/core-api")
struct CoreApi {
  config : @config.Config[SharedConfig]
  cache : CacheSystem
}

///|
fn CoreApi::new(
  _worker_id : String,
  config : @config.Config[SharedConfig],
) -> CoreApi {
  { config, cache: CacheSystem::new() }
}

///|
#derive.endpoint(get="/ping")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn CoreApi::ping(self : Self, incoming_key : String) -> String {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return e.to_json_string()
    Ok(_) => ()
  }
  "core-api online"
}

///|
#derive.endpoint(get="/student/subjects")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
#derive.endpoint_header("X-Internal-User-Id", "student_id")
pub fn CoreApi::student_get_subjects(
  self : Self,
  incoming_key : String,
  student_id : String,
) -> Result[Array[SubjectInfo], String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  let now = @wallClock.now().seconds
  match
    student_fetch_subjects(self.cache, self.config.value, student_id, now) {
    Ok(arr) => Ok(arr)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/student/terms")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
#derive.endpoint_header("X-Internal-User-Id", "student_id")
pub fn CoreApi::student_get_terms(
  self : Self,
  incoming_key : String,
  student_id : String,
) -> Result[Array[TermInfo], String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  let now = @wallClock.now().seconds
  match student_fetch_terms(self.cache, self.config.value, student_id, now) {
    Ok(arr) => Ok(arr)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/student/lessons?subject_id={subject_id}&term_id={term_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
#derive.endpoint_header("X-Internal-User-Id", "student_id")
pub fn CoreApi::student_get_lessons(
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
  let now = @wallClock.now().seconds
  match
    student_fetch_lessons(
      self.cache,
      self.config.value,
      student_id,
      subject_id,
      term_id,
      now,
    ) {
    Ok(arr) => Ok(arr)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/student/lesson?lesson_id={lesson_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
#derive.endpoint_header("X-Internal-User-Id", "student_id")
pub fn CoreApi::student_get_lesson(
  self : Self,
  incoming_key : String,
  student_id : String,
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
      student_id,
      lesson_id,
      now,
    ) {
    Ok(lc) => Ok(lc)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/student/assessments?lesson_id={lesson_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
#derive.endpoint_header("X-Internal-User-Id", "student_id")
pub fn CoreApi::student_get_lesson_assessments(
  self : Self,
  incoming_key : String,
  student_id : String,
  lesson_id : String,
) -> Result[Array[LessonAssessmentInfo], String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match student_fetch_lesson_assessments(self.config.value, student_id, lesson_id) {
    Ok(r) => Ok(r)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/student/general-assessments?session_term_id={session_term_id}&subject_id={subject_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
#derive.endpoint_header("X-Internal-User-Id", "student_id")
pub fn CoreApi::student_get_general_assessments(
  self : Self,
  incoming_key : String,
  student_id : String,
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
      student_id,
      session_term_id,
      subject_id,
    ) {
    Ok(r) => Ok(r)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/student/my-grades?assessment_type={assessment_type}&assessment_id={assessment_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
#derive.endpoint_header("X-Internal-User-Id", "student_id")
pub fn CoreApi::student_get_my_grades(
  self : Self,
  incoming_key : String,
  student_id : String,
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
      student_id,
      assessment_type,
      assessment_id,
    ) {
    Ok(r) => Ok(r)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/student/active-session-term")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn CoreApi::student_get_active_session_term(
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

///|
#derive.endpoint(get="/teacher/classes")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
#derive.endpoint_header("X-Internal-User-Id", "teacher_id")
pub fn CoreApi::teacher_get_my_classes(
  self : Self,
  incoming_key : String,
  teacher_id : String,
) -> Result[Array[TeacherClassGroup], String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  let now = @wallClock.now().seconds
  match teacher_fetch_classes(self.cache, self.config.value, teacher_id, now) {
    Ok(arr) => Ok(arr)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/teacher/terms")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn CoreApi::teacher_get_terms(
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
#derive.endpoint(get="/teacher/lessons?class_level_id={class_level_id}&subject_id={subject_id}&term_id={term_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn CoreApi::teacher_get_lessons(
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
#derive.endpoint(get="/teacher/lesson-assessments?lesson_id={lesson_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn CoreApi::teacher_get_lesson_assessments(
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
#derive.endpoint(get="/teacher/general-assessments?session_term_id={session_term_id}&subject_id={subject_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn CoreApi::teacher_get_general_assessments(
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
#derive.endpoint(get="/teacher/submissions?assessment_type={assessment_type}&assessment_id={assessment_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn CoreApi::teacher_get_submissions(
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
#derive.endpoint(get="/teacher/assessment-percentage-summary?session_term_id={session_term_id}&subject_id={subject_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn CoreApi::teacher_get_percentage_summary(
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
