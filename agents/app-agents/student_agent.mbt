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
  subject_name : String?
  term_name : String?
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

///|
#derive.golem_schema
struct EdgeCacheEntry {
  edge_id : String
  fetched_at : UInt64
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
}

///|
#derive.golem_schema
struct LessonContentCache {
  data : LessonContent
  fetched_at : UInt64
}

///|
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
  edge_cache : Map[String, EdgeCacheEntry]
  lesson_cache : Map[String, LessonContentCache]
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
    edge_cache: Map::new(),
    lesson_cache: Map::new(),
  }
}

///|
fn parse_result_array(raw : String) -> Result[Array[Json], String] {
  let val = @json.parse(raw) catch { _ => return Err("parse response failed") }
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

  let subj_sql = "SELECT id AS edge_id, out.id AS id, out.name AS name, out.code AS code " +
    "FROM has_subject " +
    "WHERE in.name = $class_level AND active = true " +
    "ORDER BY out.name ASC"
  let subj_raw = match
    surreal_query(self.config, subj_sql, bindings={ "class_level": class_level }) {
    Ok(body) => body
    Err(e) => return "ERROR: query subjects failed: " + e
  }

  let result_arr = match parse_result_array(subj_raw) {
    Ok(arr) => arr
    Err(e) => return "ERROR: " + e
  }

  let subjects : Array[SubjectInfo] = []
  let now = @wallClock.now().seconds
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
        match obj.get("edge_id") {
          Some(String(eid)) => {
            self.edge_cache.set(id, { edge_id: eid, fetched_at: now })
          }
          _ => ()
        }
        subjects.push(SubjectInfo::{ id, name, code })
      }
      _ => ()
    }
  }

  self.subject_cache = Some(SubjectCache::{ subjects, fetched_at: now })

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

  let cl = match self.profile {
    Some(p) => p.class_level
    None => return []
  }

  let subj_sql = "SELECT out.id AS id, out.name AS name, out.code AS code " +
    "FROM has_subject " +
    "WHERE in.name = $class_level AND active = true " +
    "ORDER BY out.name ASC"
  let subj_raw = match
    surreal_query(self.config, subj_sql, bindings={ "class_level": cl }) {
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

  let sql = "SELECT * FROM terms WHERE active = true ORDER BY sort_order ASC"
  let raw = match
    surreal_query(self.config, sql) {
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

  self.terms_cache.set(cl, TermCacheEntry::{ data: terms, fetched_at: now })
  self.terms_cache.get(cl).map(fn(e) { e.data }).unwrap_or([])
}

///|
/// Returns lessons for a given subject + term in the student's class level.
/// Uses edge cache to avoid graph traversal on repeated queries.
pub fn StudentAgent::get_lessons(
  self : Self,
  subject_id : String,
  term_id : String,
) -> Array[LessonInfo] {
  let now = @wallClock.now().seconds
  let cache_key = subject_id + "|" + term_id

  let cached_entry = self.lessons_cache.get(cache_key)
  match cached_entry {
    Some(entry) if now - entry.fetched_at < CACHE_TTL => return entry.data
    _ => ()
  }

  let cl = match self.profile {
    Some(p) => p.class_level
    None => return []
  }

  // Check edge cache for cached has_subject edge record ID
  let cached_edge = self.edge_cache.get(subject_id)
  let edge_id = match cached_edge {
    Some(entry) if now - entry.fetched_at < CACHE_TTL => Some(entry.edge_id)
    _ => None
  }

  // Build SQL based on whether edge is cached
  let sql = match edge_id {
    Some(_) =>
      "SELECT id, topic_title, week, " +
      "  class_subject.out.name AS subject_name, term.name AS term_name " +
      "FROM lessons " +
      "WHERE class_subject = $hs_id AND term = $term_id AND active = true " +
      "ORDER BY week ASC"
    None =>
      "SELECT id, topic_title, week, class_subject, " +
      "  class_subject.out.name AS subject_name, term.name AS term_name " +
      "FROM lessons " +
      "WHERE class_subject.in.name = $class_level " +
      "  AND class_subject.out = $subject_id " +
      "  AND class_subject.active = true " +
      "  AND term = $term_id AND active = true " +
      "ORDER BY week ASC"
  }

  let hs_binding = match edge_id {
    Some(eid) => eid
    None => ""
  }
  let raw = match
    surreal_query(self.config, sql, bindings={
      "class_level": cl,
      "subject_id": subject_id,
      "term_id": term_id,
      "hs_id": hs_binding,
    }) {
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
        let week = match obj.get("week") {
          Some(v) =>
            match v {
              Number(d, ..) => Some(d.to_int())
              _ => None
            }
          None => None
        }
        let subject_name = match obj.get("subject_name") {
          Some(v) =>
            match v {
              String(s) => Some(s)
              _ => None
            }
          None => None
        }
        let term_name = match obj.get("term_name") {
          Some(v) =>
            match v {
              String(s) => Some(s)
              _ => None
            }
          None => None
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

  // Cache the has_subject edge ID from dot-traversal results
  if edge_id == None && result_arr.length() > 0 {
    match result_arr[0] {
      Object(obj) =>
        match obj.get("class_subject") {
          Some(String(full_id)) =>
            self.edge_cache.set(subject_id, {
              edge_id: full_id,
              fetched_at: now,
            })
          _ => ()
        }
      _ => ()
    }
  }

  self.lessons_cache.set(cache_key, LessonCacheEntry::{
    data: lessons,
    fetched_at: now,
  })
  self.lessons_cache.get(cache_key).map(fn(e) { e.data }).unwrap_or([])
}

///|
/// Returns student-visible lesson content for a given lesson_id.
/// Fetches from SurrealDB with TTL caching (600s).
/// Returns None if the lesson does not exist.
pub fn StudentAgent::get_lesson(self : Self, lesson_id : String) -> LessonContent? {
  let now = @wallClock.now().seconds

  let cached = self.lesson_cache.get(lesson_id)
  match cached {
    Some(entry) if now - entry.fetched_at < CACHE_TTL => return Some(entry.data)
    _ => ()
  }

  let sql =
    "SELECT id, topic_title, week, " +
    "class_subject.out.name AS subject_name, term.name AS term_name, " +
    "objectives, content_sections, key_points " +
    "FROM lessons WHERE id = $lesson_id"

  let raw = match
    surreal_query(self.config, sql, bindings={ "lesson_id": lesson_id }) {
    Ok(body) => body
    Err(_) => {
      let old = self.lesson_cache.get(lesson_id)
      match old {
        Some(e) => return Some(e.data)
        None => return None
      }
    }
  }

  let result_arr = match parse_result_array(raw) {
    Ok(arr) => arr
    Err(_) => {
      let old = self.lesson_cache.get(lesson_id)
      match old {
        Some(e) => return Some(e.data)
        None => return None
      }
    }
  }

  if result_arr.length() == 0 {
    return None
  }

  let lesson = match result_arr[0] {
    Object(obj) => {
      let id = match obj.get("id") {
        Some(v) =>
          match v {
            String(s) => s
            _ => ""
          }
        None => ""
      }
      let topic_title = match obj.get("topic_title") {
        Some(v) =>
          match v {
            String(s) => Some(s)
            _ => None
          }
        None => None
      }
      let week = match obj.get("week") {
        Some(v) =>
          match v {
            Number(d, ..) => Some(d.to_int())
            _ => None
          }
        None => None
      }
      let subject_name = match obj.get("subject_name") {
        Some(v) =>
          match v {
            String(s) => Some(s)
            _ => None
          }
        None => None
      }
      let term_name = match obj.get("term_name") {
        Some(v) =>
          match v {
            String(s) => Some(s)
            _ => None
          }
        None => None
      }
      let objectives = match obj.get("objectives") {
        Some(v) => Some(v.stringify())
        None => None
      }
      let content_sections = match obj.get("content_sections") {
        Some(v) => Some(v.stringify())
        None => None
      }
      let key_points = match obj.get("key_points") {
        Some(v) => Some(v.stringify())
        None => None
      }
      LessonContent::{
        id,
        topic_title,
        week,
        subject_name,
        term_name,
        objectives,
        content_sections,
        key_points,
      }
    }
    _ => {
      let old = self.lesson_cache.get(lesson_id)
      match old {
        Some(e) => return Some(e.data)
        None => return None
      }
    }
  }

  self.lesson_cache.set(lesson_id, LessonContentCache::{
    data: lesson,
    fetched_at: now,
  })
  Some(lesson)
}
