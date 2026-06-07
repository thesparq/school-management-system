///|
fn try_parse_parent_students(json_str : String) -> Array[ParentStudentInfo]? {
  let val = @json.parse(json_str) catch { _ => return None }
  match val {
    Array(arr) => {
      let items : Array[ParentStudentInfo] = []
      for i in arr {
        match i {
          Object(obj) =>
            items.push(ParentStudentInfo::{
              id: match obj.get("id") {
                Some(String(s)) => s
                _ => continue
              },
              display_name: match obj.get("display_name") {
                Some(String(s)) => s
                _ => continue
              },
              current_class: match obj.get("current_class") {
                Some(String(s)) => s
                _ => ""
              },
              subject_count: match obj.get("subject_count") {
                Some(Number(n, ..)) => n.to_int()
                _ => 0
              },
            })
          _ => ()
        }
      }
      if items.length() > 0 {
        Some(items)
      } else {
        None
      }
    }
    _ => None
  }
}

///|
pub fn parent_fetch_my_students(
  cache : CacheSystem,
  config : SharedConfig,
  parent_id : String,
  now : UInt64,
) -> Result[Array[ParentStudentInfo], AppError] {
  let cache_key = "linked_students"
  match cache.get(cache_key, now) {
    Some(json_str) =>
      match try_parse_parent_students(json_str) {
        Some(items) => return Ok(items)
        None => ()
      }
    None => ()
  }
  let profile_arr = match db_parent_fetch_profile(config, parent_id) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  if profile_arr.length() == 0 {
    return Err(not_found_error("Parent profile"))
  }
  let student_ids : Array[String] = match profile_arr[0] {
    Object(obj) =>
      match obj.get("students") {
        Some(Array(a)) => {
          let ids : Array[String] = []
          for x in a {
            match x {
              String(s) => ids.push(s)
              _ => ()
            }
          }
          ids
        }
        _ => []
      }
    _ => []
  }
  if student_ids.length() == 0 {
    return Ok([])
  }
  let profiles = match db_parent_fetch_student_profiles(config, student_ids) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  let items : Array[ParentStudentInfo] = []
  for item in profiles {
    match item {
      Object(o) => {
        let cl = match o.get("current_class") {
          Some(String(s)) => s
          _ => ""
        }
        let count = match db_parent_count_subjects_for_class(config, cl) {
          Ok(n) => n
          Err(_) => 0
        }
        items.push(ParentStudentInfo::{
          id: match o.get("id") {
            Some(String(s)) => s
            _ => continue
          },
          display_name: match o.get("display_name") {
            Some(String(s)) => s
            _ => ""
          },
          current_class: cl,
          subject_count: count,
        })
      }
      _ => ()
    }
  }
  cache.set(cache_key, items.to_json().stringify(), CACHE_TTL, [], now)
  Ok(items)
}

///|
pub fn parent_verify_student_access(
  config : SharedConfig,
  parent_id : String,
  student_id : String,
) -> Result[Unit, AppError] {
  let profile_arr = match db_parent_fetch_profile(config, parent_id) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  if profile_arr.length() == 0 {
    return Err(not_found_error("Parent profile"))
  }
  let student_ids : Array[String] = match profile_arr[0] {
    Object(obj) =>
      match obj.get("students") {
        Some(Array(a)) => {
          let ids : Array[String] = []
          for x in a {
            match x {
              String(s) => ids.push(s)
              _ => ()
            }
          }
          ids
        }
        _ => []
      }
    _ => []
  }
  let mut found = false
  for id in student_ids {
    if id == student_id {
      found = true
    }
  }
  if found {
    Ok(())
  } else {
    Err(AppError::{
      code: NotFound,
      message: "Student not linked to this parent",
      debug: None,
    })
  }
}

///|
pub fn parent_fetch_student_subjects(
  config : SharedConfig,
  parent_id : String,
  student_id : String,
) -> Result[Array[SubjectInfo], AppError] {
  match parent_verify_student_access(config, parent_id, student_id) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let profile = match db_admin_fetch_student_profile(config, student_id) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  if profile.length() == 0 {
    return Err(not_found_error("Student profile"))
  }
  let cl = match profile[0] {
    Object(o) =>
      match o.get("current_class") {
        Some(String(s)) => s
        _ => return Err(not_found_error("Class level"))
      }
    _ => return Err(not_found_error("Student profile"))
  }
  let arr = match db_parent_fetch_student_subjects(config, cl) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  let items : Array[SubjectInfo] = []
  for item in arr {
    match item {
      Object(o) =>
        items.push(SubjectInfo::{
          id: match o.get("id") {
            Some(String(s)) => s
            _ => continue
          },
          name: match o.get("name") {
            Some(String(s)) => s
            _ => continue
          },
          code: match o.get("code") {
            Some(String(s)) => Some(s)
            _ => None
          },
        })
      _ => ()
    }
  }
  Ok(items)
}

///|
pub fn parent_fetch_student_terms(
  config : SharedConfig,
  parent_id : String,
  student_id : String,
) -> Result[Array[TermInfo], AppError] {
  match parent_verify_student_access(config, parent_id, student_id) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let arr = match db_parent_fetch_student_terms(config) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  let items : Array[TermInfo] = []
  for item in arr {
    match item {
      Object(o) =>
        items.push(TermInfo::{
          id: match o.get("id") {
            Some(String(s)) => s
            _ => continue
          },
          name: match o.get("name") {
            Some(String(s)) => s
            _ => continue
          },
          sort_order: match o.get("sort_order") {
            Some(Number(n, ..)) => n.to_int()
            _ => 0
          },
          active: match o.get("active") {
            Some(True) => true
            _ => false
          },
        })
      _ => ()
    }
  }
  Ok(items)
}

///|
pub fn parent_fetch_student_lessons(
  config : SharedConfig,
  parent_id : String,
  student_id : String,
  subject_id : String,
  term_id : String,
) -> Result[Array[LessonInfo], AppError] {
  match parent_verify_student_access(config, parent_id, student_id) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let profile = match db_admin_fetch_student_profile(config, student_id) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  if profile.length() == 0 {
    return Err(not_found_error("Student profile"))
  }
  let cl = match profile[0] {
    Object(o) =>
      match o.get("current_class") {
        Some(String(s)) => s
        _ => return Err(not_found_error("Class level"))
      }
    _ => return Err(not_found_error("Student profile"))
  }
  let arr = match
    db_parent_fetch_student_lessons(config, cl, subject_id, term_id) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  let items : Array[LessonInfo] = []
  for item in arr {
    match item {
      Object(o) =>
        items.push(LessonInfo::{
          id: match o.get("id") {
            Some(String(s)) => s
            _ => continue
          },
          topic_title: match o.get("topic_title") {
            Some(String(s)) => Some(s)
            _ => None
          },
          week: match o.get("week") {
            Some(Number(n, ..)) => Some(n.to_int())
            _ => None
          },
          active: match o.get("active") {
            Some(True) => Some(true)
            _ => None
          },
          subject_name: match o.get("subject_name") {
            Some(String(s)) => Some(s)
            _ => None
          },
          term_name: match o.get("term_name") {
            Some(String(s)) => Some(s)
            _ => None
          },
        })
      _ => ()
    }
  }
  Ok(items)
}

///|
pub fn parent_fetch_student_lesson(
  config : SharedConfig,
  parent_id : String,
  student_id : String,
  lesson_id : String,
) -> Result[LessonContent, AppError] {
  match parent_verify_student_access(config, parent_id, student_id) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let arr = match db_parent_fetch_student_lesson_content(config, lesson_id) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  if arr.length() > 0 {
    match arr[0] {
      Object(o) =>
        Ok(LessonContent::{
          id: match o.get("id") {
            Some(String(s)) => s
            _ => ""
          },
          topic_title: match o.get("topic_title") {
            Some(String(s)) => Some(s)
            _ => None
          },
          week: match o.get("week") {
            Some(Number(n, ..)) => Some(n.to_int())
            _ => None
          },
          subject_name: match o.get("subject_name") {
            Some(String(s)) => Some(s)
            _ => None
          },
          term_name: match o.get("term_name") {
            Some(String(s)) => Some(s)
            _ => None
          },
          objectives: match o.get("objectives") {
            Some(obj) => Some(obj.to_json().stringify())
            _ => None
          },
          content_sections: match o.get("content_sections") {
            Some(obj) => Some(obj.to_json().stringify())
            _ => None
          },
          key_points: match o.get("key_points") {
            Some(obj) => Some(obj.to_json().stringify())
            _ => None
          },
          mcq_questions: match o.get("mcq_questions") {
            Some(obj) => Some(obj.to_json().stringify())
            _ => None
          },
          theoretical_questions: match o.get("theoretical_questions") {
            Some(obj) => Some(obj.to_json().stringify())
            _ => None
          },
        })
      _ => Err(not_found_error("Lesson"))
    }
  } else {
    Err(not_found_error("Lesson"))
  }
}
