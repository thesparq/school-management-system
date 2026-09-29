///|
fn matrix_request(
  config: SharedConfig,
  http_method: @http_types.Method,
  api_path: String,
  body_json: FixedArray[Byte]?
) -> Result[(UInt, String), AppError] {
  let cfg = match resolve_matrix_cfg(config) {
    Ok(c) => c
    Err(e) => return Err(e)
  }
  let content_length = match body_json {
    Some(data) => data.length().to_string()
    None => "0"
  }
  let headers = match build_headers([
    ("Authorization", "Bearer " + cfg.admin_token),
    ("Content-Type", "application/json"),
    ("Accept", "*/*"),
    ("Content-Length", content_length),
  ]) {
    Ok(h) => h
    Err(e) => return Err(AppError::{ code: InternalError, message: e, debug: None })
  }
  
  let mut host = cfg.host
  if host.starts_with("https://") {
    host = host.substring(start=8)
  } else if host.starts_with("http://") {
    host = host.substring(start=7)
  }
  
  let auth_host = if host.contains(":") { host } else { host + ":443" }
  match http_request(
    auth_host,
    http_method,
    @http_types.Scheme::Https,
    api_path,
    headers,
    body_json
  ) {
    Ok((status, body)) => Ok((status, body))
    Err(e) => Err(AppError::{ code: InternalError, message: e, debug: None })
  }
}

///|
pub fn matrix_get_user_id(user_uuid: String) -> String {
  "@" + user_uuid + ":matrix.johnethel.school"
}

///|
pub fn matrix_create_user(
  config: SharedConfig,
  user_uuid: String,
  display_name: String
) -> Result[Unit, AppError] {
  let user_id = matrix_get_user_id(user_uuid)
  let api_path = "/_synapse/admin/v2/users/" + user_id
  
  // Random password
  let password = "tmp" + user_uuid.substring(start=0, end=8)
  
  let body_json_str = "{\"displayname\":\"" + escape_json_string(display_name) +
                      "\",\"password\":\"" + escape_json_string(password) +
                      "\",\"admin\":false}"
  
  let result = matrix_request(
    config, 
    @http_types.Method::Put, 
    api_path, 
    Some(str_to_bytes(body_json_str))
  )
  
  let (status, body_str) = match result {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  
  if status >= 200 && status < 300 {
    Ok(())
  } else {
    if body_str.contains("already taken") {
      return Ok(())
    }
    Err(AppError::{
      code: InternalError,
      message: "Matrix API error: " + status.to_string(),
      debug: Some(body_str)
    })
  }
}

///|
pub fn matrix_get_user_token(
  config: SharedConfig,
  user_uuid: String
) -> Result[String, AppError] {
  let user_id = matrix_get_user_id(user_uuid)
  let api_path = "/_synapse/admin/v1/users/" + user_id + "/login"
  
  let result = matrix_request(
    config,
    @http_types.Method::Post,
    api_path,
    Some(str_to_bytes("{}"))
  )
  let (status, body_str) = match result {
    Ok(r) => r
    Err(e) => return Err(e)
  }

  if status >= 200 && status < 300 {
    let json = @json.parse(body_str) catch {
      _ => return Err(AppError::{
        code: InternalError,
        message: "Matrix returned invalid JSON",
        debug: Some(body_str)
      })
    }
    match json {
      Object(map) => {
        match map.get("access_token") {
          Some(String(token)) => return Ok(token)
          _ => ()
        }
      }
      _ => ()
    }
    Err(AppError::{
      code: InternalError,
      message: "Matrix login response missing token",
      debug: Some(body_str)
    })
  } else {
    Err(AppError::{
      code: InternalError,
      message: "Matrix login error: " + status.to_string(),
      debug: Some(body_str)
    })
  }
}

///|
pub fn matrix_create_room(
  config: SharedConfig,
  room_name: String
) -> Result[String, AppError] {
  let api_path = "/_matrix/client/v3/createRoom"
  
  let body_json_str = "{\"name\":\"" + escape_json_string(room_name) +
                      "\",\"visibility\":\"private\",\"preset\":\"private_chat\"}"
  
  let result = matrix_request(
    config,
    @http_types.Method::Post,
    api_path,
    Some(str_to_bytes(body_json_str))
  )
  let (status, body_str) = match result {
    Ok(r) => r
    Err(e) => return Err(e)
  }

  if status >= 200 && status < 300 {
    let json = @json.parse(body_str) catch {
      _ => return Err(AppError::{
        code: InternalError,
        message: "Matrix returned invalid JSON",
        debug: Some(body_str)
      })
    }
    match json {
      Object(map) => {
        match map.get("room_id") {
          Some(String(room_id)) => return Ok(room_id)
          _ => ()
        }
      }
      _ => ()
    }
    Err(AppError::{
      code: InternalError,
      message: "Matrix create room response missing room_id",
      debug: Some(body_str)
    })
  } else {
    Err(AppError::{
      code: InternalError,
      message: "Matrix create room error: " + status.to_string(),
      debug: Some(body_str)
    })
  }
}

///|
pub fn matrix_force_join_user(
  config: SharedConfig,
  room_id: String,
  user_uuid: String
) -> Result[Unit, AppError] {
  let user_id = matrix_get_user_id(user_uuid)
  let api_path = "/_synapse/admin/v1/join/" + room_id
  
  let body_json_str = "{\"user_id\":\"" + escape_json_string(user_id) + "\"}"
  
  let result = matrix_request(
    config,
    @http_types.Method::Post,
    api_path,
    Some(str_to_bytes(body_json_str))
  )
  let (status, body_str) = match result {
    Ok(r) => r
    Err(e) => return Err(e)
  }

  if status >= 200 && status < 300 {
    Ok(())
  } else {
    if body_str.contains("is already in the room") {
      return Ok(())
    }
    Err(AppError::{
      code: InternalError,
      message: "Matrix force join error: " + status.to_string(),
      debug: Some(body_str)
    })
  }
}

///|
pub fn matrix_send_notification(
  config: SharedConfig,
  room_id: String,
  message: String
) -> Result[Unit, AppError] {
  let txn_id = "txn_" + message.length().to_string()
  let api_path = "/_matrix/client/v3/rooms/" + room_id + "/send/m.room.message/" + txn_id
  
  let body_json_str = "{\"msgtype\":\"m.text\",\"body\":\"" + escape_json_string(message) + "\"}"
  
  let result = matrix_request(
    config,
    @http_types.Method::Put,
    api_path,
    Some(str_to_bytes(body_json_str))
  )
  let (status, body_str) = match result {
    Ok(r) => r
    Err(e) => return Err(e)
  }

  if status >= 200 && status < 300 {
    Ok(())
  } else {
    Err(AppError::{
      code: InternalError,
      message: "Matrix send message error: " + status.to_string(),
      debug: Some(body_str)
    })
  }
}
