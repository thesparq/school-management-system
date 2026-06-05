pub fn teacher_fetch_classes(cache : CacheSystem, config : SharedConfig, teacher_id : String, now : UInt64) -> Result[Array[TeacherClassGroup], AppError] {
  let cache_key = "class_groups"
  match cache.get(cache_key, now) { Some(json_str) => {
    let val = @json.parse(json_str) catch { _ =>
      return Err(AppError::{ code: InternalError, message: "Corrupt cache data for class_groups", detail: None })
    }
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
      if groups.length() > 0 { return Ok(groups) }
    }; _ => () }
  }; None => () }
  let active_st = match admin_fetch_active_session_term(cache, config, now) { Ok(id) => id; Err(e) => return Err(e) }
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
  cache.set(cache_key, groups_arr.to_json().stringify(), 600UL, [], now)
  Ok(groups_arr)
}
pub fn teacher_fetch_terms(config : SharedConfig) -> Result[Array[TermInfo], AppError] {
  let result_arr = match db_teacher_fetch_terms(config) { Ok(arr) => arr; Err(e) => return Err(e) }
  let terms : Array[TermInfo] = []
  for item in result_arr { match item { Object(obj) => { terms.push(TermInfo::{ id: match obj.get("id") { Some(String(s)) => s; _ => continue }, name: match obj.get("name") { Some(String(s)) => s; _ => continue }, sort_order: match obj.get("sort_order") { Some(Number(d, ..)) => d.to_int(); _ => 0 }, active: match obj.get("active") { Some(True) => true; _ => false } }) }; _ => () } }
  if terms.length() == 0 { return Err(not_found_error("Terms")) }
  Ok(terms)
}
pub fn teacher_fetch_lessons(config : SharedConfig, class_level_id : String, subject_id : String, term_id : String) -> Result[Array[LessonInfo], AppError] {
  let result_arr = match db_teacher_fetch_lessons(config, class_level_id, subject_id, term_id) { Ok(arr) => arr; Err(e) => return Err(e) }
  let lessons : Array[LessonInfo] = []
  for item in result_arr { match item { Object(obj) => { lessons.push(LessonInfo::{ id: match obj.get("id") { Some(String(s)) => s; _ => continue }, topic_title: match obj.get("topic_title") { Some(String(s)) => Some(s); _ => None }, week: match obj.get("week") { Some(Number(d, ..)) => Some(d.to_int()); _ => None }, subject_name: match obj.get("subject_name") { Some(String(s)) => Some(s); _ => None }, term_name: match obj.get("term_name") { Some(String(s)) => Some(s); _ => None }, active: match obj.get("active") { Some(True) => Some(true); Some(False) => Some(false); _ => None } }) }; _ => () } }
  if lessons.length() == 0 { return Err(not_found_error("Lessons")) }
  Ok(lessons)
}
pub fn teacher_toggle_term(cache : CacheSystem, config : SharedConfig, teacher_id : String, term_id : String, active : Bool, now : UInt64) -> Result[Unit, AppError] {
  match db_teacher_update_record_active(config, term_id, active) { Ok(_) => (); Err(e) => return Err(e) }
  let active_st = match admin_fetch_active_session_term(cache, config, now) { Ok(id) => id; Err(_) => return Ok(()) }
  let cl_arr = match db_teacher_fetch_class_levels_for_teacher(config, teacher_id, active_st) { Ok(arr) => arr; Err(_) => return Ok(()) }
  let class_levels : Array[String] = []
  for item in cl_arr { match item { String(cl) => class_levels.push(cl); _ => () } }
  if class_levels.length() == 0 { return Ok(()) }
  let up_arr = match db_admin_fetch_students_by_class_levels(config, class_levels) { Ok(arr) => arr; Err(_) => return Ok(()) }
  let auth_key_val = config.auth_key.get() catch { _ => "" }
  if auth_key_val != "" {
    for item in up_arr { match item { Object(obj) => {
      let student_id = match obj.get("auth_id") { Some(String(s)) => s; _ => continue }
      let cl = match obj.get("class_level") { Some(String(s)) => s; _ => continue }
      let _ = StudentAgentClient::scoped(student_id, fn(c) raise @common.AgentError { c.trigger_invalidate_cache(auth_key_val, "terms:" + cl) }) catch { _ => () }
    }; _ => () } }
  }
  Ok(())
}
pub fn teacher_toggle_lesson(config : SharedConfig, lesson_id : String, active : Bool) -> Result[Unit, AppError] {
  let meta_arr = match db_teacher_fetch_lesson_meta(config, lesson_id) { Ok(arr) => arr; Err(_) => return Err(not_found_error("Lesson")) }
  if meta_arr.length() == 0 { return Err(not_found_error("Lesson")) }
  let class_level_id = match meta_arr[0] { Object(obj) => match obj.get("class_level_id") { Some(String(s)) => s; _ => return Err(not_found_error("Lesson class level")) }; _ => return Err(not_found_error("Lesson")) }
  let subject_id = match meta_arr[0] { Object(obj) => match obj.get("subject_id") { Some(String(s)) => s; _ => return Err(not_found_error("Lesson subject")) }; _ => return Err(not_found_error("Lesson")) }
  let term_id_val = match meta_arr[0] { Object(obj) => match obj.get("term_id") { Some(String(s)) => s; _ => return Err(not_found_error("Lesson term")) }; _ => return Err(not_found_error("Lesson")) }
  match db_teacher_update_record_active(config, lesson_id, active) { Ok(_) => (); Err(e) => return Err(e) }
  let up_arr = match db_admin_fetch_students_by_class_level(config, class_level_id) { Ok(arr) => arr; Err(_) => return Ok(()) }
  let auth_key_val = config.auth_key.get() catch { _ => "" }
  if auth_key_val != "" {
    for item in up_arr { match item { Object(obj) => {
      let student_id = match obj.get("auth_id") { Some(String(s)) => s; _ => continue }
      let _ = StudentAgentClient::scoped(student_id, fn(c) raise @common.AgentError { c.trigger_invalidate_cache(auth_key_val, "lessons:" + subject_id + "|" + term_id_val) }) catch { _ => () }
      let _ = StudentAgentClient::scoped(student_id, fn(c) raise @common.AgentError { c.trigger_invalidate_cache(auth_key_val, "lesson:" + lesson_id) }) catch { _ => () }
    }; _ => () } }
  }
  Ok(())
}
