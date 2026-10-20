
import html.Html
import html.Attribute

import UI
import State exposing [Model, Msg]

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
        password_card(model),
    ])
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
# anywhere in the page's own state beyond the keystrokes that put it there.
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
                { variant: Primary, size: Default, on_click: Click(SubmitPasswordChange), is_disabled: model.isSubmitting, classes: "" },
                [Html.text(if model.isSubmitting { "Saving…" } else { "Set my password" })]
            )
        ]),
    ]

    Html.div([Attribute.class("rounded-lg border bg-card p-6 space-y-4 max-w-2xl")], card)
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
