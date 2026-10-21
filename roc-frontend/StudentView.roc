
import html.Html
import html.Attribute

import UI
import State exposing [Model, Msg, list_state]
StudentView := [].{

# The name a drill view shows for a record link: read from the fetched list carrying the names
# (id|name|…), falling back to the name the click that opened the drill already set while the list
# is on its way. The fallback is what a reload or a back/forward needs: the URL restores the ids,
# and the names arrive with the lists (see the StudentLesson boot and popstate paths in State).
drill_name = |list_data, record_id, fallback| {
    if Str.is_empty(fallback) {
        drill_lookup(list_data, record_id)
    } else {
        fallback
    }
}

drill_lookup = |list_data, record_id| {
    List.fold(Str.split_on(list_data, "\n"), "", |found, line| {
        parts = Str.split_on(line, "|")
        id = match List.get(parts, 0) { Ok(v) => v, Err(_) => "" }
        name = match List.get(parts, 1) { Ok(v) => v, Err(_) => "" }
        if id == record_id { name } else { found }
    })
}

view = |model| {
    match model.route {
        StudentSubjects => student_learning_frame(model, student_subjects_view(model))
        StudentLesson => student_learning_frame(model, student_lesson_drilldown(model))
        StudentAssignments => student_assignments_view(model)
        _ => student_dashboard_shortcuts(model)
    }
}

# A stable frame for the pupil's two learning pages, in the admin LMS's own shape: the outer div and
# the lists' hidden inputs stay put while the page or the drill step changes inside. The inputs have
# to live here rather than in the page that shows them: a step restored from the URL (every exit
# from the lesson view is a real reload — see the lesson-page rule in State) draws its names from
# these lists, and a payload for an input that is not on screen is dropped.
student_learning_frame = |model, step| {
    Html.div([Attribute.class("p-4 sm:p-6 md:p-8 space-y-6")], [
        Html.input([
            Attribute.type("hidden"),
            Attribute.id("subjects_data_input"),
            Attribute.value(model.subjectsData),
            Attribute.on_input(|s| GotSubjectsData(s))
        ]),
        Html.input([
            Attribute.type("hidden"),
            Attribute.id("student_terms_data_input"),
            Attribute.value(model.studentTermsData),
            Attribute.on_input(|s| GotStudentTermsData(s))
        ]),
        Html.input([
            Attribute.type("hidden"),
            Attribute.id("student_lessons_data_input"),
            Attribute.value(model.studentLessonsData),
            Attribute.on_input(|s| GotStudentLessonsData(s))
        ]),
        step
    ])
}

# -------------------------------------------------------
# SUBJECT SELECTION (Step 1 — picks a subject)
# -------------------------------------------------------

student_subjects_view = |model| {
    Html.div([Attribute.class("space-y-6")], [
        Html.div([], [
            Html.h1([Attribute.class("text-2xl sm:text-3xl font-bold tracking-tight")], [Html.text("My Subjects")]),
            Html.p([Attribute.class("text-muted-foreground mt-1")], [Html.text("Select a subject to browse its terms and lessons.")])
        ]),

        # The subjects list in its three states: skeleton placeholders while it has not been
        # answered, the backend's own message with a retry when it failed, and the cards once it
        # loaded (or a real empty state when it holds no rows).
        match list_state(model.subjectsData) {
            Pending =>
                Html.div([Attribute.class("grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4")], [
                    subject_skeleton(""),
                    subject_skeleton(""),
                    subject_skeleton("")
                ])
            Failed(message) => UI.list_error_state("Could not load your subjects", message, Click(RetryList("/api/student/subjects")))
            Ready(rows) =>
                if List.is_empty(rows) {
                    UI.list_empty_state("book-open", "No subjects yet", "Your subjects appear here once your class is set up.")
                } else {
                    Html.div([Attribute.class("grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4")],
                        List.map(rows, |line| {
                            parts = Str.split_on(line, "|")
                            id   = match List.get(parts, 0) { Ok(v) => v, Err(_) => "" }
                            name = match List.get(parts, 1) { Ok(v) => v, Err(_) => "Unknown Subject" }
                            code = match List.get(parts, 2) { Ok(v) => v, Err(_) => "" }
                            subject_card(id, name, code)
                        })
                    )
                }
        }
    ])
}

subject_skeleton = |_| {
    Html.div([Attribute.class("rounded-lg border bg-card p-6 space-y-3 animate-pulse")], [
        Html.div([Attribute.class("h-10 w-10 rounded-xl bg-muted")], []),
        Html.div([Attribute.class("h-4 w-32 rounded bg-muted")], []),
        Html.div([Attribute.class("h-3 w-16 rounded bg-muted")], []),
        Html.div([Attribute.class("h-8 w-24 rounded bg-muted mt-2")], [])
    ])
}

subject_card = |id, name, code| {
    UI.pressable(
        { ..UI.default_pressable, classes: "group rounded-lg border bg-card p-6 space-y-4 hover:shadow-md hover:border-primary/30 transition-all", label: "", is_nav: Bool.True },
        SelectSubject(id, name),
        [
        Html.div([Attribute.class("w-12 h-12 rounded-xl bg-primary/10 flex items-center justify-center text-2xl")], [Html.text("📚")]),
        Html.div([Attribute.class("space-y-0.5")], [
            Html.h3([Attribute.class("font-semibold text-foreground group-hover:text-primary transition-colors")], [Html.text(name)]),
            Html.p([Attribute.class("text-xs text-muted-foreground font-mono")], [Html.text(if Str.is_empty(code) { "—" } else { code })])
        ]),
        Html.div([Attribute.class("flex items-center text-sm text-primary font-medium gap-1")], [
            Html.text("View Terms & Lessons"),
            Html.span([Attribute.class("text-xs group-hover:translate-x-1 transition-transform")], [Html.text("→")])
        ])
    ])
}

# -------------------------------------------------------
# LESSON DRILL-DOWN (Step 2/3/4 — terms → lessons → content)
# -------------------------------------------------------

student_lesson_drilldown = |model| {
    # The four steps of the drill, one slot in the pupil's stable frame (see student_learning_frame).
    if !Str.is_empty(model.selectedLessonId) {
        # Step 4 — Lesson content view
        student_lesson_content_view(model)
    } else if !Str.is_empty(model.selectedTermId) {
        # Step 3 — Lessons list for selected term
        student_lessons_list_view(model)
    } else if !Str.is_empty(model.selectedSubjectId) {
        # Step 2 — Terms list for selected subject
        student_terms_view(model)
    } else {
        # No state — redirect user back to subjects
        Html.div([Attribute.class("p-4 sm:p-6 md:p-8 space-y-4")], [
            Html.div([Attribute.class("flex items-center gap-2 text-sm text-muted-foreground")], [
                UI.link({ ..UI.default_link, classes: "hover:text-foreground", href: State.route_path(StudentSubjects) }, BackToSubjects, [Html.text("← Back to My Subjects")])
            ]),
            Html.div([Attribute.class("text-center py-16 text-muted-foreground space-y-3")], [
                Html.div([Attribute.class("text-5xl")], [Html.text("📚")]),
                Html.h3([Attribute.class("font-semibold text-lg")], [Html.text("No subject selected")]),
                Html.p([Attribute.class("text-sm")], [Html.text("Choose a subject from My Subjects to get started.")]),
                Html.div([Attribute.class("pt-2")], [
                    UI.link({ ..UI.default_link, classes: "inline-flex items-center gap-2 rounded-md bg-primary text-primary-foreground px-4 py-2 text-sm font-medium hover:bg-primary/90 transition", href: State.route_path(StudentSubjects) }, BackToSubjects, [Html.text("Go to My Subjects")])
                ])
            ])
        ])
    }
}

# -------------------------------------------------------
# STEP 2 — TERMS LIST
# -------------------------------------------------------

student_terms_view = |model| {
    Html.div([Attribute.class("space-y-6")], [
        # Breadcrumb nav
        Html.div([Attribute.class("flex items-center gap-2 text-sm text-muted-foreground")], [
            UI.link({ ..UI.default_link, classes: "hover:text-foreground", href: State.route_path(StudentSubjects) }, BackToSubjects, [Html.text("My Subjects")]),
            Html.span([Attribute.class("text-border")], [Html.text("›")]),
            Html.span([Attribute.class("text-foreground font-medium")], [Html.text(drill_name(model.subjectsData, model.selectedSubjectId, model.selectedSubjectName))])
        ]),

        Html.div([], [
            Html.h1([Attribute.class("text-2xl sm:text-3xl font-bold tracking-tight")], [Html.text(drill_name(model.subjectsData, model.selectedSubjectId, model.selectedSubjectName))]),
            Html.p([Attribute.class("text-muted-foreground mt-1")], [Html.text("Choose a term to view its lessons.")])
        ]),

        # The terms list in its three states, like the subjects above it.
        match list_state(model.studentTermsData) {
            Pending =>
                Html.div([Attribute.class("grid grid-cols-1 md:grid-cols-3 gap-4")], [
                    term_skeleton(""),
                    term_skeleton(""),
                    term_skeleton("")
                ])
            Failed(message) => UI.list_error_state("Could not load the terms", message, Click(RetryList("/api/student/terms")))
            Ready(rows) =>
                if List.is_empty(rows) {
                    UI.list_empty_state("calendar", "No terms yet", "Your school's terms appear here once they are published.")
                } else {
                    Html.div([Attribute.class("grid grid-cols-1 md:grid-cols-3 gap-4")],
                        List.map(rows, |line| {
                            parts = Str.split_on(line, "|")
                            id   = match List.get(parts, 0) { Ok(v) => v, Err(_) => "" }
                            name = match List.get(parts, 1) { Ok(v) => v, Err(_) => "Term" }
                            num  = match List.get(parts, 2) { Ok(v) => v, Err(_) => "" }
                            term_card(id, name, num)
                        })
                    )
                }
        }
    ])
}

term_skeleton = |_| {
    Html.div([Attribute.class("rounded-lg border bg-card p-6 space-y-3 animate-pulse")], [
        Html.div([Attribute.class("h-10 w-10 rounded-xl bg-muted")], []),
        Html.div([Attribute.class("h-4 w-28 rounded bg-muted")], []),
        Html.div([Attribute.class("h-8 w-24 rounded bg-muted mt-2")], [])
    ])
}

term_card = |id, name, num| {
    icon = match num {
        "1" => "🌱"
        "2" => "🌻"
        "3" => "🍂"
        _ => "📅"
    }
    UI.pressable(
        { ..UI.default_pressable, classes: "group rounded-lg border bg-card p-6 space-y-4 hover:shadow-md hover:border-primary/30 transition-all", label: "", is_nav: Bool.True },
        SelectTerm(id, name),
        [
        Html.div([Attribute.class("w-12 h-12 rounded-xl bg-primary/10 flex items-center justify-center text-2xl")], [Html.text(icon)]),
        Html.div([Attribute.class("space-y-0.5")], [
            Html.h3([Attribute.class("font-semibold text-foreground group-hover:text-primary transition-colors")], [Html.text(name)]),
            Html.p([Attribute.class("text-xs text-muted-foreground")], [Html.text("Click to view lessons")])
        ]),
        Html.div([Attribute.class("flex items-center text-sm text-primary font-medium gap-1")], [
            Html.text("View Lessons"),
            Html.span([Attribute.class("text-xs group-hover:translate-x-1 transition-transform")], [Html.text("→")])
        ])
    ])
}

# -------------------------------------------------------
# STEP 3 — LESSONS LIST
# -------------------------------------------------------

student_lessons_list_view = |model| {
    Html.div([Attribute.class("space-y-6")], [
        # Breadcrumb nav
        Html.div([Attribute.class("flex items-center gap-2 text-sm text-muted-foreground flex-wrap")], [
            UI.link({ ..UI.default_link, classes: "hover:text-foreground", href: State.route_path(StudentSubjects) }, BackToSubjects, [Html.text("My Subjects")]),
            Html.span([Attribute.class("text-border")], [Html.text("›")]),
            UI.link({ ..UI.default_link, classes: "hover:text-foreground", href: State.route_path(StudentLesson) }, BackToTerms, [Html.text(drill_name(model.subjectsData, model.selectedSubjectId, model.selectedSubjectName))]),
            Html.span([Attribute.class("text-border")], [Html.text("›")]),
            Html.span([Attribute.class("text-foreground font-medium")], [Html.text(drill_name(model.studentTermsData, model.selectedTermId, model.selectedTermName))])
        ]),

        Html.div([], [
            Html.h1([Attribute.class("text-2xl sm:text-3xl font-bold tracking-tight")], [Html.text(drill_name(model.studentTermsData, model.selectedTermId, model.selectedTermName))]),
            Html.p([Attribute.class("text-muted-foreground mt-1")], [
                Html.text(drill_name(model.subjectsData, model.selectedSubjectId, model.selectedSubjectName))
            ])
        ]),

        # The lessons list in its three states, like the subjects above it.
        match list_state(model.studentLessonsData) {
            Pending =>
                Html.div([Attribute.class("space-y-3")], [
                    lesson_list_skeleton(""),
                    lesson_list_skeleton(""),
                    lesson_list_skeleton("")
                ])
            Failed(message) => UI.list_error_state("Could not load the lessons", message, Click(RetryList("/api/student/lessons?subject_id=${model.selectedSubjectId}&term_id=${model.selectedTermId}")))
            Ready(rows) =>
                if List.is_empty(rows) {
                    UI.list_empty_state("book-open", "No lessons yet", "Lessons for this term appear here once they are published.")
                } else {
                    Html.div([Attribute.class("space-y-3")],
                        List.map_with_index(rows, |line, idx| {
                            parts = Str.split_on(line, "|")
                            id    = match List.get(parts, 0) { Ok(v) => v, Err(_) => "" }
                            title = match List.get(parts, 1) { Ok(v) => v, Err(_) => "Lesson" }
                            week  = match List.get(parts, 2) { Ok(v) => v, Err(_) => "" }
                            lesson_list_row(id, title, week, idx)
                        })
                    )
                }
        }
    ])
}

lesson_list_skeleton = |_| {
    Html.div([Attribute.class("rounded-lg border bg-card p-4 space-y-2 animate-pulse")], [
        Html.div([Attribute.class("flex items-center gap-4")], [
            Html.div([Attribute.class("h-8 w-8 rounded-full bg-muted")], []),
            Html.div([Attribute.class("flex-1 space-y-1.5")], [
                Html.div([Attribute.class("h-4 w-48 rounded bg-muted")], []),
                Html.div([Attribute.class("h-3 w-20 rounded bg-muted")], [])
            ])
        ])
    ])
}

idx_to_str = |n| {
    match n {
        0 => "1"
        1 => "2"
        2 => "3"
        3 => "4"
        4 => "5"
        5 => "6"
        6 => "7"
        7 => "8"
        8 => "9"
        9 => "10"
        10 => "11"
        11 => "12"
        12 => "13"
        13 => "14"
        14 => "15"
        15 => "16"
        16 => "17"
        17 => "18"
        18 => "19"
        19 => "20"
        _ => "..."
    }
}

lesson_list_row = |id, title, week, idx| {
    n = idx_to_str(idx)
    UI.pressable(
        { ..UI.default_pressable, classes: "group rounded-lg border bg-card p-4 flex items-center gap-4 hover:shadow-sm hover:border-primary/30 transition-all", label: "", is_nav: Bool.True },
        SelectLesson(id),
        [
        Html.div([Attribute.class("flex-shrink-0 w-9 h-9 rounded-full bg-primary/10 flex items-center justify-center text-sm font-bold text-primary")], [
            Html.text(n)
        ]),
        Html.div([Attribute.class("flex-1 min-w-0")], [
            Html.h3([Attribute.class("font-medium text-foreground group-hover:text-primary transition-colors truncate")], [Html.text(title)]),
            Html.p([Attribute.class("text-xs text-muted-foreground")], [
                Html.text(if Str.is_empty(week) { "Lesson ${n}" } else { "Week ${week}" })
            ])
        ]),
        Html.span([Attribute.class("text-muted-foreground text-sm group-hover:text-primary transition-colors")], [Html.text("→")])
    ])
}

# -------------------------------------------------------
# STEP 4 — LESSON CONTENT VIEWER (beautiful LMS)
# -------------------------------------------------------

student_lesson_content_view = |model| {
    Html.div([Attribute.class("relative")], [
        Html.div([Attribute.class("flex min-h-screen")], [
            Html.div([Attribute.class("flex-1 min-w-0 w-full max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8")], [

                # Hidden input — JS writes JSON lesson content here, Roc picks it up
                Html.input([
                    Attribute.type("hidden"),
                    Attribute.id("lesson_content_data_input"),
                    Attribute.value(model.currentLessonContent),
                    Attribute.on_input(|s| GotLessonContent(s))
                ]),

                # Breadcrumb nav
                Html.div([Attribute.class("flex items-center gap-2 text-sm text-muted-foreground flex-wrap")], [
                    # The crumbs leave the lesson page for real (see the lesson-page navigation rule in
                    # State): the subject's goes to that subject's terms, the term's to that term's
                    # lessons, and the hrefs carry the step the reload will restore from the address
                    # bar.
                    UI.link({ ..UI.default_link, classes: "hover:text-foreground", href: State.route_path(StudentSubjects) }, BackToSubjects, [Html.text("My Subjects")]),
                    Html.span([Attribute.class("text-border")], [Html.text("›")]),
                    UI.link({ ..UI.default_link, classes: "hover:text-foreground", href: "/student/lesson?subject=${model.selectedSubjectId}" }, BackToTerms, [Html.text(drill_name(model.subjectsData, model.selectedSubjectId, model.selectedSubjectName))]),
                    Html.span([Attribute.class("text-border")], [Html.text("›")]),
                    UI.link({ ..UI.default_link, classes: "hover:text-foreground", href: "/student/lesson?subject=${model.selectedSubjectId}&term=${model.selectedTermId}" }, BackToLessons, [Html.text(drill_name(model.studentTermsData, model.selectedTermId, model.selectedTermName))]),
                    Html.span([Attribute.class("text-border")], [Html.text("›")]),
                    Html.span([Attribute.class("text-foreground font-medium truncate max-w-xs")], [Html.text("Lesson")])
                ]),

                # Lesson header — populated by JS when currentLessonContent arrives
                Html.div([Attribute.id("lesson-header"), Attribute.class("space-y-3")], [
                    Html.div([Attribute.class("flex items-start justify-between gap-6")], [
                        Html.div([Attribute.class("space-y-2")], [
                            Html.div([
                                Attribute.id("lesson-title"),
                                Attribute.class("text-3xl font-bold text-primary leading-tight")
                            ], [lesson_title_placeholder(model)]),
                            Html.div([
                                Attribute.id("lesson-meta"),
                                Attribute.class("text-sm text-muted-foreground font-medium tracking-wide uppercase")
                            ], [Html.text("${drill_name(model.subjectsData, model.selectedSubjectId, model.selectedSubjectName)} · ${drill_name(model.studentTermsData, model.selectedTermId, model.selectedTermName)}")])
                        ]),
                        Html.div([Attribute.id("lesson-week-badge"), Attribute.class("")], [])
                    ])
                ]),

                # Tab bar: Lesson | Assessments
                Html.div([Attribute.class("flex border-b border-border"), Attribute.role("tablist")], [
                    Html.button([
                        Attribute.id("tab-lesson"),
                        Attribute.role("tab"),
                        Attribute.aria("selected", "true"),
                        Attribute.class("px-4 py-2 text-sm border-b-2 border-primary text-primary font-medium transition cursor-pointer"),
                        Attribute.type("button")
                    ], [Html.text("Lesson")]),
                    Html.button([
                        Attribute.id("tab-assessments"),
                        Attribute.role("tab"),
                        Attribute.aria("selected", "false"),
                        Attribute.class("px-4 py-2 text-sm border-b-2 border-transparent text-muted-foreground hover:text-foreground transition cursor-pointer"),
                        Attribute.type("button")
                    ], [Html.text("Assessments")])
                ]),

                # Lesson content panel — JS renders section cards here; before it does, the panel
                # shows what state the lesson fetch is in.
                Html.div([Attribute.id("lesson-panel"), Attribute.class("space-y-8 pb-16")], [
                    lesson_content_panel(model)
                ]),

                # Assessments panel
                Html.div([Attribute.id("assessments-panel"), Attribute.class("hidden space-y-4 pb-16")], [
                    Html.h2([Attribute.class("text-xl font-bold text-primary")], [Html.text("Assessments")]),
                    Html.div([Attribute.id("assessments-list")], [
                        UI.list_skeleton_cards(["w-40", "w-24"])
                    ])
                ])
            ]),

            # Right-side sticky dot section navigator (populated by JS). The panel sits IN FLOW
            # beside the dots — not absolutely positioned outside the hover group — so moving the
            # pointer from the dots into the box (across the mr-3 gap) never leaves the group and
            # the box cannot vanish mid-way.
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

# The lesson title while the content is on its way, and what to say when it could not be read.
lesson_title_placeholder = |model| {
    match list_state(model.currentLessonContent) {
        Pending => UI.skeleton_bar("h-8 w-64")
        Failed(_) => Html.text("Lesson unavailable")
        Ready(_) => Html.text("Lesson")
    }
}

# The lesson panel before the page's JavaScript has rendered the lesson into it: skeleton sections
# while the content is on its way, and the backend's own message with a retry when it failed.
lesson_content_panel = |model| {
    match list_state(model.currentLessonContent) {
        Pending =>
            Html.div([Attribute.class("space-y-8")], [
                Html.div([Attribute.class("space-y-3")], [
                    UI.skeleton_bar("h-5 w-40"),
                    UI.skeleton_bar("h-4 w-full"),
                    UI.skeleton_bar("h-4 w-5/6"),
                    UI.skeleton_bar("h-4 w-2/3")
                ]),
                Html.div([Attribute.class("space-y-3")], [
                    UI.skeleton_bar("h-5 w-48"),
                    UI.skeleton_bar("h-4 w-3/4"),
                    UI.skeleton_bar("h-4 w-1/2")
                ])
            ])

        Failed(message) => UI.list_error_state("Could not load the lesson", message, Click(RetryList("/api/student/lesson?lesson_id=${model.selectedLessonId}")))

        Ready(_) => Html.div([Attribute.class("text-sm text-muted-foreground")], [Html.text("Rendering content...")])
    }
}

# -------------------------------------------------------
# ASSIGNMENTS VIEW
# -------------------------------------------------------

student_assignments_view = |_model| {
    Html.div([Attribute.class("p-4 sm:p-6 md:p-8 space-y-6")], [
        Html.div([], [
            Html.h1([Attribute.class("text-2xl sm:text-3xl font-bold tracking-tight")], [Html.text("My Assignments")]),
            Html.p([Attribute.class("text-muted-foreground mt-1")], [Html.text("View and submit your assessments and assignments.")])
        ]),

        # Term-weighted general assessments first, then the assessments attached to individual
        # lessons. Both lists are filled by the JS in www/index.html.
        Html.div([Attribute.class("flex border-b border-border"), Attribute.role("tablist")], [
            Html.button([
                Attribute.id("tab-general-assessments"),
                Attribute.role("tab"),
                Attribute.aria("selected", "true"),
                Attribute.class("px-4 py-2 text-sm border-b-2 border-primary text-primary font-medium transition cursor-pointer"),
                Attribute.type("button"),
                # A tab switch changes the view: data-nav starts the top border progress bar.
                Attribute.data("nav", "")
            ], [Html.text("General Assessments")]),
            Html.button([
                Attribute.id("tab-lesson-assessments"),
                Attribute.role("tab"),
                Attribute.aria("selected", "false"),
                Attribute.class("px-4 py-2 text-sm border-b-2 border-transparent text-muted-foreground hover:text-foreground transition cursor-pointer"),
                Attribute.type("button"),
                Attribute.data("nav", "")
            ], [Html.text("Lesson Assessments")])
        ]),

        Html.div([Attribute.id("general-assessments-panel"), Attribute.class("space-y-4 pb-16")], [
            Html.div([Attribute.id("general-assessments-list")], [
                UI.list_skeleton_cards(["w-40", "w-24"])
            ])
        ]),

        Html.div([Attribute.id("assessments-panel"), Attribute.class("hidden space-y-4 pb-16")], [
            Html.div([Attribute.id("assessments-list")], [
                UI.list_skeleton_cards(["w-40", "w-24"])
            ])
        ])
    ])
}

# -------------------------------------------------------
# STUDENT DASHBOARD SHORTCUTS
# -------------------------------------------------------

student_dashboard_shortcuts = |model| {
    Html.div([Attribute.class("p-4 sm:p-6 md:p-8 space-y-8")], [
        Html.div([], [
            Html.h1([Attribute.class("text-2xl sm:text-3xl font-bold tracking-tight")], [
                Html.text(
                    if Str.is_empty(model.userName) { "Welcome, Student!" }
                    else { "Welcome, ${model.userName}!" }
                )
            ]),
            Html.p([Attribute.class("text-muted-foreground mt-1")], [Html.text("Here's your learning overview for today.")])
        ]),
        Html.div([Attribute.class("grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4")], [
            UI.link(
                { ..UI.default_link, classes: "group rounded-xl border bg-card p-6 space-y-4 hover:shadow-md hover:border-primary/30 transition-all", href: State.route_path(StudentSubjects) },
                NavigateTo(StudentSubjects),
                [
                Html.div([Attribute.class("flex items-center justify-between")], [
                    Html.div([Attribute.class("w-12 h-12 rounded-xl bg-blue-50 dark:bg-blue-900/20 flex items-center justify-center text-2xl")], [Html.text("📚")]),
                    Html.span([Attribute.class("text-xs text-muted-foreground bg-muted rounded-full px-2 py-0.5")], [Html.text("LMS")])
                ]),
                Html.div([Attribute.class("space-y-1")], [
                    Html.h3([Attribute.class("font-semibold text-foreground group-hover:text-primary transition-colors")], [Html.text("My Subjects")]),
                    Html.p([Attribute.class("text-sm text-muted-foreground")], [Html.text("Browse lessons, study materials, and section notes.")])
                ])
            ]),
            UI.link(
                { ..UI.default_link, classes: "group rounded-xl border bg-card p-6 space-y-4 hover:shadow-md hover:border-primary/30 transition-all", href: State.route_path(StudentAssignments) },
                NavigateTo(StudentAssignments),
                [
                Html.div([Attribute.class("flex items-center justify-between")], [
                    Html.div([Attribute.class("w-12 h-12 rounded-xl bg-amber-50 dark:bg-amber-900/20 flex items-center justify-center text-2xl")], [Html.text("📝")]),
                    Html.span([Attribute.class("text-xs text-muted-foreground bg-muted rounded-full px-2 py-0.5")], [Html.text("Assessments")])
                ]),
                Html.div([Attribute.class("space-y-1")], [
                    Html.h3([Attribute.class("font-semibold text-foreground group-hover:text-primary transition-colors")], [Html.text("Assignments")]),
                    Html.p([Attribute.class("text-sm text-muted-foreground")], [Html.text("View pending assessments and submit your work.")])
                ])
            ]),
            UI.link(
                { ..UI.default_link, classes: "group rounded-xl border bg-card p-6 space-y-4 hover:shadow-md hover:border-primary/30 transition-all", href: State.route_path(Messaging) },
                NavigateTo(Messaging),
                [
                Html.div([Attribute.class("flex items-center justify-between")], [
                    Html.div([Attribute.class("w-12 h-12 rounded-xl bg-green-50 dark:bg-green-900/20 flex items-center justify-center text-2xl")], [Html.text("💬")]),
                    Html.span([Attribute.class("text-xs text-muted-foreground bg-muted rounded-full px-2 py-0.5")], [Html.text("Messages")])
                ]),
                Html.div([Attribute.class("space-y-1")], [
                    Html.h3([Attribute.class("font-semibold text-foreground group-hover:text-primary transition-colors")], [Html.text("Messaging")]),
                    Html.p([Attribute.class("text-sm text-muted-foreground")], [Html.text("School announcements and direct messages.")])
                ])
            ])
        ])
    ])
}

}