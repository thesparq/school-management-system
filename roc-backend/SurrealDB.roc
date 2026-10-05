module [Config, query!]

import http.Request
import http.Response
import pf.Http

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
