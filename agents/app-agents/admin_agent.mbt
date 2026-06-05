///|
#derive.agent
#derive.mount("/admin/{_admin_id}")
struct AdminAgent {
  _admin_id : String
  config : @config.Config[SharedConfig]
  cache : CacheSystem
}

///|
fn AdminAgent::new(
  _admin_id : String,
  config : @config.Config[SharedConfig],
) -> AdminAgent {
  { _admin_id, config, cache: CacheSystem::new() }
}

///|
#derive.endpoint(get="/ping")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::ping(self : Self, incoming_key : String) -> String {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return e.to_json_string()
    Ok(_) => ()
  }
  "admin online"
}

///|
#derive.endpoint(get="/get-profile?target_user_id={target_user_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::get_profile(
  self : Self,
  incoming_key : String,
  target_user_id : String,
) -> Result[UserProfileInfo, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match admin_fetch_profile(self.config.value, target_user_id) {
    Ok(p) => Ok(p)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(post="/soft-delete-profile?target_user_id={target_user_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::soft_delete_profile(
  self : Self,
  incoming_key : String,
  target_user_id : String,
) -> Result[String, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match admin_soft_delete_profile(self.config.value, target_user_id) {
    Ok(_) => Ok("ok")
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/class-levels")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::get_class_levels(
  self : Self,
  incoming_key : String,
) -> Result[Array[ClassLevelInfo], String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match admin_fetch_class_levels(self.config.value) {
    Ok(arr) => Ok(arr)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/class-subjects")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::get_available_class_subjects(
  self : Self,
  incoming_key : String,
) -> Result[Array[TeacherSubjectPair], String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match admin_fetch_class_subjects(self.config.value) {
    Ok(pairs) => Ok(pairs)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/teacher/subjects?target_teacher_id={target_teacher_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::get_teacher_subjects(
  self : Self,
  incoming_key : String,
  target_teacher_id : String,
) -> Result[Array[TeacherSubjectPair], String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match admin_fetch_teacher_subjects(self.config.value, target_teacher_id) {
    Ok(pairs) => Ok(pairs)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(post="/teacher/subjects?target_teacher_id={target_teacher_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
#derive.endpoint_body("pairs_json")
pub fn AdminAgent::set_teacher_subjects(
  self : Self,
  incoming_key : String,
  target_teacher_id : String,
  pairs_json : String,
) -> Result[String, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  let now = @wallClock.now().seconds
  match
    admin_set_teacher_subjects(
      self.cache,
      self.config.value,
      target_teacher_id,
      pairs_json,
      now,
    ) {
    Ok(msg) => Ok(msg)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/active-session-term")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::get_active_session_term(
  self : Self,
  incoming_key : String,
) -> Result[SessionTermDetail, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match admin_fetch_active_session_term_detail(self.config.value) {
    Ok(detail) => Ok(detail)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/terms")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::get_terms(
  self : Self,
  incoming_key : String,
) -> Result[Array[TermSimple], String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match admin_fetch_terms(self.config.value) {
    Ok(arr) => Ok(arr)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(get="/session-terms")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::get_session_terms(
  self : Self,
  incoming_key : String,
) -> Result[Array[SessionTermInfo], String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  let now = @wallClock.now().seconds
  match admin_fetch_session_terms(self.cache, self.config.value, now) {
    Ok(arr) => Ok(arr)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(post="/create-session-term")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::create_session_term(
  self : Self,
  incoming_key : String,
  body_json : String,
) -> Result[SessionTermInfo, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match admin_create_session_term(self.cache, self.config.value, body_json) {
    Ok(info) => Ok(info)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(post="/activate-session-term?session_term_id={session_term_id}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::activate_session_term(
  self : Self,
  incoming_key : String,
  session_term_id : String,
) -> Result[String, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match
    admin_activate_session_term(self.cache, self.config.value, session_term_id) {
    Ok(_) => Ok("ok")
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(post="/invalidate-cache?key={key}")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::invalidate_cache(
  self : Self,
  incoming_key : String,
  key : String,
) -> String {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return e.to_json_string()
    Ok(_) => ()
  }
  if key == "all" {
    self.cache.invalidate_all()
  } else {
    self.cache.invalidate(key)
  }
  "OK"
}

///|
#derive.endpoint(post="/create-user")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::create_user_in_authentik(
  self : Self,
  incoming_key : String,
  body_json : String,
) -> Result[CreateUserResponse, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match admin_create_user(self.config.value, body_json) {
    Ok(r) => Ok(r)
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(post="/edit-user")
// #derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::edit_user_in_authentik(
  self : Self,
  incoming_key : String,
  body_json : String,
) -> Result[String, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match admin_edit_user(self.config.value, body_json) {
    Ok(_) => Ok("ok")
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(post="/delete-user")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::delete_user_in_authentik(
  self : Self,
  incoming_key : String,
  body_json : String,
) -> Result[String, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match admin_delete_user(self.config.value, body_json) {
    Ok(_) => Ok("ok")
    Err(e) => Err(e.to_json_string())
  }
}

///|
#derive.endpoint(post="/set-user-active")
#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")
pub fn AdminAgent::set_user_active_status(
  self : Self,
  incoming_key : String,
  body_json : String,
) -> Result[String, String] {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return Err(e.to_json_string())
    Ok(_) => ()
  }
  match admin_set_user_active(self.config.value, body_json) {
    Ok(_) => Ok("ok")
    Err(e) => Err(e.to_json_string())
  }
}
