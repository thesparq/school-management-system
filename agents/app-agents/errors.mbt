///|
/// Structured error types for the entire agent application.
/// Replaces ad-hoc string errors with typed codes that the frontend
/// can map to HTTP status codes and user-facing messages.

///|
pub enum ErrorCode {
  ValidationError
  AuthFailure
  NotFound
  AlreadyExists
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
    AlreadyExists => "ALREADY_EXISTS"
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
/// Escapes a string for safe inclusion in a JSON string literal.
/// Used by AppError serialization and other contexts.
pub fn escape_json_string(s : String) -> String {
  s
  .replace(old="\\", new="\\\\")
  .replace(old="\"", new="\\\"")
  .replace(old="\n", new="\\n")
  .replace(old="\r", new="\\r")
  .replace(old="\t", new="\\t")
}
