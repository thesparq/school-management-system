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
  if !["admin", "teacher", "student", "parent"].contains(role) { return Err(AppError::{ code: ValidationError, message: "Invalid role: " + role, debug: None }) }
  Ok(())
}
pub fn validate_name_part(value : String, field_name : String) -> Result[Unit, AppError] {
  if value.length() < 1 { return Err(AppError::{ code: ValidationError, message: field_name + " is required", debug: None }) }
  Ok(())
}
pub fn validate_dob(dob : String) -> Result[Unit, AppError] {
  if dob.length() == 0 { return Err(AppError::{ code: ValidationError, message: "Date of birth is required", debug: None }) }
  if dob.length() < 10 { return Err(AppError::{ code: ValidationError, message: "Date of birth must be a valid date", debug: None }) }
  Ok(())
}
pub fn validate_passport_url(url : String) -> Result[Unit, AppError] {
  if url.length() < 5 || !url.contains("://") { return Err(AppError::{ code: ValidationError, message: "Passport is required", debug: None }) }
  Ok(())
}
pub fn validate_student_ids_not_empty(ids : Array[String]) -> Result[Unit, AppError] {
  if ids.length() == 0 { return Err(AppError::{ code: ValidationError, message: "At least one student must be selected", debug: None }) }
  Ok(())
}
pub fn validate_class_level_exists(config : SharedConfig, class_level : String) -> Result[Unit, AppError] {
  match db_admin_fetch_class_level_by_name(config, class_level) {
    Ok(arr) => if arr.length() == 0 { Err(AppError::{ code: NotFound, message: "Class level not found: " + class_level, debug: None }) } else { Ok(()) }
    Err(e) => Err(e)
  }
}
