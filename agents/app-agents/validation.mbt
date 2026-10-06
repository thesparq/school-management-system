///|
pub fn validate_username(username : String) -> Result[Unit, AppError] {
  if username.length() < 3 {
    return Err(AppError::{
      code: ValidationError,
      message: "Username must be at least 3 characters",
      debug: None,
    })
  }
  Ok(())
}

///|
pub fn validate_name(name : String) -> Result[Unit, AppError] {
  if name.length() < 1 {
    return Err(AppError::{
      code: ValidationError,
      message: "Name is required",
      debug: None,
    })
  }
  Ok(())
}

///|
pub fn validate_email(email : String) -> Result[Unit, AppError] {
  if email.length() == 0 {
    return Err(AppError::{
      code: ValidationError,
      message: "Email address is required",
      debug: None,
    })
  }
  match email.find("@") {
    None =>
      return Err(AppError::{
        code: ValidationError,
        message: "Email address is invalid",
        debug: None,
      })
    Some(at_idx) => {
      if at_idx == 0 {
        return Err(AppError::{
          code: ValidationError,
          message: "Email address is invalid",
          debug: None,
        })
      }
      let domain = email[at_idx + 1:]
      match domain.find(".") {
        None =>
          return Err(AppError::{
            code: ValidationError,
            message: "Email address is invalid",
            debug: None,
          })
        Some(dot_idx) =>
          if dot_idx == 0 || dot_idx == domain.length() - 1 {
            return Err(AppError::{
              code: ValidationError,
              message: "Email address is invalid",
              debug: None,
            })
          }
      }
    }
  }
  Ok(())
}

///|
pub fn validate_password(password : String) -> Result[Unit, AppError] {
  if password.length() < 8 {
    return Err(AppError::{
      code: ValidationError,
      message: "Password must be at least 8 characters",
      debug: None,
    })
  }
  Ok(())
}

///|
pub fn validate_role(role : String) -> Result[Unit, AppError] {
  if !["admin", "teacher", "student", "parent"].contains(role) {
    return Err(AppError::{
      code: ValidationError,
      message: "Invalid role: " + role,
      debug: None,
    })
  }
  Ok(())
}

///|
pub fn validate_name_part(
  value : String,
  field_name : String,
) -> Result[Unit, AppError] {
  if value.length() < 1 {
    return Err(AppError::{
      code: ValidationError,
      message: field_name + " is required",
      debug: None,
    })
  }
  Ok(())
}

///|
pub fn validate_dob(dob : String) -> Result[Unit, AppError] {
  if dob.length() == 0 {
    return Err(AppError::{
      code: ValidationError,
      message: "Date of birth is required",
      debug: None,
    })
  }
  if dob.length() != 10 {
    return Err(AppError::{
      code: ValidationError,
      message: "Date of birth must be in YYYY-MM-DD format",
      debug: None,
    })
  }
  let year_str = dob[0:4]
  let month_str = dob[5:7]
  let day_str = dob[8:10]
  let sep1 = dob[4:5]
  let sep2 = dob[7:8]
  if sep1 != "-" || sep2 != "-" {
    return Err(AppError::{
      code: ValidationError,
      message: "Date of birth must be in YYYY-MM-DD format",
      debug: None,
    })
  }
  if year_str < "1900" || year_str > "2100" {
    return Err(AppError::{
      code: ValidationError,
      message: "Date of birth year must be between 1900 and 2100",
      debug: None,
    })
  }
  if month_str < "01" || month_str > "12" {
    return Err(AppError::{
      code: ValidationError,
      message: "Date of birth month must be between 1 and 12",
      debug: None,
    })
  }
  if day_str < "01" || day_str > "31" {
    return Err(AppError::{
      code: ValidationError,
      message: "Date of birth day is invalid",
      debug: None,
    })
  }
  Ok(())
}

///|
pub fn validate_passport_url(url : String) -> Result[Unit, AppError] {
  if url == "" {
    return Err(AppError::{
      code: ValidationError,
      message: "Passport is required",
      debug: None,
    })
  }
  if url.length() < 5 || !url.contains("://") {
    return Err(AppError::{
      code: ValidationError,
      message: "Passport URL must be a valid URL",
      debug: None,
    })
  }
  Ok(())
}

///|
pub fn validate_student_ids_not_empty(
  ids : Array[String],
) -> Result[Unit, AppError] {
  if ids.length() == 0 {
    return Err(AppError::{
      code: ValidationError,
      message: "At least one student must be selected",
      debug: None,
    })
  }
  Ok(())
}

///|
pub fn validate_class_level_exists(
  config : SharedConfig,
  class_level : String,
) -> Result[Unit, AppError] {
  match db_admin_fetch_class_level_by_name(config, class_level) {
    Ok(arr) =>
      if arr.length() == 0 {
        Err(AppError::{
          code: NotFound,
          message: "Class level not found: " + class_level,
          debug: None,
        })
      } else {
        Ok(())
      }
    Err(e) => Err(e)
  }
}
