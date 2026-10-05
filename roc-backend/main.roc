app [Context, program] {
    pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.14.0-rc1/GfM5qZLcKYGA9XD4V7u1S4RjWrdfws29Uz2m86C7bmUC.tar.zst",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import pf.Env
import pf.OsStr
import pf.Path
import pf.Stdout
import http.Response
import http.Method
import SurrealDB
import Base64
import Golem
import Authentik

Context : { surreal: SurrealDB.Config, dev_mode: Bool, static_dir: Str }

program = { init!, respond!, shutdown! }

# --- Environment helpers ---

env_or! : OsStr, Str => Str
env_or! = |name, fallback|
    match Env.var_str!(name) {
        Ok(value) if !Str.is_empty(value) => value
        _ => fallback
    }

# The SurrealDB HTTP API authenticates with `Basic base64(user:password)`.
# Empty when either half is missing, so a missing credential is visible rather than silent.
basic_auth! : Str, Str => Str
basic_auth! = |user, password|
    if Str.is_empty(user) or Str.is_empty(password) {
        ""
    } else {
        "Basic ${Base64.encode("${user}:${password}")}"
    }

warn! : Str => {}
warn! = |message|
    match Stdout.line!(message) {
        Ok(_) => {}
        Err(_) => {}
    }

# --- Startup ---

init! : () => [Ok({ config : Server.Config, context : Context }), Err([Exit(I64)])]
init! = || {
    # SurrealDB connection, entirely from the environment (Infisical injects the secrets).
    # SURREAL_AUTH wins verbatim; otherwise the Basic header is built from the credentials at
    # startup, so no credential lives in source. The default URL is the public prod endpoint:
    # SURREAL_DB_HOST is an in-cluster address, so only SURREAL_URL can override it.
    surreal_url = env_or!("SURREAL_URL", "https://db2.johnethel.school/sql")
    surreal_ns = env_or!("SURREAL_DB_NS", "main")
    surreal_db = env_or!("SURREAL_DB", "lessons")
    auth_override = env_or!("SURREAL_AUTH", "")
    auth_user = env_or!("SURREAL_USER", "")
    auth_password = env_or!("SURREAL_PASS", "")
    surreal_auth = if Str.is_empty(auth_override) { basic_auth!(auth_user, auth_password) } else { auth_override }
    dev_mode_str = env_or!("DEV_MODE", "false")
    static_dir_str = env_or!("STATIC_DIR", "../roc-frontend/www")
    # The platform default is loopback-only on 8000. That is the right default locally, but a
    # container (or any reverse proxy in another network namespace) cannot reach it, so deployments
    # set BIND_HOST=0.0.0.0. The port is configurable too, so a second instance (another sandbox, a
    # test run) can sit beside the first.
    bind_host = env_or!("BIND_HOST", "127.0.0.1")
    port = match U16.from_str(env_or!("PORT", "8000")) {
        Ok(parsed) => parsed
        Err(_) => 8000
    }

    if Str.is_empty(surreal_auth) {
        warn!("No SurrealDB credentials: set SURREAL_USER/SURREAL_PASS (or SURREAL_AUTH).")
    } else {
        {}
    }

    Ok({
        config: Server.default_config.with_listen({ host: bind_host, port }),
        context: {
            surreal: { url: surreal_url, ns: surreal_ns, db: surreal_db, auth: surreal_auth },
            dev_mode: dev_mode_str == "true",
            static_dir: static_dir_str,
        },
    })
}

# --- CORS ---

cors_headers = [
    { name: "Content-Type", value: "application/json" },
    { name: "Access-Control-Allow-Origin", value: "*" },
    { name: "Access-Control-Allow-Methods", value: "GET, POST, PUT, DELETE, OPTIONS" },
    { name: "Access-Control-Allow-Headers", value: "Content-Type, Authorization" },
]

# --- Auth helpers ---

get_token = |headers| {
    auth_headers = List.keep_if(headers, |h| h.name == "Authorization" or h.name == "authorization")
    match List.first(auth_headers) {
        Ok(h) => {
            if Str.starts_with(h.value, "Bearer ") {
                auth_token = Str.replace_each(h.value, "Bearer ", "")
                Ok(auth_token)
            } else {
                Err("Missing Bearer Prefix")
            }
        }
        Err(_) => Err("No Authorization header")
    }
}

# --- SurrealQL helpers ---

# Read one query parameter from a request target: query_param("/api/x?a=1&b=2", "b") == "2".
query_param : Str, Str => Str
query_param = |target, name|
    match List.get(Str.split_on(target, "${name}="), 1) {
        Ok(rest) =>
            match List.first(Str.split_on(rest, "&")) {
                Ok(value) => value
                Err(_) => ""
            }
        Err(_) => ""
    }

# Record reference for a parameter that is either a full record id
# ("subjects:agricultural_science") or a bare id ("agricultural_science").
# A record link never equals a quoted string, so the value has to stay a record literal.
record_ref! : Str, Str => Str
record_ref! = |raw, table| {
    "type::record('${table}', '${bare_id(raw)}')"
}

# Bare record id: "lessons:abc" and "abc" both become "abc". Stored string fields such as
# submissions.assessment_id hold the bare form (the MoonBit stack's convention), so rows written
# by either stack are found by both.
bare_id : Str => Str
bare_id = |raw| {
    match List.last(Str.split_on(raw, ":")) {
        Ok(id) => id |> sanitize
        Err(_) => raw |> sanitize
    }
}

# Escape text for a single-quoted SurrealQL string literal.
surreal_literal : Str => Str
surreal_literal = |text| {
    text
        |> Str.replace_each("\\", "\\\\")
        |> Str.replace_each("'", "\\'")
        |> Str.replace_each("\n", " ")
        |> Str.replace_each("\r", " ")
}

# Read a numeric JSON field as text: extract_number_field(body, "iteration") == "3".
extract_number_field : Str, Str => Str
extract_number_field = |json_str, field| {
    parts = Str.split_on(json_str, "\"${field}\":")
    match List.get(parts, 1) {
        Ok(rest) => {
            chunk = match List.first(Str.split_on(rest, ",")) { Ok(v) => v, Err(_) => rest }
            digits = List.keep_if(Str.to_utf8(chunk), |byte| byte >= 48 and byte <= 57)
            match Str.from_utf8(digits) {
                Ok(text) => text
                Err(_) => ""
            }
        }
        Err(_) => ""
    }
}

# Read a JSON boolean field: json_bool(body, "active") == "true".
json_bool : Str, Str => Str
json_bool = |json_str, field| {
    parts = Str.split_on(json_str, "\"${field}\":")
    match List.get(parts, 1) {
        Ok(rest) => if Str.starts_with(Str.trim(rest), "true") { "true" } else { "false" }
        Err(_) => "false"
    }
}

# Extract a JSON array field's text, e.g. `"questions":[{...},{...}]`. Like extract_field this scans
# text rather than parsing, but it tracks bracket depth and skips over string literals so nested
# objects and punctuation in question text survive.
extract_json_array : Str, Str => Str
extract_json_array = |json_str, field| {
    parts = Str.split_on(json_str, "\"${field}\":")
    match List.get(parts, 1) {
        Ok(rest) => {
            trimmed = Str.trim(rest)
            if Str.starts_with(trimmed, "[") {
                bytes = Str.to_utf8(trimmed)
                taken = take_json_array(bytes, 0, Bool.False, [])
                match Str.from_utf8(taken) {
                    Ok(text) => text
                    Err(_) => ""
                }
            } else {
                ""
            }
        }
        Err(_) => ""
    }
}

# Walk until the array opened by the first byte closes again. Escaped quotes inside strings are
# skipped so a `"` in question text does not end the scan.
take_json_array : List(U8), U8, Bool, List(U8) -> List(U8)
take_json_array = |bytes, depth, in_string, out| {
    match bytes {
        [] => out
        [byte, .. as rest] => {
            if in_string {
                next_out = List.append(out, byte)
                if byte == 92 { # backslash: copy the escaped byte verbatim
                    match rest {
                        [] => next_out
                        [escaped, .. as after] => take_json_array(after, depth, Bool.True, List.append(next_out, escaped))
                    }
                } else if byte == 34 {
                    take_json_array(rest, depth, Bool.False, next_out)
                } else {
                    take_json_array(rest, depth, Bool.True, next_out)
                }
            } else if byte == 34 {
                take_json_array(rest, depth, Bool.True, List.append(out, byte))
            } else if byte == 91 {
                take_json_array(rest, depth + 1, Bool.False, List.append(out, byte))
            } else if byte == 93 {
                next_depth = depth - 1
                next_out = List.append(out, byte)
                if next_depth == 0 { next_out } else { take_json_array(rest, next_depth, Bool.False, next_out) }
            } else {
                take_json_array(rest, depth, Bool.False, List.append(out, byte))
            }
        }
    }
}

# The authenticated user's id, used as the profile record id (the MoonBit stack's convention).
# The dev tokens have no userinfo body, so they fall back to their literal value.
caller_id! : Str => Str
caller_id! = |user| {
    sub = extract_field(user, "sub")
    if !Str.is_empty(sub) {
        bare_id(sub)
    } else {
        uid = extract_field(user, "uid")
        if !Str.is_empty(uid) {
            bare_id(uid)
        } else if Str.is_empty(user) {
            "unknown"
        } else {
            bare_id(user)
        }
    }
}

# A JSON array from the request body, ready to embed as a SurrealQL literal (this SurrealDB version
# has no json::parse). The column is array<object>, so it always has to be set. The extractor stops
# at the matching `]`, and callers reject `;` as well, so a payload cannot chain statements.
json_array_or_empty! = |body, field| {
    taken = extract_json_array(body, field)
    if Str.is_empty(taken) { "[]" } else { taken }
}

# --- User creation (T7) ---

# Loose shape check; the database casts to datetime and rejects anything else.
looks_like_date = |text| {
    Str.count_utf8_bytes(text) == 10 and Str.contains(text, "-")
}

# The profile tables are SCHEMAFULL and require these fields; the passport rule
# mirrors validate_passport_url in the MoonBit admin agent, so both stacks accept
# the same input.
validate_new_user! = |role, email, first_name, surname, date_of_birth, class_level, passport| {
    if Str.is_empty(email) {
        Err("email is required")
    } else if Str.is_empty(first_name) {
        Err("first_name is required")
    } else if Str.is_empty(surname) {
        Err("surname is required")
    } else if Str.is_empty(passport) {
        Err("passport is required")
    } else if !Str.contains(passport, "://") {
        Err("passport must be a URL (e.g. https://...)")
    } else if role == "Student" and Str.is_empty(date_of_birth) {
        Err("date_of_birth is required for students")
    } else if role == "Student" and !looks_like_date(date_of_birth) {
        Err("date_of_birth must look like YYYY-MM-DD")
    } else if role == "Student" and Str.is_empty(class_level) {
        Err("class_level is required for students")
    } else {
        Ok({})
    }
}

# Record links are not existence-checked by the schema, so a typo would leave a
# student pointing at a class level that does not exist.
class_level_exists! = |class_level, config| {
    res = SurrealDB.query!("SELECT id FROM ${record_ref!(class_level, "class_levels")};", config)
    match res {
        Ok(body) => Str.contains(body, "\"result\":[{\"id\"")
        Err(_) => Bool.False
    }
}

profile_table_for = |role| {
    if role == "Teacher" { "teacher_profile" }
    else if role == "Parent" { "parent_profile" }
    else if role == "Admin" { "admin_profile" }
    else { "student_profile" }
}

# Build the profile INSERT for the chosen role. Field sets mirror the prod tables:
# parents carry a single `name`, students carry date_of_birth plus their class links,
# admins may carry a role_title, teachers nothing extra.
profile_create_sql! = |role, user_id, first_name, middle_name, surname, display_name, date_of_birth, class_level, role_title, passport| {
    if role == "Parent" {
        # parent_profile carries both `name` and `display_name` in the prod schema.
        "CREATE type::record('parent_profile', '${user_id}') SET name = '${display_name}', display_name = '${display_name}', passport = '${passport}', created_at = time::now();"
    } else {
        optional = List.keep_if(
            [
                if Str.is_empty(middle_name) { "" } else { "middle_name = '${middle_name}'" },
                if Str.is_empty(role_title) { "" } else { "role_title = '${role_title}'" },
                if Str.is_empty(date_of_birth) { "" } else { "date_of_birth = <datetime> '${date_of_birth}'" },
                if Str.is_empty(class_level) { "" } else { "current_class = ${record_ref!(class_level, "class_levels")}" },
                if Str.is_empty(class_level) { "" } else { "class_enrolled = ${record_ref!(class_level, "class_levels")}" },
            ],
            |field| !Str.is_empty(field),
        )
        fields = List.concat(
            [
                "first_name = '${first_name}'",
                "surname = '${surname}'",
                "display_name = '${display_name}'",
                "passport = '${passport}'",
                "created_at = time::now()",
            ],
            optional,
        )

        "CREATE type::record('${profile_table_for(role)}', '${user_id}') SET ${Str.join_with(fields, ", ")};"
    }
}

# --- Input sanitization ---

sanitize = |val| {
    val
        |> Str.replace_each("'", "''")
        |> Str.replace_each("\\", "\\\\")
        |> Str.replace_each(";", "")
        |> Str.replace_each("--", "")
        |> Str.replace_each("/*", "")
        |> Str.replace_each("*/", "")
        |> Str.replace_each("DROP", "")
        |> Str.replace_each("DELETE", "")
        |> Str.replace_each("UPDATE ", "")
        |> Str.replace_each("ALTER ", "")
        |> Str.replace_each("REMOVE ", "")
}

# Escape text so it can be embedded inside a JSON string literal.
sanitize_json_text : Str => Str
sanitize_json_text = |text| {
    text
        |> Str.replace_each("\\", "\\\\")
        |> Str.replace_each("\"", "\\\"")
        |> Str.replace_each("\n", " ")
        |> Str.replace_each("\r", " ")
}

# --- JSON field extractor ---

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

# --- Body reader ---

read_body! = |request| {
    body_res = Server.Body.read_all!(request.body)
    match body_res {
        Ok(bytes) =>
            match Str.from_utf8(bytes) {
                Ok(s) => s
                Err(_) => "{}"
            }
        Err(_) => "{}"
    }
}

# --- Response helpers ---

json_response = |status, body| {
    Server.respond(
        Response.from_status(status)
            |> Response.with_headers(cors_headers)
            |> Response.with_body(Str.to_utf8(body))
    )
}

# SurrealDB answers HTTP 200 even when a statement fails: the failure sits in the body as
# `"status":"ERR"` with the message in `result`. Trusting the status is how a write reports success
# while nothing was stored, so every write goes through here. `Ok` is the raw body, for the callers
# that still need to read values out of it.
db_body! : Str, SurrealDB.Config => [Ok(Str), Err(Str)]
db_body! = |sql, config| {
    match SurrealDB.query!(sql, config) {
        Ok(body) =>
            if Str.contains(body, "\"status\":\"ERR\"") {
                Err(extract_field(body, "result"))
            } else {
                Ok(body)
            }
        Err(HttpErr) => Err("could not reach the database")
        Err(JsonErr) => Err("invalid response from the database")
        Err(SurrealErr(body)) => Err(extract_field(body, "result"))
    }
}

# The response for a write whose body is passed through: the stored rows, or a 500 carrying the
# statement's own message instead of a bare "Database error".
db_response! : Str, SurrealDB.Config => Server.Outcome
db_response! = |sql, config| {
    match db_body!(sql, config) {
        Ok(body) => json_response(200, body)
        Err(detail) => json_response(500, "{\"error\":\"Database error\",\"detail\":\"${sanitize_json_text(detail)}\"}")
    }
}

# --- Content-Type from file extension ---

content_type_for = |path| {
    if Str.ends_with(path, ".html") { "text/html; charset=utf-8" }
    else if Str.ends_with(path, ".css") { "text/css; charset=utf-8" }
    else if Str.ends_with(path, ".js") { "text/javascript; charset=utf-8" }
    else if Str.ends_with(path, ".mjs") { "text/javascript; charset=utf-8" }
    else if Str.ends_with(path, ".json") { "application/json; charset=utf-8" }
    else if Str.ends_with(path, ".wasm") { "application/wasm" }
    else if Str.ends_with(path, ".png") { "image/png" }
    else if Str.ends_with(path, ".jpg") or Str.ends_with(path, ".jpeg") { "image/jpeg" }
    else if Str.ends_with(path, ".svg") { "image/svg+xml" }
    else if Str.ends_with(path, ".ico") { "image/x-icon" }
    else if Str.ends_with(path, ".woff2") { "font/woff2" }
    else if Str.ends_with(path, ".woff") { "font/woff" }
    else if Str.ends_with(path, ".ttf") { "font/ttf" }
    else { "application/octet-stream" }
}

# --- Static file serving with SPA fallback ---

serve_static! : Str, Str => Server.Outcome
serve_static! = |target, static_dir| {
    # Security: prevent directory traversal
    stripped_query = match Str.split_on(target, "?") |> List.first { Ok(v) => v, Err(_) => "/" }
    stripped_hash = match Str.split_on(stripped_query, "#") |> List.first { Ok(v) => v, Err(_) => "/" }
    clean_path = stripped_hash
        |> Str.replace_each("..", "")
        |> Str.replace_each("//", "/")

    # Determine file path
    file_rel = if clean_path == "/" { "/index.html" } else { clean_path }
    file_path = "${static_dir}${file_rel}"

    # Try serving the file, fall back to index.html for SPA routing
    path_obj = Path.unix(file_path)
    file_exists = match Path.is_file!(path_obj) { Ok(b) => b, Err(_) => Bool.False }

    actual_path = if file_exists { file_path } else { "${static_dir}/index.html" }
    actual_content_type = if file_exists { content_type_for(file_path) } else { "text/html; charset=utf-8" }

    bytes_result = Path.read_bytes!(Path.unix(actual_path))
    match bytes_result {
        Ok(bytes) =>
            Server.respond(
                Response.from_status(200)
                    |> Response.with_headers([
                        { name: "Content-Type", value: actual_content_type },
                        { name: "Cache-Control", value: if Str.ends_with(actual_path, ".wasm") or Str.ends_with(actual_path, ".css") { "public, max-age=3600" } else { "no-cache" } },
                    ])
                    |> Response.with_body(bytes)
            )
        Err(_) =>
            Server.respond(
                Response.from_status(404)
                    |> Response.with_headers([{ name: "Content-Type", value: "text/plain" }])
                    |> Response.with_body(Str.to_utf8("404 Not Found"))
            )
    }
}

# --- Main request handler ---

respond! : Server.Request, Context => [Ok(Server.Outcome), Err([ServerErr(Str)])]
respond! = |request, context| {
    # OPTIONS preflight
    if Method.is_eq(request.method, OPTIONS) {
        Ok(
            Server.respond(
                Response.from_status(204)
                    |> Response.with_headers(cors_headers)
            )
        )
    } else if request.target == "/health" {
        res = SurrealDB.query!("INFO FOR DB;", context.surreal)
        status_text =
            match res {
                Ok(_) => "surreal db is healthy"
                Err(_) => "surreal db is down"
            }
        Ok(json_response(200, "{\"status\":\"healthy\", \"db\":\"${status_text}\"}"))

    # --- API routes (require auth) ---
    } else if Str.starts_with(request.target, "/api/") {
        token_res = get_token(request.headers)
        
        user_result = 
            match token_res {
                Ok("dev-skip") => if context.dev_mode { Ok("dev_user") } else { Err("Invalid token") }
                Ok("test-token") => if context.dev_mode { Ok("user_123") } else { Err("Invalid token") }
                Ok(t) => Authentik.validateToken!(t)
                Err(e) => Err(e)
            }
            
        match user_result {
            Err(e) => 
                Ok(json_response(401, "{\"error\":\"Unauthorized: ${e}\"}"))
            Ok(user_json) => {
                if Method.is_eq(request.method, GET) and request.target == "/api/students" {
                    res = SurrealDB.query!("SELECT id, display_name, first_name, surname, passport, created_at, current_class FROM student_profile WHERE deleted_at IS NONE ORDER BY created_at DESC;", context.surreal)
                    match res {
                        Ok(body) => Ok(json_response(200, body))
                        Err(_) => Ok(json_response(500, "{\"error\":\"Database error\"}"))
                    }
                } else if Method.is_eq(request.method, POST) and request.target == "/api/students" {
                    # Superseded by POST /api/users, which writes a student_profile record.
                    Ok(json_response(400, "{\"error\":\"Use POST /api/users with role=Student\"}"))
                } else if Method.is_eq(request.method, POST) and request.target == "/api/enroll" {
                    payload_raw = read_body!(request)
                    
                    student_id = extract_field(payload_raw, "student_id") |> sanitize
                    class_id = extract_field(payload_raw, "class_id") |> sanitize
                    payload_str = "{\"student_id\": \"${student_id}\", \"class_id\": \"${class_id}\"}"
                    
                    res = Golem.invokeClassAgent!("cs101", payload_str)
                    
                    match res {
                        Ok(body) => Ok(json_response(200, body))
                        Err(_) => Ok(json_response(500, "{\"error\":\"Golem error\"}"))
                    }
                } else if Method.is_eq(request.method, GET) and request.target == "/api/teachers" {
                    res = SurrealDB.query!("SELECT id, display_name, first_name, surname, passport, created_at FROM teacher_profile WHERE deleted_at IS NONE ORDER BY created_at DESC;", context.surreal)
                    match res {
                        Ok(body) => Ok(json_response(200, body))
                        Err(_) => Ok(json_response(500, "{\"error\":\"Database error\"}"))
                    }
                } else if Method.is_eq(request.method, POST) and request.target == "/api/teachers" {
                    # Superseded by POST /api/users, which writes a teacher_profile record.
                    Ok(json_response(400, "{\"error\":\"Use POST /api/users with role=Teacher\"}"))
                } else if Method.is_eq(request.method, GET) and request.target == "/api/subjects" {
                    res = SurrealDB.query!("SELECT id, name, code FROM subjects WHERE active = true ORDER BY name;", context.surreal)
                    match res {
                        Ok(body) => Ok(json_response(200, body))
                        Err(_) => Ok(json_response(500, "{\"error\":\"Database error\"}"))
                    }
                } else if Method.is_eq(request.method, POST) and request.target == "/api/subjects" {
                    payload_raw = read_body!(request)
                    
                    name_val = extract_field(payload_raw, "name") |> sanitize
                    code_val = extract_field(payload_raw, "code") |> sanitize
                    payload_str = "{\"name\": \"${name_val}\", \"code\": \"${code_val}\"}"
                    
                    Ok(db_response!("CREATE subjects CONTENT ${payload_str};", context.surreal))
                } else if Method.is_eq(request.method, GET) and request.target == "/api/terms" {
                    # Admin config hub: every term, ordered. Students get the active subset below.
                    res = SurrealDB.query!("SELECT id, name, sort_order, active FROM terms ORDER BY sort_order;", context.surreal)
                    match res {
                        Ok(body) => Ok(json_response(200, body))
                        Err(_) => Ok(json_response(500, "{\"error\":\"Database error\"}"))
                    }
                } else if Method.is_eq(request.method, POST) and request.target == "/api/terms" {
                    payload_raw = read_body!(request)
                    safe_payload = payload_raw |> sanitize
                    
                    Ok(db_response!("CREATE terms CONTENT ${safe_payload};", context.surreal))
                } else if Method.is_eq(request.method, GET) and request.target == "/api/class_levels" {
                    res = SurrealDB.query!("SELECT id, name, code, age_range FROM class_levels WHERE active = true ORDER BY name;", context.surreal)
                    match res {
                        Ok(body) => Ok(json_response(200, body))
                        Err(_) => Ok(json_response(500, "{\"error\":\"Database error\"}"))
                    }
                } else if Method.is_eq(request.method, POST) and request.target == "/api/class_levels" {
                    payload_raw = read_body!(request)
                    safe_payload = payload_raw |> sanitize
                    
                    Ok(db_response!("CREATE class_levels CONTENT ${safe_payload};", context.surreal))
                } else if Method.is_eq(request.method, GET) and request.target == "/api/curriculum" {
                    # The curriculum is the class_levels -> subjects edge in the prod schema.
                    res = SurrealDB.query!("SELECT id, in, out, active FROM has_subject WHERE active = true;", context.surreal)
                    match res {
                        Ok(body) => Ok(json_response(200, body))
                        Err(_) => Ok(json_response(500, "{\"error\":\"Database error\"}"))
                    }
                } else if Method.is_eq(request.method, POST) and request.target == "/api/curriculum" {
                    Ok(json_response(400, "{\"error\":\"Curriculum is the has_subject edge; it is managed in the database, not through this endpoint\"}"))
                } else if Method.is_eq(request.method, GET) and request.target == "/api/class_arms" {
                    Ok(json_response(410, "{\"error\":\"Class arms are not part of the current schema; use class_levels and class_terms\"}"))
                } else if Method.is_eq(request.method, POST) and request.target == "/api/class_arms" {
                    Ok(json_response(410, "{\"error\":\"Class arms are not part of the current schema; use class_levels and class_terms\"}"))
                } else if Method.is_eq(request.method, POST) and request.target == "/api/users" {
                    # Create the login in Authentik, then the role's profile record. A failed
                    # profile write removes the login again so the admin can retry.
                    payload_raw = read_body!(request)

                    role = extract_field(payload_raw, "role") |> sanitize
                    email_val = extract_field(payload_raw, "email") |> sanitize
                    first_name = extract_field(payload_raw, "first_name") |> sanitize
                    middle_name = extract_field(payload_raw, "middle_name") |> sanitize
                    surname = extract_field(payload_raw, "surname") |> sanitize
                    date_of_birth = extract_field(payload_raw, "date_of_birth") |> sanitize
                    class_level = extract_field(payload_raw, "class_level") |> sanitize
                    role_title = extract_field(payload_raw, "role_title") |> sanitize
                    passport = extract_field(payload_raw, "passport") |> sanitize
                    display_name =
                        if Str.is_empty(middle_name) { "${first_name} ${surname}" } else { "${first_name} ${middle_name} ${surname}" }

                    match validate_new_user!(role, email_val, first_name, surname, date_of_birth, class_level, passport) {
                        Err(message) => Ok(json_response(400, "{\"error\":\"${message}\"}"))
                        Ok(_) => {
                            # Check the class level before creating a login, so an invalid profile
                            # never leaves an orphan account behind.
                            class_ok =
                                if role == "Student" { class_level_exists!(class_level, context.surreal) } else { Bool.True }
                            if !class_ok {
                                Ok(json_response(400, "{\"error\":\"class_level '${class_level}' does not exist\"}"))
                            } else {
                            auth_res = Authentik.createUser!(email_val, display_name)
                            match auth_res {
                                Ok(user_id) => {
                                    create_sql = profile_create_sql!(role, user_id, first_name, middle_name, surname, display_name, date_of_birth, class_level, role_title, passport)
                                    # SurrealDB answers 200 even when a statement fails, so the body decides.
                                    created = db_body!(create_sql, context.surreal)
                                    match created {
                                        Ok(body) => Ok(json_response(200, body))
                                        Err(detail) => {
                                            # Compensate: drop the login so a retry can succeed.
                                            match Authentik.deleteUser!(user_id) {
                                                Ok(_) => {}
                                                Err(_) => {}
                                            }
                                            Ok(json_response(500, "{\"error\":\"Profile could not be created; the login was removed so you can retry\",\"detail\":\"${sanitize_json_text(detail)}\"}"))
                                        }
                                    }
                                }
                                Err(err_msg) => Ok(json_response(502, "{\"error\":\"Authentik error: ${err_msg}\"}"))
                            }
                            }
                        }
                    }
                } else if Method.is_eq(request.method, GET) and Str.starts_with(request.target, "/api/users") {
                    # Support ?role=Student|Teacher|Parent|Admin for tab filtering
                    role_param =
                        if Str.contains(request.target, "role=Student") { "student_profile" }
                        else if Str.contains(request.target, "role=Teacher") { "teacher_profile" }
                        else if Str.contains(request.target, "role=Parent") { "parent_profile" }
                        else if Str.contains(request.target, "role=Admin") { "admin_profile" }
                        else { "student_profile" }
                    query = "SELECT id, display_name, first_name, surname, email, is_active, passport, created_at, current_class FROM ${role_param} WHERE deleted_at IS NONE ORDER BY created_at DESC;"
                    res = SurrealDB.query!(query, context.surreal)
                    match res {
                        Ok(body) => Ok(json_response(200, body))
                        Err(_) => Ok(json_response(500, "{\"error\":\"Database error\"}"))
                    }

                # --- Student Lesson APIs ---
                } else if Method.is_eq(request.method, GET) and request.target == "/api/student/subjects" {
                    res = SurrealDB.query!("SELECT id, name, code FROM subjects WHERE active = true ORDER BY name;", context.surreal)
                    match res {
                        Ok(body) => Ok(json_response(200, body))
                        Err(_) => Ok(json_response(500, "{\"error\":\"Database error\"}"))
                    }
                 } else if Method.is_eq(request.method, GET) and Str.starts_with(request.target, "/api/student/terms") {
                     # Prod: terms are school-wide (Noel/Calvary/Summer)
                     res = SurrealDB.query!("SELECT id, name, sort_order FROM terms WHERE active = true ORDER BY sort_order;", context.surreal)
                     match res {
                         Ok(body) => Ok(json_response(200, body))
                         Err(_) => Ok(json_response(500, "{\"error\":\"Database error\"}"))  
                     }
                 } else if Method.is_eq(request.method, GET) and Str.starts_with(request.target, "/api/student/lessons") {
                     # Prod: a lesson hangs off the has_subject edge (class_levels -> subjects) and one
                     # terms record. The class-level filter is skipped until students are enrolled
                     # (student_profile is empty), so a subject matches every class level.
                     subject_param = query_param(request.target, "subject_id")
                     term_param = query_param(request.target, "term_id")
                     clauses = List.keep_if(
                         [
                             if Str.is_empty(subject_param) { "" } else { "has_subject.out = ${record_ref!(subject_param, "subjects")}" },
                             if Str.is_empty(term_param) { "" } else { "term = ${record_ref!(term_param, "terms")}" },
                             "active = true",
                         ],
                         |clause| !Str.is_empty(clause),
                     )
                     lessons_query = "SELECT id, topic_title, week FROM lessons WHERE ${Str.join_with(clauses, " AND ")} ORDER BY week;"
                     res = SurrealDB.query!(lessons_query, context.surreal)
                     match res {
                         Ok(body) => Ok(json_response(200, body))
                         Err(_) => Ok(json_response(500, "{\"error\":\"Database error\"}"))
                     }
                 } else if Method.is_eq(request.method, GET) and Str.starts_with(request.target, "/api/student/lesson") {
                     lesson_id = query_param(request.target, "lesson_id")
                     if Str.is_empty(lesson_id) {
                         Ok(json_response(400, "{\"error\":\"Missing lesson_id\"}"))
                     } else {
                         # The whole record: lesson content lives in the nested `content` object.
                         res = SurrealDB.query!("SELECT * FROM ${record_ref!(lesson_id, "lessons")};", context.surreal)
                         match res {
                             Ok(body) => Ok(json_response(200, body))
                             Err(_) => Ok(json_response(500, "{\"error\":\"Database error\"}"))
                         }
                     }

                # --- Teacher Lesson/Assessment APIs ---
                } else if Method.is_eq(request.method, GET) and Str.starts_with(request.target, "/api/teacher/lessons") {
                    # With a lesson id this is the viewer asking for one lesson; without it, the picker's list.
                    lesson_id = query_param(request.target, "lesson_id")
                    lessons_query =
                        if Str.is_empty(lesson_id) {
                            "SELECT id, topic_title, week, term, active FROM lessons WHERE active = true ORDER BY week LIMIT 50;"
                        } else {
                            "SELECT * FROM ${record_ref!(lesson_id, "lessons")};"
                        }
                    res = SurrealDB.query!(lessons_query, context.surreal)
                    match res {
                        Ok(body) => Ok(json_response(200, body))
                        Err(_) => Ok(json_response(500, "{\"error\":\"Database error\"}"))
                    }
                } else if Method.is_eq(request.method, GET) and Str.starts_with(request.target, "/api/student/assessments") {
                    # Students only see published (active) assessments.
                    lesson_id = query_param(request.target, "lesson_id")
                    scope = if Str.is_empty(lesson_id) or lesson_id == "none" { "" } else { "lesson = ${record_ref!(lesson_id, "lessons")} AND " }
                    res = SurrealDB.query!("SELECT * FROM lesson_assessments WHERE ${scope}active = true AND deleted_at IS NONE ORDER BY created_at DESC;", context.surreal)
                    match res {
                        Ok(body) => Ok(json_response(200, body))
                        Err(_) => Ok(json_response(500, "{\"error\":\"Database error\"}"))
                    }
                } else if Method.is_eq(request.method, GET) and Str.starts_with(request.target, "/api/teacher/lesson-assessments") {
                    # Teachers see their drafts too.
                    lesson_id = query_param(request.target, "lesson_id")
                    scope = if Str.is_empty(lesson_id) or lesson_id == "none" { "" } else { "lesson = ${record_ref!(lesson_id, "lessons")} AND " }
                    res = SurrealDB.query!("SELECT * FROM lesson_assessments WHERE ${scope}deleted_at IS NONE ORDER BY created_at DESC;", context.surreal)
                    match res {
                        Ok(body) => Ok(json_response(200, body))
                        Err(_) => Ok(json_response(500, "{\"error\":\"Database error\"}"))
                    }
                } else if Method.is_eq(request.method, POST) and request.target == "/api/teacher/create-lesson-assessment" {
                    # New assessments start as drafts: the teacher publishes them when ready.
                    payload_raw = read_body!(request)
                    lesson_id = extract_field(payload_raw, "lesson_id") |> sanitize
                    title = extract_field(payload_raw, "title") |> sanitize
                    description = extract_field(payload_raw, "description") |> sanitize
                    deadline = extract_field(payload_raw, "deadline") |> sanitize
                    questions = json_array_or_empty!(payload_raw, "questions")
                    if Str.is_empty(lesson_id) or lesson_id == "none" {
                        Ok(json_response(400, "{\"error\":\"lesson_id is required\"}"))
                    } else if Str.is_empty(title) {
                        Ok(json_response(400, "{\"error\":\"title is required\"}"))
                    } else if Str.contains(questions, ";") {
                        Ok(json_response(400, "{\"error\":\"questions must be a JSON array without statement separators\"}"))
                    } else {
                        total_mark = extract_number_field(payload_raw, "total_mark")
                        total_mark_clause = if Str.is_empty(total_mark) { "0" } else { total_mark }
                        description_clause = if Str.is_empty(description) { "" } else { ", description = '${surreal_literal(description)}'" }
                        deadline_clause = if Str.is_empty(deadline) { "" } else { ", deadline = <datetime> '${deadline}'" }
                        create_query = "CREATE lesson_assessments SET lesson = ${record_ref!(lesson_id, "lessons")}, title = '${surreal_literal(title)}'${description_clause}, questions = ${questions}, total_mark = ${total_mark_clause}, active = false, created_by = ${record_ref!(caller_id!(user_json), "teacher_profile")}, created_at = time::now()${deadline_clause};"
                        Ok(db_response!(create_query, context.surreal))
                    }
                } else if Method.is_eq(request.method, POST) and request.target == "/api/teacher/toggle-assessment-active" {
                    # Publishing and unpublishing: students only see active assessments.
                    payload_raw = read_body!(request)
                    assessment_id = extract_field(payload_raw, "assessment_id") |> sanitize
                    active = json_bool(payload_raw, "active")
                    if Str.is_empty(assessment_id) {
                        Ok(json_response(400, "{\"error\":\"assessment_id is required\"}"))
                    } else {
                        Ok(db_response!("UPDATE ${record_ref!(assessment_id, "lesson_assessments")} SET active = ${active}, updated_at = time::now();", context.surreal))
                    }
                } else if Method.is_eq(request.method, GET) and Str.starts_with(request.target, "/api/teacher/submissions") {
                    assessment_id = query_param(request.target, "assessment_id")
                    scope = if Str.is_empty(assessment_id) { "" } else { "WHERE assessment_id = '${bare_id(assessment_id)}' " }
                    subs_query = "SELECT *, student.display_name AS student_name, student.id AS student_ref, (scored_mark IS NOT NONE) AS graded FROM submissions ${scope}ORDER BY submitted_at DESC;"
                    res = SurrealDB.query!(subs_query, context.surreal)
                    match res {
                        Ok(body) => Ok(json_response(200, body))
                        Err(_) => Ok(json_response(500, "{\"error\":\"Database error\"}"))
                    }
                } else if Method.is_eq(request.method, POST) and request.target == "/api/student/submit-assessment" {
                    # One submission per student and assessment; a resubmission bumps the iteration
                    # in place so the teacher's grading list stays one row per student.
                    payload_raw = read_body!(request)
                    assessment_id = extract_field(payload_raw, "assessment_id") |> sanitize
                    answers = json_array_or_empty!(payload_raw, "answers")
                    student_id = caller_id!(user_json) |> sanitize
                    if Str.is_empty(assessment_id) {
                        Ok(json_response(400, "{\"error\":\"assessment_id is required\"}"))
                    } else if Str.contains(answers, ";") {
                        Ok(json_response(400, "{\"error\":\"answers must be a JSON array without statement separators\"}"))
                    } else {
                        bare_assessment = bare_id(assessment_id)
                        total_mark_res = SurrealDB.query!("SELECT total_mark FROM ${record_ref!(assessment_id, "lesson_assessments")};", context.surreal)
                        total_mark = match total_mark_res {
                            Ok(body) => {
                                found = extract_number_field(body, "total_mark")
                                if Str.is_empty(found) { "0" } else { found }
                            }
                            Err(_) => "0"
                        }
                        existing_res = SurrealDB.query!("SELECT meta::id(id) AS submission_id FROM submissions WHERE student = ${record_ref!(student_id, "student_profile")} AND assessment_id = '${bare_assessment}' ORDER BY iteration DESC LIMIT 1;", context.surreal)
                        existing_id = match existing_res {
                            Ok(body) => extract_field(body, "submission_id")
                            Err(_) => ""
                        }
                        submit_query =
                            if Str.is_empty(existing_id) {
                                "CREATE submissions SET assessment_type = 'lesson', assessment_id = '${bare_assessment}', student = ${record_ref!(student_id, "student_profile")}, iteration = 1, status = 'submitted', submitted_at = time::now(), answers = ${answers}, total_mark = ${total_mark};"
                            } else {
                                "UPDATE ${record_ref!(existing_id, "submissions")} SET iteration = iteration + 1, status = 'submitted', submitted_at = time::now(), answers = ${answers}, total_mark = ${total_mark};"
                            }
                        Ok(db_response!(submit_query, context.surreal))
                    }
                } else if Method.is_eq(request.method, POST) and request.target == "/api/teacher/grade-submission" {
                    payload_raw = read_body!(request)
                    submission_id = extract_field(payload_raw, "submission_id") |> sanitize
                    score = extract_number_field(payload_raw, "scored_mark")
                    if Str.is_empty(submission_id) {
                        Ok(json_response(400, "{\"error\":\"submission_id is required\"}"))
                    } else if Str.is_empty(score) {
                        Ok(json_response(400, "{\"error\":\"scored_mark must be a number\"}"))
                    } else {
                        # submissions has no graded_at column; scored_mark is what marks it graded.
                        Ok(db_response!("UPDATE ${record_ref!(submission_id, "submissions")} SET scored_mark = ${score};", context.surreal))
                    }
                } else if Method.is_eq(request.method, POST) and request.target == "/api/teacher/release-grades" {
                    payload_raw = read_body!(request)
                    submission_id = extract_field(payload_raw, "submission_id") |> sanitize
                    if Str.is_empty(submission_id) {
                        Ok(json_response(400, "{\"error\":\"submission_id is required\"}"))
                    } else {
                        Ok(db_response!("UPDATE ${record_ref!(submission_id, "submissions")} SET grade_released_at = time::now(), status = 'graded';", context.surreal))
                    }

                # --- Passport photo upload URL ---
                } else if Method.is_eq(request.method, POST) and request.target == "/api/upload-url" {
                    payload_raw = read_body!(request)
                    user_id_val = extract_field(payload_raw, "userId") |> sanitize
                    profile_type_val = extract_field(payload_raw, "profileType") |> sanitize
                    # Store the key for this user so the passport_url can be updated after upload
                    key_val = "${profile_type_val}/passports/${user_id_val}.jpg"
                    r2_public = match Env.var!("R2_PUBLIC_URL") { Ok(os) => OsStr.display(os), Err(_) => "" }
                    r2_endpoint = match Env.var!("R2_ENDPOINT_URL") { Ok(os) => OsStr.display(os), Err(_) => "" }
                    r2_bucket = match Env.var!("R2_BUCKET_NAME") { Ok(os) => OsStr.display(os), Err(_) => "" }
                    if Str.is_empty(r2_endpoint) {
                        Ok(json_response(503, "{\"error\":\"R2 not configured\"}"))
                    } else {
                        public_url = "${r2_public}/${key_val}"
                        # Return endpoint info — JS handles presigning via the port
                        Ok(json_response(200, "{\"key\":\"${key_val}\",\"publicUrl\":\"${public_url}\",\"endpoint\":\"${r2_endpoint}\",\"bucket\":\"${r2_bucket}\"}"))
                    }

                # --- Matrix token proxy ---
                } else if Method.is_eq(request.method, GET) and request.target == "/api/matrix/token" {
                    matrix_url = match Env.var!("PUBLIC_MATRIX_URL") { Ok(os) => OsStr.display(os), Err(_) => "" }
                    Ok(json_response(200, "{\"homeserver\":\"${matrix_url}\",\"token\":null}"))

                } else if Method.is_eq(request.method, PUT) and request.target == "/api/users" {
                    payload_raw = read_body!(request)
                    
                    id_val = extract_field(payload_raw, "id") |> sanitize
                    name_val = extract_field(payload_raw, "name") |> sanitize
                    email_val = extract_field(payload_raw, "email") |> sanitize
                    
                    Ok(db_response!("UPDATE student:${id_val} SET name = '${name_val}', email = '${email_val}', updated_at = time::now();", context.surreal))
                } else if Method.is_eq(request.method, DELETE) and request.target == "/api/users" {
                    payload_raw = read_body!(request)
                    
                    id_val = extract_field(payload_raw, "id") |> sanitize
                    
                    Ok(db_response!("UPDATE student:${id_val} SET deleted_at = time::now();", context.surreal))
                } else if Method.is_eq(request.method, GET) and request.target == "/api/session_terms" {
                    # Prod names this table in the singular.
                    res = SurrealDB.query!("SELECT id, session_name, term, active FROM session_term WHERE deleted_at IS NONE ORDER BY session_name;", context.surreal)
                    match res {
                        Ok(body) => Ok(json_response(200, body))
                        Err(_) => Ok(json_response(500, "{\"error\":\"Database error\"}"))
                    }
                } else if Method.is_eq(request.method, POST) and request.target == "/api/session_terms" {
                    payload_raw = read_body!(request)
                    session_name = extract_field(payload_raw, "session_name") |> sanitize
                    term_id = extract_field(payload_raw, "term") |> sanitize
                    if Str.is_empty(session_name) or Str.is_empty(term_id) {
                        Ok(json_response(400, "{\"error\":\"session_name and term are required\"}"))
                    } else {
                        Ok(db_response!("CREATE session_term SET session_name = '${session_name}', term = ${record_ref!(term_id, "terms")}, active = false, created_at = time::now();", context.surreal))
                    }
                } else {
                    Ok(json_response(404, "{\"error\":\"Not Found\"}"))
                }
            }
        }

    # --- Static file serving (SPA with fallback to index.html) ---
    } else {
        Ok(serve_static!(request.target, context.static_dir))
    }
}

shutdown! : Server.ShutdownReason, Context => [Ok({}), Err([Exit(I64)])]
shutdown! = |_reason, _context| Ok({})
