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
                            Html.input([
                                Attribute.type("file"),
                                Attribute.id("passport-file-input"),
                                Attribute.class("block w-full text-sm text-muted-foreground file:mr-4 file:py-2 file:px-4 file:rounded-md file:border-0 file:text-sm file:font-medium file:bg-primary/10 file:text-primary hover:file:bg-primary/20 cursor-pointer")
                            ]),
                            Html.p([Attribute.class("text-xs text-muted-foreground")], [Html.text("JPEG or PNG, max 5 MB. Automatic upload is not wired up yet: paste the photo URL below so the profile can be created.")])
                        ])
                    ]),
                    Html.div([Attribute.class("space-y-2 pt-3")], [
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

        Html.div([Attribute.class("flex flex-col space-y-4")], [
            Html.div([Attribute.class("flex overflow-x-auto p-1 bg-muted rounded-md w-fit")], [
                config_tab(model.activeConfigTab, Terms, "Academic Terms"),
                config_tab(model.activeConfigTab, ClassLevels, "Class Levels"),
                config_tab(model.activeConfigTab, Curriculum, "Curriculum"),
                config_tab(model.activeConfigTab, ClassArms, "Class Arms"),
                config_tab(model.activeConfigTab, Subjects, "Subjects"),
            ]),
            Html.div([Attribute.class("mt-4")], [
                match model.activeConfigTab {
                    Terms => terms_config_view(model),
                    ClassLevels => class_levels_config_view(model),
                    Curriculum => curriculum_config_view(model),
                    ClassArms => class_arms_config_view(model),
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

terms_config_view = |_model| {
    UI.card({ classes: "" }, [
        UI.card_header({ classes: "" }, [
            UI.card_title({ classes: "" }, [Html.text("Academic Terms")]),
            Html.p([Attribute.class("text-sm text-muted-foreground")], [Html.text("Manage academic sessions and terms. Create new terms and activate them when ready.")])
        ]),
        UI.card_content({ classes: "space-y-4" }, [
            Html.div([Attribute.class("rounded-md border p-4 bg-muted/50")], [
                Html.p([Attribute.class("text-sm font-medium mb-1")], [Html.text("How it works")]),
                Html.p([Attribute.class("text-sm text-muted-foreground")], [Html.text("Create a session (e.g. 2026/2027), then add terms within it (First Term, Second Term, Third Term). Only one term can be active at a time.")])
            ]),
            UI.button(
                { variant: Primary, size: Default, on_click: None, is_disabled: Bool.False, classes: "" },
                [Html.text("Create New Term")]
            )
        ])
    ])
}

class_levels_config_view = |_model| {
    UI.card({ classes: "" }, [
        UI.card_header({ classes: "" }, [
            UI.card_title({ classes: "" }, [Html.text("Class Levels")]),
            Html.p([Attribute.class("text-sm text-muted-foreground")], [Html.text("Define the grade levels in your school.")])
        ]),
        UI.card_content({ classes: "space-y-4" }, [
            Html.div([Attribute.class("rounded-md border p-4 bg-muted/50")], [
                Html.p([Attribute.class("text-sm font-medium mb-1")], [Html.text("Suggested Levels")]),
                Html.p([Attribute.class("text-sm text-muted-foreground")], [Html.text("JSS 1, JSS 2, JSS 3, SS 1, SS 2, SS 3")])
            ]),
            UI.button(
                { variant: Primary, size: Default, on_click: None, is_disabled: Bool.False, classes: "" },
                [Html.text("Add Class Level")]
            )
        ])
    ])
}

curriculum_config_view = |_model| {
    UI.card({ classes: "" }, [
        UI.card_header({ classes: "" }, [
            UI.card_title({ classes: "" }, [Html.text("Curriculum")]),
            Html.p([Attribute.class("text-sm text-muted-foreground")], [Html.text("Link subjects to class levels to define what each level studies.")])
        ]),
        UI.card_content({ classes: "space-y-4" }, [
            Html.div([Attribute.class("rounded-md border p-4 bg-muted/50")], [
                Html.p([Attribute.class("text-sm font-medium mb-1")], [Html.text("How it works")]),
                Html.p([Attribute.class("text-sm text-muted-foreground")], [Html.text("First create class levels and subjects, then use this page to assign which subjects are taught at each level.")])
            ])
        ])
    ])
}

class_arms_config_view = |_model| {
    UI.card({ classes: "" }, [
        UI.card_header({ classes: "" }, [
            UI.card_title({ classes: "" }, [Html.text("Class Arms")]),
            Html.p([Attribute.class("text-sm text-muted-foreground")], [Html.text("Define streams or arms for classes.")])
        ]),
        UI.card_content({ classes: "space-y-4" }, [
            Html.div([Attribute.class("rounded-md border p-4 bg-muted/50")], [
                Html.p([Attribute.class("text-sm font-medium mb-1")], [Html.text("Examples")]),
                Html.p([Attribute.class("text-sm text-muted-foreground")], [Html.text("Gold, Silver, Diamond, Science, Art, Commercial")])
            ]),
            UI.button(
                { variant: Primary, size: Default, on_click: None, is_disabled: Bool.False, classes: "" },
                [Html.text("Add Class Arm")]
            )
        ])
    ])
}

subjects_config_view = |_model| {
    UI.card({ classes: "" }, [
        UI.card_header({ classes: "" }, [
            UI.card_title({ classes: "" }, [Html.text("Subjects")]),
            Html.p([Attribute.class("text-sm text-muted-foreground")], [Html.text("Add and categorize subjects offered by the school.")])
        ]),
        UI.card_content({ classes: "space-y-4" }, [
            Html.div([Attribute.class("rounded-md border p-4 bg-muted/50")], [
                Html.p([Attribute.class("text-sm font-medium mb-1")], [Html.text("Core Subjects")]),
                Html.p([Attribute.class("text-sm text-muted-foreground")], [Html.text("Mathematics, English Language, Physics, Chemistry, Biology, etc.")])
            ]),
            UI.button(
                { variant: Primary, size: Default, on_click: None, is_disabled: Bool.False, classes: "" },
                [Html.text("Add Subject")]
            )
        ])
    ])
}
