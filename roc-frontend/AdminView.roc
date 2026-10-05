module [view]

import html.Html
import html.Attribute

import UI
import State exposing [Model, Msg, AdminConfigTab, AdminUserTab]

view = |model| {
    match model.route {
        AdminUserManagement => admin_users_view(model)
        AdminConfigurationHub => admin_config_view(model)
        _ => Html.div([], [Html.h1([], [Html.text("Admin Dashboard")]), Html.p([], [Html.text("Welcome to Admin Dashboard")])])
    }
}

# -------------------------------------------------------
# USER MANAGEMENT VIEW
# -------------------------------------------------------

admin_users_view = |model| {
    Html.div([Attribute.class("p-6 md:p-8 space-y-6")], [
        # Page header
        Html.div([], [
            Html.h1([Attribute.class("text-3xl font-bold tracking-tight")], [Html.text("User Management")]),
            Html.p([Attribute.class("text-muted-foreground mt-1")], [Html.text("Manage all user accounts across Students, Teachers, Parents, and Administrators.")])
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

        # Add New User card
        UI.card({ classes: "" }, [
            UI.card_header({ classes: "" }, [
                Html.div([Attribute.class("flex items-center justify-between")], [
                    Html.div([], [
                        UI.card_title({ classes: "" }, [Html.text("Add New User")]),
                        Html.p([Attribute.class("text-sm text-muted-foreground mt-1")], [Html.text("Create a new account and optionally upload a passport photograph.")])
                    ])
                ])
            ]),
            UI.card_content({ classes: "space-y-4" }, [
                Html.div([Attribute.class("grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4")], [
                    # First Name
                    Html.div([Attribute.class("space-y-2")], [
                        UI.label({ classes: "" }, [Html.text("First Name")]),
                        UI.input({
                            type: "text",
                            value: model.newUserFirstName,
                            placeholder: "e.g. Adamu",
                            on_input: Input(|s| UpdateNewUserFirstName(s)),
                            is_disabled: model.isSubmitting,
                            classes: ""
                        })
                    ]),
                    # Middle Name
                    Html.div([Attribute.class("space-y-2")], [
                        UI.label({ classes: "" }, [Html.text("Middle Name (optional)")]),
                        UI.input({
                            type: "text",
                            value: model.newUserMiddleName,
                            placeholder: "e.g. Ibrahim",
                            on_input: Input(|s| UpdateNewUserMiddleName(s)),
                            is_disabled: model.isSubmitting,
                            classes: ""
                        })
                    ]),
                    # Surname
                    Html.div([Attribute.class("space-y-2")], [
                        UI.label({ classes: "" }, [Html.text("Surname")]),
                        UI.input({
                            type: "text",
                            value: model.newUserSurname,
                            placeholder: "e.g. Musa",
                            on_input: Input(|s| UpdateNewUserSurname(s)),
                            is_disabled: model.isSubmitting,
                            classes: ""
                        })
                    ]),
                    # Email
                    Html.div([Attribute.class("space-y-2")], [
                        UI.label({ classes: "" }, [Html.text("Email Address")]),
                        UI.input({
                            type: "email",
                            value: model.newUserEmail,
                            placeholder: "e.g. adamu@johnethel.school",
                            on_input: Input(|s| UpdateNewUserEmail(s)),
                            is_disabled: model.isSubmitting,
                            classes: ""
                        })
                    ]),
                    # Role
                    Html.div([Attribute.class("space-y-2")], [
                        UI.label({ classes: "" }, [Html.text("Role")]),
                        Html.div([Attribute.class("relative")], [
                            Html.select([
                                Attribute.class("w-full h-10 rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2 disabled:opacity-50 appearance-none"),
                                Attribute.id("new-user-role-select"),
                                Attribute.on_change(|s| UpdateNewUserRole(s))
                            ], [
                                Html.option([Attribute.value("Student")], [Html.text("Student")]),
                                Html.option([Attribute.value("Teacher")], [Html.text("Teacher")]),
                                Html.option([Attribute.value("Parent")], [Html.text("Parent")]),
                                Html.option([Attribute.value("Admin")], [Html.text("Administrator")])
                            ]),
                            Html.span([Attribute.class("pointer-events-none absolute inset-y-0 right-3 flex items-center text-muted-foreground text-xs")], [Html.text("▼")])
                        ])
                    ]),
                    # Submit button
                    Html.div([Attribute.class("space-y-2 flex items-end")], [
                        UI.button(
                            { variant: Primary, size: Default, on_click: Click(SubmitNewUser), is_disabled: model.isSubmitting, classes: "w-full" },
                            [Html.text(if model.isSubmitting { "Adding..." } else { "Add User" })]
                        )
                    ])
                ]),

                # Role-specific details (student class and birth date, admin job title)
                Html.div([Attribute.class("grid grid-cols-1 md:grid-cols-3 gap-4")], [
                    Html.div([Attribute.class("space-y-2")], [
                        UI.label({ classes: "" }, [Html.text("Date of Birth (students)")]),
                        UI.input({
                            type: "date",
                            value: model.newUserDateOfBirth,
                            placeholder: "",
                            on_input: Input(|s| UpdateNewUserDateOfBirth(s)),
                            is_disabled: model.isSubmitting,
                            classes: ""
                        })
                    ]),
                    Html.div([Attribute.class("space-y-2")], [
                        UI.label({ classes: "" }, [Html.text("Class Level (students)")]),
                        UI.input({
                            type: "text",
                            value: model.newUserClassLevel,
                            placeholder: "jss_1, jss_2, jss_3, year_1 ...",
                            on_input: Input(|s| UpdateNewUserClassLevel(s)),
                            is_disabled: model.isSubmitting,
                            classes: ""
                        })
                    ]),
                    Html.div([Attribute.class("space-y-2")], [
                        UI.label({ classes: "" }, [Html.text("Role Title (admins)")]),
                        UI.input({
                            type: "text",
                            value: model.newUserRoleTitle,
                            placeholder: "e.g. Bursar",
                            on_input: Input(|s| UpdateNewUserRoleTitle(s)),
                            is_disabled: model.isSubmitting,
                            classes: ""
                        })
                    ])
                ]),

                # Passport upload row
                Html.div([Attribute.class("border-t pt-4")], [
                    Html.p([Attribute.class("text-sm font-medium mb-2")], [Html.text("Passport Photograph")]),
                    Html.div([Attribute.class("flex items-center gap-4")], [
                        Html.div([Attribute.id("passport-preview"), Attribute.class("w-16 h-16 rounded-full bg-muted border-2 border-dashed border-border flex items-center justify-center text-2xl overflow-hidden")], [
                            Html.text("📷")
                        ]),
                        Html.div([Attribute.class("flex-1 space-y-1")], [
                            # The upload itself is the page's JavaScript: it asks the backend to
                            # sign a PUT, sends the file, and writes the public URL into the field
                            # below, which is what the form submits.
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
        ]),

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

        # Role tabs + users table
        Html.div([Attribute.class("space-y-4")], [
            # Tab bar
            Html.div([Attribute.class("border-b border-border")], [
                Html.nav([Attribute.class("-mb-px flex space-x-6 overflow-x-auto")], [
                    user_tab(model.activeUserTab, Students, "👩‍🎓 Students"),
                    user_tab(model.activeUserTab, Teachers, "👨‍🏫 Teachers"),
                    user_tab(model.activeUserTab, Parents, "👨‍👩‍👧 Parents"),
                    user_tab(model.activeUserTab, Admins, "⚙️ Admins"),
                ])
            ]),

            # Users table
            UI.card({ classes: "" }, [
                UI.card_content({ classes: "p-0" }, [
                    UI.table({ classes: "" }, [
                        UI.table_header({ classes: "" }, [
                            UI.table_row({ classes: "" }, [
                                UI.table_head({ classes: "w-10" }, [Html.text("")]),
                                UI.table_head({ classes: "" }, [Html.text("Name")]),
                                UI.table_head({ classes: "" }, [Html.text("Email")]),
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
        ])
    ])
}

user_tab = |active_tab, this_tab, label| {
    is_active = active_tab == this_tab
    classes =
        if is_active {
            "whitespace-nowrap border-b-2 border-primary text-primary py-4 px-1 text-sm font-medium cursor-pointer"
        } else {
            "whitespace-nowrap border-b-2 border-transparent text-muted-foreground hover:text-foreground hover:border-border py-4 px-1 text-sm font-medium cursor-pointer transition-colors"
        }
    Html.button([
        Attribute.class(classes),
        Attribute.type("button"),
        Attribute.on_click(SetUserTab(this_tab))
    ], [Html.text(label)])
}

users_for_tab = |model| {
    raw_data = match model.activeUserTab {
        Students => model.usersStudentsData
        Teachers => model.usersTeachersData
        Parents => model.usersParentsData
        Admins => model.usersAdminsData
    }
    empty_label = match model.activeUserTab {
        Students => "No students found"
        Teachers => "No teachers found"
        Parents => "No parents found"
        Admins => "No administrators found"
    }
    if Str.is_empty(raw_data) {
        [
            UI.table_row({ classes: "" }, [
                UI.table_cell({ classes: "text-center text-muted-foreground py-12 col-span-5" }, [
                    Html.div([Attribute.class("flex flex-col items-center gap-2")], [
                        Html.span([Attribute.class("text-3xl")], [Html.text("👥")]),
                        Html.p([Attribute.class("text-sm font-medium")], [Html.text(if model.isLoading { "Loading..." } else { empty_label })]),
                        Html.p([Attribute.class("text-xs text-muted-foreground")], [Html.text(if model.isLoading { "Fetching data from server" } else { "Add a user above to get started" })])
                    ])
                ])
            ])
        ]
    } else {
        List.map(Str.split_on(raw_data, "\n"), |line| {
            parts = Str.split_on(line, "|")
            name = match List.get(parts, 0) { Ok(n) => n, Err(_) => "Unknown" }
            email = match List.get(parts, 1) { Ok(e) => e, Err(_) => "" }
            is_active = match List.get(parts, 2) { Ok(s) => s == "true", Err(_) => Bool.True }
            user_row(name, email, is_active)
        })
    }
}

user_row = |name, email, is_active| {
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
            Html.div([Attribute.class("w-8 h-8 rounded-full bg-primary/15 flex items-center justify-center text-sm font-semibold text-primary")], [
                Html.text(initial)
            ])
        ]),
        UI.table_cell({ classes: "font-medium" }, [Html.text(name)]),
        UI.table_cell({ classes: "text-muted-foreground text-sm" }, [Html.text(email)]),
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
                UI.button(
                    { variant: Ghost, size: Sm, on_click: None, is_disabled: Bool.False, classes: "text-xs" },
                    [Html.text("Edit")]
                ),
                UI.button(
                    { variant: Ghost, size: Sm, on_click: None, is_disabled: Bool.False, classes: "text-xs text-destructive hover:text-destructive" },
                    [Html.text("Deactivate")]
                )
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
		Html.input([Attribute.type("hidden"), Attribute.id("class_levels_data_input"), Attribute.value(model.classLevelsData), Attribute.on_input(|s| GotClassLevelsData(s))]),
		Html.input([Attribute.type("hidden"), Attribute.id("curriculum_data_input"), Attribute.value(model.curriculumData), Attribute.on_input(|s| GotCurriculumData(s))]),
		Html.input([Attribute.type("hidden"), Attribute.id("session_terms_data_input"), Attribute.value(model.sessionTermsData), Attribute.on_input(|s| GotSessionTermsData(s))]),

		Html.div([Attribute.class("flex flex-col space-y-4")], [
			Html.div([Attribute.class("flex overflow-x-auto p-1 bg-muted rounded-md w-fit")], [
				config_tab(model.activeConfigTab, Terms, "Academic Terms"),
				config_tab(model.activeConfigTab, ClassLevels, "Class Levels"),
				config_tab(model.activeConfigTab, Curriculum, "Curriculum"),
				config_tab(model.activeConfigTab, SessionTerms, "Session Terms"),
				config_tab(model.activeConfigTab, Subjects, "Subjects"),
			]),
			Html.div([Attribute.class("mt-4")], [
				match model.activeConfigTab {
					Terms => terms_config_view(model),
					ClassLevels => class_levels_config_view(model),
					Curriculum => curriculum_config_view(model),
					SessionTerms => session_terms_config_view(model),
					Subjects => subjects_config_view(model),
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
				Attribute.class("w-full h-10 rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2 disabled:opacity-50 appearance-none"),
				Attribute.id(select_id),
				Attribute.on_change(to_msg)
			], options),
			Html.span([Attribute.class("pointer-events-none absolute inset-y-0 right-3 flex items-center text-muted-foreground text-xs")], [Html.text("▼")])
		])
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

config_empty_row = |message| {
	UI.table_row({ classes: "" }, [
		UI.table_cell({ classes: "text-center text-muted-foreground py-12" }, [
			Html.div([Attribute.class("flex flex-col items-center gap-2")], [
				Html.span([Attribute.class("text-3xl")], [Html.text("🗂️")]),
				Html.p([Attribute.class("text-sm font-medium")], [Html.text(message)])
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
	config_card("Academic Terms", "Terms run in order within the school year; every term is listed here, active or not.", [
		config_form_row([
			config_labeled_input("Term name", "e.g. Summer Term", "text", model.newTermName, model.isConfigSubmitting, |s| UpdateNewTermName(s)),
			config_labeled_input("Sort order", "e.g. 3", "number", model.newTermSortOrder, model.isConfigSubmitting, |s| UpdateNewTermSortOrder(s)),
		], config_submit_button(model, Terms, "Create Term")),
		config_create_banner(model),
		config_table(["Term", "Sort order", "Status"], terms_rows(model))
	])
}

terms_rows = |model| {
	if Str.is_empty(model.termsData) {
		[config_empty_row(if model.isLoading { "Loading terms..." } else { "No terms yet. Create the first one above." })]
	} else {
		List.map(Str.split_on(model.termsData, "\n"), |line| {
			parts = Str.split_on(line, "|")
			name = config_field(parts, 1, "Term")
			order = config_field(parts, 2, "—")
			is_active = config_field(parts, 3, "true") == "true"
			UI.table_row({ classes: "hover:bg-muted/30 transition-colors" }, [
				UI.table_cell({ classes: "font-medium" }, [Html.text(name)]),
				UI.table_cell({ classes: "text-muted-foreground" }, [Html.text(order)]),
				UI.table_cell({ classes: "" }, [config_status_badge(is_active)])
			])
		})
	}
}

# --- Class Levels ---

class_levels_config_view = |model| {
	config_card("Class Levels", "The year groups of the school. The code is the short key records use (e.g. jss_1); only active levels are listed.", [
		config_form_row([
			config_labeled_input("Class level name", "e.g. JSS 4", "text", model.newClassLevelName, model.isConfigSubmitting, |s| UpdateNewClassLevelName(s)),
			config_labeled_input("Code", "e.g. jss_4", "text", model.newClassLevelCode, model.isConfigSubmitting, |s| UpdateNewClassLevelCode(s)),
		], config_submit_button(model, ClassLevels, "Create Class Level")),
		config_create_banner(model),
		config_table(["Class level", "Code", "Age range"], class_levels_rows(model))
	])
}

class_levels_rows = |model| {
	if Str.is_empty(model.classLevelsData) {
		[config_empty_row(if model.isLoading { "Loading class levels..." } else { "No class levels yet. Create the first one above." })]
	} else {
		List.map(Str.split_on(model.classLevelsData, "\n"), |line| {
			parts = Str.split_on(line, "|")
			name = config_field(parts, 1, "Class level")
			code = config_field(parts, 2, "—")
			age_range = config_field(parts, 3, "—")
			UI.table_row({ classes: "hover:bg-muted/30 transition-colors" }, [
				UI.table_cell({ classes: "font-medium" }, [Html.text(name)]),
				UI.table_cell({ classes: "text-muted-foreground font-mono text-xs" }, [Html.text(code)]),
				UI.table_cell({ classes: "text-muted-foreground" }, [Html.text(age_range)])
			])
		})
	}
}

# --- Curriculum ---

curriculum_config_view = |model| {
	config_card("Curriculum", "Link subjects to class levels to define what each level studies.", [
		config_form_row([
			config_labeled_select("Class level", "new-curriculum-class-level-select", config_record_options(model.classLevelsData, "No class levels yet"), |s| UpdateNewCurriculumClassLevel(s)),
			config_labeled_select("Subject", "new-curriculum-subject-select", config_record_options(model.subjectsData, "No subjects yet"), |s| UpdateNewCurriculumSubject(s)),
		], config_submit_button(model, Curriculum, "Link Subject")),
		config_create_banner(model),
		config_table(["Class level", "Subject"], curriculum_rows(model))
	])
}

curriculum_rows = |model| {
	if Str.is_empty(model.curriculumData) {
		[config_empty_row(if model.isLoading { "Loading the curriculum..." } else { "No subject is linked to a class level yet." })]
	} else {
		List.map(Str.split_on(model.curriculumData, "\n"), |line| {
			parts = Str.split_on(line, "|")
			class_level = config_record_name(model.classLevelsData, config_field(parts, 1, ""))
			subject = config_record_name(model.subjectsData, config_field(parts, 2, ""))
			UI.table_row({ classes: "hover:bg-muted/30 transition-colors" }, [
				UI.table_cell({ classes: "font-medium" }, [Html.text(class_level)]),
				UI.table_cell({ classes: "" }, [Html.text(subject)])
			])
		})
	}
}

# --- Session Terms ---

session_terms_config_view = |model| {
	config_card("Session Terms", "Pairs a school session (e.g. 2026/2027) with one of the terms above. New session terms start inactive.", [
		config_form_row([
			config_labeled_input("Session name", "e.g. 2026/2027", "text", model.newSessionTermName, model.isConfigSubmitting, |s| UpdateNewSessionTermName(s)),
			config_labeled_select("Term", "new-session-term-select", config_record_options(model.termsData, "No terms yet"), |s| UpdateNewSessionTermTerm(s)),
		], config_submit_button(model, SessionTerms, "Create Session Term")),
		config_create_banner(model),
		config_table(["Session", "Term", "Status"], session_terms_rows(model))
	])
}

session_terms_rows = |model| {
	if Str.is_empty(model.sessionTermsData) {
		[config_empty_row(if model.isLoading { "Loading session terms..." } else { "No session terms yet. Create the first one above." })]
	} else {
		List.map(Str.split_on(model.sessionTermsData, "\n"), |line| {
			parts = Str.split_on(line, "|")
			session = config_field(parts, 1, "Session")
			term = config_record_name(model.termsData, config_field(parts, 2, ""))
			is_active = config_field(parts, 3, "false") == "true"
			UI.table_row({ classes: "hover:bg-muted/30 transition-colors" }, [
				UI.table_cell({ classes: "font-medium" }, [Html.text(session)]),
				UI.table_cell({ classes: "text-muted-foreground" }, [Html.text(term)]),
				UI.table_cell({ classes: "" }, [config_status_badge(is_active)])
			])
		})
	}
}

# --- Subjects ---

subjects_config_view = |model| {
	config_card("Subjects", "The subjects the school offers. Only active subjects are listed.", [
		config_form_row([
			config_labeled_input("Subject name", "e.g. Mathematics", "text", model.newSubjectName, model.isConfigSubmitting, |s| UpdateNewSubjectName(s)),
			config_labeled_input("Code", "e.g. MTH", "text", model.newSubjectCode, model.isConfigSubmitting, |s| UpdateNewSubjectCode(s)),
		], config_submit_button(model, Subjects, "Create Subject")),
		config_create_banner(model),
		config_table(["Subject", "Code"], subjects_rows(model))
	])
}

subjects_rows = |model| {
	if Str.is_empty(model.subjectsData) {
		[config_empty_row(if model.isLoading { "Loading subjects..." } else { "No subjects yet. Create the first one above." })]
	} else {
		List.map(Str.split_on(model.subjectsData, "\n"), |line| {
			parts = Str.split_on(line, "|")
			name = config_field(parts, 1, "Subject")
			code = config_field(parts, 2, "—")
			UI.table_row({ classes: "hover:bg-muted/30 transition-colors" }, [
				UI.table_cell({ classes: "font-medium" }, [Html.text(name)]),
				UI.table_cell({ classes: "text-muted-foreground font-mono text-xs" }, [Html.text(code)])
			])
		})
	}
}
