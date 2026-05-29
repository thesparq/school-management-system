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
  week_number : Int?
}

///|
#derive.golem_schema
struct SubjectCache {
  subjects : Array[SubjectInfo]
  fetched_at : UInt64
}

///|
#derive.golem_schema
struct TermCacheEntry {
  data : Array[TermInfo]
  fetched_at : UInt64
}

///|
#derive.golem_schema
struct LessonCacheEntry {
  data : Array[LessonInfo]
  fetched_at : UInt64
}

const CACHE_TTL : UInt64 = 600

///|
/// Durable per-student agent.
/// Identified by student_id — one instance per student.
#derive.agent
struct StudentAgent {
  config : @config.Config[SurrealConfig]
  student_id : String
  mut profile : StudentProfile?
  mut subject_cache : SubjectCache?
  terms_cache : Map[String, TermCacheEntry]
  lessons_cache : Map[String, LessonCacheEntry]
}

///|
fn StudentAgent::new(
  student_id : String,
  config : @config.Config[SurrealConfig],
) -> StudentAgent {
  {
    config,
    student_id,
    profile: None,
    subject_cache: None,
    terms_cache: Map::new(),
    lessons_cache: Map::new(),
  }
}

///|
fn parse_result_array(raw : String) -> Result[Array[Json], String] {
  let val = @json.parse(raw) catch {
    _ => return Err("parse response failed")
  }
  match val {
    Array(a) => {
      if a.length() == 0 {
        return Err("response empty")
      }
      match a[0] {
        Object(obj) =>
          match obj.get("result") {
            Some(r) =>
              match r {
                Array(arr) => Ok(arr)
                _ => Err("result not an array")
              }
            None => Err("result missing")
          }
        _ => Err("element not an object")
      }
    }
    _ => Err("response not an array")
  }
}

///|
/// Tests SurrealDB connectivity.
pub fn StudentAgent::test_db(self : Self) -> String {
  match surreal_query(self.config, "SELECT * FROM 1") {
    Ok(body) => "OK: " + body
    Err(e) => "ERROR: " + e
  }
}

///|
/// Initializes this student's profile and fetches subjects from SurrealDB.
/// Idempotent — calling again with the same class_level is a no-op update.
pub fn StudentAgent::initialize(self : Self, class_level : String) -> String {
  self.profile = Some(StudentProfile::{ class_level, })

  let cl_sql =
    "SELECT VALUE id FROM class_levels WHERE name = $class_level LIMIT 1"
  let cl_raw = match
    surreal_query(self.config, cl_sql, bindings={ "class_level": class_level }) {
    Ok(body) => body
    Err(e) => return "ERROR: lookup class_level failed: " + e
  }

  let cl_val = @json.parse(cl_raw) catch {
    _ => return "ERROR: parse class_level response failed"
  }
  let cl_id = match cl_val {
    Array(arr) => {
      if arr.length() == 0 {
        return "ERROR: class_level response empty"
      }
      match arr[0] {
        Object(obj) =>
          match obj.get("result") {
            Some(r) =>
              match r {
                Array(res) => {
                  if res.length() == 0 {
                    return "ERROR: class_level not found: " + class_level
                  }
                  match res[0] {
                    String(id) => id
                    _ => return "ERROR: class_level id not a string"
                  }
                }
                _ => return "ERROR: class_level result not an array"
              }
            None => return "ERROR: class_level result missing"
          }
        _ => return "ERROR: class_level element not an object"
      }
    }
    _ => return "ERROR: class_level response not an array"
  }

  let subj_sql =
    "SELECT out.id AS id, out.name AS name, out.code AS code " +
    "FROM has_subject WHERE in = " +
    cl_id +
    " AND active = true ORDER BY out.name ASC"
  let subj_raw = match surreal_query(self.config, subj_sql) {
    Ok(body) => body
    Err(e) => return "ERROR: query subjects failed: " + e
  }

  let result_arr = match parse_result_array(subj_raw) {
    Ok(arr) => arr
    Err(e) => return "ERROR: " + e
  }

  let subjects : Array[SubjectInfo] = []
  for item in result_arr {
    match item {
      Object(obj) => {
        let id = match obj.get("id") {
          Some(v) =>
            match v {
              String(s) => s
              _ => continue
            }
          None => continue
        }
        let name = match obj.get("name") {
          Some(v) =>
            match v {
              String(s) => s
              _ => continue
            }
          None => continue
        }
        let code = match obj.get("code") {
          Some(v) =>
            match v {
              String(s) => Some(s)
              _ => None
            }
          None => None
        }
        subjects.push(SubjectInfo::{ id, name, code })
      }
      _ => ()
    }
  }

  self.subject_cache = Some(
    SubjectCache::{ subjects, fetched_at: @wallClock.now().seconds, },
  )

  "OK"
}

///|
pub fn StudentAgent::get_subjects(self : Self) -> Array[SubjectInfo] {
  let now = @wallClock.now().seconds
  let cached = self.subject_cache
  match cached {
    Some(cache) if now - cache.fetched_at < CACHE_TTL => return cache.subjects
    _ => ()
  }

  let cl_id = match self.profile {
    Some(p) => p.class_level
    None => return []
  }

  let subj_sql =
    "SELECT out.id AS id, out.name AS name, out.code AS code " +
    "FROM has_subject WHERE in = $class_level_id AND active = true " +
    "ORDER BY out.name ASC"
  let subj_raw = match surreal_query(
    self.config,
    subj_sql,
    bindings={ "class_level_id": cl_id },
  ) {
    Ok(body) => body
    Err(_) => {
      let old = self.subject_cache
      match old {
        Some(c) => return c.subjects
        None => return []
      }
    }
  }

  let result_arr = match parse_result_array(subj_raw) {
    Ok(arr) => arr
    Err(_) => {
      let old = self.subject_cache
      match old {
        Some(c) => return c.subjects
        None => return []
      }
    }
  }

  let subjects : Array[SubjectInfo] = []
  for item in result_arr {
    match item {
      Object(obj) => {
        let id = match obj.get("id") {
          Some(v) =>
            match v {
              String(s) => s
              _ => continue
            }
          None => continue
        }
        let name = match obj.get("name") {
          Some(v) =>
            match v {
              String(s) => s
              _ => continue
            }
          None => continue
        }
        let code = match obj.get("code") {
          Some(v) =>
            match v {
              String(s) => Some(s)
              _ => None
            }
          None => None
        }
        subjects.push(SubjectInfo::{ id, name, code })
      }
      _ => ()
    }
  }

  self.subject_cache = Some(SubjectCache::{ subjects, fetched_at: now })
  match self.subject_cache {
    Some(c) => c.subjects
    None => []
  }
}

///|
pub fn StudentAgent::get_terms(self : Self) -> Array[TermInfo] {
  let now = @wallClock.now().seconds
  let cl = match self.profile {
    Some(p) => p.class_level
    None => return []
  }

  let cached_entry = self.terms_cache.get(cl)
  match cached_entry {
    Some(entry) if now - entry.fetched_at < CACHE_TTL => return entry.data
    _ => ()
  }

  let sql =
    "SELECT * FROM terms WHERE active = true ORDER BY sort_order ASC"
  let raw = match surreal_query(
    self.config,
    sql,
    bindings={ "class_level_id": cl },
  ) {
    Ok(body) => body
    Err(_) => {
      let old = self.terms_cache.get(cl)
      match old {
        Some(e) => return e.data
        None => return []
      }
    }
  }

  let result_arr = match parse_result_array(raw) {
    Ok(arr) => arr
    Err(_) => {
      let old = self.terms_cache.get(cl)
      match old {
        Some(e) => return e.data
        None => return []
      }
    }
  }

  let terms : Array[TermInfo] = []
  for item in result_arr {
    match item {
      Object(obj) => {
        let id = match obj.get("id") {
          Some(v) =>
            match v {
              String(s) => s
              _ => continue
            }
          None => continue
        }
        let name = match obj.get("name") {
          Some(v) =>
            match v {
              String(s) => s
              _ => continue
            }
          None => continue
        }
        let sort_order = match obj.get("sort_order") {
          Some(v) =>
            match v {
              Number(d, ..) => d.to_int()
              _ => 0
            }
          None => 0
        }
        let active = match obj.get("active") {
          Some(v) =>
            match v {
              True => true
              _ => false
            }
          None => false
        }
        terms.push(TermInfo::{ id, name, sort_order, active })
      }
      _ => ()
    }
  }

  self.terms_cache.set(
    cl,
    TermCacheEntry::{ data: terms, fetched_at: now },
  )
  self.terms_cache
    .get(cl)
    .map(fn(e) { e.data })
    .unwrap_or([])
}

///|
pub fn StudentAgent::get_lessons(
  self : Self,
  class_subject_id : String,
) -> Array[LessonInfo] {
  let now = @wallClock.now().seconds
  let cache_key = class_subject_id

  let cached_entry = self.lessons_cache.get(cache_key)
  match cached_entry {
    Some(entry) if now - entry.fetched_at < CACHE_TTL => return entry.data
    _ => ()
  }

  let sql =
    "SELECT id, topic_title, week FROM lessons WHERE class_subject = $class_subject_id AND active = true ORDER BY week ASC"
  let raw = match surreal_query(
    self.config,
    sql,
    bindings={ "class_subject_id": class_subject_id },
  ) {
    Ok(body) => body
    Err(_) => {
      let old = self.lessons_cache.get(cache_key)
      match old {
        Some(e) => return e.data
        None => return []
      }
    }
  }

  let result_arr = match parse_result_array(raw) {
    Ok(arr) => arr
    Err(_) => {
      let old = self.lessons_cache.get(cache_key)
      match old {
        Some(e) => return e.data
        None => return []
      }
    }
  }

  let lessons : Array[LessonInfo] = []
  for item in result_arr {
    match item {
      Object(obj) => {
        let id = match obj.get("id") {
          Some(v) =>
            match v {
              String(s) => s
              _ => continue
            }
          None => continue
        }
        let topic_title = match obj.get("topic_title") {
          Some(v) =>
            match v {
              String(s) => Some(s)
              _ => None
            }
          None => None
        }
        let week_number = match obj.get("week") {
          Some(v) =>
            match v {
              Number(d, ..) => Some(d.to_int())
              _ => None
            }
          None => None
        }
        lessons.push(LessonInfo::{ id, topic_title, week_number })
      }
      _ => ()
    }
  }

  self.lessons_cache.set(
    cache_key,
    LessonCacheEntry::{ data: lessons, fetched_at: now },
  )
  self.lessons_cache
    .get(cache_key)
    .map(fn(e) { e.data })
    .unwrap_or([])
}
