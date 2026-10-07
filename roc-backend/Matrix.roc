## Matrix / Synapse plumbing for the chat page (`GET /api/matrix/token` in `main.roc`).
##
## Two calls, both against the homeserver's admin API with the shared admin token:
## `ensure_user!` is an idempotent upsert so the account exists (and picks up the display name on
## later logins), `get_user_token!` issues an access token the page can sync and send with. The
## user id is the app's own id (`@<Authentik pk>:<server>`), the form the retired MoonBit stack
## wrote, so accounts from that era are reused.
##
## The pure helpers carry no HTTP; the calls and the helpers together are exercised by
## `roc-frontend/tests/e2e/matrix_token.sh` against `mock_synapse.py` (which asserts the encoded
## user id and the trimmed homeserver), since this module imports the http packages that only
## `main.roc`'s app header declares.

import http.Request
import http.Response
import pf.Http

Matrix := [].{
    ## The Matrix user id of an app user: the app's own id (the Authentik pk the profile rows are
    ## keyed by) in the form `@<local>:<server>`.
    user_id : Str, Str -> Str
    user_id = |local_part, server_name| {
        "@${local_part}:${server_name}"
    }

    ## A user id ready for a URL path. Synapse's admin API documents the segment percent-encoded,
    ## so `@` and `:` are encoded; the pk itself is uuid/digits/dashes and passes through.
    path_segment : Str -> Str
    path_segment = |id| {
        id
            |> Str.replace_each("@", "%40")
            |> Str.replace_each(":", "%3A")
    }

    ## A base URL without trailing slashes, so `https://…/school/` and `https://…/school` build
    ## the same request URL.
    trim_slash : Str -> Str
    trim_slash = |url| {
        if Str.ends_with(url, "/") {
            trim_slash(without_trailing_slash(url))
        } else {
            url
        }
    }

    ## The URL with its final byte removed. Only ever called on a URL that ends with `/`, and the
    ## match only ever strips that byte, so the scheme's own `//` is untouched.
    without_trailing_slash : Str -> Str
    without_trailing_slash = |url| {
        match Str.from_utf8(drop_last_bytes(Str.to_utf8(url), [])) {
            Ok(trimmed) => trimmed
            Err(_) => url
        }
    }

    ## Every byte but the last. `[_]` comes before `[byte, .. as rest]` so a one-byte list is
    ## dropped whole, not recursed into.
    drop_last_bytes : List(U8), List(U8) -> List(U8)
    drop_last_bytes = |remaining, out|
        match remaining {
            [] => out
            [_] => out
            [byte, .. as rest] => drop_last_bytes(rest, List.append(out, byte))
        }

    ## PUT /_synapse/admin/v2/users/<id>: the account exists (201) or its display name is updated
    ## (200); either way the login call below has something to log in as.
    ensure_user! : Str, Str, Str, Str => [Ok(Str), Err(Str)]
    ensure_user! = |api_base, admin_token, matrix_user_id, display_name| {
        req =
            Request.from_method(PUT)
                |> Request.with_uri("${trim_slash(api_base)}/_synapse/admin/v2/users/${path_segment(matrix_user_id)}")
                |> Request.add_header("Authorization", "Bearer ${admin_token}")
                |> Request.add_header("Content-Type", "application/json")
                |> Request.with_body(Str.to_utf8("{\"displayname\": \"${json_string(display_name)}\"}"))

        match Http.send!(req) {
            Ok(response) =>
                if Response.status(response) == 200 or Response.status(response) == 201 {
                    Ok("")
                } else {
                    Err("Matrix create user failed (HTTP ${U16.to_str(Response.status(response))}${error_detail(response)})")
                }
            Err(err) => Err(transport_message(err, trim_slash(api_base)))
        }
    }

    ## POST /_synapse/admin/v1/users/<id>/login: an access token for the account, which the page
    ## sends as a bearer on the client API.
    get_user_token! : Str, Str, Str => [Ok(Str), Err(Str)]
    get_user_token! = |api_base, admin_token, matrix_user_id| {
        req =
            Request.from_method(POST)
                |> Request.with_uri("${trim_slash(api_base)}/_synapse/admin/v1/users/${path_segment(matrix_user_id)}/login")
                |> Request.add_header("Authorization", "Bearer ${admin_token}")
                |> Request.add_header("Content-Type", "application/json")
                |> Request.with_body(Str.to_utf8("{}"))

        match Http.send!(req) {
            Ok(response) =>
                if Response.status(response) == 200 {
                    body_string = match Str.from_utf8(Response.body(response)) {
                        Ok(text) => text
                        Err(_) => ""
                    }
                    token = extract_field(body_string, "access_token")

                    if Str.is_empty(token) {
                        Err("Matrix returned no access_token")
                    } else {
                        Ok(token)
                    }
                } else {
                    Err("Matrix login failed (HTTP ${U16.to_str(Response.status(response))}${error_detail(response)})")
                }
            Err(err) => Err(transport_message(err, trim_slash(api_base)))
        }
    }

    ## Whether a token the page already holds still works for this account. A minted token acts
    ## as the user (the admin API logs in "as" them), so whoami answers with the effective user:
    ## 200 + the caller's own id means the token is reusable and no new Synapse device has to be
    ## created. A 401 (or an id mismatch) means "mint a fresh one"; anything stranger is an Err
    ## the proxy reports.
    is_token_valid! : Str, Str, Str => [Ok(Bool), Err(Str)]
    is_token_valid! = |api_base, matrix_user_id, token| {
        req =
            Request.from_method(GET)
                |> Request.with_uri("${trim_slash(api_base)}/_matrix/client/v3/account/whoami")
                |> Request.add_header("Authorization", "Bearer ${token}")
                |> Request.add_header("Accept", "application/json")

        match Http.send!(req) {
            Ok(response) =>
                if Response.status(response) == 200 {
                    body_string = match Str.from_utf8(Response.body(response)) {
                        Ok(text) => text
                        Err(_) => ""
                    }
                    Ok(extract_field(body_string, "user_id") == matrix_user_id)
                } else if Response.status(response) == 401 {
                    Ok(Bool.False)
                } else {
                    Err("Matrix token check failed (HTTP ${U16.to_str(Response.status(response))}${error_detail(response)})")
                }
            Err(err) => Err(transport_message(err, trim_slash(api_base)))
        }
    }

    ## The homeserver's own error text for a failed call, if the body carries one — the admin API
    ## answers `{"errcode":…,"error":"…"}`. Empty when there is nothing to add.
    error_detail : Response -> Str
    error_detail = |response| {
        body_string = match Str.from_utf8(Response.body(response)) {
            Ok(text) => text
            Err(_) => ""
        }
        error_text = extract_field(body_string, "error")

        if Str.is_empty(error_text) {
            ""
        } else {
            ": ${error_text}"
        }
    }

    ## Escape text for a JSON string literal — the display name comes from a userinfo body and may
    ## carry quotes or newlines.
    json_string : Str -> Str
    json_string = |text| {
        text
            |> Str.replace_each("\\", "\\\\")
            |> Str.replace_each("\"", "\\\"")
            |> Str.replace_each("\n", " ")
            |> Str.replace_each("\r", " ")
    }

    ## One JSON string field, read with the fixed scanners this codebase uses everywhere (this Roc
    ## version has no JSON parser).
    extract_field : Str, Str -> Str
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

    ## A readable reason for an outbound call that never got a response, so a chat page problem is
    ## not a wall of "Http Error". The transport failure behind `HttpErr` is an opaque type this
    ## package cannot destructure, so what stays actionable is naming the homeserver being contacted
    ## — the misconfiguration this usually hides is a `PUBLIC_MATRIX_URL` that points somewhere
    ## unreachable.
    transport_message = |err, api_base| {
        match err {
            InvalidUrl(_) => "invalid URL for the Matrix homeserver: ${api_base}"
            InvalidRequest(message) => "invalid request to the Matrix homeserver: ${message}"
            _ => "cannot reach the Matrix homeserver at ${api_base}"
        }
    }
}
