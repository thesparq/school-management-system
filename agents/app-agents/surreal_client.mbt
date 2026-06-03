///|
/// SurrealDB HTTP client. Queries SurrealDB via the /sql endpoint
/// using HTTP Basic Auth. Functions take SharedConfig and resolve
/// SurrealDB credentials internally via resolve_surreal_cfg().

///|
/// Escapes a string for safe use in SurrealQL single-quoted literals.
pub fn escape_surreal_string(s : String) -> String {
  s.replace(old="'", new="''")
}

///|
fn url_encode(s : String) -> String {
  let bytes = @utf8.encode(s)
  let arr = bytes.to_fixedarray()
  let hex_chars = "0123456789ABCDEF"
  let result = StringBuilder::new()
  for b in arr {
    let v = b.to_int()
    if (v >= 0x30 && v <= 0x39) ||
      (v >= 0x41 && v <= 0x5A) ||
      (v >= 0x61 && v <= 0x7A) ||
      v == 0x2D ||
      v == 0x5F ||
      v == 0x2E ||
      v == 0x7E {
      result.write_char(v.unsafe_to_char())
    } else if v == 0x20 {
      result.write_string("%20")
    } else {
      result.write_char('%')
      result.write_char(hex_chars.get_char((v >> 4) & 0xF).unwrap())
      result.write_char(hex_chars.get_char(v & 0xF).unwrap())
    }
  }
  result.to_string()
}

///|
fn parse_result_array(raw : String) -> Result[Array[Json], AppError] {
  let val = @json.parse(raw) catch {
    _ => return Err(
      AppError::{ code: SurrealDBError, message: "Failed to parse SurrealDB response", detail: None },
    )
  }
  match val {
    Array(a) => {
      if a.length() == 0 {
        return Err(
          AppError::{ code: SurrealDBError, message: "SurrealDB response empty", detail: None },
        )
      }
      match a[0] {
        Object(obj) =>
          match obj.get("status") {
            Some(String(s)) =>
              if s == "ERR" {
                let detail = match obj.get("detail") {
                  Some(String(d)) => d
                  _ =>
                    match obj.get("message") {
                      Some(String(m)) => m
                      _ => raw
                    }
                }
                Err(
                  AppError::{ code: SurrealDBError, message: "SurrealDB: " + detail, detail: Some(raw) },
                )
              } else {
                match obj.get("result") {
                  Some(r) =>
                    match r {
                      Array(arr) => Ok(arr)
                      _ => Err(
                        AppError::{
                          code: SurrealDBError,
                          message: "SurrealDB result not an array",
                          detail: None,
                        },
                      )
                    }
                  None =>
                    Err(
                      AppError::{
                        code: SurrealDBError,
                        message: "SurrealDB result missing",
                        detail: None,
                      },
                    )
                }
              }
            _ =>
              match obj.get("result") {
                Some(r) =>
                  match r {
                    Array(arr) => Ok(arr)
                    _ => Err(
                      AppError::{
                        code: SurrealDBError,
                        message: "SurrealDB result not an array",
                        detail: None,
                      },
                    )
                  }
                None =>
                  Err(
                    AppError::{
                      code: SurrealDBError,
                      message: "SurrealDB result missing",
                      detail: None,
                    },
                  )
              }
          }
        _ =>
          Err(
            AppError::{
              code: SurrealDBError,
              message: "SurrealDB response element not an object",
              detail: None,
            },
          )
      }
    }
    _ =>
      Err(
        AppError::{
          code: SurrealDBError,
          message: "SurrealDB response not an array",
          detail: None,
        },
      )
  }
}

///|
fn surreal_query_internal(
  config : SharedConfig,
  sql : String,
  bindings : Map[String, String]?,
) -> Result[(UInt, String), AppError] {
  let cfg = match resolve_surreal_cfg(config) {
    Ok(c) => c
    Err(e) => return Err(e)
  }
  let auth_bytes = @utf8.encode(cfg.username + ":" + cfg.password).to_fixedarray()
  let auth_value = "Basic " + @base64.encode(Bytes::from_array(auth_bytes).view())

  let headers = match build_headers([
    ("Authorization", auth_value),
    ("Accept", "application/json"),
    ("Content-Type", "text/plain"),
    ("surreal-ns", cfg.ns),
    ("surreal-db", cfg.database),
  ]) {
    Ok(h) => h
    Err(_) =>
      return Err(
        AppError::{ code: InternalError, message: "Build SurrealDB headers failed", detail: None },
      )
  }

  let path = match bindings {
    Some(b) => {
      let mut first = true
      let qs = StringBuilder::new()
      qs.write_string("/sql")
      for kv in b.iter() {
        let (k, v) = kv
        qs.write_string(if first { "?" } else { "&" })
        qs.write_string(url_encode(k))
        qs.write_string("=")
        qs.write_string(url_encode(v))
        first = false
      }
      qs.to_string()
    }
    None => "/sql"
  }

  let body_bytes = @utf8.encode(sql).to_fixedarray()
  match http_request(
    cfg.host,
    @http_types.Post,
    @http_types.Https,
    path,
    headers,
    Some(body_bytes),
  ) {
    Ok((status, body)) => Ok((status, body))
    Err(e) =>
      Err(AppError::{ code: SurrealDBError, message: e, detail: None })
  }
}

///|
/// Execute a SurrealQL statement. Returns parsed result array.
/// SurrealDB errors (status:"ERR") are returned as AppError::SurrealDBError.
pub fn surreal_query(
  config : SharedConfig,
  sql : String,
  bindings? : Map[String, String],
) -> Result[Array[Json], AppError] {
  let (status, body) = match surreal_query_internal(config, sql, bindings) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  if status < 200 || status >= 300 {
    return Err(
      AppError::{
        code: SurrealDBError,
        message: "SurrealDB HTTP " + status.to_string(),
        detail: Some(body),
      },
    )
  }
  @logging.info("SurrealDB: " + sql)
  @logging.info("SurrealDB: status=" + status.to_string() + " body_len=" + body.length().to_string())
  parse_result_array(body)
}

///|
/// Save or update a user profile in SurrealDB.
/// Resolves class_level name to a record ID via a separate query
/// to produce a proper record<class_levels> reference.
pub fn surreal_save_profile(
  config : SharedConfig,
  target_user_id : String,
  role : String,
  class_level : String?,
) -> Result[Unit, AppError] {
  if !["admin", "teacher", "student"].contains(role) {
    return Err(
      AppError::{
        code: ValidationError,
        message: "Invalid role: " + role,
        detail: None,
      },
    )
  }
  let cl_record = match class_level {
    Some(cl) => {
      let lookup_sql = "SELECT VALUE id FROM class_levels WHERE name = '" +
        escape_surreal_string(cl) +
        "' LIMIT 1"
      match surreal_query(config, lookup_sql) {
        Ok(arr) =>
          if arr.length() > 0 {
            match arr[0] {
              String(slug) => Some(slug)
              _ => None
            }
          } else {
            None
          }
        Err(_) => None
      }
    }
    None => None
  }
  let sql = match cl_record {
    Some(slug) =>
      "INSERT INTO user_profile (auth_id, role, class_level, created_at) VALUES ('" +
      escape_surreal_string(target_user_id) +
      "', '" +
      escape_surreal_string(role) +
      "', type::thing(\"class_levels\", " +
      escape_surreal_string(slug) +
      "), time::now()) " +
      "ON DUPLICATE KEY UPDATE role='" +
      escape_surreal_string(role) +
      "', class_level=type::thing(\"class_levels\", " +
      escape_surreal_string(slug) +
      ")"
    None =>
      "INSERT INTO user_profile (auth_id, role, created_at) VALUES ('" +
      escape_surreal_string(target_user_id) +
      "', '" +
      escape_surreal_string(role) +
      "', time::now()) " +
      "ON DUPLICATE KEY UPDATE role='" +
      escape_surreal_string(role) +
      "'"
  }
  match surreal_query(config, sql) {
    Ok(_) => Ok(())
    Err(e) => Err(e)
  }
}

///|
/// Soft-delete a user profile in SurrealDB (sets deleted_at).
pub fn surreal_soft_delete_user(
  config : SharedConfig,
  target_user_id : String,
) -> Result[Unit, AppError] {
  let sql = "UPDATE user_profile SET deleted_at = time::now() WHERE auth_id = '" +
    escape_surreal_string(target_user_id) +
    "' AND deleted_at IS NONE"
  match surreal_query(config, sql) {
    Ok(_) => Ok(())
    Err(e) => Err(e)
  }
}

///|
/// Undo a soft-delete (for compensation when delete fails downstream).
pub fn surreal_undo_soft_delete(
  config : SharedConfig,
  target_user_id : String,
) -> Result[Unit, AppError] {
  let sql = "UPDATE user_profile SET deleted_at = NONE WHERE auth_id = '" +
    escape_surreal_string(target_user_id) +
    "'"
  match surreal_query(config, sql) {
    Ok(_) => Ok(())
    Err(e) => Err(e)
  }
}
