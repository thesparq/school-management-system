
import html.Html
import html.Attribute

import UI
import State exposing [Model, Msg, list_state, catalog_field, admin_catalog_types, admin_catalog_permissions]

# The Settings page. It holds one thing today — the password form — and the page exists mostly for the
# state it is shown in: while a login owes a password change (an administrator set the one it signed in
# with, `db/schema-v15`), the backend refuses every other route and the shell offers no other page, so
# this form is the only thing that can be done until it is answered.
SettingsView := [].{

view = |model| {
    Html.div([Attribute.class("p-6 md:p-8 space-y-6")], [
        Html.div([], [
            Html.h1([Attribute.class("text-3xl font-bold tracking-tight")], [Html.text("Settings")]),
            Html.p([Attribute.class("text-muted-foreground mt-1")], [
                Html.text("Your own account. The password is the only thing editable here for now.")
            ])
        ]),
        # The state the page is here for: why the change is owed, in the school's own words, before the
        # form rather than after a refusal.
        if model.passwordRequired {
            Html.div([Attribute.class("rounded-md border border-amber-300 dark:border-amber-800 bg-amber-50 dark:bg-amber-900/20 p-4 space-y-1")], [
                Html.p([Attribute.class("text-sm font-medium text-amber-800 dark:text-amber-200")], [Html.text(password_notice_title(model.passwordReason))]),
                Html.p([Attribute.class("text-xs text-amber-700 dark:text-amber-300")], [
                    Html.text("Choose a password of your own below. Everything else stays locked until you do.")
                ])
            ])
        } else {
            Html.div([], [])
        },
        profile_card(model),
        password_card(model),
    ])
}

# The school's record of this person, above the password form: read-only, because it is the school's data and
# changing it is an administrator's job (the Users screen). Every row is a *disabled input* rather than plain
# text, so the page looks like the rest of the app's forms and shows at a glance that none of it is the
# person's to edit. The photograph is the exception and sits beside the rows rather than in them: it is a
# picture, and printing the address of the file told the person nothing. The state input rides here: the
# payload only lands where the input is rendered, and only this page reads it.
profile_card = |model| {
    lines = profile_lines(model)
    rows = List.map(lines, |line| profile_row(model, line))
    notice = match list_state(model.profileData) {
        Ready(_) => Html.div([], [])
        Pending => Html.p([Attribute.class("text-xs text-muted-foreground italic")], [Html.text("Loading your details…")])
        Failed(message) => Html.p([Attribute.class("text-xs text-red-500")], [Html.text(message)])
    }

    Html.div([Attribute.class("rounded-lg border bg-card p-6 space-y-4 max-w-2xl")], [
        Html.input([
            Attribute.type("hidden"),
            Attribute.id("profile_data_input"),
            Attribute.value(model.profileData),
            Attribute.on_input(|s| GotProfileData(s))
        ]),
        Html.h2([Attribute.class("text-lg font-semibold")], [Html.text("Your details")]),
        Html.p([Attribute.class("text-xs text-muted-foreground")], [
            Html.text("The school's record of you. These fields are read-only — an administrator changes them from User Management.")
        ]),
        # The portrait and the details sit side by side where there is room and stack on a phone, the rule
        # the rest of the app's panels follow.
        Html.div([Attribute.class("flex flex-col sm:flex-row gap-5 sm:items-start")], [
            profile_photo(passport_url(lines), profile_initial(lines)),
            Html.div([Attribute.class("flex-1 min-w-0 space-y-4")], List.concat(rows, [notice])),
        ]),
    ])
}

# The state payload's own lines, or none while it is still coming.
profile_lines = |model| {
    match list_state(model.profileData) {
        Ready(lines) => lines
        Pending => []
        Failed(_) => []
    }
}

# One field of a `key|value` line, "" when the line has none.
profile_field = |line, index| {
    match List.get(Str.split_on(line, "|"), index) { Ok(value) => value, Err(_) => "" }
}

# The `passport` row's value — the URL of the photograph — or "" when the payload carries none. The row is
# looked up rather than assumed to be third: the backend owns the order, and a role without a photograph
# simply has no such row.
passport_url = |lines| {
    look = |remaining| match remaining {
        [] => ""
        [line, .. as rest] => if profile_field(line, 0) == "passport" { profile_field(line, 1) } else { look(rest) }
    }

    look(lines)
}

# The letter the frame falls back to when the photograph cannot be loaded: the first letter of the name the
# school has, the same language the users table uses for an account with no portrait. "?" for a payload with
# no name at all.
profile_initial = |lines| {
    look = |remaining| match remaining {
        [] => ""
        [line, .. as rest] => if profile_field(line, 0) == "name" { profile_field(line, 1) } else { look(rest) }
    }
    name = look(lines)

    if Str.is_empty(name) {
        "?"
    } else {
        match Str.to_utf8(name) |> List.first {
            Ok(byte) => match Str.from_utf8([byte]) { Ok(letter) => letter, Err(_) => "?" },
            Err(_) => "?",
        }
    }
}

# The photograph, in the place the file's address used to be printed. A person with none keeps the same
# shape — the camera placeholder the admin form uses while a photo is being chosen, with a line saying who
# can add one — so the card never collapses and the two states are the same size. A photograph that is on
# file but cannot be loaded is the page's own fallback (see `www/index.html`): the frame carries the letter
# to fall back to, and the line below is marked so the page can say what happened.
profile_photo = |url, initial| {
    frame = Attribute.class("w-28 h-28 shrink-0 rounded-xl overflow-hidden border border-border bg-muted flex items-center justify-center")
    picture =
        if Str.is_empty(url) {
            Html.div([Attribute.class("w-full h-full flex items-center justify-center text-muted-foreground")], [
                UI.icon("camera", "w-8 h-8")
            ])
        } else {
            Html.img([
                Attribute.src(url),
                Attribute.alt("Passport photograph"),
                Attribute.class("w-full h-full object-cover")
            ])
        }

    Html.div([Attribute.class("space-y-2")], [
        UI.label({ classes: "" }, [Html.text("Passport photograph")]),
        # The frame carries the id a suite reads (`profile-passport`) and the letter for the page's own
        # fallback, the same naming the rows use.
        Html.div([Attribute.id("profile-passport"), Attribute.data("photo-initial", initial), frame], [picture]),
        Html.p([Attribute.data("photo-note", ""), Attribute.class("text-xs text-muted-foreground")], [
            Html.text(
                if Str.is_empty(url) {
                    "No photograph on file yet — an administrator can add one from User Management."
                } else {
                    "As the school has it on file."
                }
            )
        ])
    ])
}

# One row: `key|value` from the payload, with the view owning the label. A key this page does not know is
# skipped, the same rule the dashboard's cards follow — and so is `passport`, whose row is drawn as a picture
# beside these rather than as the address of a file in the column of fields.
profile_row = |model, line| {
    parts = Str.split_on(line, "|")
    key = match List.get(parts, 0) { Ok(value) => value, Err(_) => "" }
    value = match List.get(parts, 1) { Ok(raw) => raw, Err(_) => "" }
    label = profile_label(key)

    if Str.is_empty(label) or key == "passport" {
        Html.div([], [])
    } else {
        # The input carries an id of its own (`profile-<key>`) so a suite can read the row and check that it is
        # disabled — the card's whole point is that these fields are not the person's to change.
        Html.div([Attribute.class("space-y-2")], [
            UI.label({ classes: "" }, [Html.text(label)]),
            Html.div([Attribute.id("profile-${key}")], [
                UI.input({
                    type: "text",
                    value: profile_value(model, key, value),
                    placeholder: "",
                    on_input: None,
                    is_disabled: Bool.True,
                    classes: ""
                })
            ])
        ])
    }
}

# The label a key carries, in the school's words. "" for a key this page does not show — which is how a row
# added for one role stays out of the others' cards.
profile_label = |key| {
    if key == "name" { "Full name" }
    else if key == "email" { "Email address" }
    else if key == "role" { "Role" }
    else if key == "passport" { "Passport photograph" }
    else if key == "class" { "Class level" }
    else if key == "date_of_birth" { "Date of birth" }
    else if key == "student_number" { "Admission number" }
    else if key == "staff_number" { "Staff ID" }
    else if key == "qualifications" { "Qualifications" }
    else if key == "date_employed" { "Date employed" }
    else if key == "pairs" { "Classes & subjects (this term)" }
    else if key == "students" { "My children" }
    else if key == "admin_type" { "Admin type" }
    else if key == "permissions" { "Permissions" }
    else { "" }
}

# The value as the card should read: two rows hold catalog *keys* rather than the school's words, so they are
# looked up (falling back to the key itself when the catalog has not arrived). Everything else is already text.
profile_value = |model, key, value| {
    if key == "role" {
        if value == "admin" { "Administrator" } else if value == "teacher" { "Teacher" } else if value == "parent" { "Parent" } else { "Student" }
    } else if key == "admin_type" {
        catalog_label(admin_catalog_types(model.adminTypesData), value)
    } else if key == "permissions" {
        keys = List.keep_if(Str.split_on(value, ","), |entry| !Str.is_empty(entry))
        Str.join_with(List.map(keys, |entry| catalog_label(admin_catalog_permissions(model.adminTypesData), entry)), ", ")
    } else {
        value
    }
}

# The label a catalog line carries for a key, or the key itself when the catalog has not arrived.
catalog_label = |lines, key| {
    look = |remaining| match remaining {
        [] => key
        [line, .. as rest] => if catalog_field(line, 1) == key { catalog_field(line, 2) } else { look(rest) }
    }

    look(lines)
}

# Why the change is owed, said the way the person met it: an account that was just made, or a password an
# administrator replaced.
password_notice_title = |reason| {
    if reason == "reset" {
        "An administrator reset your password"
    } else {
        "Your password was set for you"
    }
}

# The form. Two fields and a button: the value goes to the backend in the request body and is never stored
# anywhere in the page's own state beyond the keystrokes that put it there. It is a real `<form>`
# (see UI.form), so Enter in any of the fields sets the password — the same thing the button does.
password_card = |model| {
    card = [
        Html.h2([Attribute.class("text-lg font-semibold")], [Html.text("Password")]),
        Html.p([Attribute.class("text-xs text-muted-foreground")], [
            Html.text("At least 8 characters. You will sign in with it from now on.")
        ]),
        # The current password is asked only when nothing is owed: a change the person *chose* has to prove
        # it (Authentik checks it for us), while a change they are being made to do follows a sign-in with
        # that very password — and asking again there would let a broken check lock them out of the one
        # screen that frees them.
        if model.passwordRequired {
            Html.p([Attribute.class("text-xs text-muted-foreground")], [
                Html.text("You signed in with the password an administrator set, so there is nothing to prove — just choose your own.")
            ])
        } else {
            password_field("Current password", "current-password-field", model.currentPassword, model.isSubmitting, |s| UpdateCurrentPassword(s))
        },
        Html.div([Attribute.class("grid grid-cols-1 md:grid-cols-2 gap-4")], [
            password_field("New password", "new-password-field", model.newPassword, model.isSubmitting, |s| UpdateNewPassword(s)),
            password_field("Repeat the new password", "confirm-password-field", model.confirmPassword, model.isSubmitting, |s| UpdateConfirmPassword(s)),
        ]),
        result_banner(model.passwordResult),
        Html.div([], [
            UI.button(
                { ..UI.default_button, variant: Primary, size: Default, is_submit: Bool.True, is_disabled: model.isSubmitting, classes: "" },
                [Html.text(if model.isSubmitting { "Saving…" } else { "Set my password" })]
            )
        ]),
    ]

    Html.div([Attribute.class("rounded-lg border bg-card p-6 max-w-2xl")], [
        UI.form("space-y-4", SubmitPasswordChange, card)
    ])
}

password_field = |label, field_id, value, is_disabled, to_msg| {
    Html.div([Attribute.class("space-y-2")], [
        UI.label({ classes: "" }, [Html.text(label)]),
        Html.div([Attribute.id(field_id)], [
            UI.input({
                type: "password",
                value: value,
                placeholder: "",
                on_input: Input(to_msg),
                is_disabled: is_disabled,
                classes: ""
            })
        ])
    ])
}

result_banner = |result| {
    match result {
        None => Html.div([], [])
        Success(message) => Html.div([Attribute.class("rounded-md bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 p-3")], [
            Html.p([Attribute.class("text-sm text-green-800 dark:text-green-200")], [Html.text(message)])
        ])
        Error(message) => Html.div([Attribute.class("rounded-md bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 p-3")], [
            Html.p([Attribute.class("text-sm text-red-800 dark:text-red-200")], [Html.text(message)])
        ])
    }
}
}
