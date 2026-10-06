
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

    # A read that answers a connection-level failure by retrying once. The deployed stack drops the
    # idle keep-alive between the app and `surrealdb:8000` (docker bridge NAT), so the first request
    # after a pause fails at the socket and the retry opens a fresh connection — without this, the
    # read-handler answers the user's first load with a "Database error" 500 and their Retry click
    # (a new connection) works. Reads only, never writes: a write whose response was lost must not
    # be re-sent and applied twice. The first failure is logged so `docker logs` shows it happening.
    query_read! : Str, Config => [Ok(Str), Err([HttpErr, JsonErr, SurrealErr(Str)])]
    query_read! = |sql, config| {
        match query!(sql, config) {
            Err(HttpErr) => {
                log!("read to SurrealDB failed at the connection; retrying once: ${sql}")
                query!(sql, config)
            }
            other => other
        }
    }

    log! = |line| {
        match Stdout.line!(line) {
            Ok(_) => {}
            Err(_) => {}
        }
    }
}
