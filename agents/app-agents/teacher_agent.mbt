//|

///|
#derive.golem_schema
struct TeacherSubjectPair {
  edge_id : String
  class_level_id : String
  class_level_name : String
  subject_id : String
  subject_name : String
  subject_code : String?
}

///|
#derive.golem_schema
struct TeacherClassGroup {
  class_level_id : String
  class_level_name : String
  subjects : Array[TeacherSubjectPair]
}

///|
#derive.agent
#derive.mount("/teacher/{teacher_id}")
struct TeacherAgent {
  teacher_id : String
  config : @config.Config[SharedConfig]
  mut caches : Map[String, CacheItem]
}

///|
fn TeacherAgent::new(
  teacher_id : String,
  config : @config.Config[SharedConfig],
) -> TeacherAgent {
  { teacher_id, config, caches: Map::new() }
}

///|
fn TeacherAgent::get_active_st(self : Self) -> Result[String, AppError] {
  let now = @wallClock.now().seconds
  match self.caches.get("active_session_term") {
    Some(item) if now - item.fetched_at < CACHE_TTL =>
      match item.data {
        ActiveSessionTerm(id) => return Ok(id)
        _ => ()
      }
    _ => ()
  }
  match
    surreal_query(
      self.config.value,
      "SELECT VALUE id FROM session_term WHERE active = true LIMIT 1",
    ) {
    Ok(arr) =>
      if arr.length() > 0 {
        match arr[0] {
          String(id) => {
            self.caches.set("active_session_term", CacheItem::{
              data: ActiveSessionTerm(id),
              fetched_at: now,
            })
            Ok(id)
          }
          _ =>
            Err(
              AppError::{
                code: NotFound,
                message: "No active session term found.",
                detail: None,
              },
            )
        }
      } else {
        Err(
          AppError::{
            code: NotFound,
            message: "No active session term found.",
            detail: None,
          },
        )
      }
    Err(_) =>
      match self.caches.get("active_session_term") {
        Some(item) =>
          match item.data {
            ActiveSessionTerm(id) => Ok(id)
            _ => Err(
              AppError::{
                code: SurrealDBError,
                message: "Failed to query active session term.",
                detail: None,
              },
            )
          }
        None => Err(
          AppError::{
            code: SurrealDBError,
            message: "Failed to query active session term.",
            detail: None,
          },
        )
      }
  }
}

///|
fn TeacherAgent::fetch_class_groups(self : Self) -> Result[Unit, String] {
  let now = @wallClock.now().seconds
  let active_st = match self.get_active_st() {
    Ok(id) => id
    Err(e) => return Err(e.to_json_string())
  }
  let sql = "SELECT teacher_id, " +
    "has_subject.id AS edge_id, " +
    "has_subject.in.id AS class_level_id, " +
    "has_subject.in.name AS class_level_name, " +
    "has_subject.out.id AS subject_id, " +
    "has_subject.out.name AS subject_name, " +
    "has_subject.out.code AS subject_code " +
    "FROM teacher_assignment WHERE teacher_id = '" +
    escape_surreal_string(self.teacher_id) +
    "' AND session_term = " + active_st + " " +
    "AND deleted_at IS NONE ORDER BY class_level_name ASC, subject_name ASC"
  let result_arr = match surreal_query(self.config.value, sql) {
    Ok(arr) => arr
    Err(e) =>
      match self.caches.get("class_groups") {
        Some(item) =>
          match item.data {
            ClassGroups(arr) if arr.length() > 0 => return Ok(())
            _ => return Err(e.to_json_string())
          }
        None => return Err(e.to_json_string())
      }
  }
  let groups_map : Map[String, TeacherClassGroup] = Map::new()
  for item in result_arr {
    match item {
      Object(obj) => {
        let edge_id = match obj.get("edge_id") {
          Some(String(s)) => s
          _ => continue
        }
        let class_level_id = match obj.get("class_level_id") {
          Some(String(s)) => s
          _ => continue
        }
        let class_level_name = match obj.get("class_level_name") {
          Some(String(s)) => s
          _ => continue
        }
        let subject_id = match obj.get("subject_id") {
          Some(String(s)) => s
          _ => continue
        }
        let subject_name = match obj.get("subject_name") {
          Some(String(s)) => s
          _ => continue
        }
        let subject_code = match obj.get("subject_code") {
          Some(String(s)) => Some(s)
          _ => None
        }
        let pair = TeacherSubjectPair::{
          edge_id,
          class_level_id,
          class_level_name,
          subject_id,
          subject_name,
          subject_code,
        }
        match groups_map.get(class_level_id) {
          Some(g) => {
            g.subjects.push(pair)
            groups_map.set(class_level_id, g)
          }
          None =>
            groups_map.set(class_level_id, TeacherClassGroup::{
              class_level_id,
              class_level_name,
              subjects: [pair],
            })
        }
      }
      _ => ()
    }
  }
  let groups_arr : Array[TeacherClassGroup] = []
  for pair in groups_map.iter() {
    let (_, g) = pair
    groups_arr.push(g)
  }
  if groups_arr.length() == 0 {
    return Err(
      AppError::{
        code: NotFound,
        message: "No class assignments found for this teacher.",
        detail: None,
      }.to_json_string(),
    )
  }
  self.caches.set("class_groups", CacheItem::{
    data: ClassGroups(groups_arr),
    fetched_at: now,
  })
  Ok(())
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
  let cached = self.caches.get("class_groups")
  match cached {
    Some(item) if now - item.fetched_at < CACHE_TTL =>
      match item.data {
        ClassGroups(arr) if arr.length() > 0 => return Ok(arr)
        _ => ()
      }
    _ => ()
  }
  match self.fetch_class_groups() {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match self.caches.get("class_groups") {
    Some(item) =>
      match item.data {
        ClassGroups(arr) => Ok(arr)
        _ => Ok([])
      }
    None => Ok([])
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
  let sql = "SELECT * FROM terms ORDER BY sort_order ASC"
  let result_arr = match surreal_query(self.config.value, sql) {
    Ok(arr) => arr
    Err(_) =>
      return Err(
        AppError::{
          code: SurrealDBError,
          message: "Failed to query terms from database",
          detail: None,
        }.to_json_string(),
      )
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
        message: "No terms available.",
        detail: None,
      }.to_json_string(),
    )
  }
  Ok(terms)
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
  let sql = "SELECT id, topic_title, week, active, " +
    "topic.has_subject.out.name AS subject_name, topic.term.name AS term_name " +
    "FROM lessons " +
    "WHERE topic.has_subject.in = " + class_level_id + " " +
    "  AND topic.has_subject.out = " + subject_id + " " +
    "  AND topic.has_subject.active = true " +
    "  AND topic.term = " + term_id + " " +
    "ORDER BY week ASC"
  let result_arr = match
    surreal_query(self.config.value, sql) {
    Ok(arr) => arr
    Err(_) =>
      return Err(
        AppError::{
          code: SurrealDBError,
          message: "Failed to query lessons from database",
          detail: None,
        }.to_json_string(),
      )
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
        message: "No lessons available for this term.",
        detail: None,
      }.to_json_string(),
    )
  }
  Ok(lessons)
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
  if key == "all" || key == "class_groups" {
    self.caches = Map::new()
  } else {
    self.caches.remove(key)
  }
  "OK"
}
