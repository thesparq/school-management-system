///|
fn escape_surreal_string(s : String) -> String {
  s.replace(old="'", new="''")
}

///|
pub fn url_encode(s : String) -> String {
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
  let val = @json.parse(raw) catch { _ => return Err(surreal_error(raw, None)) }
  match val {
    Array(a) => {
      if a.length() == 0 {
        return Err(surreal_error(raw, None))
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
                Err(surreal_error(detail, None))
              } else {
                match obj.get("result") {
                  Some(r) =>
                    match r {
                      Array(arr) => Ok(arr)
                      _ => Err(surreal_error(raw, None))
                    }
                  None => Err(surreal_error(raw, None))
                }
              }
            _ =>
              match obj.get("result") {
                Some(r) =>
                  match r {
                    Array(arr) => Ok(arr)
                    _ => Err(surreal_error(raw, None))
                  }
                None => Err(surreal_error(raw, None))
              }
          }
        _ => Err(surreal_error(raw, None))
      }
    }
    _ => Err(surreal_error(raw, None))
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
  let auth_value = "Basic " +
    @base64.encode(
      Bytes::from_array(
        @utf8.encode(cfg.username + ":" + cfg.password).to_fixedarray(),
      ).view(),
    )
  let headers = match
    build_headers([
      ("Authorization", auth_value),
      ("Accept", "application/json"),
      ("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"),
      ("surreal-ns", cfg.ns),
      ("surreal-db", cfg.database),
    ]) {
    Ok(h) => h
    Err(_) =>
      return Err(surreal_error("build headers failed".to_string(), None))
  }
  let modified_sql = match bindings {
    Some(b) => {
      let mut s = sql
      for kv in b.iter() {
        let (k, v) = kv
        s = s.replace_all(old="$" + k, new="\"" + v + "\"")
      }
      s
    }
    None => sql
  }
  let path = "/sql"
  let is_local = cfg.host.starts_with("localhost") || cfg.host.starts_with("127.0.0.1")
  let scheme = if is_local { @http_types.Http } else { @http_types.Https }
  match
    http_request(
      cfg.host,
      @http_types.Post,
      scheme,
      path,
      headers,
      Some(@utf8.encode(modified_sql).to_fixedarray()),
    ) {
    Ok((status, body)) => Ok((status, body))
    Err(e) => { @logging.error("HTTP ERROR: " + e); Err(surreal_error(e, Some(sql))) }
  }
}

///|
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
    return Err(surreal_error("HTTP " + status.to_string() + " - " + body, Some(sql)))
  }
  @logging.info("SurrealDB: " + sql)
  parse_result_array(body)
}
