
import html.Html
import html.Attribute

import UI
import State exposing [Model, Msg, AdminConfigTab, AdminUserTab, list_state]
AdminView := [].{

view = |model| {
    match model.route {
        AdminUserManagement => admin_users_view(model)
        AdminConfigurationHub => admin_config_view(model)
        AdminLMS => admin_lms_view(model)
        _ => Html.div([], [Html.h1([], [Html.text("Admin Dashboard")]), Html.p([], [Html.text("Welcome to Admin Dashboard")])])
    }
}

# -------------------------------------------------------
# USER MANAGEMENT VIEW
# -------------------------------------------------------

admin_users_view = |model| {
    # One form, four modes: add (POST, empty), complete a login that has no profile yet (PUT,
    # empty), edit an existing profile (PUT, prefilled from the row), and reset a login's
    # password (a separate write; the modal shows only the password field).
    resetting = !Str.is_empty(model.resetPasswordId)
    form_mode =
        if resetting { ResetPassword }
        else if model.userEditing { EditingUser }
        else if !Str.is_empty(model.completingProfileId) { CompletingProfile }
        else { AddingUser }

    # A write that names an existing login: the two PUT modes. The email is editable in every
    # mode — the backend patches Authentik's address when a PUT carries one — and the role comes
    # from the id's table, so neither a create-only role nor a completed one is sent by a PUT.
    selected_count = U64.to_str(List.len(model.selectedUserIds))
    form_title = match form_mode {
        AddingUser => "Add New User"
        CompletingProfile => "Complete Profile"
        EditingUser => "Edit User"
        ResetPassword => "Reset password"
    }
    form_description = match form_mode {
        AddingUser => "Create a new account and optionally upload a passport photograph."
        CompletingProfile => "This login is already in the directory; the school data below is what makes it a full account. Its address is Authentik's and editable too — fixing a login's address is part of managing accounts."
        EditingUser => "Change the school data for this account, or its address. Fields left blank are left unchanged."
        ResetPassword => "Set a new password for this login. It replaces the current one in Authentik and is shown once on this page, with a Copy button."
    }


    Html.div([Attribute.class("p-6 md:p-8 space-y-6")], [
        # Page header with the entry action: Add opens the modal in create mode.
        Html.div([Attribute.class("flex items-start justify-between gap-4")], [
            Html.div([], [
                Html.h1([Attribute.class("text-3xl font-bold tracking-tight")], [Html.text("User Management")]),
                Html.p([Attribute.class("text-muted-foreground mt-1")], [Html.text("Manage all user accounts across Students, Teachers, Parents, and Administrators.")])
            ]),
            UI.button({ variant: Primary, size: Default, on_click: Click(OpenUserForm), is_disabled: model.isSubmitting, classes: "gap-2" }, [UI.icon("plus", "w-4 h-4"), Html.text("Add New User")])
        ]),

        # Submit feedback banner
        match model.submitResult {
            None => Html.div([], [])
            Success(msg) => Html.div([Attribute.class("rounded-md bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 p-4 flex items-center gap-2")], [
                Html.span([Attribute.class("text-green-600 text-lg")], [Html.text("✓")]),
                Html.p([Attribute.class("text-sm text-green-800 dark:text-green-200 font-medium")], [Html.text(msg)])
            ])
            Error(msg) => Html.div([Attribute.class("rounded-md bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 p-4 flex items-center gap-2")], [
                Html.span([Attribute.class("text-red-600 text-lg")], [Html.text("✕")]),
                Html.p([Attribute.class("text-sm text-red-800 dark:text-red-200 font-medium")], [Html.text(msg)])
            ])
        },

        # The user form (add / complete / edit / reset password) lives in a modal over the table now:
        # the page stays put, and the modal carries the four modes' fields. It opens from the header's
        # Add button, from a row's Complete profile / Edit / Reset password actions, and closes on
        # the x or when a write lands (the credentials panel then shows inline beneath the table).
        if model.userFormOpen {
              Html.div([Attribute.class("fixed inset-0 z-50 overflow-y-auto bg-black/40 p-4 md:p-8 backdrop-blur-sm")], [
                  Html.div([Attribute.class("w-full max-w-2xl mx-auto my-4 md:my-10 rounded-2xl border border-border bg-card text-card-foreground shadow-2xl")], [
                      UI.card_header({ classes: "" }, [
                          Html.div([Attribute.class("flex items-start justify-between gap-4")], [
                              Html.div([], [
                                  UI.card_title({ classes: "" }, [Html.text(form_title)]),
                                  Html.p([Attribute.class("text-sm text-muted-foreground")], [Html.text(form_description)])
                              ]),
                              Html.div([Attribute.title("Close")], [
                                  UI.button({ variant: Ghost, size: Sm, on_click: Click(CloseUserForm), is_disabled: model.isSubmitting, classes: "text-muted-foreground" }, [UI.icon("x", "w-4 h-4")])
                              ])
                          ])
                      ]),

	              UI.card_content({ classes: "space-y-6" }, [
        	                  form_banner(model),
        	                  if resetting {
        	                      reset_password_body(model)
        	                  } else {
        	                      user_form_body(model, form_mode)
        	                  }
        	              ]),
        	              # The modal's single action: create / complete / save / set password. Two
        	              # explicit buttons rather than one with a conditional on_click: Joy's runtime
        	              # attaches handlers per message, and a conditional expression as the handler
        	              # value did not dispatch from every branch.
        	              Html.div([Attribute.class("px-6 pb-6 pt-0")], [
        	                  Html.div([Attribute.class("flex justify-end border-t pt-4")], [
        	                      if resetting {
        	                          UI.button(
        	                              { variant: Primary, size: Default, on_click: Click(SubmitResetPassword), is_disabled: model.isSubmitting, classes: "w-full sm:w-auto" },
        	                              [Html.text(if model.isSubmitting { "Setting..." } else { "Set password" })]
        	                          )
        	                      } else {
        	                          UI.button(
        	                              { variant: Primary, size: Default, on_click: Click(SubmitNewUser), is_disabled: model.isSubmitting, classes: "w-full sm:w-auto" },
        	                              [Html.text(user_form_submit_label(model.isSubmitting, form_mode))]
        	                          )
        	                      }
        	                  ])
        	              ])
        	          ])
        	      ])
	        } else {
	              Html.div([], [])
	        },

	        # The teacher Assign dialog (rendered as a modal over the page, like the user form): the
	        # teacher's current pairs as removable badges plus the catalog's searchable dropdown, and a
	        # Save that replaces the whole set.
	        assign_form(model),

	        # Hidden inputs for JS data binding
        Html.input([
            Attribute.type("hidden"),
            Attribute.value(model.usersStudentsData),
            Attribute.id("users_students_data_input"),
            Attribute.on_input(|s| GotStudentsData(s))
        ]),
        Html.input([
            Attribute.type("hidden"),
            Attribute.value(model.usersTeachersData),
            Attribute.id("users_teachers_data_input"),
            Attribute.on_input(|s| GotTeachersData(s))
        ]),
        Html.input([
            Attribute.type("hidden"),
            Attribute.value(model.usersParentsData),
            Attribute.id("users_parents_data_input"),
            Attribute.on_input(|s| GotParentsData(s))
        ]),
        Html.input([
            Attribute.type("hidden"),
            Attribute.value(model.usersAdminsData),
            Attribute.id("users_admins_data_input"),
            Attribute.on_input(|s| GotAdminsData(s))
        ]),
	        Html.input([
	            Attribute.type("hidden"),
	            Attribute.value(model.userClassLevelsData),
	            Attribute.id("user_class_levels_data_input"),
	            Attribute.on_input(|s| GotUserClassLevels(s))
	        ]),

	        # The admin widgets' list payloads: the qualifications catalog, the full pair catalog, and
	        # the teacher-assignments list the Assign dialog seeds its badges from. The inputs sit here
	        # (only the users page uses them), and each fetch's answer is dispatched only into an input
	        # that exists.
	        Html.input([
	            Attribute.type("hidden"),
	            Attribute.value(model.credentialsData),
	            Attribute.id("credentials_data_input"),
	            Attribute.on_input(|s| GotCredentialsData(s))
	        ]),
	        Html.input([
	            Attribute.type("hidden"),
	            Attribute.value(model.subjectPairsData),
	            Attribute.id("subject_pairs_data_input"),
	            Attribute.on_input(|s| GotSubjectPairsData(s))
	        ]),
	        Html.input([
	            Attribute.type("hidden"),
	            Attribute.value(model.teacherAssignmentsData),
	            Attribute.id("teacher_assignments_data_input"),
	            Attribute.on_input(|s| GotTeacherAssignmentsData(s))
	        ]),


        # Role tabs + users table
        Html.div([Attribute.class("space-y-4")], [
            # Tab bar: the same segmented pill control the Configuration hub uses — one tab
            # switcher across the app rather than two styling languages.
            Html.div([Attribute.class("flex overflow-x-auto p-1 bg-muted rounded-md w-fit")], [
                user_tab(model.activeUserTab, Students, "Students", "graduation-cap"),
                user_tab(model.activeUserTab, Teachers, "Teachers", "presentation"),
                user_tab(model.activeUserTab, Parents, "Parents", "users"),
                user_tab(model.activeUserTab, Admins, "Administrators", "shield"),
            ]),

            # Bulk delete bar: appears once rows are ticked. Every listed row is deletable — the
            # backend treats a row with no login behind it as removed by the profile hide alone — so
            # anything on the tab can be selected and removed together.
            if !List.is_empty(model.selectedUserIds) {
                Html.div([Attribute.class("flex items-center justify-between rounded-md border border-border bg-muted/30 px-4 py-2")], [
                    Html.p([Attribute.class("text-sm text-muted-foreground")], [Html.text("${selected_count} selected")]),
                    Html.div([Attribute.class("flex items-center gap-2")], [
                        UI.button({ variant: Ghost, size: Sm, on_click: Click(ClearUserSelection), is_disabled: model.isSubmitting, classes: "text-xs" }, [Html.text("Clear")]),
                        UI.button({ variant: Destructive, size: Sm, on_click: Click(DeleteSelectedUsers), is_disabled: model.isSubmitting, classes: "text-xs" }, [Html.text("Delete selected")])
                    ])
                ])
            } else {
                Html.div([], [])
            },

            # Users table
            UI.card({ classes: "" }, [
                UI.card_content({ classes: "p-0" }, [
                    UI.table({ classes: "" }, [
                        UI.table_header({ classes: "" }, [
                            UI.table_row({ classes: "" }, [
                                UI.table_head({ classes: "w-8" }, [Html.text("")]),
                                UI.table_head({ classes: "w-10" }, [Html.text("")]),
                                UI.table_head({ classes: "" }, [Html.text("Name")]),
                                UI.table_head({ classes: "" }, [Html.text("Email")]),
                                # The school number is the backend's rendered form and read-only here: it
                                # is handed out by the write that makes the row (JES-… for a student,
                                # EMP-… for staff), and no form of this page changes it.
                                UI.table_head({ classes: "" }, [Html.text("School number")]),
                                UI.table_head({ classes: "" }, [Html.text("Status")]),
                                UI.table_head({ classes: "text-right" }, [Html.text("Actions")])
                            ])
                        ]),
                        UI.table_body({ classes: "" },
                            users_for_tab(model)
                        )
                    ])
                ])
            ])
        ]),

        # The one-time credentials handoff, shown only right after a create that carried a password:
        # the form has been cleared by then (the password is never stored anywhere), so this panel is
        # the single place the value exists on the page, and it clears the moment the form starts
        # another write. It sits at the END of the view on purpose: its contents change count
        # (hidden vs four rows) and Joy's renderer patches attributes against a flat ref list, so a
        # subtree whose size changes shifts the refs of everything after it — keeping it after the
        # form and the table means their refs never move and a value-input patch cannot land on a
        # text node (`node.setAttribute is not a function`).
        match model.lastCredentials {
            None => Html.div([Attribute.class("hidden")], [])
            Credentials(email, password) => Html.div([Attribute.class("rounded-md border border-primary bg-primary/10 p-4 space-y-2")], [
                Html.p([Attribute.class("text-sm font-medium")], [Html.text("Account created — copy the credentials to hand over")]),
                Html.div([Attribute.class("text-sm font-mono space-y-1")], [
                    Html.p([], [Html.text(email)]),
                    Html.p([], [Html.text(password)])
                ]),
                Html.div([Attribute.class("flex items-center gap-2")], [
                    UI.button({ variant: Outline, size: Sm, on_click: Click(CopyLastCredentials), is_disabled: Bool.False, classes: "text-xs" }, [Html.text("Copy credentials")]),
                    Html.span([Attribute.id("copy-credentials-feedback"), Attribute.class("text-xs text-muted-foreground")], [])
                ]),
                Html.p([Attribute.class("text-xs text-muted-foreground")], [Html.text("Shown once — the password is not stored anywhere after this.")])
            ])
        },
    ])
}

user_tab = |active_tab, this_tab, label, icon_name| {
    is_active = active_tab == this_tab
    base_classes = "inline-flex items-center justify-center whitespace-nowrap rounded-sm px-3 py-1.5 text-sm font-medium ring-offset-background transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50"
    classes =
        if is_active {
            Str.join_with([base_classes, "bg-background text-foreground shadow-sm"], " ")
        } else {
            Str.join_with([base_classes, "text-muted-foreground hover:bg-muted hover:text-foreground"], " ")
        }
    Html.button([
        Attribute.class("${classes} inline-flex items-center gap-1.5"),
        Attribute.type("button"),
        # A tab switch is a view change of its own: data-nav is what starts the top border
        # progress bar for one (see www/index.html).
        Attribute.data("nav", ""),
        Attribute.on_click(SetUserTab(this_tab))
    ], [UI.icon(icon_name, "w-4 h-4"), Html.text(label)])
}

# --- Add New User form pieces ---

# One labelled field of the create form.
user_form_field = |label_text, field| {
    Html.div([Attribute.class("space-y-2")], [
        UI.label({ classes: "" }, [Html.text(label_text)]),
        field
    ])
}

# The banner inside the modal (and, after a write, on the page itself): the backend's own text for
# a refusal, or the success line for a write that landed.
form_banner = |model| {
    match model.submitResult {
        None => Html.div([], [])
        Success(msg) => Html.div([Attribute.class("rounded-md bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 p-4 flex items-center gap-2")], [
            Html.span([Attribute.class("text-green-600 text-lg")], [Html.text("✓")]),
            Html.p([Attribute.class("text-sm text-green-800 dark:text-green-200 font-medium")], [Html.text(msg)])
        ])
        Error(msg) => Html.div([Attribute.class("rounded-md bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 p-4 flex items-center gap-2")], [
            Html.span([Attribute.class("text-red-600 text-lg")], [Html.text("✕")]),
            Html.p([Attribute.class("text-sm text-red-800 dark:text-red-200 font-medium")], [Html.text(msg)])
        ])
    }
}

# The modal's fields for the three writes that touch a profile (add, complete, edit): the name
# parts, the contact and role, the profile fields the chosen role uses, the create-only password,
# and the passport. The email input is enabled in every mode: a PUT that carries an email patches
# Authentik's address (the login's own), so an account created without one — or with a typo — can
# be fixed here.
user_form_body = |model, form_mode| {
    Html.div([Attribute.class("space-y-6")], [
        Html.div([Attribute.class("grid grid-cols-1 md:grid-cols-3 gap-4")], [
            user_form_field("First name", user_form_text_input("e.g. Adamu", model.newUserFirstName, model.isSubmitting, |s| UpdateNewUserFirstName(s))),
            user_form_field("Middle name", user_form_text_input("e.g. Ibrahim", model.newUserMiddleName, model.isSubmitting, |s| UpdateNewUserMiddleName(s))),
            user_form_field("Surname", user_form_text_input("e.g. Musa", model.newUserSurname, model.isSubmitting, |s| UpdateNewUserSurname(s)))
        ]),
        Html.div([Attribute.class("grid grid-cols-1 md:grid-cols-2 gap-4")], [
            user_form_field("Email address", UI.input({
                type: "email",
                value: model.newUserEmail,
                placeholder: "e.g. adamu@johnethel.school",
                on_input: Input(|s| UpdateNewUserEmail(s)),
                is_disabled: model.isSubmitting,
                classes: ""
            })),
            user_form_field("Role", user_role_select(model))
        ]),
        user_role_fields(model),
        # The teacher form's qualifications picker: the credentials catalog's searchable
        # multi-select, badge-with-removal like the retired app's CredentialsSelect. Only the
        # teacher profile carries the column, so only the teacher role shows it.
        if model.newUserRole == "Teacher" {
            user_qualifications_field(model)
        } else {
            Html.div([], [])
        },
        # The password, for create mode only: the one thing the profile fields have no place for,
        # and the one the admin hands over. Optional — a login without one is made and can get one
        # later from the row's Reset password action.
        if form_mode == AddingUser {
            Html.div([Attribute.class("grid grid-cols-1 md:grid-cols-2 gap-4")], [
                user_form_field("Password (optional)", Html.div([Attribute.class("space-y-2")], [
                    Html.div([Attribute.id("new-user-password-field")], [
                        UI.input({
                            type: "text",
                            value: model.newUserPassword,
                            placeholder: "Leave blank, or click Generate",
                            on_input: Input(|s| UpdateNewUserPassword(s)),
                            is_disabled: model.isSubmitting,
                            classes: "font-mono"
                        })
                    ]),
                    Html.div([Attribute.class("flex items-center gap-2")], [
                        UI.button({ variant: Outline, size: Sm, on_click: Click(GenerateUserPassword), is_disabled: model.isSubmitting, classes: "text-xs" }, [Html.text("Generate")]),
                        Html.span([Attribute.class("text-xs text-muted-foreground")], [Html.text("It is shown once after the account is created, with a Copy button.")])
                    ])
                ]))
            ])
        } else {
            Html.div([], [])
        },
        Html.div([Attribute.class("border-t pt-6")], [
            Html.p([Attribute.class("text-sm font-medium mb-2")], [Html.text("Passport Photograph")]),
            Html.div([Attribute.class("flex items-center gap-4")], [
                Html.div([Attribute.id("passport-preview"), Attribute.class("w-16 h-16 rounded-full bg-muted border-2 border-dashed border-border flex items-center justify-center text-muted-foreground overflow-hidden")], [
                    UI.icon("camera", "w-7 h-7")
                ]),
                Html.div([Attribute.class("flex-1 space-y-1")], [
                    Html.input([
                        Attribute.type("file"),
                        Attribute.id("passport-file-input"),
                        Attribute.class("block w-full text-sm text-muted-foreground file:mr-4 file:py-2 file:px-4 file:rounded-md file:border-0 file:text-sm file:font-medium file:bg-primary/10 file:text-primary hover:file:bg-primary/20 cursor-pointer")
                    ]),
                    Html.p([Attribute.class("text-xs text-muted-foreground")], [Html.text("JPEG or PNG, max 5 MB. Choosing a file uploads it to R2 and fills the URL below; a photo that is already hosted can be pasted there instead.")]),
                    Html.p([Attribute.id("passport-upload-status"), Attribute.class("text-xs text-muted-foreground")], [])
                ])
            ]),
            Html.div([Attribute.id("passport-url-field"), Attribute.class("space-y-2 pt-3")], [
                UI.label({ classes: "" }, [Html.text("Passport URL (required)")]),
                UI.input({
                    type: "text",
                    value: model.newUserPassportKey,
                    placeholder: "https://...",
                    on_input: Input(|s| SetPassportKey(s)),
                    is_disabled: model.isSubmitting,
                    classes: ""
                })
            ])
        ])
    ])
}

# The reset-password mode's fields: which login, and the new password with a generator.
reset_password_body = |model| {
    Html.div([Attribute.class("space-y-6")], [
        Html.div([Attribute.class("space-y-2")], [
            UI.label({ classes: "" }, [Html.text("Login")]),
            Html.p([Attribute.class("text-sm font-mono text-muted-foreground")], [Html.text(model.resetPasswordEmail)])
        ]),
        user_form_field("New password", Html.div([Attribute.class("space-y-2")], [
            Html.div([Attribute.id("new-user-password-field")], [
                UI.input({
                    type: "text",
                    value: model.newUserPassword,
                    placeholder: "Type one, or click Generate",
                    on_input: Input(|s| UpdateNewUserPassword(s)),
                    is_disabled: model.isSubmitting,
                    classes: "font-mono"
                })
            ]),
            Html.div([Attribute.class("flex items-center gap-2")], [
                UI.button({ variant: Outline, size: Sm, on_click: Click(GenerateUserPassword), is_disabled: model.isSubmitting, classes: "text-xs" }, [Html.text("Generate")]),
                Html.span([Attribute.class("text-xs text-muted-foreground")], [Html.text("8-72 characters. Shown once on this page after it is set, with a Copy button.")])
            ])
        ]))
    ])
}

# The modal's single action's label, per mode and per submitting state.
user_form_submit_label = |busy, form_mode| {
    if busy {
        match form_mode {
            AddingUser => "Adding..."
            CompletingProfile => "Completing..."
            EditingUser => "Saving..."
            ResetPassword => "Setting..."
        }
    } else {
        match form_mode {
            AddingUser => "Create User"
            CompletingProfile => "Complete profile"
            EditingUser => "Save changes"
            ResetPassword => "Set password"
        }
    }
}

user_form_text_input = |placeholder, value, is_disabled, to_msg| {
    UI.input({
        type: "text",
        value,
        placeholder,
        on_input: Input(to_msg),
        is_disabled,
        classes: ""
    })
}

# The role picker: its value is the model's, so the selection survives the re-render a role
# change causes. Completing a profile fixes the role — the row was on a role's tab and the backend
# takes the table from the id — so the picker is shown but not editable there.
user_role_select = |model| {
    completing = !Str.is_empty(model.completingProfileId)

    Html.div([Attribute.class("relative")], [
        Html.select([
            Attribute.class(config_select_classes),
            Attribute.id("new-user-role-select"),
            Attribute.value(model.newUserRole),
            Attribute.on_change(|s| UpdateNewUserRole(s)),
            Attribute.disabled(completing)
        ], [
            Html.option([Attribute.value("Student")], [Html.text("Student")]),
            Html.option([Attribute.value("Teacher")], [Html.text("Teacher")]),
            Html.option([Attribute.value("Parent")], [Html.text("Parent")]),
            Html.option([Attribute.value("Admin")], [Html.text("Administrator")])
        ]),
        Html.span([Attribute.class("pointer-events-none absolute inset-y-0 right-3 flex items-center text-muted-foreground text-xs")], [Html.text("▼")])
    ])
}

# A picker fed from /api/class_levels (the active levels): the value the form submits is the record
# id (`class_levels:jss_1`), which the backend's record_ref! reads back as the link. Until the list
# answers there is a loading option; if it errors, the form says so instead of submitting a guess.
user_class_level_select = |model, classes| {
    options = match list_state(classes) {
        Pending => [Html.option([Attribute.disabled(Bool.True), Attribute.value("")], [Html.text("Fetching class levels…")])]
        Failed(_) => [Html.option([Attribute.disabled(Bool.True), Attribute.value("")], [Html.text("Could not load class levels — refresh")])]
        Ready(lines) =>
            List.map(lines, |line| {
                parts = Str.split_on(line, "|")
                id = match List.get(parts, 0) { Ok(v) => v, Err(_) => "" }
                name = match List.get(parts, 1) { Ok(v) => v, Err(_) => id }
                Html.option([Attribute.value(id)], [Html.text(name)])
            })
    }
    placeholder = Html.option([Attribute.value(""), Attribute.disabled(Bool.True)], [Html.text("Select class level…")])

    Html.div([Attribute.class("relative")], [
        Html.select([
            Attribute.class(config_select_classes),
            Attribute.id("new-user-class-level"),
            Attribute.value(model.newUserClassLevel),
            Attribute.on_change(|s| UpdateNewUserClassLevel(s)),
            Attribute.disabled(model.isSubmitting),
        ], List.concat([placeholder], options)),
        Html.span([Attribute.class("pointer-events-none absolute inset-y-0 right-3 flex items-center text-muted-foreground text-xs")], [Html.text("▼")])
    ])
}

# The profile fields the chosen role's create actually reads: date_of_birth and class_level for a
# student, role_title for an admin, nothing extra for a teacher or a parent.
user_role_fields = |model| {
    if model.newUserRole == "Admin" {
        Html.div([Attribute.class("grid grid-cols-1 md:grid-cols-3 gap-4")], [
            user_form_field("Role title (optional)", user_form_text_input("e.g. Bursar", model.newUserRoleTitle, model.isSubmitting, |s| UpdateNewUserRoleTitle(s)))
        ])
    } else if model.newUserRole == "Student" {
        Html.div([Attribute.class("grid grid-cols-1 md:grid-cols-3 gap-4")], [
            user_form_field("Date of birth (*)", UI.input({
                type: "date",
                value: model.newUserDateOfBirth,
                placeholder: "",
                on_input: Input(|s| UpdateNewUserDateOfBirth(s)),
                is_disabled: model.isSubmitting,
                classes: ""
            })),
            user_form_field("Class level (*)", user_class_level_select(model, model.userClassLevelsData))
        ])
    } else {
        Html.div([], [])
    }
}

users_for_tab = |model| {
    (payload, retry_url, empty_title, empty_description) = match model.activeUserTab {
        Students => (model.usersStudentsData, "/api/users?role=Student", "No students yet", "Add a student above to get started.")
        Teachers => (model.usersTeachersData, "/api/users?role=Teacher", "No teachers yet", "Add a teacher above to get started.")
        Parents => (model.usersParentsData, "/api/users?role=Parent", "No parents yet", "Add a parent above to get started.")
        Admins => (model.usersAdminsData, "/api/users?role=Admin", "No administrators yet", "Add an administrator above to get started.")
    }

    # The table's seven columns: selection, avatar, name, email, school number, status, actions.
    column_widths = ["w-8", "w-8", "w-40", "w-56", "w-28", "w-20", "w-24"]

    match list_state(payload) {
        Pending => UI.table_skeleton_rows(column_widths)
        Failed(message) => [UI.table_error_state(7, "Could not load this list", message, Click(RetryList(retry_url)))]
        Ready(rows) =>
            if List.is_empty(rows) {
                [UI.table_empty_state(7, "users", empty_title, empty_description)]
            } else {
                List.map(rows, |line| {
                    # One row per line, as the page's `formatUsers` writes it. The first six fields are
                    # what the table renders; the last seven are what Edit loads into the form in the
                    # modal (only the form can change them — the backend's PUT patches the row).
                    # id|name|email|is_active|has_profile|school_number|first_name|middle_name|surname|date_of_birth|current_class|role_title|passport.
                    user_row(model, line)
                })
            }
    }
}

user_row = |model, line| {
    busy = model.isSubmitting
    parts = Str.split_on(line, "|")
    id = match List.get(parts, 0) { Ok(v) => v, Err(_) => "" }
    name = match List.get(parts, 1) { Ok(v) => v, Err(_) => "Unknown" }
    email = match List.get(parts, 2) { Ok(v) => v, Err(_) => "" }
    is_active = match List.get(parts, 3) { Ok(s) => s == "true", Err(_) => Bool.True }
    has_profile = match List.get(parts, 4) { Ok(s) => s == "true", Err(_) => Bool.True }
    school_number = match List.get(parts, 5) { Ok(v) => v, Err(_) => "" }
    selected = List.contains(model.selectedUserIds, id)
    initial =
        if Str.is_empty(name) { "?" }
        else {
            match Str.to_utf8(name) |> List.first {
                Ok(b) => match Str.from_utf8([b]) { Ok(s) => s, Err(_) => "?" }
                Err(_) => "?"
            }
        }
    UI.table_row({ classes: "hover:bg-muted/30 transition-colors" }, [
        UI.table_cell({ classes: "" }, [
            # The selection tick for the bulk delete above the table. A button rather than a real
            # checkbox so the click is a Joy message like the row's other actions.
            UI.button(
                { variant: Ghost, size: Sm, on_click: Click(ToggleUserSelected(id)), is_disabled: busy, classes: "text-xs" },
                [Html.text(if selected { "☑" } else { "☐" })]
            )
        ]),
        UI.table_cell({ classes: "" }, [
            Html.div([Attribute.class("w-8 h-8 rounded-full bg-primary/15 flex items-center justify-center text-sm font-semibold text-primary")], [
                Html.text(initial)
            ])
        ]),
        UI.table_cell({ classes: "font-medium" }, [
            Html.div([Attribute.class("flex items-center gap-2")], [
                Html.text(name),
                # A login the directory has and the profile tables do not: the row is real, its school
                # data is what is missing.
                if has_profile {
                    Html.div([], [])
                } else {
                    Html.span([Attribute.class("inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium bg-amber-50 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400")], [Html.text("No profile yet")])
                }
            ])
        ]),
        UI.table_cell({ classes: "text-muted-foreground text-sm" }, [Html.text(email)]),
        # Read-only, and a dash when the row has no number (a parent, or a login with no profile yet):
        # the form above cannot set it and no action here changes it. Monospaced and unbroken, because a
        # number is read character by character.
        UI.table_cell({ classes: "text-muted-foreground text-sm font-mono whitespace-nowrap" }, [
            Html.text(if Str.is_empty(school_number) { "—" } else { school_number })
        ]),
        UI.table_cell({ classes: "" }, [
            Html.span([
                Attribute.class(
                    if is_active {
                        "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium bg-green-50 text-green-700 dark:bg-green-900/30 dark:text-green-400"
                    } else {
                        "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium bg-muted text-muted-foreground"
                    }
                )
            ], [Html.text(if is_active { "Active" } else { "Inactive" })])
        ]),
        UI.table_cell({ classes: "text-right" }, [
            Html.div([Attribute.class("flex items-center justify-end gap-1")], [
                # A profile-less login gets the one completion action: while the login is on, the
                # modal opens with this login's school data to fill in; once it is off (the delete
                # that hid the profile also disabled the login), the action is Activate, which
                # brings both back. Every row also offers Reset password, which opens the modal in
                # its password-only mode.
                if has_profile {
                    Html.div([Attribute.class("flex items-center justify-end gap-1")], [
                        # Only a teacher row is assigned class-subject pairs; the other roles have no
                        # teaching scope. The dialog replaces the whole set when it saves.
                        if model.activeUserTab == Teachers {
                            UI.button(
                                { variant: Ghost, size: Sm, on_click: Click(OpenTeacherAssign(id)), is_disabled: busy, classes: "text-xs" },
                                [Html.text("Assign")]
                            )
                        } else {
                            Html.div([], [])
                        },
                        UI.button(
                            { variant: Ghost, size: Sm, on_click: Click(StartUserEdit(line)), is_disabled: busy, classes: "text-xs" },
                            [Html.text("Edit")]
                        ),
                        if is_active {
                            UI.button(
                                { variant: Ghost, size: Sm, on_click: Click(SubmitDeactivateUser(id)), is_disabled: busy, classes: "text-xs text-destructive hover:text-destructive" },
                                [Html.text("Delete")]
                            )
                        } else {
                            UI.button(
                                { variant: Ghost, size: Sm, on_click: Click(SubmitActivateUser(id)), is_disabled: busy, classes: "text-xs text-primary" },
                                [Html.text("Activate")]
                            )
                        },
                        UI.button(
                            { variant: Ghost, size: Sm, on_click: Click(OpenResetPassword(id, email)), is_disabled: busy, classes: "text-xs" },
                            [Html.text("Reset password")]
                        )
                    ])
                } else {
                    Html.div([Attribute.class("flex items-center justify-end gap-1")], [
                        if is_active {
                            UI.button(
                                { variant: Primary, size: Sm, on_click: Click(CompleteProfile(id, email)), is_disabled: busy, classes: "text-xs" },
                                [Html.text("Complete profile")]
                            )
                        } else {
                            UI.button(
                                { variant: Primary, size: Sm, on_click: Click(SubmitActivateUser(id)), is_disabled: busy, classes: "text-xs" },
                                [Html.text("Activate")]
                            )
                        },
                        UI.button(
                            { variant: Ghost, size: Sm, on_click: Click(OpenResetPassword(id, email)), is_disabled: busy, classes: "text-xs" },
                            [Html.text("Reset password")]
                        )
                    ])
                }
            ])
        ])
    ])
}

# -------------------------------------------------------
# CONFIGURATION HUB VIEW
# -------------------------------------------------------

admin_config_view = |model| {
	Html.div([Attribute.class("p-6 md:p-8 space-y-6")], [
		Html.div([Attribute.class("flex justify-between items-center")], [
			Html.div([], [
				Html.h1([Attribute.class("text-3xl font-bold tracking-tight")], [Html.text("Configuration Hub")]),
				Html.p([Attribute.class("text-muted-foreground mt-1")], [Html.text("Manage system-wide academic settings and structures.")])
			])
		]),

		# Hidden inputs fed by JS when the fetch_data port returns each list. They sit outside the
		# tab bodies so a response that arrives while another tab is open is still delivered.
		Html.input([Attribute.type("hidden"), Attribute.id("terms_data_input"), Attribute.value(model.termsData), Attribute.on_input(|s| GotTermsData(s))]),
		Html.input([Attribute.type("hidden"), Attribute.id("subjects_data_input"), Attribute.value(model.subjectsData), Attribute.on_input(|s| GotSubjectsData(s))]),
		# The Subjects section lists every subject (so a deactivated one can be switched back on),
		# which is a different payload from the active-only list above.
		Html.input([Attribute.type("hidden"), Attribute.id("config_subjects_data_input"), Attribute.value(model.configSubjectsData), Attribute.on_input(|s| GotConfigSubjectsData(s))]),
		Html.input([Attribute.type("hidden"), Attribute.id("class_levels_data_input"), Attribute.value(model.classLevelsData), Attribute.on_input(|s| GotClassLevelsData(s))]),
		Html.input([Attribute.type("hidden"), Attribute.id("curriculum_data_input"), Attribute.value(model.curriculumData), Attribute.on_input(|s| GotCurriculumData(s))]),
		Html.input([Attribute.type("hidden"), Attribute.id("session_terms_data_input"), Attribute.value(model.sessionTermsData), Attribute.on_input(|s| GotSessionTermsData(s))]),
		Html.input([Attribute.type("hidden"), Attribute.id("credentials_data_input"), Attribute.value(model.credentialsData), Attribute.on_input(|s| GotCredentialsData(s))]),

		Html.div([Attribute.class("flex flex-col space-y-4")], [
			Html.div([Attribute.class("flex overflow-x-auto p-1 bg-muted rounded-md w-fit")], [
				config_tab(model.activeConfigTab, Terms, "Academic Terms"),
				config_tab(model.activeConfigTab, ClassLevels, "Class Levels"),
				config_tab(model.activeConfigTab, Curriculum, "Curriculum"),
				config_tab(model.activeConfigTab, SessionTerms, "Session Terms"),
				config_tab(model.activeConfigTab, Subjects, "Subjects"),
				config_tab(model.activeConfigTab, Credentials, "Qualifications"),
			]),
			Html.div([Attribute.class("mt-4")], [
				match model.activeConfigTab {
					Terms => terms_config_view(model),
					ClassLevels => class_levels_config_view(model),
					Curriculum => curriculum_config_view(model),
					SessionTerms => session_terms_config_view(model),
					Subjects => subjects_config_view(model),
					Credentials => credentials_config_view(model),
				}
			])
		])
	])
}

config_tab = |active_tab, this_tab, label| {
    is_active = active_tab == this_tab
    base_classes = "inline-flex items-center justify-center whitespace-nowrap rounded-sm px-3 py-1.5 text-sm font-medium ring-offset-background transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50"

    classes =
        if is_active {
            Str.join_with([base_classes, "bg-background text-foreground shadow-sm"], " ")
        } else {
            Str.join_with([base_classes, "text-muted-foreground hover:bg-muted hover:text-foreground"], " ")
        }

    Html.button([
        Attribute.class(classes),
        Attribute.type("button"),
        # A section switch is a view change of its own: data-nav is what starts the top border
        # progress bar for one (see www/index.html).
        Attribute.data("nav", ""),
        Attribute.on_click(SetConfigTab(this_tab))
    ], [Html.text(label)])
}

# --- Shared pieces of a configuration section ---

config_card = |title, description, content| {
	UI.card({ classes: "" }, [
		UI.card_header({ classes: "" }, [
			UI.card_title({ classes: "" }, [Html.text(title)]),
			Html.p([Attribute.class("text-sm text-muted-foreground")], [Html.text(description)])
		]),
		UI.card_content({ classes: "space-y-6" }, content)
	])
}

config_form_row = |fields, button| {
	Html.div([Attribute.class("grid grid-cols-1 md:grid-cols-3 gap-4 items-end")], List.concat(fields, [button]))
}

config_labeled_input = |label, placeholder, input_type, value, is_disabled, to_msg| {
	Html.div([Attribute.class("space-y-2")], [
		UI.label({ classes: "" }, [Html.text(label)]),
		UI.input({
			type: input_type,
			value: value,
			placeholder: placeholder,
			on_input: Input(to_msg),
			is_disabled: is_disabled,
			classes: "",
		})
	])
}

config_labeled_select = |label, select_id, options, to_msg| {
	Html.div([Attribute.class("space-y-2")], [
		UI.label({ classes: "" }, [Html.text(label)]),
		Html.div([Attribute.class("relative")], [
			Html.select([
				Attribute.class(config_select_classes),
				Attribute.id(select_id),
				Attribute.on_change(to_msg)
			], options),
			Html.span([Attribute.class("pointer-events-none absolute inset-y-0 right-3 flex items-center text-muted-foreground text-xs")], [Html.text("▼")])
		])
	])
}

config_select_classes = "w-full h-10 rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2 disabled:opacity-50 appearance-none"

# A select in an open editor: the cell has no label (the table header names the column), and it
# opens on the row's own choice rather than the browser's first option — the runtime sets a
# select's `value` property, which is what picks the matching option.
config_row_select = |select_id, value, options, to_msg| {
	Html.div([Attribute.class("relative")], [
		Html.select([
			Attribute.class(config_select_classes),
			Attribute.id(select_id),
			Attribute.value(value),
			Attribute.on_change(to_msg)
		], options),
		Html.span([Attribute.class("pointer-events-none absolute inset-y-0 right-3 flex items-center text-muted-foreground text-xs")], [Html.text("▼")])
	])
}

config_submit_button = |model, tab, label| {
	UI.button(
		{ variant: Primary, size: Default, on_click: Click(SubmitConfigCreate(tab)), is_disabled: model.isConfigSubmitting, classes: "w-full" },
		[Html.text(if model.isConfigSubmitting { "Saving..." } else { label })]
	)
}

# The feedback from this tab's last create; SetConfigTab clears it.
config_create_banner = |model| {
	match model.configSubmitResult {
		None => Html.div([], [])
		Success(msg) => Html.div([Attribute.class("rounded-md bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 p-4 flex items-center gap-2")], [
			Html.span([Attribute.class("text-green-600 text-lg")], [Html.text("✓")]),
			Html.p([Attribute.class("text-sm text-green-800 dark:text-green-200 font-medium")], [Html.text(msg)])
		])
		Error(msg) => Html.div([Attribute.class("rounded-md bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 p-4 flex items-center gap-2")], [
			Html.span([Attribute.class("text-red-600 text-lg")], [Html.text("✕")]),
			Html.p([Attribute.class("text-sm text-red-800 dark:text-red-200 font-medium")], [Html.text(msg)])
		])
	}
}

config_table = |headers, rows| {
	UI.card({ classes: "" }, [
		UI.card_content({ classes: "p-0" }, [
			UI.table({ classes: "" }, [
				UI.table_header({ classes: "" }, [
					UI.table_row({ classes: "" }, List.map(headers, |header| UI.table_head({ classes: "" }, [Html.text(header)])))
				]),
				UI.table_body({ classes: "" }, rows)
			])
		])
	])
}

config_status_badge = |is_active| {
	Html.span([
		Attribute.class(
			if is_active {
				"inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium bg-green-50 text-green-700 dark:bg-green-900/30 dark:text-green-400"
			} else {
				"inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium bg-muted text-muted-foreground"
			}
		)
	], [Html.text(if is_active { "Active" } else { "Inactive" })])
}

# --- Editing and activating a row ---

# One input of an open editor. The placeholder differs from the create form's so the two are told
# apart at a glance (and by the browser checks).
config_edit_input = |placeholder, input_type, value, is_disabled, to_msg| {
	UI.input({
		type: input_type,
		value: value,
		placeholder: placeholder,
		on_input: Input(to_msg),
		is_disabled: is_disabled,
		classes: "",
	})
}

# A cell holding one control of an open editor.
config_edit_cell = |input| {
	UI.table_cell({ classes: "min-w-40" }, [input])
}

# The Edit control of a row: it opens that row's own fields in place, so the values being changed
# sit next to the row they belong to. The fetched line is what prefills the draft.
config_edit_button = |model, line| {
	UI.button(
		{ variant: Ghost, size: Sm, on_click: Click(StartConfigEdit(line)), is_disabled: model.isConfigSubmitting, classes: "text-xs" },
		[Html.text("Edit")]
	)
}

# The activate/deactivate control every configuration row has: the flag flips on the spot and the
# row stays in the list, badge and all, so a deactivation can be undone.
config_active_button = |model, tab, id, is_active| {
	UI.button(
		{
			variant: Ghost,
			size: Sm,
			on_click: Click(ToggleConfigActive(tab, id, !is_active)),
			is_disabled: model.isConfigSubmitting,
			classes: "text-xs",
		},
		[Html.text(if is_active { "Deactivate" } else { "Activate" })]
	)
}

config_actions_cell = |buttons| {
	UI.table_cell({ classes: "" }, [Html.div([Attribute.class("flex items-center gap-2")], buttons)])
}

# The Actions cell of a row that can be edited: open it, or flip its flag.
config_row_actions = |model, tab, line, id, is_active| {
	config_actions_cell([
		config_edit_button(model, line),
		config_active_button(model, tab, id, is_active)
	])
}

# The Actions cell of a row with no editable column: a curriculum link is linked or not.
config_toggle_actions = |model, tab, id, is_active| {
	config_actions_cell([config_active_button(model, tab, id, is_active)])
}

# The Actions cell while a row is open: Save writes the draft, Cancel drops it.
config_edit_actions = |model, tab| {
	config_actions_cell([
		UI.button(
			{ variant: Primary, size: Sm, on_click: Click(SubmitConfigUpdate(tab)), is_disabled: model.isConfigSubmitting, classes: "text-xs" },
			[Html.text(if model.isConfigSubmitting { "Saving..." } else { "Save" })]
		),
		UI.button(
			{ variant: Outline, size: Sm, on_click: Click(CancelConfigEdit), is_disabled: model.isConfigSubmitting, classes: "text-xs" },
			[Html.text("Cancel")]
		)
	])
}

# -------------------------------------------------------
# QUALIFICATIONS (the credentials catalog section)
# -------------------------------------------------------

credentials_config_view = |model| {
	config_card("Qualifications", "The catalogue of teacher qualifications (e.g. B.Ed. Mathematics). A qualification an admin deactivates leaves the catalog but is no longer offered; teacher profiles keep their links either way — nothing here is hard-deleted.", [
		config_form_row([
			config_labeled_input("Qualification name", "e.g. B.Ed. Mathematics", "text", model.newCredentialName, model.isConfigSubmitting, |s| UpdateNewCredentialName(s)),
		], config_submit_button(model, Credentials, "Create Qualification")),
		config_create_banner(model),
		config_table(["Qualification", "Status", "Actions"], credentials_rows(model))
	])
}

credentials_rows = |model| {
	match list_state(model.credentialsData) {
		Pending => UI.table_skeleton_rows(["w-48", "w-20", "w-24"])
		Failed(message) => [UI.table_error_state(3, "Could not load the qualifications", message, Click(RetryList("/api/credentials")))]
		Ready(rows) =>
			if List.is_empty(rows) {
				[UI.table_empty_state(3, "graduation-cap", "No qualifications yet", "Create the first one above.")]
			} else {
				List.map(rows, |line| credentials_row(model, line))
			}
	}
}

# One qualification: its name is editable in place (the name is what a teacher's record link
# displays as, so renaming renames it everywhere); the flag flips without deleting.
credentials_row = |model, line| {
	parts = Str.split_on(line, "|")
	id = config_field(parts, 0, "")
	is_active = config_field(parts, 2, "true") == "true"

	if !Str.is_empty(id) and model.editId == id {
		UI.table_row({ classes: "bg-muted/40" }, [
			config_edit_cell(config_edit_input("Qualification name", "text", model.editField1, model.isConfigSubmitting, |s| UpdateEditField1(s))),
			UI.table_cell({ classes: "" }, [config_status_badge(is_active)]),
			config_edit_actions(model, Credentials)
		])
	} else {
		UI.table_row({ classes: "hover:bg-muted/30 transition-colors" }, [
			UI.table_cell({ classes: "font-medium" }, [Html.text(config_field(parts, 1, "Qualification"))]),
			UI.table_cell({ classes: "" }, [config_status_badge(is_active)]),
			config_row_actions(model, Credentials, line, id, is_active)
		])
	}
}

# -------------------------------------------------------
# TEACHER ASSIGN DIALOG and the qualifications picker
# -------------------------------------------------------

# One field of a class-subject pair row by its edge id, found by folding the fetched lines (the
# same keep_if+List.first miscompile warning as config_record_name applies — fold only).
pair_field_for = |pairs_data, edge_id, index| {
	List.fold(Str.split_on(pairs_data, "\n"), "", |resolved, line| {
		parts = Str.split_on(line, "|")
		line_id = config_field(parts, 0, "")
		if line_id == edge_id { config_field(parts, index, "") } else { resolved }
	})
}

# The badge text of a pair: "JSS 1 / Agricultural Science".
pair_badge_text = |pairs_data, edge_id| {
	class_name = pair_field_for(pairs_data, edge_id, 2)
	subject_name = pair_field_for(pairs_data, edge_id, 4)
	if Str.is_empty(class_name) { subject_name } else if Str.is_empty(subject_name) { class_name } else { "${class_name} / ${subject_name}" }
}

# The catalog's display name for a selected credential id, "" while the list has not arrived.
credential_name_for = |credentials_data, id| {
	List.fold(Str.split_on(credentials_data, "\n"), "", |resolved, line| {
		parts = Str.split_on(line, "|")
		if config_field(parts, 0, "") == id { config_field(parts, 1, id) } else { resolved }
	})
}

# ASCII lowercasing for the search filters (Roc has no case conversion; the retired SearchSelect
# matched case-insensitively, and this is the same byte-level pass the backend's role matching
# uses). Everything past ASCII is left alone — a byte of a multi-byte character is never a letter.
ascii_lower = |text| {
	lowered = List.map(Str.to_utf8(text), |byte| if byte >= 65 and byte <= 90 { byte + 32 } else { byte })

	match Str.from_utf8(lowered) {
		Ok(result) => result
		Err(_) => text
	}
}

# The nav bar's active session term, as text ("" while it is loading, failed, or absent).
session_term_label = |model| {
	match list_state(model.sessionTermData) {
		Ready(rows) => match List.first(rows) { Ok(label) => label, Err(_) => "" }
		_ => ""
	}
}

# The teacher form's qualifications field: the selected badges with their removal, then a search
# box whose dropdown offers the catalog's unselected matching rows — the retired app's
# CredentialsSelect, rebuilt in the Roc page.
user_qualifications_field = |model| {
	selected = model.newUserQualifications
	Html.div([Attribute.class("space-y-2")], [
		UI.label({ classes: "" }, [Html.text("Qualifications")]),
		if List.is_empty(selected) {
			Html.p([Attribute.class("text-xs text-muted-foreground")], [Html.text("None selected.")])
		} else {
			Html.div([Attribute.class("flex flex-wrap gap-1.5")], List.map(selected, |id| {
				Html.span([Attribute.class("inline-flex items-center gap-1 rounded-full bg-muted px-2 py-0.5 text-xs font-medium")], [
					Html.text(credential_name_for(model.credentialsData, id)),
					Html.span([Attribute.class("cursor-pointer hover:text-destructive"), Attribute.on_click(RemoveQualification(id))], [Html.text("✕")])
				])
			}))
		},
		UI.input({
			type: "text",
			value: model.qualSearch,
			placeholder: "Search qualifications...",
			on_input: Input(|s| UpdateQualSearch(s)),
			is_disabled: model.isSubmitting,
			classes: "",
		}),
		if Str.is_empty(model.qualSearch) {
			Html.div([], [])
		} else {
			Html.div([Attribute.class("max-h-48 overflow-y-auto rounded-md border border-border bg-card shadow-lg")],
				List.map(List.keep_if(Str.split_on(model.credentialsData, "\n"), |line| {
					parts = Str.split_on(line, "|")
					config_field(parts, 2, "true") == "true"
						and !Str.is_empty(config_field(parts, 0, ""))
						and !List.contains(selected, config_field(parts, 0, ""))
						and Str.contains(ascii_lower(config_field(parts, 1, "")), ascii_lower(model.qualSearch))
				}), |line| {
					parts = Str.split_on(line, "|")
					id = config_field(parts, 0, "")
					Html.div([
						Attribute.class("px-3 py-2 text-sm hover:bg-muted cursor-pointer"),
						Attribute.on_click(AddQualification(id))
					], [Html.text(config_field(parts, 1, "Qualification"))])
				})
			)
		}
	])
}

# The modal for assigning class-subject pairs to one teacher: the current pairs as removable
# badges, the catalog's searchable dropdown (offering only pairs not already picked), and a Save
# that replaces the whole set — the retired TeacherUserTable dialog, rebuilt.
assign_form = |model| {
	if model.assignDialogOpen {
		Html.div([Attribute.class("fixed inset-0 z-50 overflow-y-auto bg-black/50 p-4 md:p-8")], [
			Html.div([Attribute.class("w-full max-w-lg mx-auto my-4 md:my-10 rounded-xl border border-border bg-card text-card-foreground shadow-xl")], [
				UI.card_header({ classes: "" }, [
					Html.div([Attribute.class("flex items-start justify-between gap-4")], [
						Html.div([], [
							UI.card_title({ classes: "" }, [Html.text("Assign Classes")]),
							Html.p([Attribute.class("text-sm text-muted-foreground")], [Html.text("Choose the class-subject pairs this teacher teaches. Saving replaces the current set.")])
						]),
						UI.button({ variant: Ghost, size: Sm, on_click: Click(CloseTeacherAssign), is_disabled: model.isSubmitting, classes: "text-xs" }, [Html.text("Cancel")])
					])
				]),
				UI.card_content({ classes: "space-y-4" }, [
					# The assignment is scoped to the active session term, so the dialog says which term
					# the save will write into (the backend refuses the save when there is none).
					if Str.is_empty(session_term_label(model)) {
						Html.p([Attribute.class("text-sm text-amber-600")], [Html.text("No active session term. Set one in Configuration → Session Terms.")])
					} else {
						Html.p([Attribute.class("text-sm text-muted-foreground")], [
							Html.text("Active session: "),
							Html.span([Attribute.class("font-medium")], [Html.text(session_term_label(model))])
						])
					},
					if List.is_empty(model.assignSelectedEdges) {
						Html.p([Attribute.class("text-xs text-muted-foreground")], [Html.text("No pairs assigned yet.")])
					} else {
						Html.div([Attribute.class("flex flex-wrap gap-1.5")], List.map(model.assignSelectedEdges, |edge| {
							Html.span([Attribute.class("inline-flex items-center gap-1 rounded-full bg-muted px-2 py-0.5 text-xs font-medium")], [
								Html.text(pair_badge_text(model.subjectPairsData, edge)),
								Html.span([Attribute.class("cursor-pointer hover:text-destructive"), Attribute.on_click(RemoveAssignPair(edge))], [Html.text("✕")])
							])
						}))
					},
					UI.input({
						type: "text",
						value: model.assignSearch,
						placeholder: "Search class subjects...",
						on_input: Input(|s| UpdateAssignSearch(s)),
						is_disabled: model.isSubmitting,
						classes: "",
					}),
					if Str.is_empty(model.assignSearch) {
						Html.div([], [])
					} else {
						assign_pair_options(model)
					},
					assign_save_banner(model),
				]),
				Html.div([Attribute.class("px-6 pb-6 pt-0")], [
					Html.div([Attribute.class("flex justify-end border-t pt-4 gap-2")], [
						UI.button({ variant: Outline, size: Default, on_click: Click(CloseTeacherAssign), is_disabled: model.isSubmitting, classes: "" }, [Html.text("Cancel")]),
						UI.button({ variant: Primary, size: Default, on_click: Click(SubmitTeacherAssign), is_disabled: model.isSubmitting, classes: "" }, [Html.text(if model.isSubmitting { "Saving..." } else { "Save Assignments" })])
					])
				])
			])
		])
	} else {
		Html.div([], [])
	}
}

# The dropdown's matching rows while the admin types, hiding the pairs already picked — the
# addedSet filter of the retired SearchSelect.
assign_pair_options = |model| {
	selected = model.assignSelectedEdges
	query = model.assignSearch
	Html.div([Attribute.class("max-h-48 overflow-y-auto rounded-md border border-border bg-card shadow-lg")],
		List.map(List.keep_if(Str.split_on(model.subjectPairsData, "\n"), |line| {
			parts = Str.split_on(line, "|")
			edge = config_field(parts, 0, "")
			haystack = Str.join_with([config_field(parts, 2, ""), config_field(parts, 4, "")], " / ")
			!Str.is_empty(edge) and !List.contains(selected, edge) and Str.contains(ascii_lower(haystack), ascii_lower(query))
		}), |line| {
			parts = Str.split_on(line, "|")
			edge = config_field(parts, 0, "")
			haystack = Str.join_with([config_field(parts, 2, ""), config_field(parts, 4, "")], " / ")
			Html.div([
				Attribute.class("px-3 py-2 text-sm hover:bg-muted cursor-pointer"),
				Attribute.on_click(AddAssignPair(edge))
			], [Html.text(haystack)])
		})
	)
}

assign_save_banner = |model| {
	match model.assignSaveResult {
		None => Html.div([], [])
		Success(msg) => Html.div([Attribute.class("rounded-md bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 p-4 flex items-center gap-2")], [
			Html.span([Attribute.class("text-green-600 text-lg")], [Html.text("✓")]),
			Html.p([Attribute.class("text-sm text-green-800 dark:text-green-200 font-medium")], [Html.text(msg)])
		])
		Error(msg) => Html.div([Attribute.class("rounded-md bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 p-4 flex items-center gap-2")], [
			Html.span([Attribute.class("text-red-600 text-lg")], [Html.text("✕")]),
			Html.p([Attribute.class("text-sm text-red-800 dark:text-red-200 font-medium")], [Html.text(msg)])
		])
	}
}

# -------------------------------------------------------
# ADMIN LMS (the teachers' pages for every class level)
# -------------------------------------------------------

# The class-level picker: every active class, as cards. Choosing one shows its subjects.
admin_class_picker = |model| {
	Html.div([Attribute.class("space-y-6")], [
		Html.div([], [
			Html.h1([Attribute.class("text-3xl font-bold tracking-tight")], [Html.text("LMS")]),
			Html.p([Attribute.class("text-muted-foreground mt-1")], [Html.text("Browse any class level's curriculum, exactly as a teacher sees it — without gating.")])
		]),
		Html.input([Attribute.type("hidden"), Attribute.id("admin_lms_classes_data_input"), Attribute.value(model.adminLmsClassesData), Attribute.on_input(|s| GotAdminLmsClassesData(s))]),
		match list_state(model.adminLmsClassesData) {
			Pending => Html.div([Attribute.class("grid grid-cols-1 md:grid-cols-3 gap-4")], [admin_lms_skeleton(""), admin_lms_skeleton(""), admin_lms_skeleton("")])
			Failed(message) => UI.list_error_state("Could not load the class levels", message, Click(RetryList("/api/class_levels?admin_lms=1")))
			Ready(rows) =>
				if List.is_empty(rows) {
					UI.list_empty_state("presentation", "No class levels yet", "Class levels appear here once an administrator adds them.")
				} else {
					Html.div([Attribute.class("grid grid-cols-1 md:grid-cols-3 gap-4")],
						List.map(rows, |line| {
							parts = Str.split_on(line, "|")
							id = config_field(parts, 0, "")
							name = config_field(parts, 1, "Class")
							Html.div([
								Attribute.class("group rounded-lg border bg-card p-6 space-y-4 hover:shadow-md hover:border-primary/30 transition-all cursor-pointer"),
								Attribute.data("nav", ""),
								Attribute.on_click(SelectAdminClass(id, name))
							], [
								Html.div([Attribute.class("w-12 h-12 rounded-xl bg-primary/10 flex items-center justify-center text-2xl")], [Html.text("🏫")]),
								Html.h3([Attribute.class("font-semibold text-foreground group-hover:text-primary transition-colors")], [Html.text(name)]),
								Html.p([Attribute.class("text-xs text-muted-foreground")], [Html.text("Click to view its subjects")])
							])
						})
					)
				}
		}
	])
}

# The subjects of the picked class: the pairs list filtered to that class, one card per subject.
admin_subjects_view = |model| {
	Html.div([Attribute.class("space-y-6")], [
		Html.div([Attribute.class("flex items-center gap-2 text-sm text-muted-foreground")], [
			Html.span([Attribute.class("cursor-pointer hover:text-foreground"), Attribute.on_click(BackAdminSubjects)], [Html.text("← All classes")]),
			Html.span([Attribute.class("text-border")], [Html.text("›")]),
			Html.span([Attribute.class("text-foreground font-medium")], [Html.text(model.adminLmsClassName)])
		]),
		Html.div([], [
			Html.h1([Attribute.class("text-3xl font-bold tracking-tight")], [Html.text(model.adminLmsClassName)]),
			Html.p([Attribute.class("text-muted-foreground mt-1")], [Html.text("Choose a subject to see its terms and lessons.")])
		]),
		match list_state(model.subjectPairsData) {
			Pending => Html.div([Attribute.class("grid grid-cols-1 md:grid-cols-2 gap-4")], [admin_lms_skeleton(""), admin_lms_skeleton("")])
			Failed(message) => UI.list_error_state("Could not load the subjects", message, Click(RetryList("/api/class-subjects")))
			Ready(rows) =>
				if List.is_empty(rows) {
					UI.list_empty_state("book-open", "No subjects for this class yet", "Subjects appear here once a class-subject pair is added in the Configuration Hub.")
				} else {
					Html.div([Attribute.class("grid grid-cols-1 md:grid-cols-2 gap-4")],
						List.map(List.keep_if(rows, |line| {
							parts = Str.split_on(line, "|")
							config_field(parts, 1, "") == model.adminLmsClassId
						}), |line| {
							parts = Str.split_on(line, "|")
							subject_id = config_field(parts, 3, "")
							subject_name = config_field(parts, 4, "Subject")
							Html.div([
								Attribute.class("group rounded-lg border bg-card p-6 space-y-4 hover:shadow-md hover:border-primary/30 transition-all cursor-pointer"),
								Attribute.data("nav", ""),
								Attribute.on_click(SelectAdminSubject(subject_id, subject_name))
							], [
								Html.div([Attribute.class("w-12 h-12 rounded-xl bg-primary/10 flex items-center justify-center text-2xl")], [Html.text("📖")]),
								Html.h3([Attribute.class("font-semibold text-foreground group-hover:text-primary transition-colors")], [Html.text(subject_name)]),
								Html.p([Attribute.class("text-xs text-muted-foreground")], [Html.text("Click to view terms")])
							])
						})
					)
				}
		}
	])
}

# The terms step: school-wide terms, chosen after a subject.
admin_terms_view = |model| {
	Html.div([Attribute.class("space-y-6")], [
		Html.div([Attribute.class("flex items-center gap-2 text-sm text-muted-foreground")], [
			Html.span([Attribute.class("cursor-pointer hover:text-foreground"), Attribute.on_click(BackAdminSubjects)], [Html.text("← All classes")]),
			Html.span([Attribute.class("text-border")], [Html.text("›")]),
			Html.span([Attribute.class("cursor-pointer hover:text-foreground"), Attribute.on_click(BackAdminTerms)], [Html.text(model.adminLmsClassName)]),
			Html.span([Attribute.class("text-border")], [Html.text("›")]),
			Html.span([Attribute.class("text-foreground font-medium")], [Html.text(model.adminLmsSubjectName)])
		]),
		Html.div([], [
			Html.h1([Attribute.class("text-3xl font-bold tracking-tight")], [Html.text(model.adminLmsSubjectName)]),
			Html.p([Attribute.class("text-muted-foreground mt-1")], [Html.text("Choose a term to view its lessons.")])
		]),
		Html.input([Attribute.type("hidden"), Attribute.id("admin_lms_terms_data_input"), Attribute.value(model.adminLmsTermsData), Attribute.on_input(|s| GotAdminLmsTermsData(s))]),
		match list_state(model.adminLmsTermsData) {
			Pending => Html.div([Attribute.class("grid grid-cols-1 md:grid-cols-3 gap-4")], [admin_lms_skeleton(""), admin_lms_skeleton(""), admin_lms_skeleton("")])
			Failed(message) => UI.list_error_state("Could not load the terms", message, Click(RetryList("/api/student/terms?admin_lms=1")))
			Ready(rows) =>
				if List.is_empty(rows) {
					UI.list_empty_state("calendar", "No terms yet", "The school's terms appear here once they are published.")
				} else {
					Html.div([Attribute.class("grid grid-cols-1 md:grid-cols-3 gap-4")],
						List.map(rows, |line| {
							parts = Str.split_on(line, "|")
							id = config_field(parts, 0, "")
							name = config_field(parts, 1, "Term")
							Html.div([
								Attribute.class("group rounded-lg border bg-card p-6 space-y-4 hover:shadow-md hover:border-primary/30 transition-all cursor-pointer"),
								Attribute.data("nav", ""),
								Attribute.on_click(SelectAdminTerm(id, name))
							], [
								Html.div([Attribute.class("w-12 h-12 rounded-xl bg-primary/10 flex items-center justify-center text-2xl")], [Html.text("📅")]),
								Html.h3([Attribute.class("font-semibold text-foreground group-hover:text-primary transition-colors")], [Html.text(name)]),
								Html.p([Attribute.class("text-xs text-muted-foreground")], [Html.text("Click to view lessons")])
							])
						})
					)
				}
		}
	])
}

# The lessons step: this class's subject's lessons for the picked term.
admin_lessons_view = |model| {
	Html.div([Attribute.class("space-y-6")], [
		Html.div([Attribute.class("flex items-center gap-2 text-sm text-muted-foreground flex-wrap")], [
			Html.span([Attribute.class("cursor-pointer hover:text-foreground"), Attribute.on_click(BackAdminSubjects)], [Html.text("← All classes")]),
			Html.span([Attribute.class("text-border")], [Html.text("›")]),
			Html.span([Attribute.class("cursor-pointer hover:text-foreground"), Attribute.on_click(BackAdminTerms)], [Html.text(model.adminLmsClassName)]),
			Html.span([Attribute.class("text-border")], [Html.text("›")]),
			Html.span([Attribute.class("cursor-pointer hover:text-foreground"), Attribute.on_click(BackAdminLessons)], [Html.text(model.adminLmsSubjectName)]),
			Html.span([Attribute.class("text-border")], [Html.text("›")]),
			Html.span([Attribute.class("text-foreground font-medium")], [Html.text(model.adminLmsTermName)])
		]),
		Html.div([], [
			Html.h1([Attribute.class("text-3xl font-bold tracking-tight")], [Html.text(model.adminLmsTermName)]),
			Html.p([Attribute.class("text-muted-foreground mt-1")], [Html.text(model.adminLmsSubjectName)])
		]),
		Html.input([Attribute.type("hidden"), Attribute.id("admin_lms_lessons_data_input"), Attribute.value(model.adminLmsLessonsData), Attribute.on_input(|s| GotAdminLmsLessonsData(s))]),
		match list_state(model.adminLmsLessonsData) {
			Pending => Html.div([Attribute.class("space-y-3")], [admin_lms_skeleton(""), admin_lms_skeleton("")])
			Failed(message) => UI.list_error_state("Could not load the lessons", message, Click(RetryList("/api/teacher/lessons?class_id=${model.adminLmsClassId}&subject_id=${model.adminLmsSubjectId}&term_id=${model.adminLmsTermId}&admin_lms=1")))
			Ready(rows) =>
				if List.is_empty(rows) {
					UI.list_empty_state("book-open", "No lessons yet", "Lessons for this term appear here once they are published.")
				} else {
					Html.div([Attribute.class("space-y-3")],
						List.map(rows, |line| {
							parts = Str.split_on(line, "|")
							id = config_field(parts, 0, "")
							title = config_field(parts, 1, "Lesson")
							week = config_field(parts, 2, "")
							Html.div([
								Attribute.class("group rounded-lg border bg-card p-4 flex items-center gap-4 hover:shadow-sm hover:border-primary/30 transition-all cursor-pointer"),
								Attribute.data("nav", ""),
								Attribute.on_click(OpenAdminLesson(id))
							], [
								Html.div([Attribute.class("flex-1 min-w-0")], [
									Html.h3([Attribute.class("font-medium text-foreground group-hover:text-primary transition-colors truncate")], [Html.text(title)]),
									Html.p([Attribute.class("text-xs text-muted-foreground")], [Html.text(if Str.is_empty(week) { "Lesson" } else { "Week ${week}" })])
								]),
								Html.span([Attribute.class("text-muted-foreground text-sm group-hover:text-primary transition-colors")], [Html.text("→")])
							])
						})
					)
				}
		}
	])
}

# The lesson content step: the same panel the students see, read-only (no tabs, no assessment
# actions — the page's renderLesson fills lesson-header and lesson-panel from the fetched row).
admin_lesson_view = |model| {
	Html.div([Attribute.class("relative")], [
		Html.div([Attribute.class("flex min-h-screen")], [
			Html.div([Attribute.class("flex-1 max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8")], [
				Html.input([
					Attribute.type("hidden"),
					Attribute.id("lesson_content_data_input"),
					Attribute.value(model.currentLessonContent),
					Attribute.on_input(|s| GotLessonContent(s))
				]),
				Html.div([Attribute.class("flex items-center gap-2 text-sm text-muted-foreground flex-wrap")], [
					Html.span([Attribute.class("cursor-pointer hover:text-foreground"), Attribute.on_click(BackAdminLessons)], [Html.text("← Back to lessons")]),
					Html.span([Attribute.class("text-border")], [Html.text("›")]),
					Html.span([Attribute.class("text-foreground font-medium")], [Html.text("Lesson")])
				]),
				Html.div([Attribute.id("lesson-header"), Attribute.class("space-y-3")], [
					Html.div([Attribute.class("flex items-start justify-between gap-6")], [
						Html.div([Attribute.class("space-y-2")], [
							Html.div([Attribute.id("lesson-title"), Attribute.class("text-3xl font-bold text-primary leading-tight")], [Html.text("Lesson")]),
							Html.div([Attribute.id("lesson-meta"), Attribute.class("text-sm text-muted-foreground font-medium tracking-wide uppercase")], [Html.text("")])
						]),
						Html.div([Attribute.id("lesson-week-badge"), Attribute.class("hidden")], [])
					])
				]),
				Html.div([
					Attribute.id("lesson-panel"),
					Attribute.class("space-y-8 pb-16"),
				], [
					admin_lesson_panel(model)
				])
			])
		]),

		# The same right-side section navigator the student and teacher lesson views have: the
		# panel sits in flow inside the hover group, so moving the pointer into the box keeps it
		# open (the renderLesson JS fills the dots and labels).
		Html.div([
			Attribute.id("section-nav"),
			Attribute.class("hidden md:flex fixed right-6 top-1/2 -translate-y-1/2 z-50 group items-center")
		], [
			Html.div([
				Attribute.id("section-nav-panel"),
				Attribute.class("mr-3 opacity-0 group-hover:opacity-100 pointer-events-none group-hover:pointer-events-auto transition-all duration-200 translate-x-2 group-hover:translate-x-0")
			], [
				Html.div([Attribute.class("bg-card border border-border rounded-lg shadow-lg p-3 space-y-1 w-52")], [
					Html.div([Attribute.id("section-nav-labels")], [])
				])
			]),
			Html.div([Attribute.id("section-nav-dots"), Attribute.class("flex flex-col items-center gap-2.5 py-3")], [])
		]),

		# Mobile TOC button
		Html.div([Attribute.id("mobile-toc-fab"), Attribute.class("fixed bottom-6 right-6 z-50 md:hidden")], [
			Html.button([
				Attribute.id("mobile-toc-btn"),
				Attribute.class("h-12 w-12 rounded-full bg-primary text-primary-foreground shadow-lg flex items-center justify-center hover:bg-primary/90 transition"),
				Attribute.type("button")
			], [Html.text("≡")]),
			Html.div([Attribute.id("mobile-toc-menu"), Attribute.class("hidden absolute bottom-16 right-0 bg-card border border-border rounded-lg shadow-xl p-3 space-y-1 min-w-44")], [])
		])
])
}

# The lesson panel before the page's JavaScript has rendered the lesson into it: skeleton while
# the content is on its way, and the backend's message with a retry when it failed.
admin_lesson_panel = |model| {
	match list_state(model.currentLessonContent) {
		Pending => Html.div([Attribute.class("space-y-8")], [
			Html.div([Attribute.class("space-y-3")], [UI.skeleton_bar("h-5 w-40"), UI.skeleton_bar("h-4 w-full"), UI.skeleton_bar("h-4 w-5/6"), UI.skeleton_bar("h-4 w-2/3")]),
			Html.div([Attribute.class("space-y-3")], [UI.skeleton_bar("h-5 w-48"), UI.skeleton_bar("h-4 w-3/4"), UI.skeleton_bar("h-4 w-1/2")])
		])
		Failed(message) => UI.list_error_state("Could not load the lesson", message, Click(RetryList("/api/student/lesson?lesson_id=${model.selectedLessonId}")))
		Ready(_) => Html.div([Attribute.class("text-sm text-muted-foreground")], [Html.text("Rendering content...")])
	}
}

admin_lms_skeleton = |_| {
	Html.div([Attribute.class("rounded-lg border bg-card p-6 space-y-3 animate-pulse")], [
		Html.div([Attribute.class("h-12 w-12 rounded-xl bg-muted")], []),
		Html.div([Attribute.class("h-4 w-32 rounded bg-muted")], []),
		Html.div([Attribute.class("h-8 w-24 rounded bg-muted")], [])
	])
}

# The admin LMS drill-down: class -> subjects -> terms -> lessons -> lesson content. One step is on
# screen at a time; the fetch URLs behind each step carry the picked ids, and the class filter is
# what makes the lesson list exactly one class level.
admin_lms_view = |model| {
	Html.div([Attribute.class("p-6 md:p-8 space-y-6")], [
		# The pair catalog the subjects step reads; hidden, and only present on this page (the JS
		# dispatches /api/class-subjects into it).
		Html.input([Attribute.type("hidden"), Attribute.id("subject_pairs_data_input"), Attribute.value(model.subjectPairsData), Attribute.on_input(|s| GotSubjectPairsData(s))]),
		if !Str.is_empty(model.selectedLessonId) {
			admin_lesson_view(model)
		} else if !Str.is_empty(model.adminLmsTermId) {
			admin_lessons_view(model)
		} else if !Str.is_empty(model.adminLmsSubjectId) {
			admin_terms_view(model)
		} else if !Str.is_empty(model.adminLmsClassId) {
			admin_subjects_view(model)
		} else {
			admin_class_picker(model)
		}
	])
}

# The nth "|"-separated field of a fetched row, with a fallback for a short or empty field.
config_field = |parts, index, fallback| {
	match List.get(parts, index) {
		Ok(value) => if Str.is_empty(value) { fallback } else { value }
		Err(_) => fallback
	}
}

# Display name for a record link (`terms:noel_term`) looked up in a fetched "id|name|..." list.
# Falls back to the bare id while that list has not arrived (or the row is gone).
#
# Note for the next editor: the lookup is a `List.fold` over the lines on purpose. The same thing
# written as `List.keep_if(...)` plus `match List.first(...)` makes this Roc nightly miscompile the
# app — the wasm traps with "function signature mismatch" at start and the page stays blank.
config_record_name = |list_data, record_id| {
	bare = match List.last(Str.split_on(record_id, ":")) { Ok(id) => id, Err(_) => record_id }
	List.fold(Str.split_on(list_data, "\n"), bare, |resolved, line| {
		parts = Str.split_on(line, "|")
		line_id = config_field(parts, 0, "")
		if line_id == record_id or line_id == bare {
			config_field(parts, 1, bare)
		} else {
			resolved
		}
	})
}

# Options for a record picker: one per line of a fetched "id|name|..." list.
config_record_options = |list_data, placeholder| {
	List.map(Str.split_on(list_data, "\n"), |line| {
		parts = Str.split_on(line, "|")
		Html.option([Attribute.value(config_field(parts, 0, ""))], [Html.text(config_field(parts, 1, placeholder))])
	})
}

# --- Academic Terms ---

terms_config_view = |model| {
	config_card("Academic Terms", "Terms run in order within the school year; every term is listed here, active or not. Editing rewrites the row, deactivating keeps it.", [
		config_form_row([
			config_labeled_input("Term name", "e.g. Summer Term", "text", model.newTermName, model.isConfigSubmitting, |s| UpdateNewTermName(s)),
			config_labeled_input("Sort order", "e.g. 3", "number", model.newTermSortOrder, model.isConfigSubmitting, |s| UpdateNewTermSortOrder(s)),
		], config_submit_button(model, Terms, "Create Term")),
		config_create_banner(model),
		config_table(["Term", "Sort order", "Status", "Actions"], terms_rows(model))
	])
}

# The terms table's rows: the same three states as every other list fed by the page's fetch_data
# port — skeleton placeholders while the list has not been answered, the backend's own message with
# a retry when it failed, a real empty state when it loaded no rows.
terms_rows = |model| {
	match list_state(model.termsData) {
		Pending => UI.table_skeleton_rows(["w-40", "w-16", "w-20", "w-24"])
		Failed(message) => [UI.table_error_state(4, "Could not load the terms", message, Click(RetryList("/api/terms")))]
		Ready(rows) =>
			if List.is_empty(rows) {
				[UI.table_empty_state(4, "folder", "No terms yet", "Create the first one above.")]
			} else {
				List.map(rows, |line| terms_row(model, line))
			}
	}
}

# One term: its name and sort order are editable, so the row turns into a two-input form while the
# hub has it open for editing. The status badge and the activate/deactivate control sit beside it in
# both states — a deactivated term stays visible so it can be switched back on.
terms_row = |model, line| {
	parts = Str.split_on(line, "|")
	id = config_field(parts, 0, "")
	is_active = config_field(parts, 3, "true") == "true"

	if !Str.is_empty(id) and model.editId == id {
		UI.table_row({ classes: "bg-muted/40" }, [
			config_edit_cell(config_edit_input("Term name", "text", model.editField1, model.isConfigSubmitting, |s| UpdateEditField1(s))),
			config_edit_cell(config_edit_input("Sort order", "number", model.editField2, model.isConfigSubmitting, |s| UpdateEditField2(s))),
			UI.table_cell({ classes: "" }, [config_status_badge(is_active)]),
			config_edit_actions(model, Terms)
		])
	} else {
		UI.table_row({ classes: "hover:bg-muted/30 transition-colors" }, [
			UI.table_cell({ classes: "font-medium" }, [Html.text(config_field(parts, 1, "Term"))]),
			UI.table_cell({ classes: "text-muted-foreground" }, [Html.text(config_field(parts, 2, "—"))]),
			UI.table_cell({ classes: "" }, [config_status_badge(is_active)]),
			config_row_actions(model, Terms, line, id, is_active)
		])
	}
}

# --- Class Levels ---

class_levels_config_view = |model| {
	config_card("Class Levels", "The year groups of the school. The code is the short key records use (e.g. jss_1); a deactivated level stays listed so it can be switched back on.", [
		config_form_row([
			config_labeled_input("Class level name", "e.g. JSS 4", "text", model.newClassLevelName, model.isConfigSubmitting, |s| UpdateNewClassLevelName(s)),
			config_labeled_input("Code", "e.g. jss_4", "text", model.newClassLevelCode, model.isConfigSubmitting, |s| UpdateNewClassLevelCode(s)),
		], config_submit_button(model, ClassLevels, "Create Class Level")),
		config_create_banner(model),
		config_table(["Class level", "Code", "Age range", "Status", "Actions"], class_levels_rows(model))
	])
}

class_levels_rows = |model| {
	match list_state(model.classLevelsData) {
		Pending => UI.table_skeleton_rows(["w-40", "w-16", "w-24", "w-20", "w-24"])
		Failed(message) => [UI.table_error_state(5, "Could not load the class levels", message, Click(RetryList("/api/class_levels?all=true")))]
		Ready(rows) =>
			if List.is_empty(rows) {
				[UI.table_empty_state(5, "folder", "No class levels yet", "Create the first one above.")]
			} else {
				List.map(rows, |line| class_levels_row(model, line))
			}
	}
}

class_levels_row = |model, line| {
	parts = Str.split_on(line, "|")
	id = config_field(parts, 0, "")
	is_active = config_field(parts, 4, "true") == "true"

	if !Str.is_empty(id) and model.editId == id {
		UI.table_row({ classes: "bg-muted/40" }, [
			config_edit_cell(config_edit_input("Class level name", "text", model.editField1, model.isConfigSubmitting, |s| UpdateEditField1(s))),
			config_edit_cell(config_edit_input("Code", "text", model.editField2, model.isConfigSubmitting, |s| UpdateEditField2(s))),
			config_edit_cell(config_edit_input("Age range", "text", model.editField3, model.isConfigSubmitting, |s| UpdateEditField3(s))),
			UI.table_cell({ classes: "" }, [config_status_badge(is_active)]),
			config_edit_actions(model, ClassLevels)
		])
	} else {
		UI.table_row({ classes: "hover:bg-muted/30 transition-colors" }, [
			UI.table_cell({ classes: "font-medium" }, [Html.text(config_field(parts, 1, "Class level"))]),
			UI.table_cell({ classes: "text-muted-foreground font-mono text-xs" }, [Html.text(config_field(parts, 2, "—"))]),
			UI.table_cell({ classes: "text-muted-foreground" }, [Html.text(config_field(parts, 3, "—"))]),
			UI.table_cell({ classes: "" }, [config_status_badge(is_active)]),
			config_row_actions(model, ClassLevels, line, id, is_active)
		])
	}
}

# --- Curriculum ---

curriculum_config_view = |model| {
	config_card("Curriculum", "Link subjects to class levels to define what each level studies. A link switched off stays listed (and keeps its lessons) so it can be restored.", [
		config_form_row([
			config_labeled_select("Class level", "new-curriculum-class-level-select", config_record_options(model.classLevelsData, "No class levels yet"), |s| UpdateNewCurriculumClassLevel(s)),
			config_labeled_select("Subject", "new-curriculum-subject-select", config_record_options(model.subjectsData, "No subjects yet"), |s| UpdateNewCurriculumSubject(s)),
		], config_submit_button(model, Curriculum, "Link Subject")),
		config_create_banner(model),
		config_table(["Class level", "Subject", "Status", "Actions"], curriculum_rows(model))
	])
}

curriculum_rows = |model| {
	match list_state(model.curriculumData) {
		Pending => UI.table_skeleton_rows(["w-36", "w-44", "w-20", "w-24"])
		Failed(message) => [UI.table_error_state(4, "Could not load the curriculum", message, Click(RetryList("/api/curriculum?all=true")))]
		Ready(rows) =>
			if List.is_empty(rows) {
				[UI.table_empty_state(4, "folder", "No subject is linked to a class level yet", "Link one above to define what a class level studies.")]
			} else {
				List.map(rows, |line| curriculum_row(model, line))
			}
	}
}

# A link has no editable column — the pair is the row — so its only control is the toggle.
curriculum_row = |model, line| {
	parts = Str.split_on(line, "|")
	id = config_field(parts, 0, "")
	is_active = config_field(parts, 3, "true") == "true"

	UI.table_row({ classes: "hover:bg-muted/30 transition-colors" }, [
		UI.table_cell({ classes: "font-medium" }, [Html.text(config_record_name(model.classLevelsData, config_field(parts, 1, "")))]),
		UI.table_cell({ classes: "" }, [Html.text(config_record_name(model.subjectsData, config_field(parts, 2, "")))]),
		UI.table_cell({ classes: "" }, [config_status_badge(is_active)]),
		config_toggle_actions(model, Curriculum, id, is_active)
	])
}

# --- Session Terms ---

session_terms_config_view = |model| {
	config_card("Session Terms", "Pairs a school session (e.g. 2026/2027) with one of the terms above. New session terms start inactive; activating one is what makes it usable.", [
		config_form_row([
			config_labeled_input("Session name", "e.g. 2026/2027", "text", model.newSessionTermName, model.isConfigSubmitting, |s| UpdateNewSessionTermName(s)),
			config_labeled_select("Term", "new-session-term-select", config_record_options(model.termsData, "No terms yet"), |s| UpdateNewSessionTermTerm(s)),
		], config_submit_button(model, SessionTerms, "Create Session Term")),
		config_create_banner(model),
		config_table(["Session", "Term", "Status", "Actions"], session_terms_rows(model))
	])
}

session_terms_rows = |model| {
	match list_state(model.sessionTermsData) {
		Pending => UI.table_skeleton_rows(["w-32", "w-36", "w-20", "w-24"])
		Failed(message) => [UI.table_error_state(4, "Could not load the session terms", message, Click(RetryList("/api/session_terms")))]
		Ready(rows) =>
			if List.is_empty(rows) {
				[UI.table_empty_state(4, "folder", "No session terms yet", "Create the first one above.")]
			} else {
				List.map(rows, |line| session_terms_row(model, line))
			}
	}
}

# A session term is a name plus the term it belongs to, so the editor offers both; the select opens
# on the row's own term (the draft was prefilled from the row's line).
session_terms_row = |model, line| {
	parts = Str.split_on(line, "|")
	id = config_field(parts, 0, "")
	is_active = config_field(parts, 3, "false") == "true"

	if !Str.is_empty(id) and model.editId == id {
		UI.table_row({ classes: "bg-muted/40" }, [
			config_edit_cell(config_edit_input("Session name", "text", model.editField1, model.isConfigSubmitting, |s| UpdateEditField1(s))),
			config_edit_cell(config_row_select("edit-session-term-select", model.editField2, config_record_options(model.termsData, "No terms yet"), |s| UpdateEditField2(s))),
			UI.table_cell({ classes: "" }, [config_status_badge(is_active)]),
			config_edit_actions(model, SessionTerms)
		])
	} else {
		UI.table_row({ classes: "hover:bg-muted/30 transition-colors" }, [
			UI.table_cell({ classes: "font-medium" }, [Html.text(config_field(parts, 1, "Session"))]),
			UI.table_cell({ classes: "text-muted-foreground" }, [Html.text(config_record_name(model.termsData, config_field(parts, 2, "")))]),
			UI.table_cell({ classes: "" }, [config_status_badge(is_active)]),
			config_row_actions(model, SessionTerms, line, id, is_active)
		])
	}
}

# --- Subjects ---

subjects_config_view = |model| {
	config_card("Subjects", "The subjects the school offers, active or not. Deactivating one takes it off the students' cards without deleting it, and it stays listed here.", [
		config_form_row([
			config_labeled_input("Subject name", "e.g. Mathematics", "text", model.newSubjectName, model.isConfigSubmitting, |s| UpdateNewSubjectName(s)),
			config_labeled_input("Code", "e.g. MTH", "text", model.newSubjectCode, model.isConfigSubmitting, |s| UpdateNewSubjectCode(s)),
		], config_submit_button(model, Subjects, "Create Subject")),
		config_create_banner(model),
		config_table(["Subject", "Code", "Status", "Actions"], subjects_rows(model))
	])
}

subjects_rows = |model| {
	match list_state(model.configSubjectsData) {
		Pending => UI.table_skeleton_rows(["w-40", "w-16", "w-20", "w-24"])
		Failed(message) => [UI.table_error_state(4, "Could not load the subjects", message, Click(RetryList("/api/subjects?all=true")))]
		Ready(rows) =>
			if List.is_empty(rows) {
				[UI.table_empty_state(4, "folder", "No subjects yet", "Create the first one above.")]
			} else {
				List.map(rows, |line| subjects_row(model, line))
			}
	}
}

subjects_row = |model, line| {
	parts = Str.split_on(line, "|")
	id = config_field(parts, 0, "")
	is_active = config_field(parts, 3, "true") == "true"

	if !Str.is_empty(id) and model.editId == id {
		UI.table_row({ classes: "bg-muted/40" }, [
			config_edit_cell(config_edit_input("Subject name", "text", model.editField1, model.isConfigSubmitting, |s| UpdateEditField1(s))),
			config_edit_cell(config_edit_input("Code", "text", model.editField2, model.isConfigSubmitting, |s| UpdateEditField2(s))),
			UI.table_cell({ classes: "" }, [config_status_badge(is_active)]),
			config_edit_actions(model, Subjects)
		])
	} else {
		UI.table_row({ classes: "hover:bg-muted/30 transition-colors" }, [
			UI.table_cell({ classes: "font-medium" }, [Html.text(config_field(parts, 1, "Subject"))]),
			UI.table_cell({ classes: "text-muted-foreground font-mono text-xs" }, [Html.text(config_field(parts, 2, "—"))]),
			UI.table_cell({ classes: "" }, [config_status_badge(is_active)]),
			config_row_actions(model, Subjects, line, id, is_active)
		])
	}
}

}