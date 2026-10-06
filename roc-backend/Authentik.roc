
import http.Request
import http.Response
import pf.Http
import pf.Env
import pf.OsStr
import AuthUrls

Authentik := [].{
    validateToken! : Str => [Ok(Str), Err(Str)]
    validateToken! = |token| {
        # Try direct override first, then derive from Infisical's AUTHENTIK_ISSUER_URL
        url = match Env.var!("AUTHENTIK_USERINFO_URL") {
            Ok(os) => OsStr.display(os)
            Err(_) =>
                match Env.var!("AUTHENTIK_ISSUER_URL") {
                    Ok(os) => AuthUrls.userinfo_url(OsStr.display(os))
                    Err(_) => "http://localhost:9000/application/o/userinfo/"
                }
        }

        req = 
            Request.from_method(GET)
                |> Request.with_uri(url)
                |> Request.add_header("Authorization", "Bearer ${token}")
                |> Request.add_header("Accept", "application/json")

        res = Http.send!(req)
        match res {
            Ok(response) => {
                if Response.status(response) == 200 {
                    body_str = 
                        match Str.from_utf8(Response.body(response)) {
                            Ok(s) => s
                            Err(_) => "{}"
                        }
                    Ok(body_str)
                } else {
                    Err("Invalid Token")
                }
            }
            Err(_) => Err("Http Error connecting to Authentik")
        }
    }

    extract_field = |json_str, field| {
        parts = Str.split_on(json_str, "\"${field}\":\"")
        match List.get(parts, 1) {
            Ok(rest) => {
                val_parts = Str.split_on(rest, "\"")
                match List.get(val_parts, 0) {
                    Ok(val) => val
                    Err(_) => ""
                }
            }
            Err(_) => ""
        }
    }

    # The pk of the login a response is about, as text. Authentik sends it as a **number** (`"pk":15`),
    # and as the first `pk` in the object — the group objects that follow carry a string `pk` of their
    # own, so a reader that only matches `"pk":"…"` either finds a group's pk or, on a response with no
    # groups, finds nothing at all. Finding nothing is how a created login's profile row used to be
    # written under a placeholder id instead of the login's own, leaving the login with no profile.
    user_pk! : Str => Str
    user_pk! = |body| {
        match List.get(Str.split_on(body, "\"pk\":"), 1) {
            Ok(rest) => pk_text(Str.trim(rest))
            Err(_) => ""
        }
    }

    # A `pk` value as text: `"mock_uuid_3"` -> `mock_uuid_3`, `15,"username"` -> `15`.
    pk_text : Str -> Str
    pk_text = |value| {
        if Str.starts_with(value, "\"") {
            match List.get(Str.split_on(value, "\""), 1) {
                Ok(text) => text
                Err(_) => ""
            }
        } else {
            chunk = match List.first(Str.split_on(value, ",")) { Ok(v) => v, Err(_) => value }
            digits = List.keep_if(Str.to_utf8(chunk), |byte| byte >= 48 and byte <= 57)

            match Str.from_utf8(digits) {
                Ok(text) => text
                Err(_) => ""
            }
        }
    }

    api_token! : Str => Str
    api_token! = |_| {
        match Env.var!("AUTHENTIK_API_TOKEN") {
            Ok(os_str) => OsStr.display(os_str)
            Err(_) =>
                match Env.var!("AUTHENTIK_SERVICE_ACCOUNT_TOKEN") {
                    Ok(os_str) => OsStr.display(os_str)
                    Err(_) => ""
                }
        }
    }

    api_url! : Str => Str
    api_url! = |_| {
        match Env.var!("AUTHENTIK_API_URL") {
            Ok(os) => OsStr.display(os)
            Err(_) =>
                match Env.var!("AUTHENTIK_HOST") {
                    Ok(os) => "https://${OsStr.display(os)}/api/v3/core/users/"
                    Err(_) => "http://localhost:9000/api/v3/core/users/"
                }
        }
    }

    createUser! : Str, Str => [Ok(Str), Err(Str)]
    createUser! = |email, name| {
        token = api_token!("")
        api_url = api_url!("")

        req = 
            Request.from_method(POST)
                |> Request.with_uri(api_url)
                |> Request.add_header("Authorization", "Bearer ${token}")
                |> Request.add_header("Content-Type", "application/json")
                |> Request.with_body(Str.to_utf8("{\"username\": \"${email}\", \"name\": \"${name}\", \"email\": \"${email}\"}"))

        res = Http.send!(req)

        match res {
            Ok(response) => {
                body_str = 
                    match Str.from_utf8(Response.body(response)) {
                        Ok(s) => s
                        Err(_) => "{}"
                    }
                if Response.status(response) == 201 or Response.status(response) == 200 {
                    uuid = user_pk!(body_str)

                    if Str.is_empty(uuid) {
                        # A login was created but nothing in this response names it, so there is no id to
                        # write its profile under. Answering with a placeholder id is what left an orphan
                        # `student_profile` row in production: the login existed with no profile, and the
                        # row showed up in the role's tab under an id no login has. Report it instead —
                        # the caller answers 502 and writes no profile row. The login still exists, so
                        # say so here: the operator has to find it in the directory.
                        Err("Authentik created the login but its pk was not in the response; check the directory for a login with no profile")
                    } else {
                        Ok(uuid)
                    }
                } else {
                    Err("Failed to create user")
                }
            }
            Err(_) => Err("Http Error creating user")
        }
    }

    # One page of the user directory: `{"pagination":{…},"results":[{pk, email, is_active, …}, …]}`.
    # Email, whether the account is enabled and the groups live here rather than in the profile tables,
    # so the listing calls this once and merges the attributes in by pk. The body is returned as it
    # arrives: this codebase has no JSON parser, and main.roc reads it with its own scanners.
    listUsers! : Str => [Ok(Str), Err(Str)]
    listUsers! = |page_size| {
        token = api_token!("")
        api_url = api_url!("")
        size = if Str.is_empty(page_size) { "200" } else { page_size }

        if Str.is_empty(token) {
            Err("AUTHENTIK_API_TOKEN is not set")
        } else {
            req =
                Request.from_method(GET)
                    |> Request.with_uri("${api_url}?page_size=${size}")
                    |> Request.add_header("Authorization", "Bearer ${token}")
                    |> Request.add_header("Accept", "application/json")

            match Http.send!(req) {
                Ok(response) => {
                    if Response.status(response) == 200 {
                        body_str =
                            match Str.from_utf8(Response.body(response)) {
                                Ok(s) => s
                                Err(_) => "{}"
                            }
                        Ok(body_str)
                    } else {
                        Err("Failed to list users")
                    }
                }
                Err(_) => Err("Http Error listing users")
            }
        }
    }

    # Change the identity attributes of an existing login: its email, or `is_active` to switch the
    # account off. The pk goes in the path and the caller builds the JSON body (`{"is_active": false}`
    # or `{"email": "…"}`), because what an identity update carries depends on the caller.
    updateUser! : Str, Str => [Ok(Str), Err(Str)]
    updateUser! = |user_id, json_body| {
        token = api_token!("")
        api_url = api_url!("")

        req =
            Request.from_method(PATCH)
                |> Request.with_uri("${api_url}${user_id}/")
                |> Request.add_header("Authorization", "Bearer ${token}")
                |> Request.add_header("Content-Type", "application/json")
                |> Request.with_body(Str.to_utf8(json_body))

        match Http.send!(req) {
            Ok(response) => {
                if Response.status(response) == 200 {
                    Ok(user_id)
                } else {
                    Err("Failed to update user")
                }
            }
            Err(_) => Err("Http Error updating user")
        }
    }

    # Compensating action for a profile write that failed after the login was created:
    # without it the admin is left with a login that has no profile and cannot retry.
    deleteUser! : Str => [Ok(Str), Err(Str)]
    deleteUser! = |user_id| {
        token = api_token!("")
        api_url = api_url!("")

        req =
            Request.from_method(DELETE)
                |> Request.with_uri("${api_url}${user_id}/")
                |> Request.add_header("Authorization", "Bearer ${token}")

        match Http.send!(req) {
            Ok(response) => {
                if Response.status(response) == 204 or Response.status(response) == 200 {
                    Ok(user_id)
                } else {
                    Err("Failed to delete user")
                }
            }
            Err(_) => Err("Http Error deleting user")
        }
    }
}
