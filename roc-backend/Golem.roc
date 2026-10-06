module [invokeClassAgent!]

import http.Request
import http.Response
import pf.Http
import pf.Env
import pf.OsStr

invokeClassAgent! : Str, Str => [Ok(Str), Err(Str)]
invokeClassAgent! = |class_id, payload| {
    base_url = match Env.var!("GOLEM_URL") { Ok(os) => OsStr.display(os), Err(_) => "http://localhost:9006" }
    url = "${base_url}/class-agents/${class_id}/message"
    
    # We must wrap the payload in a JSON object with a "msg" key,
    # because the MoonBit agent's `handle_message(msg: String)` expects it.
    
    # Escape quotes inside the payload
    escaped = Str.replace_each(payload, "\"", "\\\"")
    wrapped_body = "{\"msg\": \"${escaped}\"}"

    req = 
        Request.from_method(POST)
            |> Request.with_uri(url)
            |> Request.add_header("Host", "moonbit-agents.localhost:9006")
            |> Request.add_header("Accept", "application/json")
            |> Request.add_header("Content-Type", "application/json")
            |> Request.with_body(Str.to_utf8(wrapped_body))

    res = Http.send!(req)
    
    match res {
        Ok(response) => {
            if Response.status(response) == 200 {
                body_str = 
                    match Str.from_utf8(Response.body(response)) {
                        Ok(s) => s
                        Err(_) => "[]"
                    }
                Ok(body_str)
            } else {
                body_str = 
                    match Str.from_utf8(Response.body(response)) {
                        Ok(s) => s
                        Err(_) => "Unknown Error"
                    }
                Err(body_str)
            }
        }
        Err(_) => Err("Http Error")
    }
}
