///|
pub fn require_auth(config : SharedConfig, incoming_key : String) -> Result[Unit, AppError] {
  let expected = config.auth_key.get() catch { _ => return Err(AppError::{ code: InternalError, message: "Failed to read auth key configuration", detail: None }) }
  if incoming_key != expected { return Err(AppError::{ code: AuthFailure, message: "Authentication failed", detail: None }) }
  Ok(())
}
