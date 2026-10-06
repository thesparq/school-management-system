module [DomainEvent, append_event!]

import SurrealDB

DomainEvent : [
    StudentCreated({ id : Str, name : Str, email : Str }),
    TeacherAdded({ id : Str, department : Str }),
    SubjectCreated({ id : Str, title : Str }),
]

append_event! : DomainEvent, SurrealDB.Config => [Ok(Str), Err(Str)]
append_event! = |event, config| {
    payload = serialize_event(event)
    sql = "CREATE events CONTENT ${payload};"
    match SurrealDB.query!(sql, config) {
        Ok(str) => Ok(str)
        Err(_) => Err("Failed to query SurrealDB")
    }
}

serialize_event : DomainEvent -> Str
serialize_event = |event|
    match event {
        StudentCreated({ id, name, email }) =>
            "{\"type\": \"StudentCreated\", \"data\": {\"id\": \"${id}\", \"name\": \"${name}\", \"email\": \"${email}\"}}"
        TeacherAdded({ id, department }) =>
            "{\"type\": \"TeacherAdded\", \"data\": {\"id\": \"${id}\", \"department\": \"${department}\"}}"
        SubjectCreated({ id, title }) =>
            "{\"type\": \"SubjectCreated\", \"data\": {\"id\": \"${id}\", \"title\": \"${title}\"}}"
    }
