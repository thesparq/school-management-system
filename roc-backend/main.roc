app [Context, program] {
    pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.14.0-rc1/GfM5qZLcKYGA9XD4V7u1S4RjWrdfws29Uz2m86C7bmUC.tar.zst",
    http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.Server
import pf.Env
import pf.OsStr
import pf.Path
import pf.Stdout
import pf.Utc
import http.Response
import http.Method
import SurrealDB
import Base64
import Url
import R2
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

# --- DEV_MODE tokens ---

# The tokens that stand in for a login while DEV_MODE=true. Each names the role it acts as, so a
# sandbox run can drive a student, a teacher or an admin without a real Authentik session:
# `dev-skip` is the all-access admin the suites use (it has no userinfo body to read groups from),
# and `test-token` is its older alias, kept as an admin so it reaches everything it could before
# the routes were gated. Production runs DEV_MODE=false, which rejects all of them before a role
# can matter.
dev_tokens = ["dev-skip", "test-token", "dev-student", "dev-teacher"]

dev_token_role : Str -> Str
dev_token_role = |token| {
    if token == "dev-student" {
        "student"
    } else if token == "dev-teacher" {
        "teacher"
    } else {
        "admin"
    }
}

# The caller id a dev token stands for. `dev-skip` has to stay `dev_user`: the sandbox fixture
# seeds `student_profile:dev_user`, so the student flows resolve a name and an owner for it.
dev_token_body : Str -> Str
dev_token_body = |token| {
    if token == "dev-student" { "dev_student" }
    else if token == "dev-teacher" { "dev_teacher" }
    else if token == "test-token" { "user_123" }
    else { "dev_user" }
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

# A record id written out as a literal (`class_levels:jss_1`), the sibling of record_ref! for
# statements that take record links. RELATE rejects expressions, so type::record(...) cannot be
# used there; `<>` is stripped because a `->` in the id would otherwise end the RELATE clause early.
record_literal! = |table, raw| {
    id = bare_id(raw) |> Str.replace_each(">", "") |> Str.replace_each("<", "")
    "${table}:${id}"
}

# Bare record id: "lessons:abc" and "abc" both become "abc". SurrealDB renders an id part that
# looks like a number back to us quoted — `student_profile:`14`` — so the backticks come off here:
# that way an id read out of a response can be compared with (and written back as) the value it was
# built from, which is what joining a profile row to its login by pk depends on. Stored string fields
# such as submissions.assessment_id hold the bare form (the MoonBit stack's convention), so rows
# written by either stack are found by both.
bare_id : Str => Str
bare_id = |raw| {
    match List.last(Str.split_on(raw, ":")) {
        Ok(id) => id |> Str.replace_each("`", "") |> sanitize
        Err(_) => raw |> Str.replace_each("`", "") |> sanitize
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

# The role a set of group names maps to, or "" when the names carry no role group at all. One list
# for both sides that read group names: the caller's own role (the userinfo `groups` claim) and the
# directory listing (the user list endpoint's `groups_obj`). Names are compared ASCII-lowercased, so
# `Administrators` and `administrators` are one group.
role_from_group_names : List(Str) -> Str
role_from_group_names = |groups| {
    if List.any(groups, |group| group == "super admins" or group == "administrators" or group == "admin") {
        "admin"
    } else if List.any(groups, |group| group == "teachers" or group == "teacher" or group == "staff") {
        "teacher"
    } else if List.any(groups, |group| group == "parents" or group == "parent") {
        "parent"
    } else if List.any(groups, |group| group == "students" or group == "student") {
        "student"
    } else {
        ""
    }
}

# The role a caller's `groups` claim maps to. This is the same list the page uses in
# `www/index.html` (super admins/administrators/admin → admin, teachers/teacher/staff → teacher,
# parents/parent → parent, students/student → student); keep the two lists in step, because the page
# routes by this role and the backend decides with it. A claim that names no role is a student, which
# is what the page assumes too — and the fallback belongs here, at the caller's own role: the
# directory listing reads `role_from_group_names` directly, so a login in no role group (an outpost,
# a service account) is listed in no tab rather than taken for a student.
role_from_groups! : Str => Str
role_from_groups! = |user_json| {
    role = role_from_group_names(group_names_from_claim(extract_json_array(user_json, "groups")))

    if Str.is_empty(role) { "student" } else { role }
}

# The group names in a JSON array of strings — the userinfo claim, `["Students"]`.
group_names_from_claim : Str -> List(Str)
group_names_from_claim = |array_text| {
    List.map(split_json_elements(array_text), |element| ascii_lowercase(json_string_text(element)))
}

# The group names in a JSON array of objects — the user list endpoint's `groups_obj`, whose elements
# carry the name in their own `name` field. Recursive rather than a `List.map`, because the scanners
# carry an effect and `List.map` takes only pure functions.
group_names_from_objects! : List(Str), List(Str) -> List(Str)
group_names_from_objects! = |elements, out| {
    match elements {
        [] => out
        [element, .. as rest] => group_names_from_objects!(rest, List.append(out, ascii_lowercase(extract_field(element, "name"))))
    }
}

# The text of one element of a JSON string array: `"Students"` -> `Students`. An element that is
# not a quoted string (a number, an object) has no group name and comes back empty, so it matches
# nothing.
json_string_text : Str -> Str
json_string_text = |element| {
    trimmed = Str.trim(element)

    if Str.starts_with(trimmed, "\"") {
        match List.get(Str.split_on(trimmed, "\""), 1) {
            Ok(text) => text
            Err(_) => ""
        }
    } else {
        ""
    }
}

# ASCII lowercase, byte by byte: the group names being matched are ASCII, `Str` has no case
# conversion in this compiler, and `Administrators` and `administrators` have to be one name.
# Bytes past ASCII belong to multi-byte characters, which lowercasing would not change anyway.
ascii_lowercase : Str -> Str
ascii_lowercase = |text| {
    lowered = List.map(Str.to_utf8(text), |byte| if byte >= 65 and byte <= 90 { byte + 32 } else { byte })

    match Str.from_utf8(lowered) {
        Ok(result) => result
        Err(_) => text
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

# --- School numbers (a student's admission number, a staff member's staff id) ---

# What is stored is the number alone: an integer, with no prefix and no padding. Which column holds it,
# which counter hands it out, and the prefix its written form carries are decided here and nowhere else
# — the written form (`JES-000123`, `EMP-000045`) is rendered by this file, so neither the database nor
# the page spells a prefix a second time. A parent is not a school member and has no number at all.
number_column = |role| {
    if role == "Student" { "admission_number" } else if role == "Parent" { "" } else { "staff_id" }
}

# The counter a role draws from. Teachers and admins share `staff`, so a new staff member keeps drawing
# from the same series whatever their role is today — and `school_number_clause!` hands one who already
# has a number that number rather than a second one.
number_sequence = |role| { if role == "Student" { "student" } else { "staff" } }

# The prefix the written form carries, per the class of member the number belongs to.
number_prefix = |role| {
    if role == "Student" { "JES-" } else if role == "Parent" { "" } else { "EMP-" }
}

# The written form's width: six digits. A number past 999,999 simply renders with more of them — the
# integer is what is stored, so nothing truncates it.
number_width = 6

# Zero-pad a number's digits to the written form's width: pad_left("45", 6) == "000045". Roc has no pad
# function; `Str.repeat` is the string op this is built from, and digits already at the width come back
# whole.
pad_left : Str, U64 -> Str
pad_left = |text, width| {
    length = Str.count_utf8_bytes(text)

    if length >= width {
        text
    } else {
        "${Str.repeat("0", width - length)}${text}"
    }
}

# One number in the form it is written in: `JES-000123`.
number_text : Str, Str -> Str
number_text = |role, digits| { "${number_prefix(role)}${pad_left(digits, number_width)}" }

# The written number of one profile row, or "" when it has none. The listing hands the page this
# rendered form, so the page shows a number it never has to build. (Effectful because the row is
# scanned for its field rather than parsed, like every other reader of a response body.)
row_number! : Str, Str => Str
row_number! = |row, role| {
    column = number_column(role)
    digits = if Str.is_empty(column) { "" } else { extract_number_field(row, column) }

    if Str.is_empty(digits) { "" } else { number_text(role, digits) }
}

# The listing's own half of the `number_column` mapping: `, admission_number` (or `, staff_id`) to add
# to a SELECT, "" for a role whose table carries no number column.
number_select_for = |role| {
    column = number_column(role)

    if Str.is_empty(column) { "" } else { ", ${column}" }
}

# The staff number a pk already holds, as text, or "" when it holds none. Both staff tables are read,
# because one person may be a teacher today and an admin tomorrow: reusing the number they were given
# is what keeps a role change from handing them a second one. A read that fails answers "" — the write
# that follows talks to the same database, so a database that cannot answer this cannot store the row
# either.
existing_staff_id! : Str, SurrealDB.Config => Str
existing_staff_id! = |pk, config| {
    own = staff_id_in!("teacher_profile", pk, config)

    if Str.is_empty(own) { staff_id_in!("admin_profile", pk, config) } else { own }
}

# One staff table's answer for the question above: a row only when the pk has a number there, so an
# absent row and a row with no number are the same "" here.
staff_id_in! : Str, Str, SurrealDB.Config => Str
staff_id_in! = |table, pk, config| {
    match SurrealDB.query_read!("SELECT staff_id FROM ${record_ref!(pk, table)} WHERE staff_id IS NOT NONE;", config) {
        Ok(body) => extract_number_field(body, "staff_id")
        Err(_) => ""
    }
}

# The `SET` entry that hands a new profile row its number, or "" for a role that has none (a parent).
# The allocation is part of the profile write's own statement — the counter is bumped and read by the
# same `CREATE` — so a rejected or duplicate create cannot burn a number and a retry allocates the next
# one. A teacher or an admin whose pk already has a staff number reuses it as a literal instead, and
# only a pk with none draws from the counter.
school_number_clause! : Str, Str, SurrealDB.Config => Str
school_number_clause! = |pk, role, config| {
    column = number_column(role)

    if Str.is_empty(column) {
        ""
    } else {
        # Only staff numbers are shared between the two staff tables; a student's number is always a
        # fresh one (a student who becomes staff is given a staff number, not their admission number).
        reused = if role == "Student" { "" } else { existing_staff_id!(pk, config) }

        if Str.is_empty(reused) {
            "${column} = (UPDATE id_sequences:${number_sequence(role)} SET current_value += 1 RETURN current_value)[0].current_value"
        } else {
            "${column} = ${reused}"
        }
    }
}

# --- User creation (T7) ---

# Loose shape check; the database casts to datetime and rejects anything else.
looks_like_date = |text| {
    Str.count_utf8_bytes(text) == 10 and Str.contains(text, "-")
}

# Loose shape check for the address the create path hands to Authentik, and for a new one an
# update sends there.
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

# The profile fields a row has to carry: the profile tables are SCHEMAFULL and require these, and
# the passport rule mirrors validate_passport_url in the MoonBit admin agent, so both stacks accept
# the same input. POST (a new login) and the PUT that attaches a profile to an existing login both
# make a row from scratch, so both check exactly this.
validate_profile_fields! = |role, first_name, surname, date_of_birth, class_level, passport| {
    if Str.is_empty(first_name) {
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

# The create path's own check: a login needs an email, and the profile row needs the fields above.
validate_new_user! = |role, email, first_name, surname, date_of_birth, class_level, passport| {
    if Str.is_empty(email) {
        Err("email is required")
    } else {
        validate_profile_fields!(role, first_name, surname, date_of_birth, class_level, passport)
    }
}

# Record links are not existence-checked by the schema, so a typo would leave a
# student pointing at a class level that does not exist.
class_level_exists! = |class_level, config| {
    res = SurrealDB.query_read!("SELECT id FROM ${record_ref!(class_level, "class_levels")};", config)
    match res {
        Ok(body) => Str.contains(body, "\"result\":[{\"id\"")
        Err(_) => Bool.False
    }
}

# Whether the profile row is already there, `deleted_at` or not: a hidden row is still a row, and
# PUT patches it (clearing `deleted_at`) instead of building it from scratch. PUT attaches a missing
# row and patches an existing one, and the two write different field sets — a row that is being made
# has to satisfy the table's required columns — so its existence is what picks between them.
profile_row_exists! : Str, Str, SurrealDB.Config => Bool
profile_row_exists! = |table, pk, config| {
    match SurrealDB.query_read!("SELECT id FROM type::record('${table}', '${pk}');", config) {
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

# The role a profile table belongs to, the inverse of profile_table_for. PUT resolves its table from
# the id it is given, and a row that has to be made from scratch is checked against that role's own
# required fields, so the table has to name its role back.
role_of_table = |table| {
    if table == "teacher_profile" { "Teacher" }
    else if table == "parent_profile" { "Parent" }
    else if table == "admin_profile" { "Admin" }
    else { "Student" }
}

# The display name a row is given when the payload does not carry one: the name parts, the rule the
# create path has always used. A PUT that attaches a profile derives it the same way, so the same
# input writes the same row whichever path made it.
display_name_from! : Str => Str
display_name_from! = |payload_raw| {
    first_name = extract_field(payload_raw, "first_name") |> sanitize
    middle_name = extract_field(payload_raw, "middle_name") |> sanitize
    surname = extract_field(payload_raw, "surname") |> sanitize

    if Str.is_empty(middle_name) { "${first_name} ${surname}" } else { "${first_name} ${middle_name} ${surname}" }
}

# Build the profile INSERT for the chosen role. Field sets mirror the prod tables:
# parents carry a single `name`, students carry date_of_birth plus their class links,
# admins may carry a role_title, teachers nothing extra. The row's school number comes first: it is
# `school_number_clause!`'s own `SET` entry, and every role that reaches this branch has one (only a
# parent has no number, and a parent is built below).
profile_create_sql! = |role, number_clause, user_id, first_name, middle_name, surname, display_name, date_of_birth, class_level, role_title, passport| {
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
                number_clause,
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

# The fields that are set once, by the write that made the row, and are refused as a payload field
# afterwards: a student's second class link, and the two school numbers. They are named here so the
# refusal is one rule rather than a check inside each write path.
immutable_update_fields = ["class_enrolled", "admission_number", "staff_id"]

# Every payload field the update path knows about, so one sent for the wrong table can be named
# back to the caller. The immutable ones are in here to be refused; `admission_number` and `staff_id`
# are in no table's `profile_update_columns`, which is what makes a payload that carries one a 400
# instead of an ignored field.
known_update_fields = List.concat(["display_name", "first_name", "middle_name", "surname", "name", "passport", "role_title", "date_of_birth", "class_level"], immutable_update_fields)

# The fields the payload carries that this table has no column for. `name` is the legacy table's
# shape: parent_profile still has that column (it is that table's single name field), no other
# profile table does. Writing one has to be a 400 naming the field, not a statement the database
# rejects wholesale with "no such field exists".
misplaced_update_fields : Str, Str -> List(Str)
misplaced_update_fields = |table, payload_raw| {
    columns = profile_update_columns(table)

    List.keep_if(known_update_fields, |field| {
        carried = carries_field(payload_raw, field)
        carried and !List.contains(columns, field)
    })
}

# The 400's message for the first field the payload sent that this table cannot write. An immutable
# field is a column of the table — the school numbers are — so it says which rule refused it, rather
# than sending the caller looking for a typo that is not there.
misplaced_message : Str, Str -> Str
misplaced_message = |field, table| {
    if List.contains(immutable_update_fields, field) {
        "'${field}' is set when the row is created and cannot be updated"
    } else {
        "'${field}' is not a column of ${table}"
    }
}

# Whether the payload carries a field. A quoted value is what `extract_field` reads, and that is how
# every column the update path can write is sent. The immutable fields are the exception: a school
# number is an integer (`"admission_number": 12`) and a record link may be sent as a bare key, so for
# those the key itself counts as carrying the field — the refusal is about naming it, not about the
# shape of the value behind it.
carries_field : Str, Str -> Bool
carries_field = |payload_raw, field| {
    quoted = !Str.is_empty(extract_field(payload_raw, field) |> sanitize)

    if quoted {
        Bool.True
    } else if List.contains(immutable_update_fields, field) {
        # Whitespace after the colon is stripped first: a hand-written payload may carry it, and the
        # app's own never does.
        Str.contains(Str.replace_each(payload_raw, " ", ""), "\"${field}\":")
    } else {
        Bool.False
    }
}

# `field = 'value'` for a value already read out of the payload, or "" when the value is empty — an
# empty clause is dropped from a list of them, which is how an update writes only what it was given.
text_clause! : Str, Str => Str
text_clause! = |field, value| {
    if Str.is_empty(value) {
        ""
    } else {
        "${field} = '${surreal_literal(value)}'"
    }
}

# One `SET` entry for a text column, or "" when the payload does not carry that field.
update_text_clause! : Str, Str => Str
update_text_clause! = |field, payload_raw| {
    text_clause!(field, extract_field(payload_raw, field) |> sanitize)
}

# The `SET` clauses for a PUT /api/users, or the message for the 400 that stops it. Only columns the
# resolved table really has are written, and the checks mirror the create path: a student's new
# class level must exist and a date of birth must look like YYYY-MM-DD. Email is validated here but
# not written — no profile table declares an `email` column (its home is the Authentik login, per the
# identity/profile split), so the handler patches Authentik with it after these clauses pass.
update_clauses! : Str, Str, SurrealDB.Config => [Ok(List(Str)), Err(Str)]
update_clauses! = |table, payload_raw, config| {
    display_name = extract_field(payload_raw, "display_name") |> sanitize
    first_name = extract_field(payload_raw, "first_name") |> sanitize
    surname = extract_field(payload_raw, "surname") |> sanitize
    name_val = extract_field(payload_raw, "name") |> sanitize
    email = extract_field(payload_raw, "email") |> sanitize
    date_of_birth = extract_field(payload_raw, "date_of_birth") |> sanitize
    class_level = extract_field(payload_raw, "class_level") |> sanitize
    misplaced = misplaced_update_fields(table, payload_raw)

    # `display_name` is derived from the name parts, so it follows them: written as sent when the
    # payload carries it, and otherwise derived the create path's way whenever the payload carries
    # both parts. That is what makes the completing form's typed name show up even when the row it is
    # completing already exists (a profile that was soft-deleted and is being filled in again). A patch
    # that carries half a name — a surname alone, a passport — leaves the stored display name alone
    # rather than building one out of half a payload.
    display_name_value =
        if !Str.is_empty(display_name) {
            display_name
        } else if Str.is_empty(first_name) or Str.is_empty(surname) {
            ""
        } else {
            display_name_from!(payload_raw)
        }

    # `display_name` exists on every table. A parent's one name is stored in two columns, `name`
    # and `display_name`, which the create path sets to the same value — so the parent branch
    # writes the pair from whichever of the two the payload carries. Everywhere else display_name
    # is written as sent: the caller has the row's current value from the listing.
    name_clauses =
        if table == "parent_profile" {
            parent_name = if Str.is_empty(name_val) { display_name_value } else { name_val }

            if Str.is_empty(parent_name) {
                []
            } else {
                [text_clause!("name", parent_name), text_clause!("display_name", parent_name)]
            }
        } else {
            [text_clause!("display_name", display_name_value)]
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

    if !Str.is_empty(email) and !looks_like_email(email) {
        Err("email is not a valid address")
    } else if !List.is_empty(misplaced) {
        first = match List.first(misplaced) { Ok(field) => field, Err(_) => "" }

        Err(misplaced_message(first, table))
    } else if table == "student_profile" and !Str.is_empty(date_of_birth) and !looks_like_date(date_of_birth) {
        Err("date_of_birth must look like YYYY-MM-DD")
    } else if table == "student_profile" and !Str.is_empty(class_level) and !class_level_exists!(class_level, config) {
        Err("class_level '${class_level}' does not exist")
    } else if List.is_empty(clauses) and Str.is_empty(email) {
        Err("no updatable fields: send an email or at least one of ${Str.join_with(profile_update_columns(table), ", ")}")
    } else {
        Ok(clauses)
    }
}

# The fields a row a PUT has to make from scratch must carry: POST's own check, read out of the
# payload here. No email — the login the profile is being attached to already has one.
validate_attach_fields! : Str, Str => [Ok({}), Err(Str)]
validate_attach_fields! = |table, payload_raw| {
    validate_profile_fields!(
        role_of_table(table),
        extract_field(payload_raw, "first_name") |> sanitize,
        extract_field(payload_raw, "surname") |> sanitize,
        extract_field(payload_raw, "date_of_birth") |> sanitize,
        extract_field(payload_raw, "class_level") |> sanitize,
        extract_field(payload_raw, "passport") |> sanitize,
    )
}

# The columns only a row that is being made needs, beyond the patch fields `update_clauses!` writes:
# the school number `school_number_clause!` hands out — a row that is being made is exactly when a
# number is handed out, and the patch path never touches it, so a number stays what creation gave it —
# the student's second class link (`class_enrolled` is set on create and immutable after, and the
# update path refuses it as a payload field, so this is the one place it is written for a row that
# does not exist yet), and `created_at`, which the create path also sets explicitly. Empty for a patch,
# which must not rewrite any of them.
create_only_clauses! : Str, Str, Str, Bool, SurrealDB.Config => List(Str)
create_only_clauses! = |table, pk, payload_raw, creating, config| {
    if !creating {
        []
    } else {
        class_level = extract_field(payload_raw, "class_level") |> sanitize
        enrolled =
            if table != "student_profile" or Str.is_empty(class_level) {
                []
            } else {
                ["class_enrolled = ${record_ref!(class_level, "class_levels")}"]
            }
        # "" for a table whose role has no number (a parent profile), and dropped rather than written
        # as an empty `SET` entry.
        number = school_number_clause!(pk, role_of_table(table), config)
        number_clauses = List.keep_if([number], |clause| !Str.is_empty(clause))

        List.concat(number_clauses, List.concat(enrolled, ["created_at = time::now()"]))
    }
}

# The write half of PUT /api/users, shared by the patch and the attach: the email goes to Authentik
# first (the address is how the login is found, so a failure has to stop the update instead of
# leaving the two sides disagreeing), then the profile row is written. An identity-only update has no
# column to change, so there is no statement to run for the row.
# The verb follows `creating`: this SurrealDB's `UPDATE` on a record that is not there is a no-op that
# still answers OK, so a row that has to be made is `CREATE`d. An existing row is `UPDATE`d, and
# `deleted_at = NONE` is part of that write: PUT is the admin saying this profile is real, so a row
# that was soft-deleted comes back instead of staying hidden behind a success.
update_user_response! : Str, Str, Str, Bool, List(Str), SurrealDB.Config => Server.Outcome
update_user_response! = |table, id_val, payload_raw, creating, clauses, config| {
    email = extract_field(payload_raw, "email") |> sanitize
    auth_res =
        if Str.is_empty(email) {
            Ok("")
        } else {
            Authentik.updateUser!(bare_id(id_val), "{\"email\": \"${sanitize_json_text(email)}\"}")
        }

    match auth_res {
        Err(message) => json_response(502, "{\"error\":\"Authentik error: ${sanitize_json_text(message)}\"}"),
        Ok(_) =>
            if List.is_empty(clauses) {
                json_response(200, "{\"id\":\"${sanitize_json_text(id_val)}\"}")
            } else {
                verb = if creating { "CREATE" } else { "UPDATE" }
                set_clause = Str.join_with(List.concat(clauses, ["updated_at = time::now()", "deleted_at = NONE"]), ", ")

                db_response!("${verb} ${record_ref!(id_val, table)} SET ${set_clause};", config)
            }
    }
}

# --- User listing: the profile rows joined with the identity attributes Authentik owns ---

# One login's pk as text, read from the login's **own** `pk` field. It is the first `pk` in the
# object, which is the login's: Authentik sends `pk` first and the group objects (each carrying a `pk`
# of their own) after it. The value is a number there (`"pk":13`) and a string in the sandbox mock
# (`"pk":"mock_uuid_3"`), so both forms are read — reading only the quoted form is how the group's
# pk gets taken for the login's, which then never matches a profile row and lists an id nobody owns.
directory_pk! : Str => Str
directory_pk! = |element| {
    match List.get(Str.split_on(element, "\"pk\":"), 1) {
        Ok(rest) => pk_text(Str.trim(rest))
        Err(_) => ""
    }
}

# A `pk` value as text: `"mock_uuid_3"` -> `mock_uuid_3`, `13,"username"` -> `13`.
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

# The role one login in the directory belongs to, or "" when its groups name no role. The list
# endpoint's own `groups` field holds group ids, so the names are read from `groups_obj`; a login in
# no role group (an outpost, a service account) maps to no role and is listed in no tab.
directory_role! : Str => Str
directory_role! = |element| {
    role_from_group_names(group_names_from_objects!(split_json_elements(extract_json_array(element, "groups_obj")), []))
}

# Whether this element of Authentik's user list is the user a profile row's bare id names.
user_pk_matches! = |element, pk| {
    directory_pk!(element) == pk
}

# The element of Authentik's user list whose pk is this row's, or "" when the login is not in it.
# `List.map` and `List.keep_if` only take pure functions and the scanners carry an effect, so the
# walk is recursive — the same reason score_elements! is.
matching_user! : List(Str), Str => Str
matching_user! = |elements, pk| {
    match elements {
        [] => ""
        [element, .. as rest] => if user_pk_matches!(element, pk) { element } else { matching_user!(rest, pk) }
    }
}

# A record id as this file writes them: the table's name, then the bare id — without the backticks
# SurrealDB puts around an id part that looks like a number. The page hands these ids straight back
# (PUT and DELETE resolve the table from the prefix), so a row built from a profile table and a row
# built from the directory alone have to spell their ids the same way.
record_id_text! : Str => Str
record_id_text! = |raw| {
    table = match List.first(Str.split_on(raw, ":")) {
        Ok(head) => head
        Err(_) => ""
    }

    "${table}:${bare_id(raw)}"
}

# One row of the rebuilt listing: the profile's own fields (the ones the listing selects) plus the
# two identity attributes no profile table has. `id` keeps its full record form
# (`student_profile:<pk>`), which is what PUT and DELETE resolve their table from.
# `school_number` is the profile's number in the one form the page shows (`JES-000123`, `EMP-000045`),
# or "" when the row has none: the integer is what the database holds, and the rendering happens here.
# A row whose pk is not in Authentik's list carries neither identity field: nothing is known about
# that login, and answering `"is_active":false` would report an account that was never switched
# off. The frontend renders an empty email there and a missing `is_active` as active.
# `has_profile` is what tells the page this row has school data behind it: a row built from the
# directory alone is rendered as a login with no profile yet.
user_row_with_identity! = |row, users, role| {
    pk = bare_id(extract_field(row, "id"))
    user = matching_user!(users, pk)
    identity =
        if Str.is_empty(user) {
            []
        } else {
            [
                "\"email\":\"${sanitize_json_text(extract_field(user, "email"))}\"",
                "\"is_active\":${json_bool(user, "is_active")}",
            ]
        }
    fields = [
        "\"id\":\"${sanitize_json_text(record_id_text!(extract_field(row, "id")))}\"",
        "\"display_name\":\"${sanitize_json_text(extract_field(row, "display_name"))}\"",
        "\"first_name\":\"${sanitize_json_text(extract_field(row, "first_name"))}\"",
        "\"surname\":\"${sanitize_json_text(extract_field(row, "surname"))}\"",
        "\"passport\":\"${sanitize_json_text(extract_field(row, "passport"))}\"",
        "\"created_at\":\"${sanitize_json_text(extract_field(row, "created_at"))}\"",
        "\"current_class\":\"${sanitize_json_text(extract_field(row, "current_class"))}\"",
        "\"school_number\":\"${sanitize_json_text(row_number!(row, role))}\"",
        "\"has_profile\":true",
    ]

    "{${Str.join_with(List.concat(fields, identity), ",")}}"
}

# The element-wise pass over the rows, effectful for the same reason as matching_user!.
rows_with_identity! : List(Str), List(Str), Str, List(Str) => List(Str)
rows_with_identity! = |rows, users, role, out| {
    match rows {
        [] => out
        [row, .. as rest] => rows_with_identity!(rest, users, role, List.append(out, user_row_with_identity!(row, users, role)))
    }
}

# The logins the directory lists for one role: the role comes from the login's own groups, which is
# what makes a login created in Authentik itself appear in the tab before any profile exists.
logins_for_role! : List(Str), Str, List(Str) => List(Str)
logins_for_role! = |users, role, out| {
    match users {
        [] => out
        [user, .. as rest] =>
            if directory_role!(user) == role {
                logins_for_role!(rest, role, List.append(out, user))
            } else {
                logins_for_role!(rest, role, out)
            }
    }
}

# Whether the profile rows already account for this login. A login the directory lists for a role
# whose profile row is there is rendered from that row (with its identity merged in), so it must not
# be appended a second time as a login without a profile.
row_for_pk! : List(Str), Str => Bool
row_for_pk! = |rows, pk| {
    match rows {
        [] => Bool.False
        [row, .. as rest] => if bare_id(extract_field(row, "id")) == pk { Bool.True } else { row_for_pk!(rest, pk) }
    }
}

# One row for a login the profile table has no visible row for: the identity attributes Authentik
# owns, the id the listing's ids are shaped as (`<table>:<pk>`, which is what PUT attaches the
# profile to), and nothing for the school fields — no profile means they are unknown, not empty.
# `school_number` is the one the page needs a value for: the empty string is this row's own spelling
# of "no number", the same as a profile row that has none.
# `username` is what the page falls back to when the login has no name of its own (an account made
# with nothing but a username, as two of the real directory's are): it is the login's identifier, and
# without it two nameless logins are the same row to an admin.
profile_less_row! = |user, table| {
    fields = [
        "\"id\":\"${table}:${sanitize_json_text(directory_pk!(user))}\"",
        "\"display_name\":\"${sanitize_json_text(extract_field(user, "name"))}\"",
        "\"first_name\":\"\"",
        "\"surname\":\"\"",
        "\"passport\":\"\"",
        "\"created_at\":\"\"",
        "\"current_class\":\"\"",
        "\"school_number\":\"\"",
        "\"email\":\"${sanitize_json_text(extract_field(user, "email"))}\"",
        "\"username\":\"${sanitize_json_text(extract_field(user, "username"))}\"",
        "\"is_active\":${json_bool(user, "is_active")}",
        "\"has_profile\":false",
    ]

    "{${Str.join_with(fields, ",")}}"
}

# The listed logins that have no profile row of their own, in directory order. A row whose
# `deleted_at` is set is hidden from the listing's query, so its login shows up here — which is how a
# profile that was deleted can be completed again.
logins_without_profile! : List(Str), List(Str), Str, List(Str) => List(Str)
logins_without_profile! = |listed, rows, table, out| {
    match listed {
        [] => out
        [user, .. as rest] =>
            if row_for_pk!(rows, directory_pk!(user)) {
                logins_without_profile!(rest, rows, table, out)
            } else {
                logins_without_profile!(rest, rows, table, List.append(out, profile_less_row!(user, table)))
            }
    }
}

# GET /api/users: every profile row of the requested role with the login attributes Authentik owns
# (email, whether the account is enabled) merged in by pk, plus the logins the directory lists for
# that role that have no profile row — the state an admin is in after creating users in Authentik
# itself, where the login exists and the school data does not. A login in no role group (an outpost,
# a service account) belongs to no tab and is listed nowhere. Both sides are text: the database body
# and Authentik's `{"pagination":…,"results":[…]}` are read with the scanners above rather than a
# parser, and the result is rebuilt as the one-element envelope the frontend's `unwrapRows` reads
# (`data[0].result`). Rebuilding from the known fields is more predictable than editing JSON text
# in place, at the cost of dropping anything else the row carried.
merge_identity! = |body, users_body, role| {
    users = split_json_elements(extract_json_array(users_body, "results"))
    rows = split_json_elements(extract_json_array(body, "result"))
    listed = logins_for_role!(users, ascii_lowercase(role), [])
    rendered = rows_with_identity!(rows, users, role, [])
    extra = logins_without_profile!(listed, rows, profile_table_for(role), [])

    "[{\"result\":[${Str.join_with(List.concat(rendered, extra), ",")}],\"status\":\"OK\"}]"
}

# --- Configuration hub writes (lookup tables: terms, subjects, class_levels, session_term, has_subject) ---

# One `SET` entry for a text column of a lookup table, or "" when the payload does not carry that
# field. An update is a patch (`update_clauses!` reads profile updates the same way): a field the
# caller leaves out keeps its stored value instead of being blanked.
config_text_clause! : Str, Str => Str
config_text_clause! = |field, payload_raw| {
    value = extract_field(payload_raw, field) |> sanitize

    if Str.is_empty(value) {
        ""
    } else {
        "${field} = '${surreal_literal(value)}'"
    }
}

# The response for a lookup-table update. `clauses` holds the SET entries the payload produced;
# when it produced none there is nothing to write, so the 400 names the columns the table takes.
# db_response! answers 500 with the statement's own message when the write is rejected (a duplicate
# name against the table's unique index, a link the schema refuses).
config_update_response! : Str, List(Str), Str, Str, SurrealDB.Config => Server.Outcome
config_update_response! = |table, clauses, id_val, updatable, config| {
    if Str.is_empty(id_val) {
        json_response(400, "{\"error\":\"id is required\"}")
    } else if List.is_empty(clauses) {
        json_response(400, "{\"error\":\"no updatable fields: send ${updatable}\"}")
    } else {
        db_response!("UPDATE ${record_ref!(id_val, table)} SET ${Str.join_with(clauses, ", ")};", config)
    }
}

# The response for a toggle: `active` is the only column written. These tables are SCHEMAFULL and
# declare no `updated_at`, so a statement that set one would be rejected wholesale. Deactivating
# marks the row instead of deleting it — the hub keeps listing it so it can be switched back on.
config_toggle_response! : Str, Str, SurrealDB.Config => Server.Outcome
config_toggle_response! = |table, payload_raw, config| {
    id_val = extract_field(payload_raw, "id") |> sanitize
    active = json_bool(payload_raw, "active")

    if Str.is_empty(id_val) {
        json_response(400, "{\"error\":\"id is required\"}")
    } else {
        db_response!("UPDATE ${record_ref!(id_val, table)} SET active = ${active};", config)
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

# The 500 for a read whose SurrealDB call failed, carrying what actually happened rather than a bare
# "Database error": the read paths used to decide on the status alone, so a dropped connection and
# a real SurrealDB error looked identical in the Network tab and nothing in the logs said which.
db_read_error! = |err| {
    detail = match err {
        HttpErr => "could not reach the database"
        JsonErr => "invalid response from the database"
        SurrealErr(body) => {
            parsed = extract_field(body, "details")
            if Str.is_empty(parsed) { body } else { parsed }
        }
    }

    json_response(500, "{\"error\":\"Database error\",\"detail\":\"${sanitize_json_text(detail)}\"}")
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

# The same body-vs-status rule as db_body!, for a read: the query is retried once at the
# connection level (`query_read!`), so a stale keep-alive does not answer the user listing with
# a spurious "Database error". Writes keep db_body! (a retried write could run twice).
db_body_read! : Str, SurrealDB.Config => [Ok(Str), Err(Str)]
db_body_read! = |sql, config| {
    match SurrealDB.query_read!(sql, config) {
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

    # Everything is served `no-cache`, the bundle included. `app.wasm` and `runtime.js` carry no content
    # hash in their names, so caching them by age means a rebuilt bundle keeps being served to anyone who
    # already has the old one — the page then runs last week's app against today's markup, which looks like
    # a broken UI rather than a stale file. (The Joy template's own Caddyfile does the same, for the same
    # reason.) Give the files hashed names if the bundle ever needs to be cached immutably.

    bytes_result = Path.read_bytes!(Path.unix(actual_path))
    match bytes_result {
        Ok(bytes) =>
            Server.respond(
                Response.from_status(200)
                    |> Response.with_headers([
                        { name: "Content-Type", value: actual_content_type },
                        { name: "Cache-Control", value: "no-cache" },
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

# --- R2 upload helpers ---

# The object key a passport photo lives under starts with one of these, so an upload can only
# ever be signed into a profile's own folder.
profile_type_names = ["student", "teacher", "parent", "admin"]

profile_type_ok : Str -> Bool
profile_type_ok = |text| List.contains(profile_type_names, text)

# The user id part of the key: the Authentik pk for an account that exists, or the id the page
# generates for a photo chosen before the account does. Either way it has to be a plain token —
# a slash or a space would let the caller pick a key of its own choosing.
key_token_ok : Str -> Bool
key_token_ok = |text| {
    !Str.is_empty(text)
        and Str.count_utf8_bytes(text) <= 64
        and List.all(Str.to_utf8(text), |byte| is_key_token_byte(byte))
}

is_key_token_byte : U8 -> Bool
is_key_token_byte = |byte| {
    (byte >= 48 and byte <= 57) or (byte >= 97 and byte <= 122) or (byte >= 65 and byte <= 90) or byte == 45 or byte == 95
}

# The names of the variables whose value is empty. The endpoint reads all five R2 variables up
# front, so a missing one is named in the 503 rather than discovered by the browser's PUT.
unset_names : List({ name : Str, value : Str }) -> List(Str)
unset_names = |variables| List.map(List.keep_if(variables, |variable| Str.is_empty(variable.value)), |variable| variable.name)

# `20130524T000000Z`, the form SigV4 writes its timestamp in.
looks_like_amz_date : Str -> Bool
looks_like_amz_date = |text| {
    Str.count_utf8_bytes(text) == 16 and Str.ends_with(text, "Z") and Str.contains(text, "T")
}

# The timestamp to sign with: the clock, except in DEV_MODE where the request may pin it, so a
# test can compare two signatures instead of racing the second. A pinned value that is not the
# SigV4 shape is ignored rather than signed.
signing_timestamp! : Str, Bool => Str
signing_timestamp! = |pinned, dev_mode| {
    if dev_mode and looks_like_amz_date(pinned) {
        pinned
    } else {
        R2.amz_date_of(Utc.to_iso_8601(Utc.now!()))
    }
}

# --- Route authorization ---

# The role each route needs, as one matrix rather than a check inside every branch: everything
# under /api/student/ needs a student, everything under /api/teacher/ a teacher, the writes that
# manage accounts and configuration an admin, and "" means any authenticated role. Route families,
# not individual routes, so a new endpoint under an existing prefix inherits its rule.
#
# The `role` query parameter on GET /api/users?role=… is a tab *filter* and is never read here.
#
# `may_call` then lets an admin through anywhere. That is the top of the hierarchy the page's own
# navigation implies, and it is also what keeps one `dev-skip` token able to drive every suite.
config_route_prefixes = ["/api/terms", "/api/subjects", "/api/class_levels", "/api/curriculum", "/api/session_terms", "/api/class_arms"]

required_role : Method, Str -> Str
required_role = |method, target| {
    if Str.starts_with(target, "/api/student/") {
        "student"
    } else if Str.starts_with(target, "/api/teacher/") {
        "teacher"
    } else if target == "/api/users" or Str.starts_with(target, "/api/users?") {
        # Reading the directory is any role's business (the hub's tabs, the pickers); creating,
        # renaming or disabling an account is the admin's.
        if Method.is_eq(method, GET) { "" } else { "admin" }
    } else if target == "/api/students" or target == "/api/teachers" {
        # The older, unfiltered roster endpoints and their superseded creates: every student or
        # teacher in the school, so admin-only. The page's user management uses /api/users.
        "admin"
    } else if target == "/api/enroll" {
        # The retired Golem enrollment prototype: unused by the page, but it writes someone's
        # enrolment, so it stays with the admin.
        "admin"
    } else if target == "/api/upload-url" {
        # The passport signer behind the admin's create-user form.
        "admin"
    } else if List.any(config_route_prefixes, |prefix| Str.starts_with(target, prefix)) {
        # The lookup tables and the curriculum edge: every role reads them (the pickers, the
        # student cards, the hub's lists), only the admin writes (creates, the PUT patches, the
        # toggle-actives). /api/class_arms answers 410 either way but belongs to the same family.
        if Method.is_eq(method, GET) { "" } else { "admin" }
    } else {
        # /api/matrix/token (the chat proxy, which every role uses) and anything the dispatch chain
        # below will answer 404 to: no requirement here.
        ""
    }
}

# Whether a caller with `role` may use a route whose requirement is `required`: any authenticated
# role satisfies a "", every other route has to be the caller's own role, and an admin may call
# anything.
may_call : Str, Str -> Bool
may_call = |role, required| {
    if Str.is_empty(required) {
        Bool.True
    } else if role == "admin" {
        Bool.True
    } else {
        role == required
    }
}

# The 403 for a route outside the caller's role: it names the role the route needs, so a student
# hitting an admin endpoint is told what that endpoint expects rather than only "Forbidden".
forbidden_response = |role, required| {
    json_response(403, "{\"error\":\"Forbidden: this route requires the ${required} role; your role is ${role}\"}")
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
        # The container's HEALTHCHECK curls this path, so the status code — not only the body — has
        # to carry the outcome: a 200 with "surreal db is down" inside it reported a database outage
        # as a healthy container. `db_body!` is the file's own rule for "did the query really
        # succeed", so a database that answers 200 with an error statement counts as down too.
        match db_body!("INFO FOR DB;", context.surreal) {
            Ok(_) => Ok(json_response(200, "{\"status\":\"healthy\", \"db\":\"surreal db is healthy\"}")),
            Err(_) => Ok(json_response(503, "{\"status\":\"unhealthy\", \"db\":\"surreal db is down\"}")),
        }

    # --- API routes (require auth) ---
    } else if Str.starts_with(request.target, "/api/") {
        token_res = get_token(request.headers)

        # The caller's identity and role together: a DEV_MODE token names both directly, a real
        # token's body comes from Authentik and its role from that body's `groups` claim.
        auth =
            match token_res {
                Ok(token) =>
                    if context.dev_mode and List.contains(dev_tokens, token) {
                        Ok({ body: dev_token_body(token), role: dev_token_role(token) })
                    } else {
                        match Authentik.validateToken!(token) {
                            Ok(body) => Ok({ body, role: role_from_groups!(body) })
                            Err(e) => Err(e)
                        }
                    }
                Err(e) => Err(e)
            }

        required = required_role(request.method, request.target)

        match auth {
            Err(e) => 
                Ok(json_response(401, "{\"error\":\"Unauthorized: ${e}\"}"))
            Ok(caller) if !may_call(caller.role, required) =>
                Ok(forbidden_response(caller.role, required))
            Ok(caller) => {
                user_json = caller.body
                if Method.is_eq(request.method, GET) and request.target == "/api/students" {
                    res = SurrealDB.query_read!("SELECT id, display_name, first_name, surname, passport, created_at, current_class FROM student_profile WHERE deleted_at IS NONE ORDER BY created_at DESC;", context.surreal)
                    match res {
                        Ok(body) => Ok(json_response(200, body))
                        Err(err) => Ok(db_read_error!(err))
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
                    res = SurrealDB.query_read!("SELECT id, display_name, first_name, surname, passport, created_at FROM teacher_profile WHERE deleted_at IS NONE ORDER BY created_at DESC;", context.surreal)
                    match res {
                        Ok(body) => Ok(json_response(200, body))
                        Err(err) => Ok(db_read_error!(err))
                    }
                } else if Method.is_eq(request.method, POST) and request.target == "/api/teachers" {
                    # Superseded by POST /api/users, which writes a teacher_profile record.
                    Ok(json_response(400, "{\"error\":\"Use POST /api/users with role=Teacher\"}"))
                } else if Method.is_eq(request.method, GET) and Str.starts_with(request.target, "/api/subjects") {
                    # The hub asks with ?all=true so a deactivated subject stays manageable; the
                    # default list (the student's subject cards, the curriculum picker) is the
                    # active rows only, which is what deactivating a subject takes it out of.
                    scope = if query_param(request.target, "all") == "true" { "" } else { " WHERE active = true" }
                    res = SurrealDB.query_read!("SELECT id, name, code, active FROM subjects${scope} ORDER BY name;", context.surreal)
                    match res {
                        Ok(body) => Ok(json_response(200, body))
                        Err(err) => Ok(db_read_error!(err))
                    }
                } else if Method.is_eq(request.method, POST) and request.target == "/api/subjects" {
                    payload_raw = read_body!(request)
                    
                    name_val = extract_field(payload_raw, "name") |> sanitize
                    code_val = extract_field(payload_raw, "code") |> sanitize
                    payload_str = "{\"name\": \"${name_val}\", \"code\": \"${code_val}\"}"
                    
                    # The table is SCHEMAFULL, so an unnamed subject would be stored as an empty
                    # string. Reject it here so the form shows what is missing.
                    if Str.is_empty(name_val) {
                        Ok(json_response(400, "{\"error\":\"name is required\"}"))
                    } else {
                        Ok(db_response!("CREATE subjects CONTENT ${payload_str};", context.surreal))
                    }
                } else if Method.is_eq(request.method, PUT) and request.target == "/api/subjects" {
                    # A patch: only the fields the payload carries are written, and an empty one
                    # means "leave it" rather than "blank it out".
                    payload_raw = read_body!(request)
                    clauses = List.keep_if(
                        [config_text_clause!("name", payload_raw), config_text_clause!("code", payload_raw)],
                        |clause| !Str.is_empty(clause),
                    )
                    Ok(config_update_response!("subjects", clauses, extract_field(payload_raw, "id") |> sanitize, "name or code", context.surreal))
                } else if Method.is_eq(request.method, POST) and request.target == "/api/subjects/toggle-active" {
                    payload_raw = read_body!(request)
                    Ok(config_toggle_response!("subjects", payload_raw, context.surreal))
                } else if Method.is_eq(request.method, GET) and request.target == "/api/terms" {
                    # Admin config hub: every term, ordered. Students get the active subset below.
                    res = SurrealDB.query_read!("SELECT id, name, sort_order, active FROM terms ORDER BY sort_order;", context.surreal)
                    match res {
                        Ok(body) => Ok(json_response(200, body))
                        Err(err) => Ok(db_read_error!(err))
                    }
                } else if Method.is_eq(request.method, POST) and request.target == "/api/terms" {
                    payload_raw = read_body!(request)
                    safe_payload = payload_raw |> sanitize

                    term_name = extract_field(payload_raw, "name")
                    sort_order = extract_number_field(payload_raw, "sort_order")
                    if Str.is_empty(term_name) {
                        Ok(json_response(400, "{\"error\":\"name is required\"}"))
                    } else if Str.is_empty(sort_order) {
                        Ok(json_response(400, "{\"error\":\"sort_order must be a whole number\"}"))
                    } else {
                        Ok(db_response!("CREATE terms CONTENT ${safe_payload};", context.surreal))
                    }
                } else if Method.is_eq(request.method, PUT) and request.target == "/api/terms" {
                    # A term keeps its name and its place in the school year. An absent sort_order
                    # leaves the stored one alone — requiring it is the create handler's job.
                    payload_raw = read_body!(request)
                    sort_order = extract_number_field(payload_raw, "sort_order")
                    sort_clause = if Str.is_empty(sort_order) { "" } else { "sort_order = ${sort_order}" }
                    clauses = List.keep_if(
                        [config_text_clause!("name", payload_raw), sort_clause],
                        |clause| !Str.is_empty(clause),
                    )
                    Ok(config_update_response!("terms", clauses, extract_field(payload_raw, "id") |> sanitize, "name or sort_order", context.surreal))
                } else if Method.is_eq(request.method, POST) and request.target == "/api/terms/toggle-active" {
                    payload_raw = read_body!(request)
                    Ok(config_toggle_response!("terms", payload_raw, context.surreal))
                } else if Method.is_eq(request.method, GET) and Str.starts_with(request.target, "/api/class_levels") {
                    # ?all=true is the hub's view: a deactivated level stays listed so it can be
                    # edited or switched back on. Everyone else gets the active levels only.
                    scope = if query_param(request.target, "all") == "true" { "" } else { " WHERE active = true" }
                    res = SurrealDB.query_read!("SELECT id, name, code, age_range, active FROM class_levels${scope} ORDER BY name;", context.surreal)
                    match res {
                        Ok(body) => Ok(json_response(200, body))
                        Err(err) => Ok(db_read_error!(err))
                    }
                } else if Method.is_eq(request.method, POST) and request.target == "/api/class_levels" {
                    payload_raw = read_body!(request)
                    safe_payload = payload_raw |> sanitize

                    level_name = extract_field(payload_raw, "name")
                    level_code = extract_field(payload_raw, "code")
                    if Str.is_empty(level_name) {
                        Ok(json_response(400, "{\"error\":\"name is required\"}"))
                    } else if Str.is_empty(level_code) {
                        Ok(json_response(400, "{\"error\":\"code is required\"}"))
                    } else {
                        Ok(db_response!("CREATE class_levels CONTENT ${safe_payload};", context.surreal))
                    }
                } else if Method.is_eq(request.method, PUT) and request.target == "/api/class_levels" {
                    payload_raw = read_body!(request)
                    clauses = List.keep_if(
                        [
                            config_text_clause!("name", payload_raw),
                            config_text_clause!("code", payload_raw),
                            config_text_clause!("age_range", payload_raw),
                        ],
                        |clause| !Str.is_empty(clause),
                    )
                    Ok(config_update_response!("class_levels", clauses, extract_field(payload_raw, "id") |> sanitize, "name, code or age_range", context.surreal))
                } else if Method.is_eq(request.method, POST) and request.target == "/api/class_levels/toggle-active" {
                    payload_raw = read_body!(request)
                    Ok(config_toggle_response!("class_levels", payload_raw, context.surreal))
                } else if Method.is_eq(request.method, GET) and Str.starts_with(request.target, "/api/curriculum") {
                    # The curriculum is the class_levels -> subjects edge in the prod schema. The hub
                    # asks with ?all=true so a link that has been switched off stays listed (and can
                    # be switched back on); the default is the active curriculum only.
                    scope = if query_param(request.target, "all") == "true" { "" } else { " WHERE active = true" }
                    res = SurrealDB.query_read!("SELECT id, in, out, active FROM has_subject${scope};", context.surreal)
                    match res {
                        Ok(body) => Ok(json_response(200, body))
                        Err(err) => Ok(db_read_error!(err))
                    }
                } else if Method.is_eq(request.method, POST) and request.target == "/api/curriculum" {
                    # Link one class level to one subject: the has_subject edge is the curriculum.
                    # A repeated pair is refused by the edge's unique (in, out) index, whose own
                    # message comes back through db_response!.
                    payload_raw = read_body!(request)
                    class_level = extract_field(payload_raw, "class_level") |> sanitize
                    subject = extract_field(payload_raw, "subject") |> sanitize
                    if Str.is_empty(class_level) or Str.is_empty(subject) {
                        Ok(json_response(400, "{\"error\":\"class_level and subject are required\"}"))
                    } else {
                        class_link = record_literal!("class_levels", class_level)
                        subject_link = record_literal!("subjects", subject)
                        Ok(db_response!("RELATE ${class_link} -> has_subject -> ${subject_link} SET active = true;", context.surreal))
                    }
                } else if Method.is_eq(request.method, POST) and request.target == "/api/curriculum/toggle-active" {
                    # Unlinking without losing the row: the edge keeps its lessons, it just stops
                    # counting as part of the active curriculum.
                    payload_raw = read_body!(request)
                    Ok(config_toggle_response!("has_subject", payload_raw, context.surreal))
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
                    # One derivation rule for the display name, shared with the PUT that attaches a
                    # profile to a login that has none.
                    display_name = display_name_from!(payload_raw)

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
                                    # The number the new row is given: a fresh one from the role's own
                                    # counter, or the staff number this pk already holds. It travels in
                                    # the profile statement below, so the write that fails takes the
                                    # allocation down with it.
                                    number_clause = school_number_clause!(user_id, role, context.surreal)
                                    create_sql = profile_create_sql!(role, number_clause, user_id, first_name, middle_name, surname, display_name, date_of_birth, class_level, role_title, passport)
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
                    # Support ?role=Student|Teacher|Parent|Admin for tab filtering. The role picks the
                    # profile table and is what the directory's own logins are filtered by, so both
                    # sides of the listing are read from the one parameter.
                    role_param =
                        if Str.contains(request.target, "role=Teacher") { "Teacher" }
                        else if Str.contains(request.target, "role=Parent") { "Parent" }
                        else if Str.contains(request.target, "role=Admin") { "Admin" }
                        else { "Student" }
                    # The profile tables hold the app's own fields only, so no email or is_active here:
                    # both are identity attributes Authentik owns (see the merge below). The role's own
                    # number column is selected too — the row handed back carries it as the rendered
                    # `school_number`.
                    number_select = number_select_for(role_param)
                    query = "SELECT id, display_name, first_name, surname, passport, created_at, current_class${number_select} FROM ${profile_table_for(role_param)} WHERE deleted_at IS NONE ORDER BY created_at DESC;"
                    match db_body_read!(query, context.surreal) {
                        Err(detail) => Ok(json_response(500, "{\"error\":\"Database error\",\"detail\":\"${sanitize_json_text(detail)}\"}")),
                        Ok(body) =>
                            match Authentik.listUsers!("200") {
                                Ok(users_body) => Ok(json_response(200, merge_identity!(body, users_body, role_param))),
                                Err(_) =>
                                    # Authentik is unreachable (or no token is configured): answer the
                                    # rows as the database has them rather than failing the listing.
                                    # Their identity columns are then unknown, which is why nothing
                                    # is invented for them — no email, and no is_active that would
                                    # report a login state that was never observed.
                                    Ok(json_response(200, body)),
                            }
                    }

                # --- Student Lesson APIs ---
                } else if Method.is_eq(request.method, GET) and request.target == "/api/student/subjects" {
                    res = SurrealDB.query_read!("SELECT id, name, code FROM subjects WHERE active = true ORDER BY name;", context.surreal)
                    match res {
                        Ok(body) => Ok(json_response(200, body))
                        Err(err) => Ok(db_read_error!(err))
                    }
                 } else if Method.is_eq(request.method, GET) and Str.starts_with(request.target, "/api/student/terms") {
                     # Prod: terms are school-wide (Noel/Calvary/Summer)
                     res = SurrealDB.query_read!("SELECT id, name, sort_order FROM terms WHERE active = true ORDER BY sort_order;", context.surreal)
                     match res {
                         Ok(body) => Ok(json_response(200, body))
                         Err(err) => Ok(db_read_error!(err))  
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
                     res = SurrealDB.query_read!(lessons_query, context.surreal)
                     match res {
                         Ok(body) => Ok(json_response(200, body))
                         Err(err) => Ok(db_read_error!(err))
                     }
                 } else if Method.is_eq(request.method, GET) and Str.starts_with(request.target, "/api/student/lesson") {
                     lesson_id = query_param(request.target, "lesson_id")
                     if Str.is_empty(lesson_id) {
                         Ok(json_response(400, "{\"error\":\"Missing lesson_id\"}"))
                     } else {
                         # The whole record: lesson content lives in the nested `content` object.
                         res = SurrealDB.query_read!("SELECT * FROM ${record_ref!(lesson_id, "lessons")};", context.surreal)
                         match res {
                             Ok(body) => Ok(json_response(200, body))
                             Err(err) => Ok(db_read_error!(err))
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
                    res = SurrealDB.query_read!(lessons_query, context.surreal)
                    match res {
                        Ok(body) => Ok(json_response(200, body))
                        Err(err) => Ok(db_read_error!(err))
                    }
                } else if Method.is_eq(request.method, GET) and Str.starts_with(request.target, "/api/student/assessments") {
                    # Students only see published (active) assessments.
                    lesson_id = query_param(request.target, "lesson_id")
                    scope = if Str.is_empty(lesson_id) or lesson_id == "none" { "" } else { "lesson = ${record_ref!(lesson_id, "lessons")} AND " }
                    res = SurrealDB.query_read!("SELECT * FROM lesson_assessments WHERE ${scope}active = true AND deleted_at IS NONE ORDER BY created_at DESC;", context.surreal)
                    match res {
                        Ok(body) => Ok(json_response(200, body))
                        Err(err) => Ok(db_read_error!(err))
                    }
                } else if Method.is_eq(request.method, GET) and Str.starts_with(request.target, "/api/teacher/lesson-assessments") {
                    # Teachers see their drafts too.
                    lesson_id = query_param(request.target, "lesson_id")
                    scope = if Str.is_empty(lesson_id) or lesson_id == "none" { "" } else { "lesson = ${record_ref!(lesson_id, "lessons")} AND " }
                    res = SurrealDB.query_read!("SELECT * FROM lesson_assessments WHERE ${scope}deleted_at IS NONE ORDER BY created_at DESC;", context.surreal)
                    match res {
                        Ok(body) => Ok(json_response(200, body))
                        Err(err) => Ok(db_read_error!(err))
                    }
                } else if Method.is_eq(request.method, POST) and request.target == "/api/teacher/create-lesson-assessment" {
                    # New assessments start as drafts: the teacher publishes them when ready.
                    payload_raw = read_body!(request)
                    lesson_id = extract_field(payload_raw, "lesson_id") |> sanitize
                    title = extract_field(payload_raw, "title") |> sanitize
                    description = extract_field(payload_raw, "description") |> sanitize
                    deadline = extract_field(payload_raw, "deadline") |> sanitize
                    scheduled_at = extract_field(payload_raw, "scheduled_at") |> sanitize
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
                        # Absent leaves the column empty, which means "open now"; submit refuses an
                        # answer that arrives before it (see the not_yet_open branch there).
                        scheduled_at_clause = if Str.is_empty(scheduled_at) { "" } else { ", scheduled_at = <datetime> '${scheduled_at}'" }
                        create_query = "CREATE lesson_assessments SET lesson = ${record_ref!(lesson_id, "lessons")}, title = '${surreal_literal(title)}'${description_clause}, questions = ${questions}, total_mark = ${total_mark_clause}${max_resubmissions_clause}, active = false, created_by = ${record_ref!(caller_id!(user_json), "teacher_profile")}, created_at = time::now()${deadline_clause}${scheduled_at_clause};"
                        Ok(db_response!(create_query, context.surreal))
                    }
                } else if Method.is_eq(request.method, GET) and Str.starts_with(request.target, "/api/student/general-assessments") {
                    # Students only see published (active) general assessments. The subject and
                    # session term filters are optional, like the lesson filter above.
                    subject_param = query_param(request.target, "subject_id")
                    session_param = query_param(request.target, "session_term_id")
                    clauses = List.keep_if(
                        [
                            if Str.is_empty(subject_param) { "" } else { "subject = ${record_ref!(subject_param, "subjects")}" },
                            if Str.is_empty(session_param) { "" } else { "session_term = ${record_ref!(session_param, "session_term")}" },
                            "active = true",
                            "deleted_at IS NONE",
                        ],
                        |clause| !Str.is_empty(clause),
                    )
                    res = SurrealDB.query_read!("SELECT *, subject.name AS subject_name, session_term.session_name AS session_term_name FROM general_assessments WHERE ${Str.join_with(clauses, " AND ")} ORDER BY created_at DESC;", context.surreal)
                    match res {
                        Ok(body) => Ok(json_response(200, body))
                        Err(err) => Ok(db_read_error!(err))
                    }
                } else if Method.is_eq(request.method, GET) and Str.starts_with(request.target, "/api/teacher/general-assessments") {
                    # Teachers see their drafts too.
                    subject_param = query_param(request.target, "subject_id")
                    session_param = query_param(request.target, "session_term_id")
                    clauses = List.keep_if(
                        [
                            if Str.is_empty(subject_param) { "" } else { "subject = ${record_ref!(subject_param, "subjects")}" },
                            if Str.is_empty(session_param) { "" } else { "session_term = ${record_ref!(session_param, "session_term")}" },
                            "deleted_at IS NONE",
                        ],
                        |clause| !Str.is_empty(clause),
                    )
                    res = SurrealDB.query_read!("SELECT *, subject.name AS subject_name, session_term.session_name AS session_term_name FROM general_assessments WHERE ${Str.join_with(clauses, " AND ")} ORDER BY created_at DESC;", context.surreal)
                    match res {
                        Ok(body) => Ok(json_response(200, body))
                        Err(err) => Ok(db_read_error!(err))
                    }
                } else if Method.is_eq(request.method, POST) and request.target == "/api/teacher/create-general-assessment" {
                    # A general assessment hangs off a subject and a session term instead of a lesson,
                    # and carries a percentage weight for the term result. Like a lesson assessment it
                    # starts as a draft and the teacher publishes it from the list.
                    payload_raw = read_body!(request)
                    subject_id = extract_field(payload_raw, "subject_id") |> sanitize
                    session_term_id = extract_field(payload_raw, "session_term_id") |> sanitize
                    title = extract_field(payload_raw, "title") |> sanitize
                    description = extract_field(payload_raw, "description") |> sanitize
                    percentage_weight = extract_number_field(payload_raw, "percentage_weight")
                    deadline = extract_field(payload_raw, "deadline") |> sanitize
                    scheduled_at = extract_field(payload_raw, "scheduled_at") |> sanitize
                    questions = json_array_or_empty!(payload_raw, "questions")
                    if Str.is_empty(subject_id) or subject_id == "none" {
                        Ok(json_response(400, "{\"error\":\"subject_id is required\"}"))
                    } else if Str.is_empty(session_term_id) or session_term_id == "none" {
                        Ok(json_response(400, "{\"error\":\"session_term_id is required\"}"))
                    } else if Str.is_empty(title) {
                        Ok(json_response(400, "{\"error\":\"title is required\"}"))
                    } else if Str.is_empty(percentage_weight) {
                        Ok(json_response(400, "{\"error\":\"percentage_weight must be a whole number\"}"))
                    } else if Str.contains(questions, ";") {
                        Ok(json_response(400, "{\"error\":\"questions must be a JSON array without statement separators\"}"))
                    } else {
                        # The weights in one term/subject may not add up to more than 100%, the rule the
                        # MoonBit stack enforced (db_sum_percentage_weights). `GROUP ALL` collapses the
                        # matches into the one sum row (this SurrealDB needs it for aggregates); no
                        # matches answer 0.
                        existing_body = match SurrealDB.query_read!("SELECT math::sum(percentage_weight) AS total FROM general_assessments WHERE session_term = ${record_ref!(session_term_id, "session_term")} AND subject = ${record_ref!(subject_id, "subjects")} AND deleted_at IS NONE GROUP ALL;", context.surreal) {
                            Ok(body) => body
                            Err(_) => ""
                        }
                        if field_int!(existing_body, "total") + field_int!(payload_raw, "percentage_weight") > 100 {
                            Ok(json_response(400, "{\"error\":\"Total percentage weight for assessments in this term exceeds 100%\"}"))
                        } else {
                            total_mark = extract_number_field(payload_raw, "total_mark")
                            total_mark_clause = if Str.is_empty(total_mark) { "0" } else { total_mark }
                            max_resubmissions = extract_number_field(payload_raw, "max_resubmissions")
                            max_resubmissions_clause = if Str.is_empty(max_resubmissions) { "" } else { ", max_resubmissions = ${max_resubmissions}" }
                            description_clause = if Str.is_empty(description) { "" } else { ", description = '${surreal_literal(description)}'" }
                            deadline_clause = if Str.is_empty(deadline) { "" } else { ", deadline = <datetime> '${deadline}'" }
                            # Absent leaves the column empty, which means "open now"; submit refuses an
                            # answer that arrives before it (see the not_yet_open branch there).
                            scheduled_at_clause = if Str.is_empty(scheduled_at) { "" } else { ", scheduled_at = <datetime> '${scheduled_at}'" }
                            create_query = "CREATE general_assessments SET subject = ${record_ref!(subject_id, "subjects")}, session_term = ${record_ref!(session_term_id, "session_term")}, title = '${surreal_literal(title)}'${description_clause}, questions = ${questions}, total_mark = ${total_mark_clause}, percentage_weight = ${percentage_weight}${max_resubmissions_clause}, active = false, created_by = ${record_ref!(caller_id!(user_json), "teacher_profile")}, created_at = time::now()${deadline_clause}${scheduled_at_clause};"
                            Ok(db_response!(create_query, context.surreal))
                        }
                    }
                } else if Method.is_eq(request.method, POST) and request.target == "/api/teacher/toggle-assessment-active" {
                    # Publishing and unpublishing: students only see active assessments. The type
                    # picks the table; absent means a lesson assessment, so the lesson UI and its
                    # callers keep working unchanged.
                    payload_raw = read_body!(request)
                    assessment_id = extract_field(payload_raw, "assessment_id") |> sanitize
                    assessment_type = extract_field(payload_raw, "assessment_type") |> sanitize
                    assessment_table = if assessment_type == "general" { "general_assessments" } else { "lesson_assessments" }
                    active = json_bool(payload_raw, "active")
                    if Str.is_empty(assessment_id) {
                        Ok(json_response(400, "{\"error\":\"assessment_id is required\"}"))
                    } else {
                        Ok(db_response!("UPDATE ${record_ref!(assessment_id, assessment_table)} SET active = ${active}, updated_at = time::now();", context.surreal))
                    }
                } else if Method.is_eq(request.method, GET) and Str.starts_with(request.target, "/api/teacher/submissions") {
                    assessment_id = query_param(request.target, "assessment_id")
                    scope = if Str.is_empty(assessment_id) { "" } else { "WHERE assessment_id = '${bare_id(assessment_id)}' " }
                    subs_query = "SELECT *, student.display_name AS student_name, student.id AS student_ref, (scored_mark IS NOT NONE) AS graded FROM submissions ${scope}ORDER BY submitted_at DESC;"
                    res = SurrealDB.query_read!(subs_query, context.surreal)
                    match res {
                        Ok(body) => Ok(json_response(200, body))
                        Err(err) => Ok(db_read_error!(err))
                    }
                } else if Method.is_eq(request.method, POST) and request.target == "/api/student/submit-assessment" {
                    # One submission per student and assessment; a resubmission bumps the iteration
                    # in place so the teacher's grading list stays one row per student. The deadline
                    # and the resubmission limit are enforced here — the page's disabled button is
                    # cosmetic, this is the authority. The type picks the assessment table; absent
                    # means a lesson assessment, so the lesson UI keeps working unchanged.
                    payload_raw = read_body!(request)
                    assessment_id = extract_field(payload_raw, "assessment_id") |> sanitize
                    assessment_type = extract_field(payload_raw, "assessment_type") |> sanitize
                    is_general = assessment_type == "general"
                    assessment_table = if is_general { "general_assessments" } else { "lesson_assessments" }
                    stored_type = if is_general { "general" } else { "lesson" }
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
                        assessment_body = match SurrealDB.query_read!("SELECT id, active, total_mark, max_resubmissions, questions, (deadline IS NOT NONE AND deadline < time::now()) AS expired, (scheduled_at IS NOT NONE AND scheduled_at > time::now()) AS not_yet_open FROM ${record_ref!(assessment_id, assessment_table)};", context.surreal) {
                            Ok(body) => body
                            Err(_) => ""
                        }
                        # A draft is invisible to students, and the list endpoint only ever hands out
                        # published ones — so a submission naming a draft (a stale tab, a hand-made
                        # request) is refused rather than silently accepted.
                        if Str.is_empty(extract_field(assessment_body, "id")) {
                            Ok(json_response(404, "{\"error\":\"No such assessment\"}"))
                        } else if json_bool(assessment_body, "active") != "true" {
                            Ok(json_response(409, "{\"error\":\"This assessment is not published\"}"))
                        } else if json_bool(assessment_body, "not_yet_open") == "true" {
                            Ok(json_response(409, "{\"error\":\"This assessment is not open yet\"}"))
                        } else if json_bool(assessment_body, "expired") == "true" {
                            Ok(json_response(409, "{\"error\":\"The deadline for this assessment has passed\"}"))
                        } else {
                            bare_assessment = bare_id(assessment_id)
                            existing_body = match SurrealDB.query_read!("SELECT meta::id(id) AS submission_id, iteration, (grade_released_at IS NOT NONE) AS released FROM submissions WHERE student = ${record_ref!(student_id, "student_profile")} AND assessment_type = '${stored_type}' AND assessment_id = '${bare_assessment}' ORDER BY iteration DESC LIMIT 1;", context.surreal) {
                                Ok(body) => body
                                Err(_) => ""
                            }
                            existing_id = extract_field(existing_body, "submission_id")
                            # max_resubmissions 0 (the schema default) means unlimited.
                            max_resubmissions = field_int!(assessment_body, "max_resubmissions")
                            attempts = field_int!(existing_body, "iteration")
                            # A released grade is final: the MoonBit stack refused a resubmit once
                            # grade_released_at was set (student_handler_assessment.mbt). Without the
                            # check the resubmit replaces the answers the released mark was awarded for
                            # while scored_mark and grade_released_at stay on the row, so the teacher's
                            # released grade would point at answers that no longer exist.
                            if !Str.is_empty(existing_id) and json_bool(existing_body, "released") == "true" {
                                Ok(json_response(409, "{\"error\":\"The grade for this assessment has been released; it can no longer be resubmitted\"}"))
                            } else if !Str.is_empty(existing_id) and max_resubmissions > 0 and attempts >= max_resubmissions {
                                Ok(json_response(409, "{\"error\":\"Resubmission limit reached\"}"))
                            } else {
                                found_mark = extract_number_field(assessment_body, "total_mark")
                                total_mark = if Str.is_empty(found_mark) { "0" } else { found_mark }
                                scored_answers = score_mcq_answers!(answers, extract_json_array(assessment_body, "questions"))
                                submit_query =
                                    if Str.is_empty(existing_id) {
                                        "CREATE submissions SET assessment_type = '${stored_type}', assessment_id = '${bare_assessment}', student = ${record_ref!(student_id, "student_profile")}, iteration = 1, status = 'submitted', submitted_at = time::now(), answers = ${scored_answers}, total_mark = ${total_mark};"
                                    } else {
                                        "UPDATE ${record_ref!(existing_id, "submissions")} SET assessment_type = '${stored_type}', iteration = iteration + 1, status = 'submitted', submitted_at = time::now(), answers = ${scored_answers}, total_mark = ${total_mark};"
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
                    # The photo lives at `<profileType>/passports/<userId>.jpg`, so the public URL
                    # is known before the upload happens — and so is what a signature needs.
                    r2_endpoint = env_or!("R2_ENDPOINT_URL", "")
                    r2_bucket = env_or!("R2_BUCKET_NAME", "")
                    r2_access = env_or!("R2_ACCESS_KEY_ID", "")
                    r2_secret = env_or!("R2_SECRET_ACCESS_KEY", "")
                    r2_public = env_or!("R2_PUBLIC_URL", "")
                    unset = unset_names([
                        { name: "R2_ENDPOINT_URL", value: r2_endpoint },
                        { name: "R2_BUCKET_NAME", value: r2_bucket },
                        { name: "R2_ACCESS_KEY_ID", value: r2_access },
                        { name: "R2_SECRET_ACCESS_KEY", value: r2_secret },
                        { name: "R2_PUBLIC_URL", value: r2_public },
                    ])

                    # Without the credentials there is nothing to sign with, and answering a URL
                    # that does not work would only move the failure to the browser's PUT.
                    if !List.is_empty(unset) {
                        Ok(json_response(503, "{\"error\":\"R2 uploads are not configured: ${Str.join_with(unset, ", ")} ${if List.len(unset) == 1 { "is" } else { "are" }} not set\"}"))
                    } else if !profile_type_ok(profile_type_val) {
                        Ok(json_response(400, "{\"error\":\"profileType must be one of ${Str.join_with(profile_type_names, ", ")}\"}"))
                    } else if !key_token_ok(user_id_val) {
                        Ok(json_response(400, "{\"error\":\"userId must be a plain id: letters, digits, '-' or '_'\"}"))
                    } else {
                        key_val = "${profile_type_val}/passports/${user_id_val}.jpg"
                        # Long enough for a photo on a slow connection, short enough that a leaked
                        # URL is worthless: ten minutes.
                        expires = 600
                        upload_url = R2.upload_url({
                            endpoint: r2_endpoint,
                            bucket: r2_bucket,
                            key: key_val,
                            access_key: r2_access,
                            secret_key: r2_secret,
                            amz_date: signing_timestamp!(extract_field(payload_raw, "amzDate") |> sanitize, context.dev_mode),
                            expires: expires,
                        })
                        public_url = "${r2_public}/${key_val}"

                        Ok(json_response(200, "{\"key\":\"${key_val}\",\"uploadUrl\":\"${upload_url}\",\"publicUrl\":\"${public_url}\",\"expiresIn\":${U64.to_str(expires)}}"))
                    }

                # --- Matrix token proxy ---
                } else if Method.is_eq(request.method, GET) and request.target == "/api/matrix/token" {
                    matrix_url = match Env.var!("PUBLIC_MATRIX_URL") { Ok(os) => OsStr.display(os), Err(_) => "" }
                    Ok(json_response(200, "{\"homeserver\":\"${matrix_url}\",\"token\":null}"))

                } else if Method.is_eq(request.method, PUT) and request.target == "/api/users" {
                    # Update the profile row the id names. The table comes from the id's own prefix
                    # (`student_profile:<uuid>`, as the listings return it). A row that is not there
                    # yet is attached to the login that id names instead — the state an admin is in
                    # after creating the login in Authentik itself, where the directory lists a user
                    # the profile tables have nothing for. The row is then made from this payload
                    # alone (the tables are SCHEMAFULL), so the create path's required fields are
                    # checked first; a row that is there is patched, keeping every field the payload
                    # leaves out.
                    payload_raw = read_body!(request)
                    id_val = extract_field(payload_raw, "id") |> sanitize

                    if Str.is_empty(id_val) {
                        Ok(json_response(400, "{\"error\":\"id is required\"}"))
                    } else {
                        match profile_table_of(id_val) {
                            Err(message) => Ok(json_response(400, "{\"error\":\"${sanitize_json_text(message)}\"}")),
                            Ok(table) => {
                                pk = bare_id(id_val)
                                creating = !profile_row_exists!(table, pk, context.surreal)
                                fields_res =
                                    if creating { validate_attach_fields!(table, payload_raw) } else { Ok({}) }

                                match fields_res {
                                    Err(message) => Ok(json_response(400, "{\"error\":\"${message}\"}")),
                                    Ok(_) =>
                                        match update_clauses!(table, payload_raw, context.surreal) {
                                            Err(message) => Ok(json_response(400, "{\"error\":\"${sanitize_json_text(message)}\"}")),
                                            Ok(clauses) => {
                                                all_clauses =
                                                    List.concat(
                                                        clauses,
                                                        create_only_clauses!(table, pk, payload_raw, creating, context.surreal),
                                                    )

                                                Ok(update_user_response!(table, id_val, payload_raw, creating, all_clauses, context.surreal))
                                            }
                                        }
                                }
                            }
                        }
                    }
                } else if Method.is_eq(request.method, DELETE) and request.target == "/api/users" {
                    # Soft delete the profile row, then switch the login off. The listings filter on
                    # `deleted_at IS NONE`, so the row (and its history) stays in the database and
                    # simply stops appearing; the live login is what still lets the user in, so it is
                    # disabled right after, and a failure there is reported (502) rather than answered
                    # as a success the admin would trust.
                    payload_raw = read_body!(request)
                    id_val = extract_field(payload_raw, "id") |> sanitize

                    if Str.is_empty(id_val) {
                        Ok(json_response(400, "{\"error\":\"id is required\"}"))
                    } else {
                        match profile_table_of(id_val) {
                            Err(message) => Ok(json_response(400, "{\"error\":\"${sanitize_json_text(message)}\"}")),
                            Ok(table) =>
                                match db_body!("UPDATE ${record_ref!(id_val, table)} SET deleted_at = time::now();", context.surreal) {
                                    Err(detail) => Ok(json_response(500, "{\"error\":\"Database error\",\"detail\":\"${sanitize_json_text(detail)}\"}")),
                                    Ok(body) =>
                                        match Authentik.updateUser!(bare_id(id_val), "{\"is_active\": false}") {
                                            Ok(_) => Ok(json_response(200, body)),
                                            Err(message) => Ok(json_response(502, "{\"error\":\"The profile is hidden, but the login could not be disabled in Authentik; the user can still sign in\",\"detail\":\"${sanitize_json_text(message)}\"}")),
                                        }
                                }
                        }
                    }
                } else if Method.is_eq(request.method, GET) and request.target == "/api/session_terms/active" {
                    # The nav bar's badge: the one active session term, with its term's own name joined
                    # in (`term.name` follows the record link). The page refetches it on every
                    # navigation. Under /api/session_terms, so every authenticated role may read it.
                    res = SurrealDB.query_read!("SELECT id, session_name, term.name AS term_name FROM session_term WHERE active = true LIMIT 1;", context.surreal)
                    match res {
                        Ok(body) => Ok(json_response(200, body))
                        Err(err) => Ok(db_read_error!(err))
                    }
                } else if Method.is_eq(request.method, GET) and request.target == "/api/session_terms" {
                    # Prod names this table in the singular.
                    res = SurrealDB.query_read!("SELECT id, session_name, term, active FROM session_term WHERE deleted_at IS NONE ORDER BY session_name;", context.surreal)
                    match res {
                        Ok(body) => Ok(json_response(200, body))
                        Err(err) => Ok(db_read_error!(err))
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
                } else if Method.is_eq(request.method, PUT) and request.target == "/api/session_terms" {
                    # A session term is a name plus the term it belongs to, so both are updatable.
                    payload_raw = read_body!(request)
                    term_id = extract_field(payload_raw, "term") |> sanitize
                    term_clause = if Str.is_empty(term_id) { "" } else { "term = ${record_ref!(term_id, "terms")}" }
                    clauses = List.keep_if(
                        [config_text_clause!("session_name", payload_raw), term_clause],
                        |clause| !Str.is_empty(clause),
                    )
                    Ok(config_update_response!("session_term", clauses, extract_field(payload_raw, "id") |> sanitize, "session_name or term", context.surreal))
                } else if Method.is_eq(request.method, POST) and request.target == "/api/session_terms/toggle-active" {
                    # New session terms are created inactive, so this is what makes one usable.
                    payload_raw = read_body!(request)
                    Ok(config_toggle_response!("session_term", payload_raw, context.surreal))
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
