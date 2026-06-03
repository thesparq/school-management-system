///|
/// SharedConfig is the single @config.Config injected into every agent.
/// Fields are prefixed (surreal_*, authentik_*) for clarity.
/// Companion helper structs SurrealCfg and AuthentikCfg provide
/// resolved values to client functions.

///|
#derive.config
pub(all) struct SharedConfig {
  surreal_host : @config.Secret[String]
  surreal_ns : @config.Secret[String]
  surreal_database : @config.Secret[String]
  surreal_username : @config.Secret[String]
  surreal_password : @config.Secret[String]
  authentik_host : @config.Secret[String]
  authentik_api_token : @config.Secret[String]
  auth_key : @config.Secret[String]
}

///|
/// Resolved SurrealDB connection values (no secrets).
pub(all) struct SurrealCfg {
  host : String
  ns : String
  database : String
  username : String
  password : String
}

///|
/// Resolved Authentik connection values (no secrets).
pub(all) struct AuthentikCfg {
  host : String
  api_token : String
}

///|
pub fn resolve_surreal_cfg(
  config : SharedConfig,
) -> Result[SurrealCfg, AppError] {
  let host = config.surreal_host.get() catch {
    _ => return Err(AppError::{ code: InternalError, message: "Surreal host missing", detail: None })
  }
  let ns = config.surreal_ns.get() catch {
    _ => return Err(AppError::{ code: InternalError, message: "Surreal ns missing", detail: None })
  }
  let database = config.surreal_database.get() catch {
    _ =>
      return Err(AppError::{ code: InternalError, message: "Surreal database missing", detail: None })
  }
  let username = config.surreal_username.get() catch {
    _ =>
      return Err(AppError::{ code: InternalError, message: "Surreal username missing", detail: None })
  }
  let password = config.surreal_password.get() catch {
    _ =>
      return Err(AppError::{ code: InternalError, message: "Surreal password missing", detail: None })
  }
  Ok(SurrealCfg::{ host, ns, database, username, password })
}

///|
pub fn resolve_authentik_cfg(
  config : SharedConfig,
) -> Result[AuthentikCfg, AppError] {
  let host = config.authentik_host.get() catch {
    _ =>
      return Err(AppError::{ code: InternalError, message: "Authentik host missing", detail: None })
  }
  let api_token = config.authentik_api_token.get() catch {
    _ =>
      return Err(
        AppError::{ code: InternalError, message: "Authentik token missing", detail: None },
      )
  }
  Ok(AuthentikCfg::{ host, api_token })
}
