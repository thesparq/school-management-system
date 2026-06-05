///|
pub fn escape_surreal_string(s : String) -> String { s.replace(old="'", new="''") }
pub fn url_encode(s : String) -> String {
  let bytes = @utf8.encode(s); let arr = bytes.to_fixedarray()
  let hex_chars = "0123456789ABCDEF"; let result = StringBuilder::new()
  for b in arr {
    let v = b.to_int()
    if (v >= 0x30 && v <= 0x39) || (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A) || v == 0x2D || v == 0x5F || v == 0x2E || v == 0x7E { result.write_char(v.unsafe_to_char()) }
    else if v == 0x20 { result.write_string("%20") } else { result.write_char('%'); result.write_char(hex_chars.get_char((v >> 4) & 0xF).unwrap()); result.write_char(hex_chars.get_char(v & 0xF).unwrap()) }
  }
  result.to_string()
}
fn parse_result_array(raw : String) -> Result[Array[Json], AppError] {
  let val = @json.parse(raw) catch { _ => return Err(surreal_error(raw, None)) }
  match val {
    Array(a) => {
      if a.length() == 0 { return Err(surreal_error(raw, None)) }
      match a[0] {
        Object(obj) => match obj.get("status") {
          Some(String(s)) => if s == "ERR" {
            let detail = match obj.get("detail") { Some(String(d)) => d; _ => match obj.get("message") { Some(String(m)) => m; _ => raw } }
            Err(surreal_error(detail, None))
          } else { match obj.get("result") { Some(r) => match r { Array(arr) => Ok(arr); _ => Err(surreal_error(raw, None)) }; None => Err(surreal_error(raw, None)) } }
          _ => match obj.get("result") { Some(r) => match r { Array(arr) => Ok(arr); _ => Err(surreal_error(raw, None)) }; None => Err(surreal_error(raw, None)) }
        }
        _ => Err(surreal_error(raw, None))
      }
    }
    _ => Err(surreal_error(raw, None))
  }
}
fn surreal_query_internal(config : SharedConfig, sql : String, bindings : Map[String, String]?) -> Result[(UInt, String), AppError] {
  let cfg = match resolve_surreal_cfg(config) { Ok(c) => c; Err(e) => return Err(e) }
  let auth_value = "Basic " + @base64.encode(Bytes::from_array(@utf8.encode(cfg.username + ":" + cfg.password).to_fixedarray()).view())
  let headers = match build_headers([("Authorization", auth_value), ("Accept", "application/json"), ("Content-Type", "text/plain"), ("surreal-ns", cfg.ns), ("surreal-db", cfg.database)]) { Ok(h) => h; Err(_) => return Err(surreal_error("build headers failed".to_string(), None)) }
  let path = match bindings {
    Some(b) => { let mut first = true; let qs = StringBuilder::new(); qs.write_string("/sql"); for kv in b.iter() { let (k, v) = kv; qs.write_string(if first { "?" } else { "&" }); qs.write_string(url_encode(k)); qs.write_string("="); qs.write_string(url_encode(v)); first = false }; qs.to_string() }
    None => "/sql"
  }
  match http_request(cfg.host, @http_types.Post, @http_types.Https, path, headers, Some(@utf8.encode(sql).to_fixedarray())) { Ok((status, body)) => Ok((status, body)); Err(e) => Err(surreal_error(e, Some(sql))) }
}
pub fn surreal_query(config : SharedConfig, sql : String, bindings? : Map[String, String]) -> Result[Array[Json], AppError] {
  let (status, body) = match surreal_query_internal(config, sql, bindings) { Ok(r) => r; Err(e) => return Err(e) }
  if status < 200 || status >= 300 { return Err(surreal_error(body, Some(sql))) }
  @logging.info("SurrealDB: " + sql)
  parse_result_array(body)
}
