app [Model, Msg, init, update, render, subscriptions] {
        # Joy 0.34.0 (release bundle): fixes the host allocator bug that used to crash this app
        # once its model grew (the boxy runtime grows memory behind the host's back; see the
        # retired JOY_HOST_PATCH.md). The vendored patched 0.33.0 checkout in joy/ is gone.
        pf: platform "https://github.com/niclas-ahden/joy/releases/download/0.34.0/2B3sC6U2dWkVUK2VY2gJS5Wej9YCDo3ZYq2e7tMWUCNp.tar.zst",
        html: "https://github.com/niclas-ahden/joy-html/releases/download/0.17.0/AcmwFzyfbsf5RALWNdX6cXw1cuuDXt96YfcysNqgFqoG.tar.zst",
}

import html.Html exposing [div, h1, p, text, a, span]
import html.Attribute exposing [class]
import pf.DOM
import pf.Sub

import State exposing [Route, list_state]
import UI

import DashboardView
import SettingsView
import AdminView
import TeacherView
import StudentView
import MessagingView

Model : State.Model
Msg : State.Msg

init = State.init

subscriptions : Model -> List(Sub(Msg))
subscriptions = |_model| [
	DOM.on_url_change(|url| UrlChanged(url))
]

update = State.update

# --- The notifications bell's dropdown content ---
# The page's JS keeps the toast history and serializes it here one "kind|title|message" line at a
# time (see formatNotifications in www/index.html) — the same bridge every other fetched list uses,
# so the badge and the panel are rendered by the vdom like everything else instead of being poked
# into this subtree directly (that bypassed the vdom's own tracking of it and corrupted later
# patches elsewhere on the page).
notification_lines = |data| List.drop_if(Str.split_on(data, "\n"), Str.is_empty)

notification_badge = |data| {
	n = List.len(notification_lines(data))
	count_text = if n > 99 { "99+" } else { U64.to_str(n) }
	span(
		[class(if n > 0 { "absolute -top-1 -right-1 h-4 min-w-4 px-1 rounded-full bg-destructive text-destructive-foreground text-[10px] flex items-center justify-center" } else { "hidden" })],
		[text(count_text)]
	)
}

notification_entry = |line| {
	parts = Str.split_on(line, "|")
	title = match List.get(parts, 1) { Ok(v) => v, Err(_) => "" }
	message = match List.get(parts, 2) { Ok(v) => v, Err(_) => "" }
	div([class("px-3 py-2 border-b border-border/50")], List.concat(
		[p([class("text-sm font-medium")], [text(title)])],
		if Str.is_empty(message) { [] } else { [p([class("text-xs text-muted-foreground")], [text(message)])] }
	))
}

notifications_panel_body = |model| {
	lines = notification_lines(model.notificationsData)
	if List.is_empty(lines) {
		[div([class("p-3 text-sm text-muted-foreground")], [text("No notifications yet.")])]
	} else {
		List.concat(
			[
				div([class("p-2 border-b flex items-center justify-between")], [
					span([class("text-xs font-medium")], [text("Notifications")]),
					UI.button({ ..UI.default_button, variant: Ghost, size: Sm, on_click: Click(ClearNotifications), classes: "text-xs text-destructive h-auto py-0" }, [text("Clear all")])
				])
			],
			List.map(lines, notification_entry)
		)
	}
}

render : Model -> Html(Msg)
render = |model| {
	theme_class =
		match model.theme {
			Dark => "dark flex h-screen w-screen overflow-hidden bg-background text-foreground font-sans"
			Light => "flex h-screen w-screen overflow-hidden bg-background text-foreground font-sans"
		}

	# Sidebar Navigation Items
	sidebar_navs =
	if model.passwordRequired {
		# A password change is owed: the shell offers one page, because the backend refuses every
		# other route (see password_change_cleared! in main.roc). Signing out stays in the avatar menu.
		[
			UI.sidebar_nav_item({ ..UI.default_sidebar_nav_item, is_active: model.route == Settings, on_click: Click(NavigateTo(Settings)) }, [text("Settings")])
		]
	} else {
				List.concat(
			[
				UI.sidebar_nav_item({ ..UI.default_sidebar_nav_item, is_active: model.route == Dashboard, on_click: Click(NavigateTo(Dashboard)) }, [text("Dashboard")])
			],
			match model.role {
				Admin => {
			                                        # An administrator's own sidebar follows the permissions their row carries: a
			                                        # supervisor (the LMS and assessments, no user management) is not offered a
			                                        # screen the backend would refuse. Each item names the permission it needs —
			                                        # the same keys the backend's own gate asks for — and Messaging is every
			                                        # role's, so it stays.
			                                        items = [
			                                                { permission: "users.manage", route: AdminUserManagement, label: "User Management" },
			                                                { permission: "setup.manage", route: AdminConfigurationHub, label: "Configuration Hub" },
			                                                { permission: "lessons.manage", route: AdminLMS, label: "LMS" },
			                                        ]
			                                        shown = List.keep_if(items, |item| State.caller_has_permission(model, item.permission))

			                                        List.concat(
			                                                List.map(shown, |item| {
			                                                        UI.sidebar_nav_item(
			                                                                { ..UI.default_sidebar_nav_item, is_active: model.route == item.route, on_click: Click(NavigateTo(item.route)) },
			                                                                [text(item.label)]
			                                                        )
			                                                }),
			                                                [UI.sidebar_nav_item({ ..UI.default_sidebar_nav_item, is_active: model.route == Messaging, on_click: Click(NavigateTo(Messaging)) }, [text("Messaging")])]
			                                        )
			                                }
				Teacher => [
					UI.sidebar_nav_item({ ..UI.default_sidebar_nav_item, is_active: model.route == TeacherMyClasses, on_click: Click(NavigateTo(TeacherMyClasses)) }, [text("My Classes")]),
					UI.sidebar_nav_item({ ..UI.default_sidebar_nav_item, is_active: model.route == TeacherAssessments, on_click: Click(NavigateTo(TeacherAssessments)) }, [text("Assessments & Grading")]),
					UI.sidebar_nav_item({ ..UI.default_sidebar_nav_item, is_active: model.route == Messaging, on_click: Click(NavigateTo(Messaging)) }, [text("Messaging")])
				]
				Student => [
					UI.sidebar_nav_item({ ..UI.default_sidebar_nav_item, is_active: model.route == StudentSubjects, on_click: Click(NavigateTo(StudentSubjects)) }, [text("My Subjects")]),
					UI.sidebar_nav_item({ ..UI.default_sidebar_nav_item, is_active: model.route == Messaging, on_click: Click(NavigateTo(Messaging)) }, [text("Messaging")])
				]
				Parent => [
					UI.sidebar_nav_item({ ..UI.default_sidebar_nav_item, is_active: model.route == Dashboard, on_click: Click(NavigateTo(Dashboard)) }, [text("My Children")]),
					UI.sidebar_nav_item({ ..UI.default_sidebar_nav_item, is_active: model.route == Messaging, on_click: Click(NavigateTo(Messaging)) }, [text("Messaging")])
				]
				Unauthenticated => []
			}
		)
	}

	# User initials for avatar
	user_initial =
		if Str.is_empty(model.userName) {
			match model.role { Admin => "A", Teacher => "T", Student => "S", Parent => "P", _ => "U" }
		} else {
			match Str.to_utf8(model.userName) |> List.first {
				Ok(b) => match Str.from_utf8([b]) { Ok(s) => s, Err(_) => "U" }
				Err(_) => "U"
			}
		}

	user_display_name =
		if Str.is_empty(model.userName) {
			match model.role { Admin => "Admin User", Teacher => "Teacher", Student => "Student", Parent => "Parent", _ => "User" }
		} else {
			model.userName
		}

	user_display_email =
		if Str.is_empty(model.userEmail) { "user@school.com" } else { model.userEmail }

	# Sidebar Header Content
	sidebar_header_content =
		UI.sidebar_header({ classes: "p-0 border-b shrink-0 flex items-center h-16" }, [
			Html.div([Attribute.class("flex items-center justify-center px-4 py-2 w-full")], [
				                            Html.img([Attribute.src("/logo.jpg"), Attribute.alt("Johnethel School"), Attribute.class("h-10 object-contain")])
			])
		])

	# Sidebar User Footer
	sidebar_user_footer =
		div([class("p-4 border-t bg-muted/20 shrink-0")], [
			div([class("flex items-center gap-3")], [
				div([class("w-10 h-10 rounded-full bg-primary/20 flex items-center justify-center font-bold text-primary")], [
					text(user_initial)
				]),
				div([class("flex flex-col overflow-hidden")], [
					div([class("text-sm font-medium leading-tight truncate")], [text(user_display_name)]),
					div([class("text-xs text-muted-foreground truncate")], [text(user_display_email)])
				])
			])
		])

	# Desktop Sidebar
	sidebar =
		UI.sidebar({ classes: "w-64 h-full hidden md:flex flex-col flex-shrink-0" }, [
			sidebar_header_content,
			div([class("flex-1 overflow-y-auto p-4")], [
				UI.sidebar_nav({ classes: "space-y-1" }, sidebar_navs)
			]),
			sidebar_user_footer
		])

	# Mobile Sidebar Overlay
	mobile_sidebar =
		if model.mobileMenuOpen {
			div([class("fixed inset-0 z-50 md:hidden")], [
				div([class("fixed inset-0 bg-black/50"), Attribute.on_click(ToggleMobileMenu)], []),
				div([class("fixed left-0 top-0 bottom-0 w-64 bg-card border-r shadow-xl flex flex-col z-51")], [
					sidebar_header_content,
					div([class("flex-1 overflow-y-auto p-4")], [
						UI.sidebar_nav({ classes: "space-y-1" }, sidebar_navs)
					]),
					sidebar_user_footer
				])
			])
		} else {
			div([], [])
		}

	# Breadcrumbs (clickable)
	breadcrumb_items =
		match model.route {
			Dashboard => [
				span([class("text-foreground font-semibold")], [text("Dashboard")])
			]
			AdminUserManagement => [
				a([class("hover:text-foreground transition-colors cursor-pointer"), Attribute.on_click(NavigateTo(Dashboard))], [text("Dashboard")]),
				span([class("mx-2")], [text("/")]),
				span([class("text-foreground")], [text("User Management")])
			]
			AdminConfigurationHub => [
				a([class("hover:text-foreground transition-colors cursor-pointer"), Attribute.on_click(NavigateTo(Dashboard))], [text("Dashboard")]),
				span([class("mx-2")], [text("/")]),
				span([class("text-foreground")], [text("Configuration Hub")])
			]
			AdminLMS => [
				a([class("hover:text-foreground transition-colors cursor-pointer"), Attribute.on_click(NavigateTo(Dashboard))], [text("Dashboard")]),
				span([class("mx-2")], [text("/")]),
				span([class("text-foreground")], [text("LMS")])
			]
			TeacherLessonViewer => [
				a([class("hover:text-foreground transition-colors cursor-pointer"), Attribute.on_click(NavigateTo(Dashboard))], [text("Dashboard")]),
				span([class("mx-2")], [text("/")]),
				span([class("text-foreground")], [text("Lesson Viewer")])
			]
			TeacherAssessments => [
				a([class("hover:text-foreground transition-colors cursor-pointer"), Attribute.on_click(NavigateTo(Dashboard))], [text("Dashboard")]),
				span([class("mx-2")], [text("/")]),
				span([class("text-foreground")], [text("Assessments & Grading")])
			]
			StudentLessonViewer => [
				a([class("hover:text-foreground transition-colors cursor-pointer"), Attribute.on_click(NavigateTo(Dashboard))], [text("Dashboard")]),
				span([class("mx-2")], [text("/")]),
				span([class("text-foreground")], [text("My Lessons")])
			]
			StudentAssignments => [
				a([class("hover:text-foreground transition-colors cursor-pointer"), Attribute.on_click(NavigateTo(Dashboard))], [text("Dashboard")]),
				span([class("mx-2")], [text("/")]),
				span([class("text-foreground")], [text("Assignments")])
			]
			StudentSubjects => [
				a([class("hover:text-foreground transition-colors cursor-pointer"), Attribute.on_click(NavigateTo(Dashboard))], [text("Dashboard")]),
				span([class("mx-2")], [text("/")]),
				span([class("text-foreground")], [text("My Subjects")])
			]
			StudentLesson => [
				a([class("hover:text-foreground transition-colors cursor-pointer"), Attribute.on_click(NavigateTo(Dashboard))], [text("Dashboard")]),
				span([class("mx-2")], [text("/")]),
				span([class("text-foreground")], [text("Lesson")])
			]
			TeacherMyClasses => [
				a([class("hover:text-foreground transition-colors cursor-pointer"), Attribute.on_click(NavigateTo(Dashboard))], [text("Dashboard")]),
				span([class("mx-2")], [text("/")]),
				span([class("text-foreground")], [text("My Classes")])
			]
			Messaging => [
				a([class("hover:text-foreground transition-colors cursor-pointer"), Attribute.on_click(NavigateTo(Dashboard))], [text("Dashboard")]),
				span([class("mx-2")], [text("/")]),
				span([class("text-foreground")], [text("Messaging")])
			]
			Settings => [
				a([class("hover:text-foreground transition-colors cursor-pointer"), Attribute.on_click(NavigateTo(Dashboard))], [text("Dashboard")]),
				span([class("mx-2")], [text("/")]),
				span([class("text-foreground")], [text("Settings")])
			]
			_ => [
				a([class("hover:text-foreground transition-colors cursor-pointer"), Attribute.on_click(NavigateTo(Dashboard))], [text("Dashboard")]),
				span([class("mx-2")], [text("/")]),
				span([class("text-foreground")], [text("Page")])
			]
		}

	# Top Nav Bar
	# The active session term the page's JavaScript fetches on boot and on every navigation
	# (60-second cache). While the first answer is on its way the bar shows a small spinner; it shows
	# the badge once the term is known and nothing at all when there is none (or the fetch failed),
	# because this is a marker on the bar, not a page-level state.
	session_term_bar =
		match list_state(model.sessionTermData) {
			Pending =>
				span([class("hidden sm:flex items-center"), Attribute.aria("label", "Loading the active session term")], [
					span([class("h-3.5 w-3.5 rounded-full border-2 border-secondary-500 border-t-transparent animate-spin")], [])
				])
			Failed(_) => span([], [])
			Ready(rows) =>
				# One row: the badge text the page built from the session term's own two names.
				match rows {
					[term_label, .. as _rest] =>
						span([
							Attribute.id("active-session-term"),
							class("hidden sm:inline-flex items-center gap-1.5 rounded-full border border-secondary-300 bg-secondary-50 px-2.5 py-0.5 text-xs font-medium text-secondary-800 dark:border-secondary-700 dark:bg-secondary-900/40 dark:text-secondary-200")
						], [text(term_label)])
					_ => span([], [])
				}
		}

	top_nav =
		div([class("h-16 border-b bg-card flex items-center justify-between px-4 md:px-6 shrink-0 shadow-sm z-10 relative")], [
			div([class("flex items-center gap-3")], List.concat(
				[
					UI.button({ ..UI.default_button, variant: Ghost, size: Icon, on_click: Click(ToggleMobileMenu), classes: "md:hidden" }, [
						text("☰")
					])
				],
				[div([class("breadcrumb-trail flex items-center min-w-0 text-xs sm:text-sm font-medium text-muted-foreground")], breadcrumb_items)]
			)),
			div([class("flex items-center gap-2")], List.concat(
				[session_term_bar],
				[
					UI.button({ ..UI.default_button, variant: Ghost, size: Icon, on_click: Click(ToggleTheme) }, [
						text(match model.theme { Light => "🌙", Dark => "☀️" })
					]),
					# The notifications bell: open state and content are the app's, the same "app owns it,
					# the page only reports an outside click" pattern as the avatar menu below (writing the
					# toast history straight into this node's DOM bypassed the vdom's own tracking of this
					# subtree and corrupted later patches). The page serializes its toast history into
					# notificationsData through the usual hidden-input bridge (see www/index.html).
					div([Attribute.id("notifications-bell-wrap"), class("relative")], [
						UI.button({ ..UI.default_button, variant: Ghost, size: Icon, on_click: Click(ToggleNotifications) }, [
							text("🔔")
						]),
						notification_badge(model.notificationsData),
						div([
							Attribute.id("notifications-panel"),
							class(if model.notificationsOpen { "absolute right-0 mt-2 w-72 max-h-96 overflow-y-auto bg-card border border-border rounded-md shadow-lg z-50" } else { "hidden" }),
						], notifications_panel_body(model))
					]),
					                                        div([class("relative")], [
					                                                div([Attribute.id("user-menu-button")], [
					                                                        UI.button({ ..UI.default_button, variant: Ghost, size: Icon, on_click: Click(ToggleUserMenu), classes: "rounded-full bg-muted" }, [
					                                                                text(user_initial)
					                                                        ])
					                                                ]),
					                                                div([
					                                                        Attribute.id("user-menu"),
					                                                        class(if model.userMenuOpen { "absolute right-0 mt-2 w-56 bg-card border rounded-md shadow-md py-1 z-50" } else { "hidden" })
					                                                ], [
					                                                        div([class("px-4 py-2 space-y-0.5")], [
					                                                                p([class("text-sm font-medium truncate")], [text(if Str.is_empty(model.userName) { "Signed in" } else { model.userName })]),
					                                                                p([class("text-xs text-muted-foreground truncate")], [text(if Str.is_empty(model.userEmail) { "no address on the token" } else { model.userEmail })])
					                                                        ]),
					                                                        div([class("border-t my-1")], []),
					                                                        UI.button({ ..UI.default_button, variant: Ghost, classes: "w-full justify-start rounded-none px-4 py-2", on_click: Click(NavigateTo(Settings)) }, [
					                                                        	text("Settings")
					                                                        ]),
					                                                        UI.button({ ..UI.default_button, variant: Ghost, classes: "w-full justify-start rounded-none px-4 py-2", on_click: Click(SignOut) }, [
					                                                                text("Sign Out")
					                                                        ])
					                                                ])
					                                        ])
				]
			))
		])

	# Main Content Area dispatched by Route
	content =
		match model.route {
			Settings => SettingsView.view(model)
			Dashboard => DashboardView.view(model)
			AdminUserManagement | AdminConfigurationHub | AdminLMS => AdminView.view(model)
			TeacherLessonViewer | TeacherAssessments => TeacherView.view(model)
			StudentLessonViewer | StudentAssignments => StudentView.view(model)
			StudentSubjects | StudentLesson => StudentView.view(model)
			TeacherMyClasses => TeacherView.view(model)
			Messaging => MessagingView.view(model)
			_ => div([], [h1([], [text("404 Not Found")])])
		}

	div([class(theme_class)], [
		# The active session term: fed by the page's JavaScript on boot and on every navigation
		# (see refreshActiveSessionTerm in www/index.html). Its payload is what session_term_bar reads.
		        Html.input([
		                Attribute.type("hidden"),
		                Attribute.id("active_session_term_input"),
		                Attribute.value(model.sessionTermData),
		                Attribute.on_input(|s| GotSessionTermData(s))
		        ]),
		        # The caller's own rights and the admin catalog. Both sit at the root rather than on a page, because
		        # the sidebar reads the rights on *every* admin route — a payload dispatched into an input that is not
		        # rendered is dropped, and the sidebar would draw the screens the backend refuses.
		        Html.input([
		                Attribute.type("hidden"),
		                Attribute.id("admin_rights_data_input"),
		                Attribute.value(model.adminRightsData),
		                Attribute.on_input(|s| GotAdminRightsData(s))
		        ]),
		        Html.input([
		                Attribute.type("hidden"),
		                Attribute.id("admin_types_data_input"),
		                Attribute.value(model.adminTypesData),
		                Attribute.on_input(|s| GotAdminTypesData(s))
		        ]),

		        # Whether this login owes a password change: fetched by the page on boot and on every navigation
		        # (see refreshPasswordState in www/index.html), and the first thing the shell reads before it draws
		        # its navigation — while it stands, Settings is the only page offered.
		        Html.input([
		        	Attribute.type("hidden"),
		        	Attribute.id("password_state_data_input"),
		        	Attribute.value(model.passwordStateData),
		        	Attribute.on_input(|s| GotPasswordState(s))
		        ]),
	# The avatar menu closes when the page's own listener sees a click outside it (www/index.html
	# dispatches this input), so it never stays open behind a navigation.
	Html.input([
		Attribute.type("hidden"),
		Attribute.id("user_menu_close_input"),
		Attribute.value(""),
		Attribute.on_input(|_s| CloseUserMenu)
	]),
	# The notifications bell's own pair: the page's toast history, serialized the same way every
	# other fetched list arrives, and the same outside-click-closes bridge as the avatar menu.
	Html.input([
		Attribute.type("hidden"),
		Attribute.id("notifications_data_input"),
		Attribute.value(model.notificationsData),
		Attribute.on_input(|s| GotNotificationsData(s))
	]),
	Html.input([
		Attribute.type("hidden"),
		Attribute.id("notifications_close_input"),
		Attribute.value(""),
		Attribute.on_input(|_s| CloseNotifications)
	]),
		mobile_sidebar,
		sidebar,
		div([class("flex-1 flex flex-col h-full overflow-hidden")], [
			top_nav,
			div([class("flex-1 overflow-auto bg-muted/10")], [content])
		])
	])
}
