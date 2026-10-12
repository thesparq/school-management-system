
import html.Html exposing [div, text, h1, h2, p, span]
import html.Attribute exposing [class]
import UI
import State exposing [Model, Role, list_state]
DashboardView := [].{

view = |model| {
    div([], [
        # The dashboard's numbers, fed by the page's fetch of /api/dashboard. One hidden input for every
        # role's dashboard: it lives here rather than in each of them, so a card can never be left
        # without the payload it reads.
        Html.input([
            Attribute.type("hidden"),
            Attribute.id("dashboard_data_input"),
            Attribute.value(model.dashboardData),
            Attribute.on_input(|s| GotDashboardData(s))
        ]),
        match model.role {
            Admin => admin_dashboard(model)
            Teacher => teacher_dashboard(model)
            Student => student_dashboard(model)
            Parent => parent_dashboard(model)
            _ => default_dashboard(model)
        }
    ])
}

# One number from that payload, which arrives as a "key|value" line per count. A key the answer does
# not carry — or a payload that never landed — shows a dash, so one missing number cannot blank the
# cards around it. A fold rather than keep_if + List.first: the latter miscompiles on this nightly
# (see UI.roc's note).
dashboard_stat = |model, key| {
    found = List.fold(Str.split_on(model.dashboardData, "\n"), "", |best, line| {
        parts = Str.split_on(line, "|")
        name = match List.get(parts, 0) { Ok(v) => v, Err(_) => "" }
        value = match List.get(parts, 1) { Ok(v) => v, Err(_) => "" }
        if name == key and !Str.is_empty(value) { value } else { best }
    })
    if Str.is_empty(found) { "—" } else { found }
}

# The status card reads the same payload's state rather than the numbers: a dashboard that could not
# load its counts should say so instead of claiming everything is fine.
dashboard_status = |model| {
    match list_state(model.dashboardData) {
        Pending => { value: "Checking…", hint: "Reading the latest numbers", icon: "⏳" }
        Failed(message) => { value: "Unavailable", hint: message, icon: "⚠️" }
        Ready(_) => { value: "Online", hint: "All services operational", icon: "✅" }
    }
}

welcome_section = |model, subtitle| {
    name = if Str.is_empty(model.userName) { "User" } else { model.userName }
    div([class("mb-8")], [
        h1([class("text-3xl font-bold tracking-tight")], [text("Welcome back, ${name}")]),
        p([class("text-muted-foreground mt-1")], [text(subtitle)])
    ])
}

stat_card = |title, value, subtitle, icon| {
    UI.card({ classes: "" }, [
        UI.card_header({ classes: "flex flex-row items-center justify-between pb-2" }, [
            div([class("text-sm font-medium text-muted-foreground")], [text(title)]),
            div([class("text-2xl")], [text(icon)])
        ]),
        UI.card_content({ classes: "" }, [
            p([class("text-3xl font-bold")], [text(value)]),
            p([class("text-xs text-muted-foreground mt-1")], [text(subtitle)])
        ])
    ])
}

admin_dashboard = |model| {
    status = dashboard_status(model)
    div([class("p-6 md:p-8 space-y-8")], [
        welcome_section(model, "Here's what's happening in your school today."),
        div([class("grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4")], [
            stat_card("Total Students", dashboard_stat(model, "students"), "Enrolled accounts", "🎓"),
            stat_card("Total Teachers", dashboard_stat(model, "teachers"), "Teaching accounts", "👩‍🏫"),
            stat_card("Active Classes", dashboard_stat(model, "classes"), "Class levels in use", "🏫"),
            stat_card("System Status", status.value, status.hint, status.icon)
        ]),
        div([class("grid grid-cols-1 md:grid-cols-2 gap-6")], [
            UI.card({ classes: "" }, [
                UI.card_header({ classes: "" }, [
                    UI.card_title({ classes: "" }, [text("Quick Actions")])
                ]),
                UI.card_content({ classes: "space-y-3" }, [
                    UI.button({ ..UI.default_button, variant: Outline, classes: "w-full justify-start gap-2", on_click: Click(NavigateTo(AdminUserManagement)) }, [
                        text("👤  Manage Users")
                    ]),
                    UI.button({ ..UI.default_button, variant: Outline, classes: "w-full justify-start gap-2", on_click: Click(NavigateTo(AdminConfigurationHub)) }, [
                        text("⚙️  Configuration Hub")
                    ])
                ])
            ]),
            UI.card({ classes: "" }, [
                UI.card_header({ classes: "" }, [
                    UI.card_title({ classes: "" }, [text("Recent Activity")])
                ]),
                UI.card_content({ classes: "" }, [
                    p([class("text-sm text-muted-foreground")], [text("Activity feed will appear here once data is synced.")])
                ])
            ])
        ])
    ])
}

teacher_dashboard = |model| {
    div([class("p-6 md:p-8 space-y-8")], [
        welcome_section(model, "Manage your classes and assessments."),
        div([class("grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4")], [
            stat_card("My Classes", dashboard_stat(model, "classes"), "Assigned class-subject pairs", "📚"),
            stat_card("Pending Grades", dashboard_stat(model, "pending_grades"), "Submissions awaiting review", "📝"),
            stat_card("Assessments", dashboard_stat(model, "assessments"), "Published on your lessons", "📋")
        ]),
        UI.card({ classes: "" }, [
            UI.card_header({ classes: "" }, [
                UI.card_title({ classes: "" }, [text("Quick Actions")])
            ]),
            UI.card_content({ classes: "space-y-3" }, [
                UI.button({ ..UI.default_button, variant: Outline, classes: "w-full justify-start gap-2", on_click: Click(NavigateTo(TeacherLessonViewer)) }, [
                    text("📖  View Lessons")
                ]),
                UI.button({ ..UI.default_button, variant: Outline, classes: "w-full justify-start gap-2", on_click: Click(NavigateTo(TeacherAssessments)) }, [
                    text("✏️  Assessments & Grading")
                ])
            ])
        ])
    ])
}

student_dashboard = |model| {
    div([class("p-6 md:p-8 space-y-8")], [
        welcome_section(model, "Keep up the great work! Here's your learning overview."),
        div([class("grid grid-cols-1 sm:grid-cols-2 gap-4")], [
            stat_card("My Subjects", dashboard_stat(model, "subjects"), "Subjects your class takes", "📚"),
            stat_card("Pending Assignments", dashboard_stat(model, "assignments"), "Published, not yet submitted", "📝")
        ]),
        UI.card({ classes: "" }, [
            UI.card_header({ classes: "" }, [
                UI.card_title({ classes: "" }, [text("Quick Actions")])
            ]),
            UI.card_content({ classes: "space-y-3" }, [
                UI.button({ ..UI.default_button, variant: Outline, classes: "w-full justify-start gap-2", on_click: Click(NavigateTo(StudentLessonViewer)) }, [
                    text("📖  View Lessons")
                ]),
                UI.button({ ..UI.default_button, variant: Outline, classes: "w-full justify-start gap-2", on_click: Click(NavigateTo(StudentAssignments)) }, [
                    text("✏️  My Assignments")
                ])
            ])
        ])
    ])
}

parent_dashboard = |model| {
    div([class("p-6 md:p-8 space-y-8")], [
        welcome_section(model, "Monitor your children's academic progress."),
        UI.card({ classes: "" }, [
            UI.card_header({ classes: "" }, [
                UI.card_title({ classes: "" }, [text("My Children")])
            ]),
            UI.card_content({ classes: "" }, [
                p([class("text-sm text-muted-foreground")], [text("Your linked students will appear here once your account is configured.")])
            ])
        ])
    ])
}

default_dashboard = |_model| {
    div([class("p-6 md:p-8 flex items-center justify-center min-h-[60vh]")], [
        UI.card({ classes: "max-w-md w-full text-center" }, [
            UI.card_content({ classes: "py-12 space-y-4" }, [
                div([class("text-5xl mb-4")], [text("🔒")]),
                h2([class("text-xl font-semibold")], [text("Authentication Required")]),
                p([class("text-muted-foreground")], [text("Please sign in to access the school management system.")])
            ])
        ])
    ])
}

}