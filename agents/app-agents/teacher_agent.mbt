//|
#derive.agent
#derive.mount("/teacher/{teacher_id}")
struct TeacherAgent { teacher_id : String; config : @config.Config[SharedConfig]; cache : CacheSystem }
fn TeacherAgent::new(teacher_id : String, config : @config.Config[SharedConfig]) -> TeacherAgent { { teacher_id, config, cache: CacheSystem::new() } }

///|
#derive.endpoint(get="/ping")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn TeacherAgent::ping(self : Self, incoming_key : String) -> String {
  match require_auth(self.config.value, incoming_key) { Err(e) => return e.to_json_string(); Ok(_) => () }
  "teacher online"
}
#derive.endpoint(get="/classes")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn TeacherAgent::get_my_classes(self : Self, incoming_key : String) -> Result[Array[TeacherClassGroup], String] {
  match require_auth(self.config.value, incoming_key) { Err(e) => return Err(e.to_json_string()); Ok(_) => () }
  let now = @wallClock.now().seconds
  match teacher_fetch_classes(self.cache, self.config.value, self.teacher_id, now) { Ok(arr) => Ok(arr); Err(e) => Err(e.to_json_string()) }
}
#derive.endpoint(get="/terms")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn TeacherAgent::get_terms(self : Self, incoming_key : String) -> Result[Array[TermInfo], String] {
  match require_auth(self.config.value, incoming_key) { Err(e) => return Err(e.to_json_string()); Ok(_) => () }
  let now = @wallClock.now().seconds
  match teacher_fetch_terms(self.cache, self.config.value, now) { Ok(arr) => Ok(arr); Err(e) => Err(e.to_json_string()) }
}
#derive.endpoint(get="/lessons?class_level_id={class_level_id}&subject_id={subject_id}&term_id={term_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn TeacherAgent::get_lessons(self : Self, incoming_key : String, class_level_id : String, subject_id : String, term_id : String) -> Result[Array[LessonInfo], String] {
  match require_auth(self.config.value, incoming_key) { Err(e) => return Err(e.to_json_string()); Ok(_) => () }
  let now = @wallClock.now().seconds
  match teacher_fetch_lessons(self.cache, self.config.value, class_level_id, subject_id, term_id, now) { Ok(arr) => Ok(arr); Err(e) => Err(e.to_json_string()) }
}
#derive.endpoint(post="/invalidate-cache?key={key}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn TeacherAgent::invalidate_cache(self : Self, incoming_key : String, key : String) -> String {
  match require_auth(self.config.value, incoming_key) { Err(e) => return e.to_json_string(); Ok(_) => () }
  if key == "all" { self.cache.invalidate_all() } else { self.cache.invalidate(key) }
  "OK"
}
#derive.endpoint(post="/toggle-lesson-active?lesson_id={lesson_id}&active={active}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn TeacherAgent::toggle_lesson_active(self : Self, incoming_key : String, lesson_id : String, active : Bool) -> Result[String, String] {
  match require_auth(self.config.value, incoming_key) { Err(e) => return Err(e.to_json_string()); Ok(_) => () }
  match teacher_toggle_lesson(self.cache, self.config.value, lesson_id, active) { Ok(_) => Ok("ok"); Err(e) => Err(e.to_json_string()) }
}
