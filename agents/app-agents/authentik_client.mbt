///|
fn authentik_request(config : SharedConfig, http_method : @http_types.Method, api_path : String, body_json : FixedArray[Byte]?) -> Result[(UInt, String), AppError] {
  let cfg = match resolve_authentik_cfg(config) { Ok(c) => c; Err(e) => return Err(e) }
  let content_length = match body_json { Some(data) => data.length().to_string(); None => "0" }
  let headers = match build_headers([("Authorization", "Bearer " + cfg.api_token), ("Content-Type", "application/json"), ("Accept", "*/*"), ("Content-Length", content_length)]) { Ok(h) => h; Err(e) => return Err(AppError::{ code: AuthentikError, message: e, debug: None }) }
  match http_request(cfg.host, http_method, @http_types.Https, api_path, headers, body_json) { Ok((status, body)) => Ok((status, body)); Err(e) => Err(AppError::{ code: AuthentikError, message: e, debug: None }) }
}
fn check_authentik_status(status : UInt, body : String, operation : String) -> Result[Unit, AppError] {
  if status < 200 || status >= 300 { Err(AppError::{ code: AuthentikError, message: operation + ": HTTP " + status.to_string(), debug: Some(body) }) } else { Ok(()) }
}
pub fn authentik_create_user(config : SharedConfig, username : String, name : String, email : String, password : String, is_active : Bool, group_pk : String) -> Result[(Int, String), AppError] {
  let body = "{\"username\":\"" + escape_json_string(username) + "\",\"name\":\"" + escape_json_string(name) + "\",\"email\":\"" + escape_json_string(email) + "\",\"password\":\"" + escape_json_string(password) + "\",\"is_active\":" + (if is_active { "true" } else { "false" }) + (if group_pk != "" { ",\"groups\":[\"" + escape_json_string(group_pk) + "\"]" } else { "" }) + ",\"path\":\"users\"}"
  let (status, resp_body) = match authentik_request(config, @http_types.Post, "/api/v3/core/users/", Some(@utf8.encode(body).to_fixedarray())) { Ok(r) => r; Err(e) => return Err(e) }
  match check_authentik_status(status, resp_body, "Authentik create") { Ok(_) => (); Err(e) => return Err(e) }
  let parsed = @json.parse(resp_body) catch { _ => return Err(AppError::{ code: AuthentikError, message: "Authentik create: parse response failed", debug: None }) }
  let obj = match parsed { Object(o) => o; _ => return Err(AppError::{ code: AuthentikError, message: "Authentik create: response not an object", debug: None }) }
  let pk = match obj.get("pk") { Some(Number(n, ..)) => n.to_int(); _ => return Err(AppError::{ code: AuthentikError, message: "Authentik create: pk missing", debug: None }) }
  let uuid = match obj.get("uuid") { Some(String(s)) => s; _ => return Err(AppError::{ code: AuthentikError, message: "Authentik create: uuid missing", debug: None }) }
  Ok((pk, uuid))
}
pub fn authentik_set_password(config : SharedConfig, pk : Int, password : String) -> Result[Unit, AppError] {
  let body = "{\"password\":\"" + escape_json_string(password) + "\"}"
  let (status, resp_body) = match authentik_request(config, @http_types.Post, "/api/v3/core/users/" + pk.to_string() + "/set_password/", Some(@utf8.encode(body).to_fixedarray())) { Ok(r) => r; Err(e) => return Err(e) }
  check_authentik_status(status, resp_body, "Authentik set_password")
}
pub fn authentik_update_profile(config : SharedConfig, pk : Int, username : String, name : String, email : String) -> Result[Unit, AppError] {
  let body = "{\"username\":\"" + escape_json_string(username) + "\",\"name\":\"" + escape_json_string(name) + "\",\"email\":\"" + escape_json_string(email) + "\"}"
  let (status, resp_body) = match authentik_request(config, @http_types.Patch, "/api/v3/core/users/" + pk.to_string() + "/", Some(@utf8.encode(body).to_fixedarray())) { Ok(r) => r; Err(e) => return Err(e) }
  check_authentik_status(status, resp_body, "Authentik update profile")
}
pub fn authentik_set_active(config : SharedConfig, pk : Int, is_active : Bool) -> Result[Unit, AppError] {
  let body = "{\"is_active\":" + (if is_active { "true" } else { "false" }) + "}"
  let (status, resp_body) = match authentik_request(config, @http_types.Patch, "/api/v3/core/users/" + pk.to_string() + "/", Some(@utf8.encode(body).to_fixedarray())) { Ok(r) => r; Err(e) => return Err(e) }
  check_authentik_status(status, resp_body, "Authentik set_active")
}
pub fn authentik_add_to_group(config : SharedConfig, group_pk : String, user_pk : Int) -> Result[Unit, AppError] {
  let body = "{\"pk\":" + user_pk.to_string() + "}"
  let (status, resp_body) = match authentik_request(config, @http_types.Post, "/api/v3/core/groups/" + group_pk + "/add_user/", Some(@utf8.encode(body).to_fixedarray())) { Ok(r) => r; Err(e) => return Err(e) }
  check_authentik_status(status, resp_body, "Authentik add to group")
}
pub fn authentik_remove_from_group(config : SharedConfig, group_pk : String, user_pk : Int) -> Result[Unit, AppError] {
  let body = "{\"pk\":" + user_pk.to_string() + "}"
  let (status, resp_body) = match authentik_request(config, @http_types.Post, "/api/v3/core/groups/" + group_pk + "/remove_user/", Some(@utf8.encode(body).to_fixedarray())) { Ok(r) => r; Err(e) => return Err(e) }
  check_authentik_status(status, resp_body, "Authentik remove from group")
}
pub fn authentik_delete_user(config : SharedConfig, pk : Int) -> Result[Unit, AppError] {
  let (status, resp_body) = match authentik_request(config, @http_types.Delete, "/api/v3/core/users/" + pk.to_string() + "/", None) { Ok(r) => r; Err(e) => return Err(e) }
  check_authentik_status(status, resp_body, "Authentik delete")
}
pub fn authentik_get_group_pk_by_name(config : SharedConfig, name : String) -> Result[String, AppError] {
  let lower_name = name.to_lower()
  let (status, resp_body) = match authentik_request(config, @http_types.Get, "/api/v3/core/groups/?page_size=100&search=" + url_encode(name), None) { Ok(r) => r; Err(e) => return Err(e) }
  match check_authentik_status(status, resp_body, "Authentik get groups") { Ok(_) => (); Err(e) => return Err(e) }
  let parsed = @json.parse(resp_body) catch { _ => return Err(AppError::{ code: AuthentikError, message: "Authentik get groups: parse failed", debug: None }) }
  let obj = match parsed { Object(o) => o; _ => return Err(AppError::{ code: AuthentikError, message: "Authentik get groups: response not an object", debug: None }) }
  let results = match obj.get("results") { Some(Array(arr)) => arr; _ => return Err(not_found_error("Group: " + name)) }
  for item in results { match item { Object(group_obj) => { let group_name = match group_obj.get("name") { Some(String(s)) => s; _ => continue }; if group_name.to_lower() == lower_name { match group_obj.get("pk") { Some(String(pk)) => return Ok(pk); _ => continue } } }; _ => () } }
  Err(not_found_error("Group: " + name))
}
