///|
/// Shared WASI HTTP request/response logic used by both
/// surreal_client.mbt and authentik_client.mbt.
/// Handles body writing, 15s timeout via @poll.poll,
/// response stream chunking, and byte assembly.

///|
fn str_to_bytes(s : String) -> FixedArray[Byte] {
  @utf8.encode(s).to_fixedarray()
}

///|
fn bytes_to_str(bs : FixedArray[Byte]) -> String {
  @utf8.decode_lossy(Bytes::from_array(bs).view())
}

///|
/// Performs an HTTP request against a given host.
/// Returns (status_code, response_body) or an error string.
/// Callers should wrap the error string into their own AppError variant.
fn http_request_raw(
  host : String,
  method : @http_types.Method,
  scheme : @http_types.Scheme,
  path : String,
  headers : @http_types.Fields,
  body : FixedArray[Byte]?,
  timeout_ns : UInt64,
) -> Result[(UInt, String), String] {
  let request = @http_types.OutgoingRequest::outgoing_request(headers)
  let _ = request.set_method(method)
  let _ = request.set_scheme(Some(scheme))
  let _ = request.set_authority(Some(host))
  let _ = request.set_path_with_query(Some(path))

  let outgoing_body = match request.body() {
    Ok(b) => b
    Err(_) => return Err("request body already taken")
  }

  match body {
    Some(data) => {
      let output_stream = match outgoing_body.write() {
        Ok(s) => s
        Err(_) => {
          let _ = @http_types.OutgoingBody::finish(outgoing_body, None)
          return Err("body write stream failed")
        }
      }
      match output_stream.blocking_write_and_flush(data) {
        Ok(_) => ()
        Err(_) => {
          output_stream.drop()
          let _ = @http_types.OutgoingBody::finish(outgoing_body, None)
          return Err("write body failed")
        }
      }
      output_stream.drop()
    }
    None => {
      let output_stream = match outgoing_body.write() {
        Ok(s) => s
        Err(_) => {
          let _ = @http_types.OutgoingBody::finish(outgoing_body, None)
          return Err("body write stream failed")
        }
      }
      match output_stream.blocking_write_and_flush(FixedArray::make(0, b'\x00')) {
        Ok(_) => ()
        Err(_) => {
          output_stream.drop()
          let _ = @http_types.OutgoingBody::finish(outgoing_body, None)
          return Err("write body failed")
        }
      }
      output_stream.drop()
    }
  }

  match @http_types.OutgoingBody::finish(outgoing_body, None) {
    Ok(_) => ()
    Err(_) => return Err("finish body failed")
  }

  let future_response = match @http.handle(request, None) {
    Ok(f) => f
    Err(_) => return Err("http handle failed")
  }

  let pollable = future_response.subscribe()
  let timer = @monotonic.subscribe_duration(timeout_ns)
  let ready = @poll.poll([pollable, timer])
  let mut http_ready = false
  for idx in ready {
    if idx == 0U {
      http_ready = true
      break
    }
  }
  if !http_ready {
    return Err("http request timed out")
  }

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

  let chunks : Array[FixedArray[Byte]] = []
  let mut done = false
  while !done {
    match stream.blocking_read(65536UL) {
      Ok(chunk) =>
        if chunk.length() == 0 {
          done = true
        } else {
          chunks.push(chunk)
        }
      Err(_) => done = true
    }
  }
  stream.drop()
  let _ = @http_types.IncomingBody::finish(incoming_body)

  let total = chunks.iter().fold(init=0, fn(acc, c) { acc + c.length() })
  let bytes : FixedArray[Byte] = FixedArray::make(total, b'\x00')
  let mut offset = 0
  for chunk in chunks {
    chunk.blit_to(bytes, len=chunk.length(), src_offset=0, dst_offset=offset)
    offset += chunk.length()
  }

  Ok((status, bytes_to_str(bytes)))
}

///|
/// Helper: builds headers from a list of (name, value) string pairs.
/// Returns Err if header construction fails.
pub fn build_headers(
  pairs : Array[(String, String)],
) -> Result[@http_types.Fields, String] {
  let list = pairs.map(fn(kv) {
    let (k, v) = kv
    (k, str_to_bytes(v))
  })
  match @http_types.Fields::from_list(list) {
    Ok(h) => Ok(h)
    Err(_) => Err("build headers failed")
  }
}

///|
/// Performs an HTTP request. Wraps http_request_raw with common defaults.
/// The caller provides pre-built headers and body.
pub fn http_request(
  host : String,
  method : @http_types.Method,
  scheme : @http_types.Scheme,
  path : String,
  headers : @http_types.Fields,
  body : FixedArray[Byte]?,
) -> Result[(UInt, String), String] {
  http_request_raw(host, method, scheme, path, headers, body, 15_000_000_000UL)
}
