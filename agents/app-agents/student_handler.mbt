///|
fn parse_profile(json_str : String) -> StudentProfile? {
  let val = @json.parse(json_str) catch { _ => return None }
  match val {
    Object(obj) =>
      Some(StudentProfile::{
        surname: match obj.get("surname") {
          Some(String(s)) => s
          _ => ""
        },
        first_name: match obj.get("first_name") {
          Some(String(s)) => s
          _ => ""
        },
        middle_name: match obj.get("middle_name") {
          Some(String(s)) => Some(s)
          _ => None
        },
        display_name: match obj.get("display_name") {
          Some(String(s)) => s
          _ => ""
        },
        date_of_birth: match obj.get("date_of_birth") {
          Some(String(s)) => s
          _ => ""
        },
        current_class: match obj.get("current_class") {
          Some(String(s)) => s
          _ => ""
        },
        passport: match obj.get("passport") {
          Some(String(s)) => s
          _ => ""
        },
      })
    _ => None
  }
}

///|
fn json_parse_array_safe(json_str : String) -> Array[Json]? {
  let val = @json.parse(json_str) catch { _ => return None }
  match val {
    Array(arr) => Some(arr)
    _ => None
  }
}

///|
fn json_parse_object_safe(json_str : String) -> Map[String, Json]? {
  let val = @json.parse(json_str) catch { _ => return None }
  match val {
    Object(obj) => Some(obj)
    _ => None
  }
}

///|
pub fn student_get_class_level(
  cache : CacheSystem,
  config : SharedConfig,
  student_id : String,
  now : UInt64,
) -> Result[String, AppError] {
  let cache_key = "profile"
  match cache.get(cache_key, now) {
    Some(json_str) =>
      match parse_profile(json_str) {
        Some(p) if p.current_class != "" => return Ok(p.current_class)
        _ => ()
      }
    None => ()
  }
  let arr = match db_student_fetch_profile(config, student_id) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  if arr.length() > 0 {
    let row = arr[0].stringify()
    match parse_profile(row) {
      Some(p) if p.current_class != "" => {
        cache.set(cache_key, row, CACHE_TTL, [], now)
        return Ok(p.current_class)
      }
      _ => ()
    }
  }
  Err(AppError::{
    code: NotInitialized,
    message: "Account not initialized. Please contact your school administrator.",
    debug: None,
  })
}

///|
pub fn student_fetch_subjects(
  cache : CacheSystem,
  config : SharedConfig,
  student_id : String,
  now : UInt64,
) -> Result[Array[SubjectInfo], AppError] {
  let cache_key = "subjects"
  match cache.get(cache_key, now) {
    Some(json_str) =>
      match json_parse_array_safe(json_str) {
        Some(arr) => {
          let items : Array[SubjectInfo] = []
          for i in arr {
            match i {
              Object(obj) =>
                items.push(SubjectInfo::{
                  id: match obj.get("id") {
                    Some(String(s)) => s
                    _ => continue
                  },
                  name: match obj.get("name") {
                    Some(String(s)) => s
                    _ => continue
                  },
                  code: match obj.get("code") {
                    Some(String(s)) => Some(s)
                    _ => None
                  },
                })
              _ => ()
            }
          }
          if items.length() > 0 {
            return Ok(items)
          }
        }
        None => ()
      }
    None => ()
  }
  let cl = match student_get_class_level(cache, config, student_id, now) {
    Ok(c) => c
    Err(e) => return Err(e)
  }
  let result_arr = match db_student_fetch_subjects(config, cl) {
    Ok(arr) => arr
    Err(e) => return Err(e)
  }
  let subjects : Array[SubjectInfo] = []
  for item in result_arr {
    match item {
      Object(obj) =>
        subjects.push(SubjectInfo::{
          id: match obj.get("id") {
            Some(String(s)) => s
            _ => continue
          },
          name: match obj.get("name") {
            Some(String(s)) => s
            _ => continue
          },
          code: match obj.get("code") {
            Some(String(s)) => Some(s)
            _ => None
          },
        })
      _ => ()
    }
  }
  if subjects.length() == 0 {
    return Err(not_found_error("Subjects"))
  }
  cache.set(
    cache_key,
    subjects.to_json().stringify(),
    CACHE_TTL,
    ["profile"],
    now,
  )
  Ok(subjects)
}

///|
pub fn student_fetch_terms(
  cache : CacheSystem,
  config : SharedConfig,
  student_id : String,
  now : UInt64,
) -> Result[Array[TermInfo], AppError] {
  let cl = match student_get_class_level(cache, config, student_id, now) {
    Ok(c) => c
    Err(e) => return Err(e)
  }
  let cache_key = "terms:" + cl
  match cache.get(cache_key, now) {
    Some(json_str) =>
      match json_parse_array_safe(json_str) {
        Some(arr) => {
          let items : Array[TermInfo] = []
          for i in arr {
            match i {
              Object(obj) =>
                items.push(TermInfo::{
                  id: match obj.get("id") {
                    Some(String(s)) => s
                    _ => continue
                  },
                  name: match obj.get("name") {
                    Some(String(s)) => s
                    _ => continue
                  },
                  sort_order: match obj.get("sort_order") {
                    Some(Number(d, ..)) => d.to_int()
                    _ => 0
                  },
                  active: match obj.get("active") {
                    Some(True) => true
                    _ => false
                  },
                })
              _ => ()
            }
          }
          if items.length() > 0 {
            return Ok(items)
          }
        }
        None => ()
      }
    None => ()
  }
  let result_arr = match db_student_fetch_terms(config) {
    Ok(arr) => arr
    Err(e) => return Err(e)
  }
  let terms : Array[TermInfo] = []
  for item in result_arr {
    match item {
      Object(obj) =>
        terms.push(TermInfo::{
          id: match obj.get("id") {
            Some(String(s)) => s
            _ => continue
          },
          name: match obj.get("name") {
            Some(String(s)) => s
            _ => continue
          },
          sort_order: match obj.get("sort_order") {
            Some(Number(d, ..)) => d.to_int()
            _ => 0
          },
          active: match obj.get("active") {
            Some(True) => true
            _ => false
          },
        })
      _ => ()
    }
  }
  if terms.length() == 0 {
    return Err(not_found_error("Terms"))
  }
  cache.set(cache_key, terms.to_json().stringify(), CACHE_TTL, ["profile"], now)
  Ok(terms)
}

///|
pub fn student_fetch_lessons(
  cache : CacheSystem,
  config : SharedConfig,
  student_id : String,
  subject_id : String,
  term_id : String,
  now : UInt64,
) -> Result[Array[LessonInfo], AppError] {
  let cache_key = "lessons:" + subject_id + "|" + term_id
  match cache.get(cache_key, now) {
    Some(json_str) =>
      match json_parse_array_safe(json_str) {
        Some(arr) => {
          let items : Array[LessonInfo] = []
          for i in arr {
            match i {
              Object(obj) =>
                items.push(LessonInfo::{
                  id: match obj.get("id") {
                    Some(String(s)) => s
                    _ => continue
                  },
                  topic_title: match obj.get("topic_title") {
                    Some(String(s)) => Some(s)
                    _ => None
                  },
                  week: match obj.get("week") {
                    Some(Number(d, ..)) => Some(d.to_int())
                    _ => None
                  },
                  subject_name: match obj.get("subject_name") {
                    Some(String(s)) => Some(s)
                    _ => None
                  },
                  term_name: match obj.get("term_name") {
                    Some(String(s)) => Some(s)
                    _ => None
                  },
                  active: match obj.get("active") {
                    Some(True) => Some(true)
                    Some(False) => Some(false)
                    _ => None
                  },
                })
              _ => ()
            }
          }
          if items.length() > 0 {
            return Ok(items)
          }
        }
        None => ()
      }
    None => ()
  }
  let cl = match student_get_class_level(cache, config, student_id, now) {
    Ok(c) => c
    Err(e) => return Err(e)
  }
  let result_arr = match
    db_student_fetch_lessons(config, cl, subject_id, term_id) {
    Ok(arr) => arr
    Err(e) => return Err(e)
  }
  let lessons : Array[LessonInfo] = []
  for item in result_arr {
    match item {
      Object(obj) =>
        lessons.push(LessonInfo::{
          id: match obj.get("id") {
            Some(String(s)) => s
            _ => continue
          },
          topic_title: match obj.get("topic_title") {
            Some(String(s)) => Some(s)
            _ => None
          },
          week: match obj.get("week") {
            Some(Number(d, ..)) => Some(d.to_int())
            _ => None
          },
          subject_name: match obj.get("subject_name") {
            Some(String(s)) => Some(s)
            _ => None
          },
          term_name: match obj.get("term_name") {
            Some(String(s)) => Some(s)
            _ => None
          },
          active: match obj.get("active") {
            Some(True) => Some(true)
            Some(False) => Some(false)
            _ => None
          },
        })
      _ => ()
    }
  }
  if lessons.length() == 0 {
    return Err(not_found_error("Lessons"))
  }
  cache.set(
    cache_key,
    lessons.to_json().stringify(),
    CACHE_TTL,
    ["profile"],
    now,
  )
  Ok(lessons)
}

///|
pub fn student_fetch_lesson(
  cache : CacheSystem,
  config : SharedConfig,
  student_id : String,
  lesson_id : String,
  now : UInt64,
) -> Result[LessonContent?, AppError] {
  let cl = match student_get_class_level(cache, config, student_id, now) {
    Ok(c) => c
    Err(e) => return Err(e)
  }
  let cache_key = "lesson:" + lesson_id + "|" + cl
  match cache.get(cache_key, now) {
    Some(json_str) =>
      match json_parse_object_safe(json_str) {
        Some(obj) => return Ok(Some(parse_lesson_content(obj)))
        None => ()
      }
    None => ()
  }
  let result_arr = match
    db_student_fetch_lesson_content(config, lesson_id, cl) {
    Ok(arr) => arr
    Err(e) => return Err(e)
  }
  if result_arr.length() == 0 {
    return Ok(None)
  }
  let obj = match result_arr[0] {
    Object(o) => o
    _ => return Ok(None)
  }
  let lesson = parse_lesson_content(obj)
  let subject_id = match obj.get("subject_id") {
    Some(String(s)) => s
    _ => ""
  }
  let term_id = match obj.get("term_id") {
    Some(String(s)) => s
    _ => ""
  }
  if subject_id != "" && term_id != "" {
    cache.set(
      cache_key,
      lesson.to_json().stringify(),
      CACHE_TTL,
      ["lessons:" + subject_id + "|" + term_id],
      now,
    )
  }
  Ok(Some(lesson))
}

///|
fn parse_lesson_content(obj : Map[String, Json]) -> LessonContent {
  LessonContent::{
    id: match obj.get("id") {
      Some(String(s)) => s
      _ => ""
    },
    topic_title: match obj.get("topic_title") {
      Some(String(s)) => Some(s)
      _ => None
    },
    week: match obj.get("week") {
      Some(Number(d, ..)) => Some(d.to_int())
      _ => None
    },
    subject_name: match obj.get("subject_name") {
      Some(String(s)) => Some(s)
      _ => None
    },
    term_name: match obj.get("term_name") {
      Some(String(s)) => Some(s)
      _ => None
    },
    objectives: match obj.get("objectives") {
      Some(v) => Some(v.stringify())
      _ => None
    },
    content_sections: match obj.get("content_sections") {
      Some(v) => Some(v.stringify())
      _ => None
    },
    key_points: match obj.get("key_points") {
      Some(v) => Some(v.stringify())
      _ => None
    },
    mcq_questions: match obj.get("mcq_questions") {
      Some(v) => Some(v.stringify())
      _ => None
    },
    theoretical_questions: match obj.get("theoretical_questions") {
      Some(v) => Some(v.stringify())
      _ => None
    },
  }
}
