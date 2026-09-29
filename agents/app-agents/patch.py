import sys

with open("agents/app-agents/http_client.mbt", "r") as f:
    code = f.read()

# Replace drops properly
old_block = """
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
"""

new_block = """
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
  
  pollable.drop()
  timer.drop()

  if !http_ready {
    future_response.drop()
    return Err("http request timed out")
  }

  let response = match future_response.get() {
    Some(Ok(Ok(r))) => r
    Some(Ok(Err(_))) => { future_response.drop(); return Err("http response error") }
    Some(Err(_)) => { future_response.drop(); return Err("response already consumed") }
    None => { future_response.drop(); return Err("response not ready after poll") }
  }
  future_response.drop()

  let status = response.status()
  let incoming_body = match response.consume() {
    Ok(b) => b
    Err(_) => { response.drop(); return Err("consume body failed") }
  }
  response.drop()
"""

new_code = code.replace(old_block, new_block)

with open("agents/app-agents/http_client.mbt", "w") as f:
    f.write(new_code)
