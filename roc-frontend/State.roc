module [Model, Msg, init, update, Route, Role, AdminConfigTab, AdminUserTab]

import pf.Effect exposing [Effect]
import pf.Http
import pf.Port
import Auth

AdminConfigTab : [Terms, ClassLevels, Curriculum, SessionTerms, Subjects]

AdminUserTab : [Students, Teachers, Parents, Admins]

Route : [
	Dashboard,
	AdminUserManagement,
	AdminConfigurationHub,
	TeacherLessonViewer,
	TeacherAssessments,
	StudentLessonViewer,
	StudentAssignments,
	StudentSubjects,
	StudentLesson,
	TeacherMyClasses,
	Messaging,
	NotFound,
]

Role : [Admin, Teacher, Student, Parent, Unauthenticated]

Model : {
	route : Route,
	role : Role,
	authToken : Str,
	userEmail : Str,
	userName : Str,
	theme : [Light, Dark],
	isPinging : Bool,
	pingResult : [None, Success(Str), Error(Str)],
	newUserFirstName : Str,
	newUserMiddleName : Str,
	newUserSurname : Str,
	newUserEmail : Str,
	isSubmitting : Bool,
	isLoading : Bool,
	mobileMenuOpen : Bool,
	usersData : Str,
	termsData : Str,
	subjectsData : Str,
	submitResult : [None, Success(Str), Error(Str)],
	activeConfigTab : AdminConfigTab,
	activeUserTab : AdminUserTab,
	newUserRole : Str,
	newUserPassportKey : Str,
	newUserDateOfBirth : Str,
	newUserClassLevel : Str,
	newUserRoleTitle : Str,
	appOrigin : Str,
	usersStudentsData : Str,
	usersTeachersData : Str,
	usersParentsData : Str,
	usersAdminsData : Str,
	selectedSubjectId : Str,
	selectedSubjectName : Str,
	selectedTermId : Str,
	selectedTermName : Str,
	selectedLessonId : Str,
	studentTermsData : Str,
	studentLessonsData : Str,
	teacherLessonsData : Str,
	currentLessonContent : Str,
	# Configuration hub: the five list payloads the page's hidden inputs carry, one form per
	# section, and the feedback from the last create.
	classLevelsData : Str,
	curriculumData : Str,
	sessionTermsData : Str,
	# The hub's own subject list: every subject, active or not. `subjectsData` above is the
	# active-only one the student's cards and the pickers read, which is what deactivating a
	# subject takes it out of.
	configSubjectsData : Str,
	newTermName : Str,
	newTermSortOrder : Str,
	newSubjectName : Str,
	newSubjectCode : Str,
	newClassLevelName : Str,
	newClassLevelCode : Str,
	newSessionTermName : Str,
	newSessionTermTerm : Str,
	newCurriculumClassLevel : Str,
	newCurriculumSubject : Str,
	isConfigSubmitting : Bool,
	configSubmitResult : [None, Success(Str), Error(Str)],
	# The row the hub has open for editing, and its editable columns. Only one row is edited at a
	# time, so one draft serves every section: editId is the row's record id and the fields are
	# its own values in the order its fetched line carries them (e.g. for a term name, sort
	# order, —; for a session term name, term link). The section's update call names them.
	editId : Str,
	editField1 : Str,
	editField2 : Str,
	editField3 : Str,
}

Msg : [
	UrlChanged(Str),
	NavigateTo(Route),
	ToggleTheme,
	ToggleMobileMenu,
	TestConnectionClicked,
	PingCompleted([Success(Str), Error(Str)]),
	UpdateNewUserFirstName(Str),
	UpdateNewUserMiddleName(Str),
	UpdateNewUserSurname(Str),
	UpdateNewUserDateOfBirth(Str),
	UpdateNewUserClassLevel(Str),
	UpdateNewUserRoleTitle(Str),
	UpdateNewUserEmail(Str),
	SubmitNewUser,
	GotUsersData(Str),
	GotTermsData(Str),
	GotSubjectsData(Str),
	DataLoaded,
	SubmitCompleted(Try(Http.Response, [HttpErr([Timeout, NetworkError])])),
	SetConfigTab(AdminConfigTab),
	SignOut,
	SetUserTab(AdminUserTab),
	UpdateNewUserRole(Str),
	SetPassportKey(Str),
	GotStudentsData(Str),
	GotTeachersData(Str),
	GotParentsData(Str),
	GotAdminsData(Str),
	LoadLessons(Str, Str),
	ViewLesson(Str),
	SelectSubject(Str, Str),
	SelectTerm(Str, Str),
	SelectLesson(Str),
	GotStudentTermsData(Str),
	GotTeacherLessonsData(Str),
	OpenTeacherLesson(Str),
	GotStudentLessonsData(Str),
	GotLessonContent(Str),
	BackToSubjects,
	BackToTerms,
	GotClassLevelsData(Str),
	GotCurriculumData(Str),
	GotSessionTermsData(Str),
	GotConfigSubjectsData(Str),
	UpdateNewTermName(Str),
	UpdateNewTermSortOrder(Str),
	UpdateNewSubjectName(Str),
	UpdateNewSubjectCode(Str),
	UpdateNewClassLevelName(Str),
	UpdateNewClassLevelCode(Str),
	UpdateNewSessionTermName(Str),
	UpdateNewSessionTermTerm(Str),
	UpdateNewCurriculumClassLevel(Str),
	UpdateNewCurriculumSubject(Str),
	SubmitConfigCreate(AdminConfigTab),
	ConfigCreateCompleted(AdminConfigTab, Try(Http.Response, [HttpErr([Timeout, NetworkError])])),
	StartConfigEdit(Str),
	CancelConfigEdit,
	UpdateEditField1(Str),
	UpdateEditField2(Str),
	UpdateEditField3(Str),
	SubmitConfigUpdate(AdminConfigTab),
	ConfigUpdateCompleted(AdminConfigTab, Try(Http.Response, [HttpErr([Timeout, NetworkError])])),
	ToggleConfigActive(AdminConfigTab, Str, Bool),
	ConfigToggleCompleted(AdminConfigTab, Bool, Try(Http.Response, [HttpErr([Timeout, NetworkError])])),
]

parse_route = |url| {
	match url {
		"/admin/users" => AdminUserManagement
		"/admin/config" => AdminConfigurationHub
		"/teacher/lessons" => TeacherLessonViewer
		"/teacher/assessments" => TeacherAssessments
		"/student/lessons" => StudentLessonViewer
		"/student/assignments" => StudentAssignments
		"/student/subjects" => StudentSubjects
		"/student/lesson" => StudentLesson
		"/teacher/classes" => TeacherMyClasses
		"/messaging" => Messaging
		"/" => Dashboard
		_ => NotFound
	}
}

init : Str -> (Model, List(Effect(Msg)))
init = |flags| {
	parts = Str.split_on(flags, "|")
	
	themeStr = match List.get(parts, 0) { Ok(t) => t, Err(_) => "light" }
	tokenToUse = match List.get(parts, 1) { Ok(t) => t, Err(_) => "" }
	roleStr = match List.get(parts, 2) { Ok(t) => t, Err(_) => "Student" }
	emailStr = match List.get(parts, 3) { Ok(t) => t, Err(_) => "" }
	nameStr = match List.get(parts, 4) { Ok(t) => t, Err(_) => "" }
	pathStr = match List.get(parts, 5) { Ok(t) => t, Err(_) => "/" }
	# The page passes its own origin so requests are not pinned to localhost:8000.
	originStr = match List.get(parts, 6) { Ok(o) => o, Err(_) => "http://localhost:8000" }
		
	initialRole = 
		if Str.is_empty(tokenToUse) { Unauthenticated } 
		else if roleStr == "Admin" { Admin }
		else if roleStr == "Teacher" { Teacher }
		else if roleStr == "Parent" { Parent }
		else { Student }

	initialRoute = parse_route(pathStr)

	model = {
		route: initialRoute,
		role: initialRole,
		authToken: tokenToUse,
		userEmail: emailStr,
		userName: nameStr,
		theme: if themeStr == "dark" { Dark } else { Light },
		isPinging: Bool.False,
		pingResult: None,
		newUserFirstName: "",
		newUserMiddleName: "",
		newUserSurname: "",
		newUserEmail: "",
		isSubmitting: Bool.False,
		isLoading: Bool.True,
		mobileMenuOpen: Bool.False,
		usersData: "",
		termsData: "",
		subjectsData: "",
		submitResult: None,
		activeConfigTab: Terms,
		activeUserTab: Students,
		newUserRole: "Student",
		newUserPassportKey: "",
		newUserDateOfBirth: "",
		newUserClassLevel: "",
		newUserRoleTitle: "",
		appOrigin: originStr,
		usersStudentsData: "",
		usersTeachersData: "",
		usersParentsData: "",
		usersAdminsData: "",
		selectedSubjectId: "",
		selectedSubjectName: "",
		selectedTermId: "",
		selectedTermName: "",
		selectedLessonId: "",
		studentTermsData: "",
		studentLessonsData: "",
		teacherLessonsData: "",
		currentLessonContent: "",
		classLevelsData: "",
		curriculumData: "",
		sessionTermsData: "",
		configSubjectsData: "",
		newTermName: "",
		newTermSortOrder: "",
		newSubjectName: "",
		newSubjectCode: "",
		newClassLevelName: "",
		newClassLevelCode: "",
		newSessionTermName: "",
		newSessionTermTerm: "",
		newCurriculumClassLevel: "",
		newCurriculumSubject: "",
		isConfigSubmitting: Bool.False,
		configSubmitResult: None,
		editId: "",
		editField1: "",
		editField2: "",
		editField3: "",
	}

	# Boot fetches. Note for the next editor: keep every effect list inline inside its branch. This Roc
	# nightly miscompiles a branch (an `if`/`else`) that yields a bound `List(Effect(Msg))`: it emits a
	# gigantic function and the wasm then traps with "function signature mismatch" at start, blanking
	# the page. A `match` with full inline lists (as here) compiles and runs.
	(model, match initialRoute {
		AdminConfigurationHub => [
			Port.send("fetch_data", "/api/users?role=Student"),
			Port.send("fetch_data", "/api/users?role=Teacher"),
			Port.send("fetch_data", "/api/users?role=Parent"),
			Port.send("fetch_data", "/api/users?role=Admin"),
			Port.send("fetch_data", "/api/subjects"),
			Port.send("fetch_data", "/api/teacher/lessons"),
			Port.send("fetch_data", "/api/terms"),
			Port.send("fetch_data", "/api/class_levels?all=true"),
			Port.send("fetch_data", "/api/curriculum?all=true"),
			Port.send("fetch_data", "/api/session_terms"),
			Port.send("fetch_data", "/api/subjects?all=true"),
		]
		_ => [
			Port.send("fetch_data", "/api/users?role=Student"),
			Port.send("fetch_data", "/api/users?role=Teacher"),
			Port.send("fetch_data", "/api/users?role=Parent"),
			Port.send("fetch_data", "/api/users?role=Admin"),
			Port.send("fetch_data", "/api/subjects"),
			Port.send("fetch_data", "/api/teacher/lessons"),
		]
	})
}

# --- Configuration hub ---

# Re-fetch the list a create or an update just changed, so the new row (or the new values) appear
# without a reload. A subject change also refreshes the active-only list, which is what the
# student's cards and the curriculum picker read.
config_refresh_effects = |tab| {
	match tab {
		Terms => [Port.send("fetch_data", "/api/terms")]
		Subjects => [Port.send("fetch_data", "/api/subjects?all=true"), Port.send("fetch_data", "/api/subjects")]
		ClassLevels => [Port.send("fetch_data", "/api/class_levels?all=true")]
		Curriculum => [Port.send("fetch_data", "/api/curriculum?all=true")]
		SessionTerms => [Port.send("fetch_data", "/api/session_terms")]
	}
}

config_section_label = |tab| {
	match tab {
		Terms => "Term"
		Subjects => "Subject"
		ClassLevels => "Class level"
		Curriculum => "Curriculum link"
		SessionTerms => "Session term"
	}
}

# The section's endpoint: one URL per section, used by its create, its update and its toggle.
config_endpoint = |tab| {
	match tab {
		Terms => "terms"
		Subjects => "subjects"
		ClassLevels => "class_levels"
		Curriculum => "curriculum"
		SessionTerms => "session_terms"
	}
}

# The endpoint and payload for one section's create form. An empty field is sent as-is: the
# backend validates and answers 400 with the text the form then shows.
config_create_call = |model, tab| {
	payload = match tab {
		Terms => {
			sort_clause = if Str.is_empty(model.newTermSortOrder) { "" } else { ",\"sort_order\":${model.newTermSortOrder}" }
			"{\"name\":\"${model.newTermName}\"${sort_clause}}"
		}
		Subjects => "{\"name\":\"${model.newSubjectName}\",\"code\":\"${model.newSubjectCode}\"}"
		ClassLevels => "{\"name\":\"${model.newClassLevelName}\",\"code\":\"${model.newClassLevelCode}\"}"
		SessionTerms => "{\"session_name\":\"${model.newSessionTermName}\",\"term\":\"${model.newSessionTermTerm}\"}"
		Curriculum => "{\"class_level\":\"${model.newCurriculumClassLevel}\",\"subject\":\"${model.newCurriculumSubject}\"}"
	}

	{ endpoint: config_endpoint(tab), payload }
}

# One `"field":"value"` pair of a request body, or "" when the value is empty: the update
# endpoints patch, so an empty field means "leave that column as it is".
json_text_field = |field, value| {
	if Str.is_empty(value) { "" } else { ",\"${field}\":\"${value}\"" }
}

# The same for a number (the backend reads it with extract_number_field).
json_number_field = |field, value| {
	if Str.is_empty(value) { "" } else { ",\"${field}\":${value}" }
}

# One "|"-separated field of a fetched row (the page's own line format), "" when the row is short.
config_part = |parts, index| {
	match List.get(parts, index) {
		Ok(value) => value
		Err(_) => ""
	}
}

# The endpoint and payload for saving the row the hub has open for editing. The draft fields are the
# row's own values in the order its fetched line carries them, so each section names the columns
# they belong to; a section only offers editing for the columns its table can write.
config_update_call = |model, tab| {
	id_field = "{\"id\":\"${model.editId}\""

	payload = match tab {
		Terms => "${id_field}${json_text_field("name", model.editField1)}${json_number_field("sort_order", model.editField2)}}"
		Subjects => "${id_field}${json_text_field("name", model.editField1)}${json_text_field("code", model.editField2)}}"
		ClassLevels => "${id_field}${json_text_field("name", model.editField1)}${json_text_field("code", model.editField2)}${json_text_field("age_range", model.editField3)}}"
		SessionTerms => "${id_field}${json_text_field("session_name", model.editField1)}${json_text_field("term", model.editField2)}}"
		# A curriculum link has no editable column — it is linked or not — so the views only ever
		# offer its toggle; this branch keeps the match exhaustive.
		Curriculum => "${id_field}}"
	}

	{ endpoint: config_endpoint(tab), payload }
}

# Leaving edit mode, after a save or a cancel. Only one row is open at a time.
config_edit_cleared = |model| {
	{ ..model, editId: "", editField1: "", editField2: "", editField3: "" }
}

# A successful create clears only its own form.
config_form_cleared = |model, tab| {
	match tab {
		Terms => { ..model, newTermName: "", newTermSortOrder: "" }
		Subjects => { ..model, newSubjectName: "", newSubjectCode: "" }
		ClassLevels => { ..model, newClassLevelName: "", newClassLevelCode: "" }
		SessionTerms => { ..model, newSessionTermName: "", newSessionTermTerm: "" }
		Curriculum => { ..model, newCurriculumClassLevel: "", newCurriculumSubject: "" }
	}
}

# One string field out of a response body: json_string_field(body, "error").
json_string_field = |body, field| {
	match List.get(Str.split_on(body, "\"${field}\":\""), 1) {
		Ok(rest) => match List.first(Str.split_on(rest, "\"")) { Ok(value) => value, Err(_) => "" }
		Err(_) => ""
	}
}

# What a failed write should show: the database's own statement text (`detail`) when present,
# otherwise the headline a 400 validation answer carries in `error`.
backend_error_message = |body| {
	detail = json_string_field(body, "detail")
	headline = json_string_field(body, "error")
	if !Str.is_empty(detail) {
		if Str.is_empty(headline) { detail } else { "${headline}: ${detail}" }
	} else if !Str.is_empty(headline) {
		headline
	} else {
		"Request failed"
	}
}

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UrlChanged(url) => {
			newRoute = parse_route(url)
			# Browser back/forward into the hub: the page is reloaded from scratch by the runtime, so
			# its lists are fetched again. Lists stay inline here too — see the note in init.
			fetches = match newRoute {
				AdminConfigurationHub => [
					Port.send("fetch_data", "/api/terms"),
					Port.send("fetch_data", "/api/subjects"),
					Port.send("fetch_data", "/api/subjects?all=true"),
					Port.send("fetch_data", "/api/class_levels?all=true"),
					Port.send("fetch_data", "/api/curriculum?all=true"),
					Port.send("fetch_data", "/api/session_terms"),
				]
				_ => []
			}
			({ ..model, route: newRoute, mobileMenuOpen: Bool.False }, fetches)
		}
		# Entering the hub fetches its lists: the page's hidden inputs only exist there.
		NavigateTo(AdminConfigurationHub) => (
			{ ..model, route: AdminConfigurationHub, mobileMenuOpen: Bool.False },
			[
				Port.send("push_state", "/admin/config"),
				Port.send("fetch_data", "/api/terms"),
				Port.send("fetch_data", "/api/subjects"),
				Port.send("fetch_data", "/api/subjects?all=true"),
				Port.send("fetch_data", "/api/class_levels?all=true"),
				Port.send("fetch_data", "/api/curriculum?all=true"),
				Port.send("fetch_data", "/api/session_terms"),
			]
		)
		NavigateTo(route) => {
			urlStr = match route {
				Dashboard => "/"
				AdminUserManagement => "/admin/users"
				AdminConfigurationHub => "/admin/config"
				TeacherLessonViewer => "/teacher/lessons"
				TeacherAssessments => "/teacher/assessments"
				StudentLessonViewer => "/student/lessons"
				StudentAssignments => "/student/assignments"
				StudentSubjects => "/student/subjects"
				StudentLesson => "/student/lesson"
				TeacherMyClasses => "/teacher/classes"
				Messaging => "/messaging"
				NotFound => "/404"
			}
			({ ..model, route: route, mobileMenuOpen: Bool.False }, [Port.send("push_state", urlStr)])
		}
		ToggleTheme => {
			newTheme = match model.theme {
				Light => Dark
				Dark => Light
			}
			themeStr = match newTheme { Light => "light", Dark => "dark" }
			({ ..model, theme: newTheme }, [Port.send("save_theme", themeStr)])
		}
		ToggleMobileMenu => {
			({ ..model, mobileMenuOpen: !(model.mobileMenuOpen) }, [])
		}
		SignOut => {
			({ ..model, route: Dashboard, role: Unauthenticated, authToken: "" }, [
				Port.send("save_token", ""),
				Port.send("redirect", "https://auth.johnethel.school/application/o/school-management-system/end-session/?post_logout_redirect_uri=http://localhost:9090/")
			])
		}
		TestConnectionClicked =>
			(
				{ ..model, isPinging: Bool.True, pingResult: None },
				[
					Http.get("http://localhost:8000/health", |res| 
						match res {
							Ok(_) => PingCompleted(Success("Healthy"))
							Err(_) => PingCompleted(Error("Error"))
						}
					)
				]
			)
		PingCompleted(res) => {
			newResult : [None, Success(Str), Error(Str)]
			newResult = match res {
				Success(s) => Success(s)
				Error(e) => Error(e)
			}
			({ ..model, isPinging: Bool.False, pingResult: newResult }, [])
		}
		UpdateNewUserFirstName(s) =>
			({ ..model, newUserFirstName: s }, [])
		UpdateNewUserMiddleName(s) =>
			({ ..model, newUserMiddleName: s }, [])
		UpdateNewUserSurname(s) =>
			({ ..model, newUserSurname: s }, [])
		UpdateNewUserDateOfBirth(s) =>
			({ ..model, newUserDateOfBirth: s }, [])
		UpdateNewUserClassLevel(s) =>
			({ ..model, newUserClassLevel: s }, [])
		UpdateNewUserRoleTitle(s) =>
			({ ..model, newUserRoleTitle: s }, [])
		SetConfigTab(tab) =>
			({ ..model, activeConfigTab: tab, configSubmitResult: None }, [])
		UpdateNewUserEmail(s) =>
			({ ..model, newUserEmail: s }, [])
		GotUsersData(str) => ({ ..model, usersData: str, isLoading: Bool.False }, [])
		GotTermsData(str) => ({ ..model, termsData: str }, [])
		GotSubjectsData(str) => ({ ..model, subjectsData: str }, [])
		GotClassLevelsData(str) => ({ ..model, classLevelsData: str }, [])
		GotCurriculumData(str) => ({ ..model, curriculumData: str }, [])
		GotSessionTermsData(str) => ({ ..model, sessionTermsData: str }, [])
		GotConfigSubjectsData(str) => ({ ..model, configSubjectsData: str }, [])
		UpdateNewTermName(s) => ({ ..model, newTermName: s }, [])
		UpdateNewTermSortOrder(s) => ({ ..model, newTermSortOrder: s }, [])
		UpdateNewSubjectName(s) => ({ ..model, newSubjectName: s }, [])
		UpdateNewSubjectCode(s) => ({ ..model, newSubjectCode: s }, [])
		UpdateNewClassLevelName(s) => ({ ..model, newClassLevelName: s }, [])
		UpdateNewClassLevelCode(s) => ({ ..model, newClassLevelCode: s }, [])
		UpdateNewSessionTermName(s) => ({ ..model, newSessionTermName: s }, [])
		UpdateNewSessionTermTerm(s) => ({ ..model, newSessionTermTerm: s }, [])
		UpdateNewCurriculumClassLevel(s) => ({ ..model, newCurriculumClassLevel: s }, [])
		UpdateNewCurriculumSubject(s) => ({ ..model, newCurriculumSubject: s }, [])
		SubmitConfigCreate(tab) => {
			call = config_create_call(model, tab)
			req = {
				method: POST,
				uri: "${model.appOrigin}/api/${call.endpoint}",
				headers: [
					{ name: "Authorization", value: "Bearer ${model.authToken}" },
					{ name: "Content-Type", value: "application/json" }
				],
				body: Str.to_utf8(call.payload),
				timeout_ms: NoTimeout,
			}
			(
				{ ..model, isConfigSubmitting: Bool.True, configSubmitResult: None },
				[Http.request(req, |res| ConfigCreateCompleted(tab, res))]
			)
		}
		ConfigCreateCompleted(tab, res) => {
			newResult : [None, Success(Str), Error(Str)]
			newResult = match res {
				Ok(response) =>
					if response.status == 200 {
						Success("${config_section_label(tab)} created")
					} else {
						Error(backend_error_message(Str.from_utf8_lossy(response.body)))
					}
				Err(HttpErr(Timeout)) => Error("The request timed out")
				Err(HttpErr(NetworkError)) => Error("Could not reach the server")
			}
			# A create that succeeded clears its form and reloads the list so the new row shows up.
			cleared = match newResult {
				Success(_) => config_form_cleared(model, tab)
				_ => model
			}
			refreshes = match newResult {
				Success(_) => config_refresh_effects(tab)
				_ => []
			}
			({ ..cleared, isConfigSubmitting: Bool.False, configSubmitResult: newResult }, refreshes)
		}
		DataLoaded => ({ ..model, isLoading: Bool.False }, [])
		# --- Editing and activating a configuration row ---
		# Opening a row prefills the draft from its own fetched line, so the inputs start on the
		# current values and a save only has to send what the user changed.
		StartConfigEdit(line) => {
			parts = Str.split_on(line, "|")
			(
				{
					..model,
					editId: config_part(parts, 0),
					editField1: config_part(parts, 1),
					editField2: config_part(parts, 2),
					editField3: config_part(parts, 3),
				},
				[]
			)
		}
		CancelConfigEdit => (config_edit_cleared(model), [])
		UpdateEditField1(s) => ({ ..model, editField1: s }, [])
		UpdateEditField2(s) => ({ ..model, editField2: s }, [])
		UpdateEditField3(s) => ({ ..model, editField3: s }, [])
		SubmitConfigUpdate(tab) => {
			call = config_update_call(model, tab)
			req = {
				method: PUT,
				uri: "${model.appOrigin}/api/${call.endpoint}",
				headers: [
					{ name: "Authorization", value: "Bearer ${model.authToken}" },
					{ name: "Content-Type", value: "application/json" }
				],
				body: Str.to_utf8(call.payload),
				timeout_ms: NoTimeout,
			}
			(
				{ ..model, isConfigSubmitting: Bool.True, configSubmitResult: None },
				[Http.request(req, |res| ConfigUpdateCompleted(tab, res))]
			)
		}
		ConfigUpdateCompleted(tab, res) => {
			newResult : [None, Success(Str), Error(Str)]
			newResult = match res {
				Ok(response) =>
					if response.status == 200 {
						Success("${config_section_label(tab)} updated")
					} else {
						Error(backend_error_message(Str.from_utf8_lossy(response.body)))
					}
				Err(HttpErr(Timeout)) => Error("The request timed out")
				Err(HttpErr(NetworkError)) => Error("Could not reach the server")
			}
			# A saved row closes its editor and reloads the list, so the new values show up (and a
			# refusal keeps the editor open with the backend's text in the banner).
			closed = match newResult {
				Success(_) => config_edit_cleared(model)
				_ => model
			}
			refreshes = match newResult {
				Success(_) => config_refresh_effects(tab)
				_ => []
			}
			({ ..closed, isConfigSubmitting: Bool.False, configSubmitResult: newResult }, refreshes)
		}
		ToggleConfigActive(tab, id, active) => {
			active_str = if active { "true" } else { "false" }
			req = {
				method: POST,
				uri: "${model.appOrigin}/api/${config_endpoint(tab)}/toggle-active",
				headers: [
					{ name: "Authorization", value: "Bearer ${model.authToken}" },
					{ name: "Content-Type", value: "application/json" }
				],
				body: Str.to_utf8("{\"id\":\"${id}\",\"active\":${active_str}}"),
				timeout_ms: NoTimeout,
			}
			(
				{ ..model, isConfigSubmitting: Bool.True, configSubmitResult: None },
				[Http.request(req, |res| ConfigToggleCompleted(tab, active, res))]
			)
		}
		ConfigToggleCompleted(tab, active, res) => {
			verb = if active { "activated" } else { "deactivated" }
			newResult : [None, Success(Str), Error(Str)]
			newResult = match res {
				Ok(response) =>
					if response.status == 200 {
						Success("${config_section_label(tab)} ${verb}")
					} else {
						Error(backend_error_message(Str.from_utf8_lossy(response.body)))
					}
				Err(HttpErr(Timeout)) => Error("The request timed out")
				Err(HttpErr(NetworkError)) => Error("Could not reach the server")
			}
			# The row keeps its place in the list either way — the badge is what changes.
			refreshes = match newResult {
				Success(_) => config_refresh_effects(tab)
				_ => []
			}
			({ ..model, isConfigSubmitting: Bool.False, configSubmitResult: newResult }, refreshes)
		}
		SubmitNewUser => {
			payload = "{\"role\":\"${model.newUserRole}\",\"email\":\"${model.newUserEmail}\",\"first_name\":\"${model.newUserFirstName}\",\"middle_name\":\"${model.newUserMiddleName}\",\"surname\":\"${model.newUserSurname}\",\"date_of_birth\":\"${model.newUserDateOfBirth}\",\"class_level\":\"${model.newUserClassLevel}\",\"role_title\":\"${model.newUserRoleTitle}\",\"passport\":\"${model.newUserPassportKey}\"}"
			req = {
				method: POST,
				uri: "${model.appOrigin}/api/users",
				headers: [
					{ name: "Authorization", value: "Bearer ${model.authToken}" },
					{ name: "Content-Type", value: "application/json" }
				],
				body: Str.to_utf8(payload),
				timeout_ms: NoTimeout,
			}
			(
				{ ..model, isSubmitting: Bool.True, submitResult: None },
				[Http.request(req, |res| SubmitCompleted(res))]
			)
		}
		SubmitCompleted(res) => {
			newResult : [None, Success(Str), Error(Str)]
			newResult = match res {
				Ok(response) => {
					if response.status == 200 {
						Success("User created")
					} else {
						# Failures answer {"error":"..."} with the validation text, or a write's own
						# {"error":"Database error","detail":"..."}; show what the backend said.
						Error(backend_error_message(Str.from_utf8_lossy(response.body)))
					}
				}
				Err(HttpErr(Timeout)) => Error("The request timed out")
				Err(HttpErr(NetworkError)) => Error("Could not reach the server")
			}
			# Refresh the role lists so the new account shows up without a manual reload.
			refresh = match newResult {
				Success(_) => [
					Port.send("fetch_data", "/api/users?role=Student"),
					Port.send("fetch_data", "/api/users?role=Teacher"),
					Port.send("fetch_data", "/api/users?role=Parent"),
					Port.send("fetch_data", "/api/users?role=Admin"),
				]
				_ => []
			}
			({ ..model, isSubmitting: Bool.False, submitResult: newResult, newUserFirstName: "", newUserMiddleName: "", newUserSurname: "", newUserEmail: "", newUserDateOfBirth: "", newUserClassLevel: "", newUserRoleTitle: "" }, refresh)
		}
		SetUserTab(tab) => ({ ..model, activeUserTab: tab }, [])
		UpdateNewUserRole(s) => ({ ..model, newUserRole: s }, [])
		SetPassportKey(k) => ({ ..model, newUserPassportKey: k }, [])
		GotStudentsData(s) => ({ ..model, usersStudentsData: s, isLoading: Bool.False }, [])
		GotTeachersData(s) => ({ ..model, usersTeachersData: s, isLoading: Bool.False }, [])
		GotParentsData(s) => ({ ..model, usersParentsData: s, isLoading: Bool.False }, [])
		GotAdminsData(s) => ({ ..model, usersAdminsData: s, isLoading: Bool.False }, [])
		LoadLessons(_subjectId, _termId) => (model, [])
		ViewLesson(_lessonId) => (model, [])
		SelectSubject(id, name) => (
			{ ..model,
				selectedSubjectId: id,
				selectedSubjectName: name,
				selectedTermId: "",
				selectedTermName: "",
				selectedLessonId: "",
				studentTermsData: "",
				studentLessonsData: "",
				currentLessonContent: "",
				route: StudentLesson,
			},
			[
				Port.send("push_state", "/student/lesson"),
				Port.send("fetch_data", "/api/student/terms"),
			]
		)
		SelectTerm(id, name) => (
			{ ..model,
				selectedTermId: id,
				selectedTermName: name,
				selectedLessonId: "",
				studentLessonsData: "",
				currentLessonContent: "",
			},
			[Port.send("fetch_data", "/api/student/lessons?subject_id=${model.selectedSubjectId}&term_id=${id}")]
		)
		SelectLesson(id) => (
			{ ..model,
				selectedLessonId: id,
				currentLessonContent: "",
			},
			[Port.send("fetch_data", "/api/student/lesson?lesson_id=${id}")]
		)
		GotStudentTermsData(s) => ({ ..model, studentTermsData: s }, [])
		GotStudentLessonsData(s) => ({ ..model, studentLessonsData: s }, [])
		GotTeacherLessonsData(s) => ({ ..model, teacherLessonsData: s }, [])
		# The viewer reads the lesson from the URL, so open it through the address bar.
		OpenTeacherLesson(id) =>
			(
				{ ..model, selectedLessonId: id },
				[Port.send("push_state", "/teacher/lessons?id=${id}")]
			)
		GotLessonContent(s) => ({ ..model, currentLessonContent: s }, [])
		BackToSubjects => (
			{ ..model,
				selectedSubjectId: "",
				selectedSubjectName: "",
				selectedTermId: "",
				selectedTermName: "",
				selectedLessonId: "",
				studentTermsData: "",
				studentLessonsData: "",
				currentLessonContent: "",
				route: StudentSubjects,
			},
			[Port.send("push_state", "/student/subjects")]
		)
		BackToTerms => (
			{ ..model,
				selectedTermId: "",
				selectedTermName: "",
				selectedLessonId: "",
				studentLessonsData: "",
				currentLessonContent: "",
			},
			[]
		)
	}
