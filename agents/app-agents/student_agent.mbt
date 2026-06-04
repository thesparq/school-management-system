//|

///|
#derive.golem_schema
struct SubjectInfo {
  id : String
  name : String
  code : String?
}

///|
#derive.golem_schema
struct StudentProfile {
  class_level : String
}

///|
#derive.golem_schema
struct TermInfo {
  id : String
  name : String
  sort_order : Int
  active : Bool
}

///|
#derive.golem_schema
struct LessonInfo {
  id : String
  topic_title : String?
  week : Int?
  active : Bool?
  subject_name : String?
  term_name : String?
}

///|
#derive.golem_schema
struct LessonContent {
  id : String
  topic_title : String?
  week : Int?
  subject_name : String?
  term_name : String?
  objectives : String?
  content_sections : String?
  key_points : String?
  mcq_questions : String?
  theoretical_questions : String?
}

///|
#derive.agent
#derive.mount("/student/{student_id}")
struct StudentAgent {
  student_id : String
  config : @config.Config[SharedConfig]
  mut caches : Map[String, CacheItem]
}

///|
fn StudentAgent::new(
  student_id : String,
  config : @config.Config[SharedConfig],
) -> StudentAgent {
  { student_id, config, caches: Map::new() }
}

///|
fn parse_profile(json_str : String) -> StudentProfile? {
  let val = @json.parse(json_str) catch { _ => return None }
  match val {
    Object(obj) => {
      let class_level = match obj.get("class_level") {
        Some(String(s)) => s
        _ => ""
      }
      Some(StudentProfile::{ class_level, })
    }
    _ => None
  }
}

///|
/// Reactive gatekeeper. Checks profile cache first; on miss or expired TTL,
/// queries the DB. No negative caching — if no row exists, returns None
/// and does NOT cache the failure.
fn StudentAgent::get_class_level(self : Self) -> String? {
  let now = @wallClock.now().seconds
  match self.caches.get("profile") {
    Some(item) if now - item.fetched_at < CACHE_TTL =>
      match item.data {
        Profile(profile) if profile.class_level != "" =>
          return Some(profile.class_level)
        _ => ()
      }
    _ => ()
  }
  let sql = "SELECT * FROM user_profile WHERE auth_id = '" +
    escape_surreal_string(self.student_id) +
    "' AND deleted_at IS NONE LIMIT 1"
  match surreal_query(self.config.value, sql) {
    Ok(arr) =>
      if arr.length() > 0 {
        let row = arr[0].stringify()
        match parse_profile(row) {
          Some(profile) => {
            if profile.class_level != "" {
              self.caches.set("profile", CacheItem::{
                data: Profile(profile),
                fetched_at: now,
              })
            }
            Some(profile.class_level)
          }
          None => None
        }
      } else {
        None
      }
    Err(_) => None
  }
}

///|
fn not_initialized_err() -> String {
  AppError::{
    code: NotInitialized,
    message: "Account not initialized. Please contact your school administrator.",
    detail: None,
  }.to_json_string()
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
  let cached = self.caches.get("subjects")
  match cached {
    Some(item) if now - item.fetched_at < CACHE_TTL =>
      match item.data {
        Subjects(arr) if arr.length() > 0 => return Ok(arr)
        _ => ()
      }
    _ => ()
  }
  let cl = match self.get_class_level() {
    Some(cl) => cl
    None => return Err(not_initialized_err())
  }
  let sql = "SELECT out.id AS id, out.name AS name, out.code AS code " +
    "FROM has_subject " +
    "WHERE in = $class_level AND active = true " +
    "ORDER BY name ASC"
  let result_arr = match
    surreal_query(self.config.value, sql, bindings={ "class_level": cl }) {
    Ok(arr) => arr
    Err(_) => {
      match cached {
        Some(item) =>
          match item.data {
            Subjects(arr) if arr.length() > 0 => return Ok(arr)
            _ => ()
          }
        _ => ()
      }
      return Err(
        AppError::{
          code: SurrealDBError,
          message: "Failed to query subjects from database",
          detail: None,
        }.to_json_string(),
      )
    }
  }
  let subjects : Array[SubjectInfo] = []
  for item in result_arr {
    match item {
      Object(obj) => {
        let id = match obj.get("id") {
          Some(String(s)) => s
          _ => continue
        }
        let name = match obj.get("name") {
          Some(String(s)) => s
          _ => continue
        }
        let code = match obj.get("code") {
          Some(String(s)) => Some(s)
          _ => None
        }
        subjects.push(SubjectInfo::{ id, name, code })
      }
      _ => ()
    }
  }
  if subjects.length() == 0 {
    return Err(
      AppError::{
        code: NotFound,
        message: "No subjects are assigned to your class yet.",
        detail: None,
      }.to_json_string(),
    )
  }
  self.caches.set("subjects", CacheItem::{
    data: Subjects(subjects),
    fetched_at: now,
  })
  Ok(subjects)
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
  let cl = match self.get_class_level() {
    Some(cl) => cl
    None => return Err(not_initialized_err())
  }
  let cache_key = "terms:" + cl
  let cached = self.caches.get(cache_key)
  match cached {
    Some(item) if now - item.fetched_at < CACHE_TTL =>
      match item.data {
        Terms(arr) if arr.length() > 0 => return Ok(arr)
        _ => ()
      }
    _ => ()
  }
  let sql = "SELECT * FROM terms WHERE active = true ORDER BY sort_order ASC"
  let result_arr = match surreal_query(self.config.value, sql) {
    Ok(arr) => arr
    Err(_) => {
      match cached {
        Some(item) =>
          match item.data {
            Terms(arr) if arr.length() > 0 => return Ok(arr)
            _ => ()
          }
        _ => ()
      }
      return Err(
        AppError::{
          code: SurrealDBError,
          message: "Failed to query terms from database",
          detail: None,
        }.to_json_string(),
      )
    }
  }
  let terms : Array[TermInfo] = []
  for item in result_arr {
    match item {
      Object(obj) => {
        let id = match obj.get("id") {
          Some(String(s)) => s
          _ => continue
        }
        let name = match obj.get("name") {
          Some(String(s)) => s
          _ => continue
        }
        let sort_order = match obj.get("sort_order") {
          Some(Number(d, ..)) => d.to_int()
          _ => 0
        }
        let active = match obj.get("active") {
          Some(True) => true
          _ => false
        }
        terms.push(TermInfo::{ id, name, sort_order, active })
      }
      _ => ()
    }
  }
  if terms.length() == 0 {
    return Err(
      AppError::{
        code: NotFound,
        message: "No terms are available for your class.",
        detail: None,
      }.to_json_string(),
    )
  }
  self.caches.set(cache_key, CacheItem::{ data: Terms(terms), fetched_at: now })
  Ok(terms)
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
  let cache_key = "lessons:" + subject_id + "|" + term_id
  let cached = self.caches.get(cache_key)
  match cached {
    Some(item) if now - item.fetched_at < CACHE_TTL =>
      match item.data {
        Lessons(arr) if arr.length() > 0 => return Ok(arr)
        _ => ()
      }
    _ => ()
  }
  let cl = match self.get_class_level() {
    Some(cl) => cl
    None => return Err(not_initialized_err())
  }
  let sql = "SELECT id, topic_title, week, active, " +
    "  topic.has_subject.out.name AS subject_name, topic.term.name AS term_name " +
    "FROM lessons " +
    "WHERE topic.has_subject.in = " +
    cl +
    " " +
    "  AND topic.has_subject.out = " +
    subject_id +
    " " +
    "  AND topic.has_subject.active = true " +
    "  AND topic.term = " +
    term_id +
    " " +
    "  AND active = true " +
    "ORDER BY week ASC"
  let result_arr = match surreal_query(self.config.value, sql) {
    Ok(arr) => arr
    Err(_) => {
      match cached {
        Some(item) =>
          match item.data {
            Lessons(arr) if arr.length() > 0 => return Ok(arr)
            _ => ()
          }
        _ => ()
      }
      return Err(
        AppError::{
          code: SurrealDBError,
          message: "Failed to query lessons from database",
          detail: None,
        }.to_json_string(),
      )
    }
  }
  let lessons : Array[LessonInfo] = []
  for item in result_arr {
    match item {
      Object(obj) => {
        let id = match obj.get("id") {
          Some(String(s)) => s
          _ => continue
        }
        let topic_title = match obj.get("topic_title") {
          Some(String(s)) => Some(s)
          _ => None
        }
        let week = match obj.get("week") {
          Some(Number(d, ..)) => Some(d.to_int())
          _ => None
        }
        let subject_name = match obj.get("subject_name") {
          Some(String(s)) => Some(s)
          _ => None
        }
        let term_name = match obj.get("term_name") {
          Some(String(s)) => Some(s)
          _ => None
        }
        let active = match obj.get("active") {
          Some(True) => Some(true)
          Some(False) => Some(false)
          _ => None
        }
        lessons.push(LessonInfo::{
          id,
          topic_title,
          week,
          active,
          subject_name,
          term_name,
        })
      }
      _ => ()
    }
  }
  if lessons.length() == 0 {
    return Err(
      AppError::{
        code: NotFound,
        message: "No lessons are available for this term yet.",
        detail: None,
      }.to_json_string(),
    )
  }
  self.caches.set(cache_key, CacheItem::{
    data: Lessons(lessons),
    fetched_at: now,
  })
  Ok(lessons)
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
  let cache_key = "lesson:" + lesson_id
  let cached = self.caches.get(cache_key)
  match cached {
    Some(item) if now - item.fetched_at < CACHE_TTL =>
      match item.data {
        LessonContent(lc) => return Ok(Some(lc))
        _ => ()
      }
    _ => ()
  }
  let sql = "SELECT id, topic_title, week, " +
    "topic.has_subject.out.name AS subject_name, topic.term.name AS term_name, " +
    "objectives, content_sections, key_points, " +
    "mcq_questions, theoretical_questions " +
    "FROM lessons WHERE id = $lesson_id"
  let result_arr = match
    surreal_query(self.config.value, sql, bindings={ "lesson_id": lesson_id }) {
    Ok(arr) => arr
    Err(_) => {
      match cached {
        Some(item) =>
          match item.data {
            LessonContent(lc) => return Ok(Some(lc))
            _ => ()
          }
        _ => ()
      }
      return Err(
        AppError::{
          code: SurrealDBError,
          message: "Failed to query lesson from database",
          detail: None,
        }.to_json_string(),
      )
    }
  }
  if result_arr.length() == 0 {
    return Ok(None)
  }
  let lesson = match result_arr[0] {
    Object(obj) => {
      let lid = match obj.get("id") {
        Some(String(s)) => s
        _ => ""
      }
      let t = match obj.get("topic_title") {
        Some(String(s)) => Some(s)
        _ => None
      }
      let w = match obj.get("week") {
        Some(Number(d, ..)) => Some(d.to_int())
        _ => None
      }
      let sn = match obj.get("subject_name") {
        Some(String(s)) => Some(s)
        _ => None
      }
      let tn = match obj.get("term_name") {
        Some(String(s)) => Some(s)
        _ => None
      }
      let objs = match obj.get("objectives") {
        Some(v) => Some(v.stringify())
        _ => None
      }
      let cs = match obj.get("content_sections") {
        Some(v) => Some(v.stringify())
        _ => None
      }
      let kp = match obj.get("key_points") {
        Some(v) => Some(v.stringify())
        _ => None
      }
      let mcq = match obj.get("mcq_questions") {
        Some(v) => Some(v.stringify())
        _ => None
      }
      let tq = match obj.get("theoretical_questions") {
        Some(v) => Some(v.stringify())
        _ => None
      }
      LessonContent::{
        id: lid,
        topic_title: t,
        week: w,
        subject_name: sn,
        term_name: tn,
        objectives: objs,
        content_sections: cs,
        key_points: kp,
        mcq_questions: mcq,
        theoretical_questions: tq,
      }
    }
    _ => {
      match cached {
        Some(item) =>
          match item.data {
            LessonContent(lc) => return Ok(Some(lc))
            _ => ()
          }
        _ => ()
      }
      return Ok(None)
    }
  }
  self.caches.set(cache_key, CacheItem::{
    data: LessonContent(lesson),
    fetched_at: now,
  })
  Ok(Some(lesson))
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
  if key == "all" || key == "profile" {
    self.caches = Map::new()
  } else {
    self.caches.remove(key)
  }
  "OK"
}
