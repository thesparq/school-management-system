//|

///|
#derive.golem_schema
struct TeacherSubjectPair {
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
/// Durable per-teacher agent.
/// Identified by teacher_id — one instance per teacher.
#derive.agent
struct TeacherAgent {
  config : @config.Config[SurrealConfig]
  teacher_id : String
  mut class_groups : Map[String, TeacherClassGroup]
}

///|
fn TeacherAgent::new(
  teacher_id : String,
  config : @config.Config[SurrealConfig],
) -> TeacherAgent {
  { config, teacher_id, class_groups: Map::new() }
}

///|
/// Fetches assigned class-subject pairs from teacher_assignment table
/// via direct SurrealDB query, groups them by class_level_id,
/// and stores in durable state.
pub fn TeacherAgent::trigger_initialize(self : Self) -> String {
  let sql = "SELECT teacher_id, class_level_id, subject_id, " +
    "(SELECT VALUE name FROM class_levels WHERE id = type::thing(\"class_levels\", class_level_id))[0] AS class_level_name, " +
    "(SELECT VALUE name FROM subjects WHERE id = type::thing(\"subjects\", subject_id))[0] AS subject_name, " +
    "(SELECT VALUE code FROM subjects WHERE id = type::thing(\"subjects\", subject_id))[0] AS subject_code " +
    "FROM teacher_assignment WHERE teacher_id = '" +
    escape_surreal_string(self.teacher_id) +
    "' AND deleted_at IS NONE ORDER BY class_level_name ASC, subject_name ASC"
  let result_arr = match surreal_query_retry(self.config, sql, None) {
    Ok(arr) => arr
    Err(_) => return "ERROR: db query failed"
  }
  let groups : Map[String, TeacherClassGroup] = Map::new()
  for item in result_arr {
    match item {
      Object(obj) => {
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
        let gid = class_level_id
        let pair = TeacherSubjectPair::{
          class_level_id,
          class_level_name,
          subject_id,
          subject_name,
          subject_code,
        }
        match groups.get(gid) {
          Some(g) => {
            g.subjects.push(pair)
            groups.set(gid, g)
          }
          None =>
            groups.set(gid, TeacherClassGroup::{
              class_level_id: gid,
              class_level_name,
              subjects: [pair],
            })
        }
      }
      _ => ()
    }
  }
  self.class_groups = groups
  "OK"
}

///|
/// Clears the cached class groups. Next call to trigger_initialize()
/// will re-fetch from the database.
pub fn TeacherAgent::invalidate_cache(self : Self) -> String {
  self.class_groups = Map::new()
  "OK"
}

///|
/// Returns the teacher's assigned classes with subjects.
/// Returns [] if not yet initialized.
pub fn TeacherAgent::get_my_classes(self : Self) -> Array[TeacherClassGroup] {
  let result : Array[TeacherClassGroup] = []
  for pair in self.class_groups.iter() {
    let (_, g) = pair
    result.push(g)
  }
  result
}

///|
/// Returns all active terms (same query pattern as StudentAgent).
pub fn TeacherAgent::get_terms(self : Self) -> Array[TermInfo] {
  let sql = "SELECT * FROM terms WHERE active = true ORDER BY sort_order ASC"
  let raw = match surreal_query(self.config, sql) {
    Ok(body) => body
    Err(_) => return []
  }

  let result_arr = match parse_result_array(raw) {
    Ok(arr) => arr
    Err(_) => return []
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
  terms
}

///|
/// Returns lessons for a given class_level + subject + term.
/// Uses dot-traversal on the has_subject edge.
pub fn TeacherAgent::get_lessons(
  self : Self,
  class_level_id : String,
  subject_id : String,
  term_id : String,
) -> Array[LessonInfo] {
  let sql = "SELECT id, topic_title, week, " +
    "class_subject.out.name AS subject_name, term.name AS term_name " +
    "FROM lessons " +
    "WHERE class_subject.in = $class_level_id " +
    "  AND class_subject.out = $subject_id " +
    "  AND class_subject.active = true " +
    "  AND term = $term_id AND active = true " +
    "ORDER BY week ASC"
  let raw = match
    surreal_query(self.config, sql, bindings={
      "class_level_id": class_level_id,
      "subject_id": subject_id,
      "term_id": term_id,
    }) {
    Ok(body) => body
    Err(_) => return []
  }

  let result_arr = match parse_result_array(raw) {
    Ok(arr) => arr
    Err(_) => return []
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
        lessons.push(LessonInfo::{
          id,
          topic_title,
          week,
          subject_name,
          term_name,
        })
      }
      _ => ()
    }
  }
  lessons
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
