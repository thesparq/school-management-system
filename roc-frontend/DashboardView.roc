module [view]

import html.Html exposing [Html, div, text, h1, h2, p, span]
import html.Attribute exposing [class]
import UI
import State exposing [Model, Role]

view = |model| {
    match model.role {
        Admin => admin_dashboard(model)
        Teacher => teacher_dashboard(model)
        Student => student_dashboard(model)
        Parent => parent_dashboard(model)
        _ => default_dashboard(model)
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
    div([class("p-6 md:p-8 space-y-8")], [
        welcome_section(model, "Here's what's happening in your school today."),
        div([class("grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4")], [
            stat_card("Total Students", "—", "Syncing from database", "🎓"),
            stat_card("Total Teachers", "—", "Syncing from database", "👩‍🏫"),
            stat_card("Active Classes", "—", "Syncing from database", "🏫"),
            stat_card("System Status", "Online", "All services operational", "✅")
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
            stat_card("My Classes", "—", "View your class assignments", "📚"),
            stat_card("Pending Grades", "—", "Submissions awaiting review", "📝"),
            stat_card("Assessments", "—", "Active assessments", "📋")
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
            stat_card("My Subjects", "—", "View your enrolled subjects", "📚"),
            stat_card("Pending Assignments", "—", "Due assignments", "📝")
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
