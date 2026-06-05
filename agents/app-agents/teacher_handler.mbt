fn try_parse_class_groups(json_str : String) -> Array[TeacherClassGroup]? {
  let val = @json.parse(json_str) catch { _ => return None }
  match val { Array(json_arr) => {
    let groups : Array[TeacherClassGroup] = []
    for item in json_arr { match item { Object(obj) => {
      let class_level_id = match obj.get("class_level_id") { Some(String(s)) => s; _ => continue }; let class_level_name = match obj.get("class_level_name") { Some(String(s)) => s; _ => continue }
      let subjects_arr = match obj.get("subjects") { Some(Array(a)) => a; _ => continue }; let pairs : Array[TeacherSubjectPair] = []
      for s in subjects_arr { match s { Object(so) => { pairs.push(TeacherSubjectPair::{
        edge_id: match so.get("edge_id") { Some(String(ss)) => ss; _ => continue }, class_level_id: match so.get("class_level_id") { Some(String(ss)) => ss; _ => continue },
        class_level_name: match so.get("class_level_name") { Some(String(ss)) => ss; _ => continue }, subject_id: match so.get("subject_id") { Some(String(ss)) => ss; _ => continue },
        subject_name: match so.get("subject_name") { Some(String(ss)) => ss; _ => continue }, subject_code: match so.get("subject_code") { Some(String(ss)) => Some(ss); _ => None },
      }) }; _ => () } }
      groups.push(TeacherClassGroup::{ class_level_id, class_level_name, subjects: pairs })
    }; _ => () } }
    if groups.length() > 0 { Some(groups) } else { None }
  }; _ => None }
}

fn try_parse_terms(json_str : String) -> Array[TermInfo]? {
  let val = @json.parse(json_str) catch { _ => return None }
  match val { Array(arr) => {
    let items : Array[TermInfo] = []
    for i in arr { match i { Object(obj) => { items.push(TermInfo::{
      id: match obj.get("id") { Some(String(s)) => s; _ => continue },
      name: match obj.get("name") { Some(String(s)) => s; _ => continue },
      sort_order: match obj.get("sort_order") { Some(Number(d, ..)) => d.to_int(); _ => 0 },
      active: match obj.get("active") { Some(True) => true; _ => false },
    }) }; _ => () } }
    if items.length() > 0 { Some(items) } else { None }
  }; _ => None }
}

fn try_parse_lessons(json_str : String) -> Array[LessonInfo]? {
  let val = @json.parse(json_str) catch { _ => return None }
  match val { Array(arr) => {
    let items : Array[LessonInfo] = []
    for i in arr { match i { Object(obj) => { items.push(LessonInfo::{
      id: match obj.get("id") { Some(String(s)) => s; _ => continue },
      topic_title: match obj.get("topic_title") { Some(String(s)) => Some(s); _ => None },
      week: match obj.get("week") { Some(Number(d, ..)) => Some(d.to_int()); _ => None },
      subject_name: match obj.get("subject_name") { Some(String(s)) => Some(s); _ => None },
      term_name: match obj.get("term_name") { Some(String(s)) => Some(s); _ => None },
      active: match obj.get("active") { Some(True) => Some(true); Some(False) => Some(false); _ => None },
    }) }; _ => () } }
    if items.length() > 0 { Some(items) } else { None }
  }; _ => None }
}

pub fn teacher_fetch_classes(cache : CacheSystem, config : SharedConfig, teacher_id : String, now : UInt64) -> Result[Array[TeacherClassGroup], AppError] {
  let cache_key = "class_groups"
  match cache.get(cache_key, now) { 
    Some(json_str) => match try_parse_class_groups(json_str) { Some(groups) => return Ok(groups); None => () }
    None => ()
  }
  let active_st = match admin_fetch_active_session_term_id(cache, config, now) { Ok(id) => id; Err(e) => return Err(e) }
  let result_arr = match db_teacher_fetch_class_groups(config, teacher_id, active_st) { Ok(arr) => arr; Err(e) => return Err(e) }
  let groups_map : Map[String, TeacherClassGroup] = Map([], capacity=0)
  for item in result_arr { match item { Object(obj) => {
    let edge_id = match obj.get("edge_id") { Some(String(s)) => s; _ => continue }; let class_level_id = match obj.get("class_level_id") { Some(String(s)) => s; _ => continue }
    let class_level_name = match obj.get("class_level_name") { Some(String(s)) => s; _ => continue }; let subject_id = match obj.get("subject_id") { Some(String(s)) => s; _ => continue }
    let subject_name = match obj.get("subject_name") { Some(String(s)) => s; _ => continue }; let subject_code = match obj.get("subject_code") { Some(String(s)) => Some(s); _ => None }
    let pair = TeacherSubjectPair::{ edge_id, class_level_id, class_level_name, subject_id, subject_name, subject_code }
    match groups_map.get(class_level_id) { Some(g) => { g.subjects.push(pair); groups_map[class_level_id] = g }; None => groups_map[class_level_id] = TeacherClassGroup::{ class_level_id, class_level_name, subjects: [pair] } }
  }; _ => () } }
  let groups_arr : Array[TeacherClassGroup] = []
  for pair in groups_map.iter() { let (_, g) = pair; groups_arr.push(g) }
  if groups_arr.length() == 0 { return Err(not_found_error("Class assignments")) }
  cache.set(cache_key, groups_arr.to_json().stringify(), CACHE_TTL, [], now)
  Ok(groups_arr)
}
pub fn teacher_fetch_terms(cache : CacheSystem, config : SharedConfig, now : UInt64) -> Result[Array[TermInfo], AppError] {
  let cache_key = "terms:all"
  match cache.get(cache_key, now) {
    Some(json_str) => match try_parse_terms(json_str) { Some(items) => return Ok(items); None => () }
    None => ()
  }
  let result_arr = match db_teacher_fetch_terms(config) { Ok(arr) => arr; Err(e) => return Err(e) }
  let terms : Array[TermInfo] = []
  for item in result_arr { match item { Object(obj) => { terms.push(TermInfo::{ id: match obj.get("id") { Some(String(s)) => s; _ => continue }, name: match obj.get("name") { Some(String(s)) => s; _ => continue }, sort_order: match obj.get("sort_order") { Some(Number(d, ..)) => d.to_int(); _ => 0 }, active: match obj.get("active") { Some(True) => true; _ => false } }) }; _ => () } }
  if terms.length() == 0 { return Err(not_found_error("Terms")) }
  cache.set(cache_key, terms.to_json().stringify(), CACHE_TTL, [], now)
  Ok(terms)
}
pub fn teacher_fetch_lessons(cache : CacheSystem, config : SharedConfig, class_level_id : String, subject_id : String, term_id : String, now : UInt64) -> Result[Array[LessonInfo], AppError] {
  let cache_key = "lessons:" + class_level_id + "|" + subject_id + "|" + term_id
  match cache.get(cache_key, now) {
    Some(json_str) => match try_parse_lessons(json_str) { Some(items) => return Ok(items); None => () }
    None => ()
  }
  let result_arr = match db_teacher_fetch_lessons(config, class_level_id, subject_id, term_id) { Ok(arr) => arr; Err(e) => return Err(e) }
  let lessons : Array[LessonInfo] = []
  for item in result_arr { match item { Object(obj) => { lessons.push(LessonInfo::{ id: match obj.get("id") { Some(String(s)) => s; _ => continue }, topic_title: match obj.get("topic_title") { Some(String(s)) => Some(s); _ => None }, week: match obj.get("week") { Some(Number(d, ..)) => Some(d.to_int()); _ => None }, subject_name: match obj.get("subject_name") { Some(String(s)) => Some(s); _ => None }, term_name: match obj.get("term_name") { Some(String(s)) => Some(s); _ => None }, active: match obj.get("active") { Some(True) => Some(true); Some(False) => Some(false); _ => None } }) }; _ => () } }
  if lessons.length() == 0 { return Err(not_found_error("Lessons")) }
  cache.set(cache_key, lessons.to_json().stringify(), CACHE_TTL, ["terms:all"], now)
  Ok(lessons)
}
pub fn teacher_toggle_lesson(cache : CacheSystem, config : SharedConfig, lesson_id : String, active : Bool) -> Result[Unit, AppError] {
  let meta_arr = match db_teacher_fetch_lesson_meta(config, lesson_id) { Ok(arr) => arr; Err(_) => return Err(not_found_error("Lesson")) }
  if meta_arr.length() == 0 { return Err(not_found_error("Lesson")) }
  let meta_obj = match meta_arr[0] { Object(obj) => obj; _ => return Err(not_found_error("Lesson")) }
  let class_level_id = match meta_obj.get("class_level_id") { Some(String(s)) => s; _ => return Err(not_found_error("Lesson class level")) }
  let subject_id = match meta_obj.get("subject_id") { Some(String(s)) => s; _ => return Err(not_found_error("Lesson subject")) }
  let term_id_val = match meta_obj.get("term_id") { Some(String(s)) => s; _ => return Err(not_found_error("Lesson term")) }
  match db_teacher_update_record_active(config, lesson_id, active) { Ok(_) => (); Err(e) => return Err(e) }
  cache.invalidate("terms:all")
  let up_arr = match db_admin_fetch_students_by_class_level(config, class_level_id) { Ok(arr) => arr; Err(e) => return Err(e) }
  let ak = config.auth_key.get() catch { _ => "" }
  if ak != "" {
    for item in up_arr { match item { Object(obj) => {
      let student_id = match obj.get("auth_id") { Some(String(s)) => s; _ => continue }
      let _ = StudentAgentClient::scoped(student_id, fn(c) raise @common.AgentError { c.trigger_invalidate_cache(ak, "lessons:" + subject_id + "|" + term_id_val) }) catch { _ => () }
      let _ = StudentAgentClient::scoped(student_id, fn(c) raise @common.AgentError { c.trigger_invalidate_cache(ak, "lesson:" + lesson_id) }) catch { _ => () }
    }; _ => () } }
  }
  Ok(())
}
