
import http.Request
import http.Response
import pf.Http
import pf.Stdout

SurrealDB := [].{
    Config : {
        url: Str,
        ns: Str,
        db: Str,
        auth: Str,
    }

    query! : Str, Config => [Ok(Str), Err([HttpErr, JsonErr, SurrealErr(Str)])]
    query! = |sql, config| {
        req = 
            Request.from_method(POST)
                |> Request.with_uri(config.url)
                |> Request.add_header("Accept", "application/json")
                |> Request.add_header("surreal-ns", config.ns)
                |> Request.add_header("surreal-db", config.db)
                |> Request.add_header("Authorization", config.auth)
                |> Request.with_body(Str.to_utf8(sql))

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
                    Err(SurrealErr(body_str))
                }
            }
            Err(_) => Err(HttpErr)
        }
    }

    # A read that answers a failure with one retry. The deployed stack can drop the idle keep-alive
    # between the app and `surrealdb:8000` (docker bridge NAT), so the first request after a pause can
    # fail at the socket — and SurrealDB itself can answer non-200 briefly (its own 5xx under a burst).
    # A read retried after either is harmless: the same statement answers the same rows. A write whose
    # response was lost must never be re-sent and applied twice, so writes keep `query!`. Every failed
    # attempt is logged with its kind, so `docker logs` shows which half it was.
    query_read! : Str, Config => [Ok(Str), Err([HttpErr, JsonErr, SurrealErr(Str)])]
    query_read! = |sql, config| {
        match query!(sql, config) {
            Ok(_) => query!(sql, config)
            Err(JsonErr) => Err(JsonErr)
            Err(err) => {
                log!("read to SurrealDB failed (${describe_error!(err)}); retrying once: ${sql}")
                retried = query!(sql, config)
                match retried {
                    Err(JsonErr) => {}
                    Err(retried_err) => log!("read retry also failed (${describe_error!(retried_err)}): ${sql}")
                    Ok(_) => {}
                }
                retried
            }
        }
    }

    # What one error actually was, for the logs: a connection failure, an unparseable body, or
    # SurrealDB's own message.
    describe_error! : [HttpErr, JsonErr, SurrealErr(Str)] => Str
    describe_error! = |err| {
        match err {
            HttpErr => "connection"
            JsonErr => "unparseable body"
            SurrealErr(body) => "SurrealDB: ${body}"
        }
    }

    log! = |line| {
        match Stdout.line!(line) {
            Ok(_) => {}
            Err(_) => {}
        }
    }
}
