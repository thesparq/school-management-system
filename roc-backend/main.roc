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
import Url
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
# The value is percent-decoded through Url first: a record id holds a colon, which is not a legal
# query character, so a conforming client sends `?lesson_id=lessons%3Aabc` — read raw, that asks the
# database for a record literally named `lessons%3Aabc` and finds nothing. A value with nothing to
# decode (the app's own links send `lessons:abc`) comes back unchanged.
query_param : Str, Str => Str
query_param = |target, name|
    match List.get(Str.split_on(target, "${name}="), 1) {
        Ok(rest) =>
            match List.first(Str.split_on(rest, "&")) {
                Ok(value) => Url.decode(value)
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

# A numeric JSON field as an integer; missing or malformed counts as 0. The JSON scanners in this
# file carry an effect, so anything reading a number through them does too.
field_int! : Str, Str => U64
field_int! = |json_str, field| {
    match U64.from_str(extract_number_field(json_str, field)) {
        Ok(number) => number
        Err(_) => 0
    }
}

# Split a JSON array literal into its top-level element texts: `["a","b"]` -> ["\"a\"", "\"b\""].
# Depth- and string-aware like take_json_array, so commas inside nested objects or strings do not
# split and escaped quotes survive. Anything that is not an array yields no elements.
split_json_elements : Str -> List(Str)
split_json_elements = |json_str| {
    trimmed = Str.trim(json_str)
    if Str.starts_with(trimmed, "[") {
        # The walk starts after the array's own opening bracket; its closing bracket ends it.
        collect_elements(List.drop_first(Str.to_utf8(trimmed), 1), 0, Bool.False, [], [])
    } else {
        []
    }
}

# Walk an array literal's bytes. `depth` counts the nested [] and {} inside it: a comma at depth 0
# separates elements and the first ] at depth 0 closes the array.
collect_elements : List(U8), U64, Bool, List(U8), List(Str) -> List(Str)
collect_elements = |bytes, depth, in_string, current, out| {
    match bytes {
        [] => out
        [byte, .. as rest] => {
            if in_string {
                next = List.append(current, byte)
                if byte == 92 {
                    match rest {
                        [] => out
                        [escaped, .. as after] => collect_elements(after, depth, Bool.True, List.append(next, escaped), out)
                    }
                } else if byte == 34 {
                    collect_elements(rest, depth, Bool.False, next, out)
                } else {
                    collect_elements(rest, depth, Bool.True, next, out)
                }
            } else if byte == 34 {
                collect_elements(rest, depth, Bool.True, List.append(current, byte), out)
            } else if byte == 91 or byte == 123 {
                collect_elements(rest, depth + 1, Bool.False, List.append(current, byte), out)
            } else if byte == 93 or byte == 125 {
                if depth == 0 { flush_element(current, out) } else { collect_elements(rest, depth - 1, Bool.False, List.append(current, byte), out) }
            } else if byte == 44 and depth == 0 {
                collect_elements(rest, 0, Bool.False, [], flush_element(current, out))
            } else {
                collect_elements(rest, depth, Bool.False, List.append(current, byte), out)
            }
        }
    }
}

flush_element : List(U8), List(Str) -> List(Str)
flush_element = |bytes, out| {
    match Str.from_utf8(bytes) {
        Ok(text) => {
            trimmed = Str.trim(text)
            if Str.is_empty(trimmed) { out } else { List.append(out, trimmed) }
        }
        Err(_) => out
    }
}

# Replace one field's numeric value in a JSON object literal, leaving the rest of the literal
# verbatim: replace_number_field("{\"a\":1,\"b\":2}", "a", "0") == "{\"a\":0,\"b\":2}".
replace_number_field : Str, Str, Str -> Str
replace_number_field = |json_str, field, value| {
    marker = "\"${field}\":"
    match Str.split_on(json_str, marker) {
        [head, second, .. as tail] => {
            rest = Str.join_with(List.concat([second], tail), marker)
            kept = match Str.from_utf8(drop_number(Str.to_utf8(Str.trim(rest)))) {
                Ok(text) => text
                Err(_) => ""
            }
            "${head}${marker}${value}${kept}"
        }
        _ => json_str
    }
}

# Digits plus the punctuation of a numeric literal (sign, decimal point, exponent).
drop_number : List(U8) -> List(U8)
drop_number = |bytes| {
    match bytes {
        [] => []
        [byte, .. as rest] => if is_number_byte(byte) { drop_number(rest) } else { bytes }
    }
}

is_number_byte = |byte| {
    (byte >= 48 and byte <= 57) or byte == 45 or byte == 43 or byte == 46 or byte == 101 or byte == 69
}

# The assessment question a submission answer refers to: its `question_index` is the position in
# the assessment's `questions` array, the same index the student form numbers its answers with.
# "" when there is no such question.
question_for! : List(Str), Str => Str
question_for! = |questions, index_text| {
    match U64.from_str(index_text) {
        Ok(index) => match List.get(questions, index) { Ok(question) => question, Err(_) => "" }
        Err(_) => ""
    }
}

# MCQ auto-scoring, following the MoonBit student agent (student_handler_assessment.mbt): an MCQ
# earns the question's marks when its letter matches the question's stored `answer`, and 0
# otherwise; an MCQ whose stored answer is empty cannot be scored and keeps what the client sent,
# which is the agent's unscored case. `answers.*` has exactly four sub-fields, so there is no
# field to hold a separate awarded mark: the award goes into `allocated_mark`, and the question's
# own allocation stays readable in the assessment's `questions[*].marks`.
score_one_answer! : Str, List(Str) => Str
score_one_answer! = |element, questions| {
    if extract_field(element, "answer_type") != "mcq" {
        element
    } else {
        question = question_for!(questions, extract_number_field(element, "question_index"))
        correct = extract_field(question, "answer")
        allocated = extract_number_field(element, "allocated_mark")
        if Str.is_empty(correct) or Str.is_empty(allocated) {
            # Nothing to compare against, or the mark is not a number: leave the answer as sent.
            element
        } else {
            marks = extract_number_field(question, "marks")
            awarded =
                if Str.trim(extract_field(element, "answer_text")) == Str.trim(correct) {
                    if Str.is_empty(marks) { allocated } else { marks }
                } else {
                    "0"
                }
            replace_number_field(element, "allocated_mark", awarded)
        }
    }
}

# The element-wise pass. `List.map` only takes a pure function and the answer scanners carry an
# effect, so the walk is recursive.
score_elements! : List(Str), List(Str), List(Str) => List(Str)
score_elements! = |elements, questions, out| {
    match elements {
        [] => out
        [element, .. as rest] => score_elements!(rest, questions, List.append(out, score_one_answer!(element, questions)))
    }
}

# Score a whole answers array against the assessment's questions. The stored text keeps the
# client's own fields; only an MCQ's `allocated_mark` is rewritten.
score_mcq_answers! : Str, Str => Str
score_mcq_answers! = |answers_json, questions_json| {
    questions = split_json_elements(questions_json)
    scored = score_elements!(split_json_elements(answers_json), questions, [])
    "[${Str.join_with(scored, ",")}]"
}

# --- User creation (T7) ---

# Loose shape check; the database casts to datetime and rejects anything else.
looks_like_date = |text| {
    Str.count_utf8_bytes(text) == 10 and Str.contains(text, "-")
}

# Loose shape check for the address the create path hands to Authentik. An update validates it the
# same way, then refuses it (see update_clauses!): the profile tables have no email column.
looks_like_email = |text| {
    parts = Str.split_on(text, "@")

    local = match List.first(parts) { Ok(value) => value, Err(_) => "" }
    domain = match List.last(parts) { Ok(value) => value, Err(_) => "" }

    !Str.is_empty(local)
        and !Str.contains(local, " ")
        and !Str.contains(domain, " ")
        and Str.contains(domain, ".")
        and !Str.starts_with(domain, ".")
        and !Str.ends_with(domain, ".")
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

# --- User update and soft delete (the profile table an id names) ---

# The four role profile tables, as the listings group them.
profile_tables = ["student_profile", "teacher_profile", "parent_profile", "admin_profile"]

# Which table a user id names. The listings return their ids as `student_profile:<uuid>`, so the
# table is read off the id's own prefix rather than a `role` in the payload: a request then cannot
# claim one role while naming another role's row, and DELETE — whose payload carries nothing but the
# id — resolves its table the same way. A bare id names no table, so it is refused instead of
# guessed at.
profile_table_of : Str -> [Ok(Str), Err(Str)]
profile_table_of = |raw_id| {
    table = match List.first(Str.split_on(raw_id, ":")) {
        Ok(head) => head
        Err(_) => ""
    }

    if List.contains(profile_tables, table) {
        Ok(table)
    } else {
        Err("id must name a profile row (${Str.join_with(profile_tables, ", ")}), got '${table}'")
    }
}

# The profile columns an update may write, per table. These are the tables' own fields
# (`profile_create_sql!` writes the same ones on create); `class_level` is the payload key for the
# student's `current_class` link, and parent_profile's single name column is `name`.
profile_update_columns : Str -> List(Str)
profile_update_columns = |table|
    if table == "parent_profile" {
        ["display_name", "name", "passport"]
    } else if table == "admin_profile" {
        ["display_name", "first_name", "middle_name", "surname", "passport", "role_title"]
    } else if table == "teacher_profile" {
        ["display_name", "first_name", "middle_name", "surname", "passport"]
    } else {
        ["display_name", "first_name", "middle_name", "surname", "passport", "date_of_birth", "class_level"]
    }

# Every payload field the update path knows about, so one sent for the wrong table can be named
# back to the caller. `class_enrolled` is here to be refused: it is set on create and immutable.
known_update_fields = ["display_name", "first_name", "middle_name", "surname", "name", "passport", "role_title", "date_of_birth", "class_level", "class_enrolled"]

# The fields the payload carries that this table has no column for. `name` is the legacy table's
# shape: parent_profile still has that column (it is that table's single name field), no other
# profile table does. Writing one has to be a 400 naming the field, not a statement the database
# rejects wholesale with "no such field exists".
misplaced_update_fields : Str, Str -> List(Str)
misplaced_update_fields = |table, payload_raw| {
    columns = profile_update_columns(table)

    List.keep_if(known_update_fields, |field| {
        carried = !Str.is_empty(extract_field(payload_raw, field) |> sanitize)
        carried and !List.contains(columns, field)
    })
}

# One `SET` entry for a text column, or "" when the payload does not carry that field.
update_text_clause! : Str, Str => Str
update_text_clause! = |field, payload_raw| {
    value = extract_field(payload_raw, field) |> sanitize

    if Str.is_empty(value) {
        ""
    } else {
        "${field} = '${surreal_literal(value)}'"
    }
}

# The `SET` clauses for a PUT /api/users, or the message for the 400 that stops it. Only columns the
# resolved table really has are written, and the checks mirror the create path: a student's new
# class level must exist and a date of birth must look like YYYY-MM-DD. Email is refused rather than
# written — no profile table declares an `email` column (its home is the Authentik login, per the
# identity/profile split), so the write would fail inside the database, and dropping the field
# silently would report a change that never happened.
update_clauses! : Str, Str, SurrealDB.Config => [Ok(List(Str)), Err(Str)]
update_clauses! = |table, payload_raw, config| {
    display_name = extract_field(payload_raw, "display_name") |> sanitize
    name_val = extract_field(payload_raw, "name") |> sanitize
    email = extract_field(payload_raw, "email") |> sanitize
    date_of_birth = extract_field(payload_raw, "date_of_birth") |> sanitize
    class_level = extract_field(payload_raw, "class_level") |> sanitize
    misplaced = misplaced_update_fields(table, payload_raw)

    # `display_name` exists on every table. A parent's one name is stored in two columns, `name`
    # and `display_name`, which the create path sets to the same value — so the parent branch
    # writes the pair from whichever of the two the payload carries. Everywhere else display_name
    # is written as sent: the caller has the row's current value from the listing.
    name_clauses =
        if table == "parent_profile" {
            parent_name = if Str.is_empty(name_val) { display_name } else { name_val }

            if Str.is_empty(parent_name) {
                []
            } else {
                ["name = '${surreal_literal(parent_name)}'", "display_name = '${surreal_literal(parent_name)}'"]
            }
        } else {
            [update_text_clause!("display_name", payload_raw)]
        }

    role_clauses =
        if table == "parent_profile" {
            []
        } else if table == "admin_profile" {
            [
                update_text_clause!("first_name", payload_raw),
                update_text_clause!("surname", payload_raw),
                update_text_clause!("middle_name", payload_raw),
                update_text_clause!("role_title", payload_raw),
            ]
        } else if table == "teacher_profile" {
            [
                update_text_clause!("first_name", payload_raw),
                update_text_clause!("surname", payload_raw),
                update_text_clause!("middle_name", payload_raw),
            ]
        } else {
            [
                update_text_clause!("first_name", payload_raw),
                update_text_clause!("surname", payload_raw),
                update_text_clause!("middle_name", payload_raw),
                if Str.is_empty(date_of_birth) { "" } else { "date_of_birth = <datetime> '${date_of_birth}'" },
                if Str.is_empty(class_level) { "" } else { "current_class = ${record_ref!(class_level, "class_levels")}" },
            ]
        }

    candidates = List.concat(name_clauses, List.concat([update_text_clause!("passport", payload_raw)], role_clauses))
    clauses = List.keep_if(candidates, |clause| !Str.is_empty(clause))

    if !Str.is_empty(email) {
        if looks_like_email(email) {
            Err("email has no column on ${table}: it belongs to the Authentik login")
        } else {
            Err("email is not a valid address")
        }
    } else if !List.is_empty(misplaced) {
        first = match List.first(misplaced) { Ok(field) => field, Err(_) => "" }

        Err("'${first}' is not a column of ${table}")
    } else if table == "student_profile" and !Str.is_empty(date_of_birth) and !looks_like_date(date_of_birth) {
        Err("date_of_birth must look like YYYY-MM-DD")
    } else if table == "student_profile" and !Str.is_empty(class_level) and !class_level_exists!(class_level, config) {
        Err("class_level '${class_level}' does not exist")
    } else if List.is_empty(clauses) {
        Err("no updatable fields: send at least one of ${Str.join_with(profile_update_columns(table), ", ")}")
    } else {
        Ok(clauses)
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
                        # Optional, like the deadline: absent stores the schema default, 0 = unlimited.
                        max_resubmissions = extract_number_field(payload_raw, "max_resubmissions")
                        max_resubmissions_clause = if Str.is_empty(max_resubmissions) { "" } else { ", max_resubmissions = ${max_resubmissions}" }
                        description_clause = if Str.is_empty(description) { "" } else { ", description = '${surreal_literal(description)}'" }
                        deadline_clause = if Str.is_empty(deadline) { "" } else { ", deadline = <datetime> '${deadline}'" }
                        create_query = "CREATE lesson_assessments SET lesson = ${record_ref!(lesson_id, "lessons")}, title = '${surreal_literal(title)}'${description_clause}, questions = ${questions}, total_mark = ${total_mark_clause}${max_resubmissions_clause}, active = false, created_by = ${record_ref!(caller_id!(user_json), "teacher_profile")}, created_at = time::now()${deadline_clause};"
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
                    # in place so the teacher's grading list stays one row per student. The deadline
                    # and the resubmission limit are enforced here — the page's disabled button is
                    # cosmetic, this is the authority.
                    payload_raw = read_body!(request)
                    assessment_id = extract_field(payload_raw, "assessment_id") |> sanitize
                    answers = json_array_or_empty!(payload_raw, "answers")
                    student_id = caller_id!(user_json) |> sanitize
                    if Str.is_empty(assessment_id) {
                        Ok(json_response(400, "{\"error\":\"assessment_id is required\"}"))
                    } else if Str.contains(answers, ";") {
                        Ok(json_response(400, "{\"error\":\"answers must be a JSON array without statement separators\"}"))
                    } else {
                        # One read of the assessment feeds the checks, the total mark and the
                        # questions. `expired` is decided by the database, so no clock or date
                        # parsing here and no gap between the check and the stored deadline.
                        assessment_body = match SurrealDB.query!("SELECT total_mark, max_resubmissions, questions, (deadline IS NOT NONE AND deadline < time::now()) AS expired FROM ${record_ref!(assessment_id, "lesson_assessments")};", context.surreal) {
                            Ok(body) => body
                            Err(_) => ""
                        }
                        if json_bool(assessment_body, "expired") == "true" {
                            Ok(json_response(409, "{\"error\":\"The deadline for this assessment has passed\"}"))
                        } else {
                            bare_assessment = bare_id(assessment_id)
                            existing_body = match SurrealDB.query!("SELECT meta::id(id) AS submission_id, iteration FROM submissions WHERE student = ${record_ref!(student_id, "student_profile")} AND assessment_id = '${bare_assessment}' ORDER BY iteration DESC LIMIT 1;", context.surreal) {
                                Ok(body) => body
                                Err(_) => ""
                            }
                            existing_id = extract_field(existing_body, "submission_id")
                            max_resubmissions = field_int!(assessment_body, "max_resubmissions")
                            attempts = field_int!(existing_body, "iteration")
                            # max_resubmissions 0 (the schema default) means unlimited.
                            if !Str.is_empty(existing_id) and max_resubmissions > 0 and attempts >= max_resubmissions {
                                Ok(json_response(409, "{\"error\":\"Resubmission limit reached\"}"))
                            } else {
                                found_mark = extract_number_field(assessment_body, "total_mark")
                                total_mark = if Str.is_empty(found_mark) { "0" } else { found_mark }
                                scored_answers = score_mcq_answers!(answers, extract_json_array(assessment_body, "questions"))
                                submit_query =
                                    if Str.is_empty(existing_id) {
                                        "CREATE submissions SET assessment_type = 'lesson', assessment_id = '${bare_assessment}', student = ${record_ref!(student_id, "student_profile")}, iteration = 1, status = 'submitted', submitted_at = time::now(), answers = ${scored_answers}, total_mark = ${total_mark};"
                                    } else {
                                        "UPDATE ${record_ref!(existing_id, "submissions")} SET iteration = iteration + 1, status = 'submitted', submitted_at = time::now(), answers = ${scored_answers}, total_mark = ${total_mark};"
                                    }
                                Ok(db_response!(submit_query, context.surreal))
                            }
                        }
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
                    # Update the profile row the id names. The table comes from the id's own prefix
                    # (`student_profile:<uuid>`, as the listings return it).
                    payload_raw = read_body!(request)
                    id_val = extract_field(payload_raw, "id") |> sanitize

                    if Str.is_empty(id_val) {
                        Ok(json_response(400, "{\"error\":\"id is required\"}"))
                    } else {
                        match profile_table_of(id_val) {
                            Err(message) => Ok(json_response(400, "{\"error\":\"${sanitize_json_text(message)}\"}"))
                            Ok(table) =>
                                match update_clauses!(table, payload_raw, context.surreal) {
                                    Err(message) => Ok(json_response(400, "{\"error\":\"${sanitize_json_text(message)}\"}"))
                                    Ok(clauses) => {
                                        set_clause = Str.join_with(List.concat(clauses, ["updated_at = time::now()"]), ", ")
                                        # db_response! answers 500 with the statement's own message
                                        # when the write is rejected, instead of a false 200.
                                        Ok(db_response!("UPDATE ${record_ref!(id_val, table)} SET ${set_clause};", context.surreal))
                                    }
                                }
                        }
                    }
                } else if Method.is_eq(request.method, DELETE) and request.target == "/api/users" {
                    # Soft delete: the listings filter on `deleted_at IS NONE`, so the row (and its
                    # history) stays in the database and simply stops appearing.
                    payload_raw = read_body!(request)
                    id_val = extract_field(payload_raw, "id") |> sanitize

                    if Str.is_empty(id_val) {
                        Ok(json_response(400, "{\"error\":\"id is required\"}"))
                    } else {
                        match profile_table_of(id_val) {
                            Err(message) => Ok(json_response(400, "{\"error\":\"${sanitize_json_text(message)}\"}"))
                            Ok(table) => Ok(db_response!("UPDATE ${record_ref!(id_val, table)} SET deleted_at = time::now();", context.surreal))
                        }
                    }
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
