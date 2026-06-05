///|
pub enum ErrorCode {
  ValidationError
  AuthFailure
  NotFound
  NotInitialized
  AuthentikError
  SurrealDBError
  InternalError
}

///|
pub struct AppError {
  code : ErrorCode
  message : String
  detail : String?
}

///|
fn AppError::to_code_string(self : AppError) -> String {
  match self.code {
    ValidationError => "VALIDATION_ERROR"
    AuthFailure => "AUTH_FAILURE"
    NotFound => "NOT_FOUND"
    NotInitialized => "NOT_INITIALIZED"
    AuthentikError => "AUTHENTIK_ERROR"
    SurrealDBError => "SURREALDB_ERROR"
    InternalError => "INTERNAL_ERROR"
  }
}

///|
pub fn AppError::to_json_string(self : AppError) -> String {
  let detail_json = match self.detail {
    Some(d) => "\"" + escape_json_string(d) + "\""
    None => "null"
  }
  "{\"error\":{\"code\":\"" +
  self.to_code_string() +
  "\",\"message\":\"" +
  escape_json_string(self.message) +
  "\",\"detail\":" +
  detail_json +
  "}}"
}

///|
pub fn escape_json_string(s : String) -> String {
  s.replace(old="\\", new="\\\\").replace(old="\"", new="\\\"").replace(old="\n", new="\\n").replace(old="\r", new="\\r").replace(old="\t", new="\\t")
}

///|
pub fn surreal_error(body : String, sql : String?) -> AppError {
  AppError::{ code: SurrealDBError, message: "SurrealDB query failed", detail: Some(match sql { Some(s) => "SQL: " + s + " | Response: " + body; None => "Response: " + body }) }
}

pub fn not_found_error(resource : String) -> AppError {
  AppError::{ code: NotFound, message: resource + " not found", detail: None }
}

///|
pub fn validation_error(msg : String) -> AppError {
  AppError::{ code: ValidationError, message: msg, detail: None }
}
