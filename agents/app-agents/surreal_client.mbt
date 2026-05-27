//|
/// Utility module for querying SurrealDB from Golem agents via WASI HTTP.
/// Uses HTTP Basic Auth (username:password base64-encoded).

///|
fn str_to_bytes(s : String) -> FixedArray[Byte] {
  @utf8.encode(s).to_fixedarray()
}

///|
fn bytes_to_str(bs : FixedArray[Byte]) -> String {
  @utf8.decode_lossy(Bytes::from_array(bs).view())
}

///|
/// Shared SurrealDB connection config.
/// All 5 fields are Golem secrets — set via secretDefaults locally,
/// or via `golem secret create` in production.
#derive.config
pub(all) struct SurrealConfig {
  host      : @config.Secret[String]
  ns        : @config.Secret[String]
  database  : @config.Secret[String]
  username  : @config.Secret[String]
  password  : @config.Secret[String]
}

///|
/// Execute a SurrealQL statement against SurrealDB over HTTP Basic Auth.
/// Takes the agent's injected config — resolves secrets internally.
pub fn surreal_query(
  config : @config.Config[SurrealConfig],
  sql    : String,
) -> Result[String, String] {
  let host = config.value.host.get()      catch { _ => return Err("surreal host missing") }
  let ns   = config.value.ns.get()        catch { _ => return Err("surreal ns missing") }
  let db   = config.value.database.get()  catch { _ => return Err("surreal database missing") }
  let user = config.value.username.get()  catch { _ => return Err("surreal username missing") }
  let pass = config.value.password.get()  catch { _ => return Err("surreal password missing") }

  let auth_bytes = str_to_bytes(user + ":" + pass)
  let auth_value = "Basic " + @base64.encode(Bytes::from_array(auth_bytes).view())

  let headers = match @http_types.Fields::from_list([
    ("Authorization", str_to_bytes(auth_value)),
    ("Accept",        str_to_bytes("application/json")),
    ("Content-Type",  str_to_bytes("text/plain")),
    ("surreal-ns",    str_to_bytes(ns)),
    ("surreal-db",    str_to_bytes(db)),
  ]) {
    Ok(h) => h
    Err(_) => return Err("build headers failed")
  }

  let request = @http_types.OutgoingRequest::outgoing_request(headers)
  let _ = request.set_method(@http_types.Post)
  let _ = request.set_scheme(Some(@http_types.Https))
  let _ = request.set_authority(Some(host))
  let _ = request.set_path_with_query(Some("/sql"))

  let body = match request.body() {
    Ok(b) => b
    Err(_) => return Err("request body already taken")
  }

  let output_stream = match body.write() {
    Ok(s) => s
    Err(_) => {
      let _ = @http_types.OutgoingBody::finish(body, None)
      return Err("body write stream failed")
    }
  }

  match output_stream.blocking_write_and_flush(str_to_bytes(sql)) {
    Ok(_) => ()
    Err(_) => {
      output_stream.drop()
      let _ = @http_types.OutgoingBody::finish(body, None)
      return Err("write body failed")
    }
  }
  output_stream.drop()

  match @http_types.OutgoingBody::finish(body, None) {
    Ok(_) => ()
    Err(_) => return Err("finish body failed")
  }

  let future_response = match @http.handle(request, None) {
    Ok(f) => f
    Err(_) => return Err("http handle failed")
  }

  let pollable = future_response.subscribe()
  pollable.block()

  let response = match future_response.get() {
    Some(Ok(Ok(r))) => r
    Some(Ok(Err(_))) => return Err("http response error")
    Some(Err(_)) => return Err("response already consumed")
    None => return Err("response not ready after poll")
  }

  let status = response.status()
  let incoming_body = match response.consume() {
    Ok(b) => b
    Err(_) => return Err("consume body failed")
  }

  let stream = match incoming_body.stream() {
    Ok(s) => s
    Err(_) => {
      let _ = @http_types.IncomingBody::finish(incoming_body)
      return Err("incoming stream failed")
    }
  }

  let bytes = match stream.blocking_read(1048576UL) {
    Ok(b) => b
    Err(_) => {
      stream.drop()
      let _ = @http_types.IncomingBody::finish(incoming_body)
      return Err("read body failed")
    }
  }
  stream.drop()
  let _ = @http_types.IncomingBody::finish(incoming_body)

  if status >= 200 && status < 300 {
    Ok(bytes_to_str(bytes))
  } else {
    Err("SurrealDB " + status.to_string() + ": " + bytes_to_str(bytes))
  }
}
