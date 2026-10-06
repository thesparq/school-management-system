#!/bin/bash
cat << 'INNER_EOF' >> agents/app-agents/admin_agent.mbt

///|
#derive.endpoint(post="/timetables")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::create_timetable(
  self : Self,
  incoming_key : String,
  body_json : String,
) -> Result[String, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  let payload : Json = match @json.parse?(body_json) {
    Ok(v) => v
    Err(_) => return Err(AppError::{ code: ValidationError, message: "Invalid JSON", debug: None }.to_json_string())
  }
  let payload_obj = match payload.as_object() {
    Some(v) => v
    None => return Err(AppError::{ code: ValidationError, message: "Expected JSON object", debug: None }.to_json_string())
  }
  let name = match payload_obj.get("name") {
    Some(String(s)) => s
    _ => return Err(AppError::{ code: ValidationError, message: "Missing name", debug: None }.to_json_string())
  }
  let desc = match payload_obj.get("description") {
    Some(String(s)) => s
    _ => ""
  }
  
  let term_query = "SELECT * FROM session_term WHERE active = true LIMIT 1"
  let term_res = surreal_query(self.config.value, term_query)
  let term_id = match term_res {
    Ok(arr) => if arr.length() > 0 {
      match arr[0].as_object().unwrap().get("id") {
        Some(String(s)) => s
        _ => return Err(AppError::{ code: InternalError, message: "No active term", debug: None }.to_json_string())
      }
    } else {
      return Err(AppError::{ code: InternalError, message: "No active term", debug: None }.to_json_string())
    }
    Err(e) => return Err(e.to_json_string())
  }
  
  let q = "CREATE timetables CONTENT { name: $name, description: $desc, session_term: $term, is_active: false }"
  let map = Map::new()
  map.set("name", name)
  map.set("desc", desc)
  map.set("term", term_id)
  
  let db_result = surreal_query(self.config.value, q, bindings=map)
  match db_result {
    Ok(json_arr) => Ok(json_arr.to_json().to_string())
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(put="/timetables/config")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::update_timetable_config(
  self : Self,
  incoming_key : String,
  body_json : String,
) -> Result[String, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  let payload : Json = match @json.parse?(body_json) {
    Ok(v) => v
    Err(_) => return Err(AppError::{ code: ValidationError, message: "Invalid JSON", debug: None }.to_json_string())
  }
  let payload_obj = match payload.as_object() {
    Some(v) => v
    None => return Err(AppError::{ code: ValidationError, message: "Expected JSON object", debug: None }.to_json_string())
  }
  let tt_id = match payload_obj.get("timetable_id") {
    Some(String(s)) => s
    _ => return Err(AppError::{ code: ValidationError, message: "Missing timetable_id", debug: None }.to_json_string())
  }
  let configs = match payload_obj.get("day_configs") {
    Some(Array(a)) => Array::make(a.length(), a[0]) 
    _ => return Err(AppError::{ code: ValidationError, message: "Missing day_configs", debug: None }.to_json_string())
  }
  
  let configs_json = payload_obj.get("day_configs").unwrap()
  let configs_json_str = configs_json.to_json().to_string()
  let tt_id_str = tt_id
  let q = "UPDATE type::thing('timetables', '" + tt_id_str + "') MERGE { day_configs: " + configs_json_str + " }"
  
  let db_result = surreal_query(self.config.value, q)
  match db_result {
    Ok(json_arr) => Ok(json_arr.to_json().to_string())
    Err(e) => Err(e.to_json_string())
  }
}
INNER_EOF

export PATH="$HOME/.moonup/toolchains/0.9.2+bbe2b338f/bin:$PATH"
cd agents && moon check
