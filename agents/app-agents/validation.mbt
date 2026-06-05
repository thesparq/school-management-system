///|
pub fn validate_username(username : String) -> Result[Unit, AppError] {
  if username.length() < 3 { return Err(AppError::{ code: ValidationError, message: "Username must be at least 3 characters", debug: None }) }
  Ok(())
}
pub fn validate_name(name : String) -> Result[Unit, AppError] {
  if name.length() < 1 { return Err(AppError::{ code: ValidationError, message: "Name is required", debug: None }) }
  Ok(())
}
pub fn validate_email(email : String) -> Result[Unit, AppError] {
  if !email.contains("@") || !email.contains(".") { return Err(AppError::{ code: ValidationError, message: "Email address is invalid", debug: None }) }
  Ok(())
}
pub fn validate_password(password : String) -> Result[Unit, AppError] {
  if password.length() < 8 { return Err(AppError::{ code: ValidationError, message: "Password must be at least 8 characters", debug: None }) }
  Ok(())
}
pub fn validate_role(role : String) -> Result[Unit, AppError] {
  if !["admin", "teacher", "student"].contains(role) { return Err(AppError::{ code: ValidationError, message: "Invalid role: " + role, debug: None }) }
  Ok(())
}
pub fn validate_class_level_exists(config : SharedConfig, class_level : String) -> Result[Unit, AppError] {
  match db_admin_fetch_class_level_by_name(config, class_level) {
    Ok(arr) => if arr.length() == 0 { Err(AppError::{ code: NotFound, message: "Class level not found: " + class_level, debug: None }) } else { Ok(()) }
    Err(e) => Err(e)
  }
}
