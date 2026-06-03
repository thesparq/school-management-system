///|
/// Input validation functions for user CRUD operations.
/// Each returns AppError::ValidationError on failure.

///|
pub fn validate_username(username : String) -> Result[Unit, AppError] {
  if username.length() < 3 {
    return Err(
      AppError::{
        code: ValidationError,
        message: "Username must be at least 3 characters",
        detail: None,
      },
    )
  }
  Ok(())
}

///|
pub fn validate_name(name : String) -> Result[Unit, AppError] {
  if name.length() < 1 {
    return Err(
      AppError::{
        code: ValidationError,
        message: "Name is required",
        detail: None,
      },
    )
  }
  Ok(())
}

///|
pub fn validate_email(email : String) -> Result[Unit, AppError] {
  if !email.contains("@") || !email.contains(".") {
    return Err(
      AppError::{
        code: ValidationError,
        message: "Email address is invalid",
        detail: Some(email),
      },
    )
  }
  Ok(())
}

///|
pub fn validate_password(password : String) -> Result[Unit, AppError] {
  if password.length() < 8 {
    return Err(
      AppError::{
        code: ValidationError,
        message: "Password must be at least 8 characters",
        detail: None,
      },
    )
  }
  Ok(())
}

///|
pub fn validate_role(role : String) -> Result[Unit, AppError] {
  if !["admin", "teacher", "student"].contains(role) {
    return Err(
      AppError::{
        code: ValidationError,
        message: "Invalid role: " + role,
        detail: None,
      },
    )
  }
  Ok(())
}

///|
pub fn validate_class_level_exists(
  config : SharedConfig,
  class_level : String,
) -> Result[Unit, AppError] {
  let sql = "SELECT id FROM class_levels WHERE name = '" +
    escape_surreal_string(class_level) +
    "' LIMIT 1"
  match surreal_query(config, sql) {
    Ok(arr) => {
      if arr.length() == 0 {
        Err(
          AppError::{
            code: NotFound,
            message: "Class level not found: " + class_level,
            detail: None,
          },
        )
      } else {
        Ok(())
      }
    }
    Err(e) => Err(e)
  }
}
