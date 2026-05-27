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
/// Durable per-student agent.
/// Identified by student_id — one instance per student.
#derive.agent
struct StudentAgent {
  config : @config.Config[SurrealConfig]
  student_id : String
  mut profile : StudentProfile?
  subjects : Map[String, SubjectInfo]
}

///|
fn StudentAgent::new(
  student_id : String,
  config : @config.Config[SurrealConfig],
) -> StudentAgent {
  { config, student_id, profile: None, subjects: Map::new() }
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

  let cl_sql = "SELECT VALUE id FROM class_levels WHERE name = $class_level LIMIT 1"
  let cl_raw = match surreal_query(self.config, cl_sql, bindings={ "class_level": class_level }) {
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

  let subj_sql = "SELECT subject_id.id, subject_id.name, subject_id.code " +
    "FROM class_subjects WHERE class_level_id = " +
    cl_id +
    " AND active = true ORDER BY subject_id.name ASC"
  let subj_raw = match surreal_query(self.config, subj_sql) {
    Ok(body) => body
    Err(e) => return "ERROR: query subjects failed: " + e
  }

  let parsed = @json.parse(subj_raw) catch {
    _ => return "ERROR: parse subjects response failed"
  }
  let result_arr = match parsed {
    Array(a) => {
      if a.length() == 0 {
        return "ERROR: subjects response empty"
      }
      match a[0] {
        Object(obj) =>
          match obj.get("result") {
            Some(r) =>
              match r {
                Array(arr) => arr
                _ => return "ERROR: subjects result not an array"
              }
            None => return "ERROR: subjects result missing"
          }
        _ => return "ERROR: subjects element not an object"
      }
    }
    _ => return "ERROR: subjects response not an array"
  }

  for item in result_arr {
    match item {
      Object(obj) =>
        match obj.get("subject_id") {
          Some(subj_val) =>
            match subj_val {
              Object(subj) => {
                let id = match subj.get("id") {
                  Some(v) =>
                    match v {
                      String(s) => s
                      _ => continue
                    }
                  None => continue
                }
                let name = match subj.get("name") {
                  Some(v) =>
                    match v {
                      String(s) => s
                      _ => continue
                    }
                  None => continue
                }
                let code = match subj.get("code") {
                  Some(v) =>
                    match v {
                      String(s) => Some(s)
                      _ => None
                    }
                  None => None
                }
                self.subjects.set(id, SubjectInfo::{ id, name, code })
              }
              _ => ()
            }
          None => ()
        }
      _ => ()
    }
  }

  "OK"
}

///|
/// Returns this student's subjects as a JSON array string.
/// Returns an empty array if the student has not been initialized.
pub fn StudentAgent::get_subjects(self : Self) -> String {
  let items = self.subjects
    .iter()
    .map(fn(pair) {
      let (_id, info) = pair
      let code_str = match info.code {
        None => "null"
        Some(c) => "\"" + c.replace(old="\"", new="\\\"") + "\""
      }
      "{\"id\":\"" +
      info.id.replace(old="\"", new="\\\"") +
      "\"," +
      "\"name\":\"" +
      info.name.replace(old="\"", new="\\\"") +
      "\"," +
      "\"code\":" +
      code_str +
      "}"
    })
    .collect()
  "[" + items.join(",") + "]"
}
