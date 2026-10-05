module [view]

import html.Html
import html.Attribute

import UI
import State exposing [Model, Msg]

view = |model| {
    match model.route {
        TeacherMyClasses => teacher_classes_view(model)
        TeacherLessonViewer => teacher_lesson_view(model)
        TeacherAssessments => teacher_assessments_view(model)
        _ => teacher_dashboard_shortcuts(model)
    }
}

# -------------------------------------------------------
# MY CLASSES VIEW (Teacher entry point for LMS)
# -------------------------------------------------------

teacher_classes_view = |model| {
    Html.div([Attribute.class("p-6 md:p-8 space-y-6")], [
        Html.div([], [
            Html.h1([Attribute.class("text-3xl font-bold tracking-tight")], [Html.text("My Classes")]),
            Html.p([Attribute.class("text-muted-foreground mt-1")], [Html.text("View your teaching assignments and manage lesson content.")])
        ]),

        # Hidden input for subjects data
        Html.input([
            Attribute.type("hidden"),
            Attribute.id("subjects_data_input"),
            Attribute.value(model.subjectsData),
            Attribute.on_input(|s| GotSubjectsData(s))
        ]),

        if Str.is_empty(model.subjectsData) {
            Html.div([Attribute.class("grid grid-cols-1 md:grid-cols-2 gap-4")], [
                teacher_subject_skeleton(""),
                teacher_subject_skeleton("")
            ])
        } else {
            Html.div([Attribute.class("grid grid-cols-1 md:grid-cols-2 gap-4")],
                List.map(Str.split_on(model.subjectsData, "\n"), |line| {
                    parts = Str.split_on(line, "|")
                    id = match List.get(parts, 0) { Ok(v) => v, Err(_) => "" }
                    name = match List.get(parts, 1) { Ok(v) => v, Err(_) => "Unknown Subject" }
                    teacher_subject_card(id, name)
                })
            )
        }
    ])
}

teacher_subject_skeleton = |_| {
    Html.div([Attribute.class("rounded-lg border bg-card p-6 space-y-4 animate-pulse")], [
        Html.div([Attribute.class("flex items-center gap-4")], [
            Html.div([Attribute.class("h-12 w-12 rounded-xl bg-muted")], []),
            Html.div([Attribute.class("space-y-2 flex-1")], [
                Html.div([Attribute.class("h-4 w-36 rounded bg-muted")], []),
                Html.div([Attribute.class("h-3 w-20 rounded bg-muted")], [])
            ])
        ]),
        Html.div([Attribute.class("h-8 w-32 rounded bg-muted")], [])
    ])
}

teacher_subject_card = |id, name| {
    Html.div([
        Attribute.class("group rounded-lg border bg-card p-6 space-y-4 hover:shadow-md hover:border-primary/30 transition-all cursor-pointer"),
        Attribute.on_click(NavigateTo(TeacherLessonViewer))
    ], [
        Html.div([Attribute.class("flex items-center gap-4")], [
            Html.div([Attribute.class("w-12 h-12 rounded-xl bg-primary/10 flex items-center justify-center text-2xl")], [Html.text("📖")]),
            Html.div([Attribute.class("flex-1 space-y-0.5")], [
                Html.h3([Attribute.class("font-semibold text-foreground group-hover:text-primary transition-colors")], [Html.text(name)]),
                Html.p([Attribute.class("text-xs text-muted-foreground")], [Html.text("ID: ${id}")])
            ])
        ]),
        Html.div([Attribute.class("flex gap-2")], [
            Html.span([Attribute.class("inline-flex items-center gap-1 text-xs rounded-md px-2 py-1 bg-muted text-muted-foreground")], [Html.text("📝 Manage Lessons")]),
            Html.span([Attribute.class("inline-flex items-center gap-1 text-xs rounded-md px-2 py-1 bg-muted text-muted-foreground")], [Html.text("📊 Assessments")])
        ])
    ])
}

# -------------------------------------------------------
# TEACHER LESSON VIEWER (same structure as student but with
# teacher-specific tabs: Lesson | Assessments | Grading)
# -------------------------------------------------------

teacher_lesson_view = |_model| {
    Html.div([Attribute.class("relative")], [
        Html.div([Attribute.class("flex min-h-screen")], [
            # Main content column
            Html.div([Attribute.class("flex-1 max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8")], [

                # Back + lesson header
                Html.div([Attribute.id("lesson-header"), Attribute.class("space-y-3")], [
                    Html.div([Attribute.class("flex items-center gap-2 text-sm text-muted-foreground")], [
                        Html.span([Attribute.class("cursor-pointer hover:text-foreground"), Attribute.on_click(NavigateTo(TeacherMyClasses))], [Html.text("← Back to My Classes")])
                    ]),
                    Html.div([Attribute.class("flex items-start justify-between gap-6")], [
                        Html.div([Attribute.class("space-y-2")], [
                            Html.div([Attribute.id("lesson-title"), Attribute.class("text-3xl font-bold text-primary leading-tight")], [Html.text("Loading lesson...")]),
                            Html.div([Attribute.id("lesson-meta"), Attribute.class("text-sm text-muted-foreground font-medium tracking-wide uppercase")], [Html.text("Subject · Term")])
                        ]),
                        Html.div([Attribute.id("lesson-week-badge"), Attribute.class("hidden")], [])
                    ])
                ]),

                # Tab bar: Lesson | Assessments | Grading
                Html.div([Attribute.class("flex border-b border-border")], [
                    Html.button([
                        Attribute.id("tab-lesson"),
                        Attribute.class("px-4 py-2 text-sm border-b-2 border-primary text-primary font-medium transition cursor-pointer"),
                        Attribute.type("button")
                    ], [Html.text("Lesson")]),
                    Html.button([
                        Attribute.id("tab-assessments"),
                        Attribute.class("px-4 py-2 text-sm border-b-2 border-transparent text-muted-foreground hover:text-foreground transition cursor-pointer"),
                        Attribute.type("button")
                    ], [Html.text("Assessments")]),
                    Html.button([
                        Attribute.id("tab-grading"),
                        Attribute.class("px-4 py-2 text-sm border-b-2 border-transparent text-muted-foreground hover:text-foreground transition cursor-pointer"),
                        Attribute.type("button")
                    ], [Html.text("Grading")])
                ]),

                # Lesson content panel
                Html.div([Attribute.id("lesson-panel"), Attribute.class("space-y-8 pb-16")], [
                    Html.div([Attribute.class("flex items-center justify-center py-16 text-muted-foreground")], [
                        Html.div([Attribute.class("text-center space-y-2")], [
                            Html.div([Attribute.class("text-4xl")], [Html.text("📖")]),
                            Html.p([Attribute.class("text-sm")], [Html.text("Select a lesson from My Classes to begin.")])
                        ])
                    ])
                ]),

                # Assessments panel (teacher can create)
                Html.div([Attribute.id("assessments-panel"), Attribute.class("hidden space-y-4 pb-16")], [
                    Html.div([Attribute.class("flex items-center justify-between")], [
                        Html.h2([Attribute.class("text-xl font-bold text-primary")], [Html.text("Assessments")]),
                        Html.button([
                            Attribute.id("create-assessment-btn"),
                            Attribute.class("inline-flex items-center gap-2 rounded-md bg-primary text-primary-foreground px-4 py-2 text-sm font-medium hover:bg-primary/90 transition cursor-pointer"),
                            Attribute.type("button")
                        ], [Html.text("+ Create Assessment")])
                    ]),
                    Html.div([Attribute.id("assessments-list")], [
                        Html.div([Attribute.class("text-center py-8 text-muted-foreground")], [Html.text("Loading assessments...")])
                    ])
                ]),

                # Grading panel (teacher only)
                Html.div([Attribute.id("grading-panel"), Attribute.class("hidden space-y-4 pb-16")], [
                    Html.h2([Attribute.class("text-xl font-bold text-primary")], [Html.text("Grading")]),
                    Html.div([Attribute.id("grading-list")], [
                        Html.div([Attribute.class("text-center py-8 text-muted-foreground")], [Html.text("Loading submissions...")])
                    ])
                ]),

                # Create assessment modal (hidden by default)
                Html.div([Attribute.id("create-assessment-modal"), Attribute.class("hidden fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4")], [
                    Html.div([Attribute.class("bg-card border rounded-xl shadow-2xl w-full max-w-2xl max-h-[90vh] flex flex-col")], [
                        Html.div([Attribute.class("flex items-center justify-between p-6 border-b")], [
                            Html.h3([Attribute.class("text-lg font-semibold")], [Html.text("Create Assessment")]),
                            Html.button([
                                Attribute.id("close-create-modal"),
                                Attribute.class("text-muted-foreground hover:text-foreground text-xl cursor-pointer"),
                                Attribute.type("button")
                            ], [Html.text("✕")])
                        ]),
                        Html.div([Attribute.class("flex-1 overflow-y-auto p-6 space-y-4")], [
                            Html.div([Attribute.class("space-y-2")], [
                                Html.label([Attribute.class("text-sm font-medium")], [Html.text("Assessment Title")]),
                                Html.input([
                                    Attribute.id("assessment-title-input"),
                                    Attribute.class("w-full rounded-md border border-input bg-background px-3 py-2 text-sm"),
                                    Attribute.placeholder("e.g. Week 3 Quiz")
                                ])
                            ]),
                            Html.div([Attribute.id("assessment-questions-area"), Attribute.class("space-y-3")], [
                                Html.p([Attribute.class("text-sm text-muted-foreground italic")], [Html.text("Questions from this lesson will appear here.")])
                            ])
                        ]),
                        Html.div([Attribute.class("flex justify-end gap-3 p-6 border-t")], [
                            Html.button([
                                Attribute.id("cancel-create-modal"),
                                Attribute.class("px-4 py-2 text-sm rounded-md border hover:bg-muted transition cursor-pointer"),
                                Attribute.type("button")
                            ], [Html.text("Cancel")]),
                            Html.button([
                                Attribute.id("submit-create-assessment"),
                                Attribute.class("px-4 py-2 text-sm rounded-md bg-primary text-primary-foreground hover:bg-primary/90 transition cursor-pointer"),
                                Attribute.type("button")
                            ], [Html.text("Create")])
                        ])
                    ])
                ])
            ]),

            # Right-side sticky section navigator (same as student view)
            Html.div([
                Attribute.id("section-nav"),
                Attribute.class("hidden md:block fixed right-6 top-1/2 -translate-y-1/2 z-50 group")
            ], [
                Html.div([
                    Attribute.id("section-nav-panel"),
                    Attribute.class("absolute right-full top-1/2 -translate-y-1/2 mr-3 opacity-0 group-hover:opacity-100 pointer-events-none group-hover:pointer-events-auto transition-all duration-200 translate-x-2 group-hover:translate-x-0")
                ], [
                    Html.div([Attribute.class("bg-card border border-border rounded-lg shadow-lg p-3 space-y-1 w-52")], [
                        Html.div([Attribute.id("section-nav-labels")], [])
                    ])
                ]),
                Html.div([Attribute.id("section-nav-dots"), Attribute.class("flex flex-col items-center gap-2.5 py-3")], [])
            ])
        ]),

        # Mobile FAB
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

# -------------------------------------------------------
# TEACHER ASSESSMENTS OVERVIEW
# -------------------------------------------------------

teacher_assessments_view = |_model| {
    Html.div([Attribute.class("p-6 md:p-8 space-y-6")], [
        Html.div([], [
            Html.h1([Attribute.class("text-3xl font-bold tracking-tight")], [Html.text("Assessments & Grading")]),
            Html.p([Attribute.class("text-muted-foreground mt-1")], [Html.text("Create assessments, review submissions, and release grades.")])
        ]),
        Html.div([Attribute.class("grid grid-cols-1 md:grid-cols-3 gap-4")], [
            # Stats
            Html.div([Attribute.class("rounded-xl border bg-card p-6 space-y-1")], [
                Html.p([Attribute.class("text-sm text-muted-foreground")], [Html.text("Active Assessments")]),
                Html.p([Attribute.class("text-3xl font-bold text-primary")], [Html.text("—")]),
                Html.p([Attribute.class("text-xs text-muted-foreground")], [Html.text("Across all lessons")])
            ]),
            Html.div([Attribute.class("rounded-xl border bg-card p-6 space-y-1")], [
                Html.p([Attribute.class("text-sm text-muted-foreground")], [Html.text("Pending Submissions")]),
                Html.p([Attribute.class("text-3xl font-bold text-amber-500")], [Html.text("—")]),
                Html.p([Attribute.class("text-xs text-muted-foreground")], [Html.text("Awaiting your review")])
            ]),
            Html.div([Attribute.class("rounded-xl border bg-card p-6 space-y-1")], [
                Html.p([Attribute.class("text-sm text-muted-foreground")], [Html.text("Grades Released")]),
                Html.p([Attribute.class("text-3xl font-bold text-green-500")], [Html.text("—")]),
                Html.p([Attribute.class("text-xs text-muted-foreground")], [Html.text("Students can see scores")])
            ])
        ]),
        Html.div([Attribute.class("text-center py-12 text-muted-foreground space-y-3 border rounded-xl bg-card")], [
            Html.div([Attribute.class("text-4xl")], [Html.text("📊")]),
            Html.h3([Attribute.class("font-semibold text-lg")], [Html.text("Manage Assessments via Lessons")]),
            Html.p([Attribute.class("text-sm max-w-xs mx-auto")], [Html.text("Navigate to My Classes, open a lesson, and use the Assessments and Grading tabs to manage student work.")]),
            Html.div([Attribute.class("pt-2")], [
                Html.span([
                    Attribute.class("inline-flex items-center gap-2 rounded-md bg-primary text-primary-foreground px-4 py-2 text-sm font-medium hover:bg-primary/90 transition cursor-pointer"),
                    Attribute.on_click(NavigateTo(TeacherMyClasses))
                ], [Html.text("Go to My Classes →")])
            ])
        ])
    ])
}

# -------------------------------------------------------
# TEACHER DASHBOARD SHORTCUTS
# -------------------------------------------------------

teacher_dashboard_shortcuts = |model| {
    Html.div([Attribute.class("p-6 md:p-8 space-y-8")], [
        Html.div([], [
            Html.h1([Attribute.class("text-3xl font-bold tracking-tight")], [
                Html.text(
                    if Str.is_empty(model.userName) { "Welcome, Teacher!" }
                    else { "Welcome, ${model.userName}!" }
                )
            ]),
            Html.p([Attribute.class("text-muted-foreground mt-1")], [Html.text("Manage your classes, lessons, and student assessments.")])
        ]),

        Html.div([Attribute.class("grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4")], [
            # My Classes
            Html.div([
                Attribute.class("group rounded-xl border bg-card p-6 space-y-4 hover:shadow-md hover:border-primary/30 transition-all cursor-pointer"),
                Attribute.on_click(NavigateTo(TeacherMyClasses))
            ], [
                Html.div([Attribute.class("flex items-center justify-between")], [
                    Html.div([Attribute.class("w-12 h-12 rounded-xl bg-blue-50 dark:bg-blue-900/20 flex items-center justify-center text-2xl")], [Html.text("📖")]),
                    Html.span([Attribute.class("text-xs text-muted-foreground bg-muted rounded-full px-2 py-0.5")], [Html.text("LMS")])
                ]),
                Html.div([Attribute.class("space-y-1")], [
                    Html.h3([Attribute.class("font-semibold text-foreground group-hover:text-primary transition-colors")], [Html.text("My Classes")]),
                    Html.p([Attribute.class("text-sm text-muted-foreground")], [Html.text("View teaching assignments and manage lesson content.")])
                ])
            ]),

            # Assessments & Grading
            Html.div([
                Attribute.class("group rounded-xl border bg-card p-6 space-y-4 hover:shadow-md hover:border-primary/30 transition-all cursor-pointer"),
                Attribute.on_click(NavigateTo(TeacherAssessments))
            ], [
                Html.div([Attribute.class("flex items-center justify-between")], [
                    Html.div([Attribute.class("w-12 h-12 rounded-xl bg-amber-50 dark:bg-amber-900/20 flex items-center justify-center text-2xl")], [Html.text("📊")]),
                    Html.span([Attribute.class("text-xs text-muted-foreground bg-muted rounded-full px-2 py-0.5")], [Html.text("Grading")])
                ]),
                Html.div([Attribute.class("space-y-1")], [
                    Html.h3([Attribute.class("font-semibold text-foreground group-hover:text-primary transition-colors")], [Html.text("Assessments & Grading")]),
                    Html.p([Attribute.class("text-sm text-muted-foreground")], [Html.text("Create quizzes, review submissions, and release grades.")])
                ])
            ]),

            # Messaging
            Html.div([
                Attribute.class("group rounded-xl border bg-card p-6 space-y-4 hover:shadow-md hover:border-primary/30 transition-all cursor-pointer"),
                Attribute.on_click(NavigateTo(Messaging))
            ], [
                Html.div([Attribute.class("flex items-center justify-between")], [
                    Html.div([Attribute.class("w-12 h-12 rounded-xl bg-green-50 dark:bg-green-900/20 flex items-center justify-center text-2xl")], [Html.text("💬")]),
                    Html.span([Attribute.class("text-xs text-muted-foreground bg-muted rounded-full px-2 py-0.5")], [Html.text("Messages")])
                ]),
                Html.div([Attribute.class("space-y-1")], [
                    Html.h3([Attribute.class("font-semibold text-foreground group-hover:text-primary transition-colors")], [Html.text("Messaging")]),
                    Html.p([Attribute.class("text-sm text-muted-foreground")], [Html.text("Class announcements and school-wide communications.")])
                ])
            ])
        ])
    ])
}
