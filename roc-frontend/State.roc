module [Model, Msg, init, update, Route, Role, AdminConfigTab, AdminUserTab, ListState, list_state]

import pf.Effect
import pf.Http
import pf.Port

AdminConfigTab : [Terms, ClassLevels, Curriculum, SessionTerms, Subjects, Credentials]

AdminUserTab : [Students, Teachers, Parents, Admins]

# What a row action did: the message a deactivate/activate completion carries, so the banner can
# say which one landed (or which one failed).
UserToggleAction : [Deactivate, Activate]

Route : [
	Dashboard,
	AdminUserManagement,
	AdminConfigurationHub,
	AdminLMS,
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

# What one hidden input's payload says about a list. The page's JavaScript answers every fetch —
# a request that failed answers `error` with the backend's own message — so a list is never left
# waiting: `""` means no answer yet (the view shows its skeleton and nobody is stuck), `ok` carries
# the formatted rows (possibly none, which is a real empty state), and `error` carries what failed.
ListState : [Pending, Ready(List(Str)), Failed(Str)]

# Decode a payload: `"ok"` and `"ok\n<row>\n<row>"` are the loaded rows, `"error\n<message>"` is a
# failure, and anything else (including the model's own initial `""`) has not been answered yet.
list_state : Str -> ListState
list_state = |payload| {
	match Str.split_on(payload, "\n") {
		["ok", .. as rows] => Ready(rows)
		["error", .. as message_parts] => {
			message = Str.join_with(message_parts, "\n")
			Failed(if Str.is_empty(message) { "Request failed" } else { message })
		}
		_ => if Str.is_empty(payload) { Pending } else { Failed("Unexpected response") }
	}
}

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
	    mobileMenuOpen : Bool,
	    # The nav bar's avatar menu. It is a click-toggled menu rather than a hover one: a hover menu
	    # cannot be opened on a touch screen, and it closes the moment the pointer leaves it.
	    userMenuOpen : Bool,
	usersData : Str,
	termsData : Str,
	subjectsData : Str,
	submitResult : [None, Success(Str), Error(Str)],
	activeConfigTab : AdminConfigTab,
	activeUserTab : AdminUserTab,
	newUserRole : Str,
	newUserPassportKey : Str,
	# The nav bar's active-session-term payload, refetched by the page's JavaScript on every
	# navigation. Its own status is what tells the bar whether to show a spinner, a badge or nothing.
	sessionTermData : Str,
	newUserDateOfBirth : Str,
	newUserClassLevel : Str,
	newUserRoleTitle : Str,
	# The id of the login whose profile is being completed, empty while the form is creating a new
	# login. One form serves both: with an id it is a PUT that attaches the profile to that login,
	# without one a POST that creates the login and its profile together.
	completingProfileId : Str,
	# The password the create form is typing or has generated. Optional, sent with the create only,
	# and cleared the moment the create is done: the backend sets it in Authentik and never returns
	# it, so the one-time credentials panel below is the only place the value shows again.
	newUserPassword : Str,
	# Whether the form is editing an existing profile (PUT, prefilled) rather than completing a
	# login that has no profile yet (PUT, empty). The two are the same write; this only picks the
	# form's own labels and the success message.
	userEditing : Bool,
	    # One create's handoff: the email and password, shown once with a copy button right after a
	    # create that carried a password, then cleared the moment the form starts another write. The
	    # password is never stored anywhere — not in the backend, not in this model beyond this.
	    lastCredentials : [None, Credentials(Str, Str)],
	    # The user form (add / complete / edit / reset password) lives in a modal; this flag plus the
	    # two modes below say it is on screen. Closing it clears the modes.
	    userFormOpen : Bool,
	    # The id and address of the row whose login's password is being reset, empty otherwise: a
	    # modal mode that shows only the password field and posts /api/users/set-password.
	    resetPasswordId : Str,
	    resetPasswordEmail : Str,
	    # The rows ticked for a bulk delete, as their record ids. A delete works for every row now -
	    # including one with no login behind it, which the backend treats as deletable by the profile
	    # hide alone - and the Delete button above the table removes the whole selection.
	    selectedUserIds : List(Str),
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
	    userClassLevelsData : Str,
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
	newCredentialName : Str,
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
	# The teacher's own class-subject pairs (My Classes cards), the full catalog fed to the Assign
	# dialog and the admin LMS, and one teacher's current pairs (the dialog's badges).
	teacherClassesData : Str,
	subjectPairsData : Str,
	teacherAssignmentsData : Str,
	# The qualifications catalog and the teacher form's selection of it.
	credentialsData : Str,
	newUserQualifications : List(Str),
	qualSearch : Str,
	# The teacher-row Assign dialog: which teacher it is open for, the working set of edges, the
	# dropdown's search text, and the last save's outcome.
	assignDialogOpen : Bool,
	assignTeacherId : Str,
	assignSelectedEdges : List(Str),
	assignSearch : Str,
	assignSaveResult : [None, Success(Str), Error(Str)],
	# Whether the dialog's badge list has been seeded from the fetched teacher-assignments payload
	# (the fetch answers after the dialog opens). Once seeded it is the admin's working set — a
	# refetch after a save must not overwrite edits.
	assignSeeded : Bool,
	# The admin LMS drill-down: the picked class, subject and term, and the fetched lists.
	adminLmsClassId : Str,
	adminLmsClassName : Str,
	adminLmsSubjectId : Str,
	adminLmsSubjectName : Str,
	adminLmsTermId : Str,
	adminLmsTermName : Str,
	adminLmsTermsData : Str,
	adminLmsLessonsData : Str,
	adminLmsClassesData : Str,
}

Msg : [
	UrlChanged(Str),
	NavigateTo(Route),
	    ToggleTheme,
	    ToggleMobileMenu,
	    # The avatar menu: toggled by the avatar, and closed by a click anywhere outside it (the page's
	    # own listener sends CloseUserMenu) so it never stays open behind a navigation.
	    ToggleUserMenu,
	    CloseUserMenu,
	TestConnectionClicked,
	PingCompleted([Success(Str), Error(Str)]),
	UpdateNewUserFirstName(Str),
	UpdateNewUserMiddleName(Str),
	UpdateNewUserSurname(Str),
	UpdateNewUserDateOfBirth(Str),
	UpdateNewUserClassLevel(Str),
	UpdateNewUserRoleTitle(Str),
	UpdateNewUserEmail(Str),
	UpdateNewUserPassword(Str),
	# Fill the password field with a generated one. The page's own generator answers through the
	# input event, exactly like typing, so the value lands in the model the same way a typed one
	# does.
	GenerateUserPassword,
	# The one-time credentials panel's copy button: copies `email\npassword` to the clipboard.
	CopyLastCredentials,
	SubmitNewUser,
	# A user row the directory lists without a profile: load that login into the form so the admin can
	# fill in the school data and attach it (PUT /api/users). The id is what the write names the row
	# by; the email is shown so the form says which login it is completing.
	CompleteProfile(Str, Str),
	CancelCompleteProfile,
	# A row's working actions: load an existing profile into the form for patching (PUT — the line
	# is the row's own, so the form starts prefilled), and the two toggles, deactivate (DELETE
	# /api/users) and activate (POST /api/users/activate) for a row whose login is off.
	StartUserEdit(Str),
	    SubmitDeactivateUser(Str),
	    SubmitActivateUser(Str),
	    UserToggleCompleted(UserToggleAction, Try(Http.Response, [HttpErr([Timeout, NetworkError])])),
	    # The user form modal: open it for a fresh create (header's Add button) and close it (Cancel,
	    # or any completed write). The row actions open it through their own modes.
	    OpenUserForm,
	    CloseUserForm,
	    # Reset a login's password from its row: the modal switches to the password-only mode,
	    # posts /api/users/set-password, and hands the new value over once through the credentials
	    # panel — the backend sets it in Authentik and never returns it.
	    OpenResetPassword(Str, Str),
	    SubmitResetPassword,
	    ResetPasswordCompleted(Try(Http.Response, [HttpErr([Timeout, NetworkError])])),
	    # Bulk delete: tick rows and remove them all. The requests are the same DELETE /api/users as
	    # the row's Delete action, one per selected id.
	    ToggleUserSelected(Str),
	    ClearUserSelection,
	    DeleteSelectedUsers,
	GotUsersData(Str),
	GotTermsData(Str),
	GotSubjectsData(Str),
	GotSessionTermData(Str),
	# Ask for one list again, by the URL the page's fetch_data port takes: what a failed list's
	# Retry control sends. The list keeps its payload until the answer lands, so a retry never
	# flashes a skeleton over data that is already there.
	RetryList(Str),
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
	# A My Classes card: open the lesson picker scoped to that subject (its lessons are the
	# teacher's own, filtered by the subject the card carried).
	OpenTeacherSubject(Str, Str),
	GotStudentLessonsData(Str),
	GotLessonContent(Str),
	BackToSubjects,
	BackToTerms,
	    GotClassLevelsData(Str)
    GotUserClassLevels(Str)
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
	GotTeacherClassesData(Str),
	GotSubjectPairsData(Str),
	GotTeacherAssignmentsData(Str),
	GotCredentialsData(Str),
	UpdateNewCredentialName(Str),
	# The teacher-row Assign action: open the dialog (and load the pairs it shows), work the
	# dropdown, save the whole replacement list.
	OpenTeacherAssign(Str),
	CloseTeacherAssign,
	AddAssignPair(Str),
	RemoveAssignPair(Str),
	UpdateAssignSearch(Str),
	SubmitTeacherAssign,
	TeacherAssignCompleted(Try(Http.Response, [HttpErr([Timeout, NetworkError])])),
	# The teacher form's qualifications picker.
	AddQualification(Str),
	RemoveQualification(Str),
	UpdateQualSearch(Str),
	# The admin LMS drill-down: class -> subject -> term -> lessons -> lesson content.
	SelectAdminClass(Str, Str),
	BackAdminSubjects,
	SelectAdminSubject(Str, Str),
	BackAdminTerms,
	SelectAdminTerm(Str, Str),
	OpenAdminLesson(Str),
	BackAdminLessons,
	GotAdminLmsTermsData(Str),
	GotAdminLmsLessonsData(Str),
	GotAdminLmsClassesData(Str),
]

	parse_route = |url| {
	match url {
		"/admin/users" => AdminUserManagement
		"/admin/config" => AdminConfigurationHub
		"/admin/lms" => AdminLMS
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
		            mobileMenuOpen: Bool.False,
		            userMenuOpen: Bool.False,
		sessionTermData: "",
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
		            completingProfileId: "",
		            newUserPassword: "",
		            userEditing: Bool.False,
		            lastCredentials: None,
		            userFormOpen: Bool.False,
		            resetPasswordId: "",
		            resetPasswordEmail: "",
		            selectedUserIds: [],
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
		            userClassLevelsData: "",
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
		newCredentialName: "",
		isConfigSubmitting: Bool.False,
		configSubmitResult: None,
		editId: "",
		editField1: "",
		editField2: "",
		editField3: "",
		teacherClassesData: "",
		subjectPairsData: "",
		teacherAssignmentsData: "",
		credentialsData: "",
		newUserQualifications: [],
		qualSearch: "",
		assignDialogOpen: Bool.False,
		assignTeacherId: "",
		assignSelectedEdges: [],
		assignSearch: "",
		assignSaveResult: None,
		assignSeeded: Bool.False,
		adminLmsClassId: "",
		adminLmsClassName: "",
		adminLmsSubjectId: "",
		adminLmsSubjectName: "",
		adminLmsTermId: "",
		adminLmsTermName: "",
		adminLmsTermsData: "",
		adminLmsLessonsData: "",
		adminLmsClassesData: "",
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
			Port.send("fetch_data", "/api/credentials"),
		]
			                _ => [
		                        Port.send("fetch_data", "/api/users?role=Student"),
		                        Port.send("fetch_data", "/api/users?role=Teacher"),
		                        Port.send("fetch_data", "/api/users?role=Parent"),
		                        Port.send("fetch_data", "/api/users?role=Admin"),
		                        Port.send("fetch_data", "/api/subjects"),
		                        Port.send("fetch_data", "/api/teacher/lessons"),
		                        Port.send("fetch_data", "/api/teacher/classes"),
		                        # The AdminUserManagement view's create form needs the active class levels for
		                        # its picker even when the page is reached by a direct load (init, not NavigateTo).
		                        Port.send("fetch_data", "/api/class_levels"),
		                        # The catalog and the pairs the admin widgets read. Fetched everywhere so a
		                        # direct load of any page has them ready; a role that cannot read either gets
		                        # a 403 the dispatcher drops (the inputs only exist on the admin pages).
		                        Port.send("fetch_data", "/api/credentials"),
		                        Port.send("fetch_data", "/api/class-subjects"),
		                        Port.send("fetch_data", "/api/class_levels?admin_lms=1"),
		                        Port.send("fetch_data", "/api/student/terms?admin_lms=1"),
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
		Credentials => [Port.send("fetch_data", "/api/credentials")]
	}
}

config_section_label = |tab| {
	match tab {
		Terms => "Term"
		Subjects => "Subject"
		ClassLevels => "Class level"
		Curriculum => "Curriculum link"
		SessionTerms => "Session term"
		Credentials => "Qualification"
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
		Credentials => "credentials"
	}
}

# The role a user tab holds, the same names the role picker and the backend's `role=` parameter use.
# Completing a profile starts from the tab the row was on, so the form shows that role's fields.
user_tab_role = |tab| {
	match tab {
		Students => "Student"
		Teachers => "Teacher"
		Parents => "Parent"
		Admins => "Admin"
	}
}

# Whether a user-form value may be sent. The create/update payload is hand-written JSON with no
# escape handling (the backend reads each field as the text between its first two quotes), and the
# directory rows are "|"-separated lines the Edit form splits back apart — so a double quote or
# backslash would be stored silently truncated, and a pipe or line break would shift the row fields
# under Edit. Refused up front with the form's own message, never silently corrupted.
user_text_ok : Str -> Bool
user_text_ok = |text| {
	!Str.contains(text, "\"") and !Str.contains(text, "\\") and !Str.contains(text, "|") and !Str.contains(text, "\n")
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
		Credentials => "{\"name\":\"${model.newCredentialName}\"}"
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
		# A qualification's only editable column is its name.
		Credentials => "${id_field}${json_text_field("name", model.editField1)}}"
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
		Credentials => { ..model, newCredentialName: "" }
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
					Port.send("fetch_data", "/api/credentials"),
				]
				AdminLMS => [
					Port.send("fetch_data", "/api/class_levels?admin_lms=1"),
					Port.send("fetch_data", "/api/class-subjects"),
					Port.send("fetch_data", "/api/student/terms?admin_lms=1"),
				]
				_ => []
			}
			({ ..model, route: newRoute, mobileMenuOpen: Bool.False }, fetches)
		}
		# Entering a page fetches what it cannot show without: the hub its five lists (its hidden
		# inputs only exist there), and user management the list of the tab it opens on, so it shows
		# current data rather than whatever a previous visit left in the model.
		NavigateTo(AdminUserManagement) => {
			active_tab_url = match model.activeUserTab {
				Students => "/api/users?role=Student"
				Teachers => "/api/users?role=Teacher"
				Parents => "/api/users?role=Parent"
				Admins => "/api/users?role=Admin"
			}
			(
				{ ..model, route: AdminUserManagement, mobileMenuOpen: Bool.False },
			                        [
			                                Port.send("push_state", "/admin/users"),
			                                Port.send("fetch_data", active_tab_url),
			                                # The create form's class-level picker needs the active levels, and
			                                # fetching them here means the dropdown is ready before a first submit.
			                                Port.send("fetch_data", "/api/class_levels"),
			                                # The teacher form's qualifications picker and the Assign dialog's pairs.
			                                Port.send("fetch_data", "/api/credentials"),
			                                Port.send("fetch_data", "/api/class-subjects"),
			                        ]
			)
		}
		NavigateTo(AdminLMS) => (
			{ ..model, route: AdminLMS, mobileMenuOpen: Bool.False, adminLmsClassId: "", adminLmsClassName: "", adminLmsSubjectId: "", adminLmsSubjectName: "", adminLmsTermId: "", adminLmsTermName: "", adminLmsLessonsData: "", currentLessonContent: "" },
			[
				Port.send("push_state", "/admin/lms"),
				Port.send("fetch_data", "/api/class_levels?admin_lms=1"),
				Port.send("fetch_data", "/api/class-subjects"),
				Port.send("fetch_data", "/api/student/terms?admin_lms=1"),
			]
		)
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
				Port.send("fetch_data", "/api/credentials"),
			]
		)
		NavigateTo(route) => {
			urlStr = match route {
				Dashboard => "/"
				AdminUserManagement => "/admin/users"
				AdminConfigurationHub => "/admin/config"
				AdminLMS => "/admin/lms"
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
		            ToggleUserMenu => {
			                    ({ ..model, userMenuOpen: !(model.userMenuOpen) }, [])
		}
		            CloseUserMenu => {
			                    ({ ..model, userMenuOpen: Bool.False }, [])
		}
		                SignOut => {
		                        ({ ..model, route: Dashboard, role: Unauthenticated, authToken: "", userMenuOpen: Bool.False }, [
		                                Port.send("save_token", ""),
		                                # The page builds this URL: the post-logout redirect is the app's own origin,
		                                # which a fixed string here could not know. The retired app did the same, from
		                                # Authentik's `end_session_endpoint` and its own ORIGIN.
		                                Port.send("end_session", "")
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
		UpdateNewUserPassword(s) =>
			({ ..model, newUserPassword: s }, [])
		GenerateUserPassword =>
			(model, [Port.send("generate_password", "")])
		CopyLastCredentials =>
			match model.lastCredentials {
				None => (model, [])
				Credentials(email, password) =>
					(
						model,
						[Port.send("copy_to_clipboard", if Str.is_empty(email) { password } else { "${email}\n${password}" })]
					)
			}
		GotUsersData(str) => ({ ..model, usersData: str }, [])
		GotTermsData(str) => ({ ..model, termsData: str }, [])
		GotSubjectsData(str) => ({ ..model, subjectsData: str }, [])
		            GotClassLevelsData(str) => ({ ..model, classLevelsData: str }, [])
		            GotUserClassLevels(str) => ({ ..model, userClassLevelsData: str }, [])
		GotCurriculumData(str) => ({ ..model, curriculumData: str }, [])
		GotSessionTermsData(str) => ({ ..model, sessionTermsData: str }, [])
		GotConfigSubjectsData(str) => ({ ..model, configSubjectsData: str }, [])
		UpdateNewCredentialName(s) => ({ ..model, newCredentialName: s }, [])
		GotTeacherClassesData(s) => ({ ..model, teacherClassesData: s }, [])
		GotSubjectPairsData(s) => ({ ..model, subjectPairsData: s }, [])
		GotCredentialsData(s) => ({ ..model, credentialsData: s }, [])
		GotAdminLmsTermsData(s) => ({ ..model, adminLmsTermsData: s }, [])
		GotAdminLmsLessonsData(s) => ({ ..model, adminLmsLessonsData: s }, [])
		GotAdminLmsClassesData(s) => ({ ..model, adminLmsClassesData: s }, [])
		# --- The teacher-row Assign dialog ---
		OpenTeacherAssign(id) => (
			{ ..model, assignDialogOpen: Bool.True, assignTeacherId: id, assignSelectedEdges: [], assignSeeded: Bool.False, assignSearch: "", assignSaveResult: None },
			[
				Port.send("fetch_data", "/api/class-subjects"),
				Port.send("fetch_data", "/api/teacher-assignments?teacher_id=${id}"),
			]
		)
		CloseTeacherAssign => ({ ..model, assignDialogOpen: Bool.False, assignTeacherId: "", assignSelectedEdges: [], assignSeeded: Bool.False, assignSearch: "", assignSaveResult: None }, [])
		GotTeacherAssignmentsData(s) => {
			# The fetch answers after the dialog opened, so the current pairs seed the badge list once
			# — never again, or a post-save refetch would undo the admin's edits.
			(after, effects) =
				if model.assignDialogOpen and !model.assignSeeded {
					seeded = match list_state(s) {
						Ready(rows) => List.keep_if(List.map(rows, |line| config_part(Str.split_on(line, "|"), 0)), |edge| !Str.is_empty(edge))
						_ => []
					}
					({ ..model, teacherAssignmentsData: s, assignSelectedEdges: seeded, assignSeeded: Bool.True }, [])
				} else {
					({ ..model, teacherAssignmentsData: s }, [])
				}
			(after, effects)
		}
		AddAssignPair(edge) => (
			{ ..model, assignSelectedEdges: List.append(model.assignSelectedEdges, edge), assignSearch: "", assignSaveResult: None },
			[]
		)
		RemoveAssignPair(edge) => ({ ..model, assignSelectedEdges: List.keep_if(model.assignSelectedEdges, |e| e != edge) }, [])
		UpdateAssignSearch(s) => ({ ..model, assignSearch: s }, [])
		SubmitTeacherAssign => {
			# The whole replacement list, like the retired agent's save: what the dialog shows is what
			# the teacher ends up with (the backend hides the dropped rows and revives or creates the
			# kept ones, scoped to the active session term). An empty list means "clear the teacher".
			pairs_json = "[${Str.join_with(List.map(model.assignSelectedEdges, |edge| "{\"edge_id\":\"${edge}\"}"), ",")}]"
			req = {
				method: POST,
				uri: "${model.appOrigin}/api/teacher-assignments",
				headers: [
					{ name: "Authorization", value: "Bearer ${model.authToken}" },
					{ name: "Content-Type", value: "application/json" }
				],
				body: Str.to_utf8("{\"teacher_id\":\"${model.assignTeacherId}\",\"pairs\":${pairs_json}}"),
				timeout_ms: NoTimeout,
			}
			({ ..model, assignSaveResult: None }, [Http.request(req, |res| TeacherAssignCompleted(res))])
		}
		TeacherAssignCompleted(res) => {
			newResult : [None, Success(Str), Error(Str)]
			newResult = match res {
				Ok(response) =>
					if response.status == 200 {
						Success("Assignments saved")
					} else {
						Error(backend_error_message(Str.from_utf8_lossy(response.body)))
					}
				Err(HttpErr(Timeout)) => Error("The request timed out")
				Err(HttpErr(NetworkError)) => Error("Could not reach the server")
			}
			# The badges and the next open of the dialog should match what the save wrote.
			refreshes = match newResult {
				Success(_) => [
					Port.send("fetch_data", "/api/class-subjects"),
					Port.send("fetch_data", "/api/teacher-assignments?teacher_id=${model.assignTeacherId}"),
				]
				_ => []
			}
			({ ..model, assignSaveResult: newResult }, refreshes)
		}
		# --- The teacher form's qualifications picker ---
		AddQualification(id) => ({ ..model, newUserQualifications: List.append(model.newUserQualifications, id), qualSearch: "" }, [])
		RemoveQualification(id) => ({ ..model, newUserQualifications: List.keep_if(model.newUserQualifications, |q| q != id) }, [])
		UpdateQualSearch(s) => ({ ..model, qualSearch: s }, [])
		# --- The admin LMS drill-down ---
		SelectAdminClass(id, name) => (
			{ ..model, adminLmsClassId: id, adminLmsClassName: name, adminLmsSubjectId: "", adminLmsSubjectName: "", adminLmsTermId: "", adminLmsTermName: "", adminLmsLessonsData: "", currentLessonContent: "" },
			[]
		)
		BackAdminSubjects => (
			{ ..model, adminLmsClassId: "", adminLmsClassName: "", adminLmsSubjectId: "", adminLmsSubjectName: "", adminLmsTermId: "", adminLmsTermName: "", adminLmsLessonsData: "", currentLessonContent: "" },
			[]
		)
		SelectAdminSubject(id, name) => (
			{ ..model, adminLmsSubjectId: id, adminLmsSubjectName: name, adminLmsTermId: "", adminLmsTermName: "", adminLmsLessonsData: "", currentLessonContent: "" },
			[Port.send("fetch_data", "/api/student/terms?admin_lms=1")]
		)
		BackAdminTerms => (
			{ ..model, adminLmsSubjectId: "", adminLmsSubjectName: "", adminLmsTermId: "", adminLmsTermName: "", adminLmsLessonsData: "", currentLessonContent: "" },
			[]
		)
		SelectAdminTerm(id, name) => (
			{ ..model, adminLmsTermId: id, adminLmsTermName: name, adminLmsLessonsData: "", currentLessonContent: "" },
			[Port.send("fetch_data", "/api/teacher/lessons?class_id=${model.adminLmsClassId}&subject_id=${model.adminLmsSubjectId}&term_id=${id}&admin_lms=1")]
		)
		OpenAdminLesson(id) => (
			{ ..model, selectedLessonId: id, currentLessonContent: "" },
			[Port.send("fetch_data", "/api/student/lesson?lesson_id=${id}")]
		)
		BackAdminLessons => (
			{ ..model, adminLmsTermId: "", adminLmsTermName: "", adminLmsLessonsData: "", selectedLessonId: "", currentLessonContent: "" },
			[]
		)
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
		# A retry re-runs exactly the fetch the failed list's control names.
		RetryList(url) => (model, [Port.send("fetch_data", url)])
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
			# The form's values travel as hand-written JSON in the payload (the backend reads between
			# the first two quotes of each field, so nothing is escaped) and as "|"-separated directory
			# lines the Edit form splits back apart. A double quote or backslash in a value would
			# therefore be stored silently truncated, and a pipe or line break would shift the fields
			# under Edit — so such values are refused up front, like the required-field checks. The
			# input is rejected, never corrupted.
			forbidden = List.keep_if([
				model.newUserFirstName,
				model.newUserMiddleName,
				model.newUserSurname,
				model.newUserEmail,
				model.newUserDateOfBirth,
				model.newUserClassLevel,
				model.newUserRoleTitle,
				model.newUserPassportKey,
				model.newUserPassword,
			], |field| !user_text_ok(field))
			if !List.is_empty(forbidden) {
				(
					{ ..model, isSubmitting: Bool.False, submitResult: Error("Values may not contain double quotes, backslashes, pipes or line breaks") },
					[]
				)
			} else {
			# One form, two writes. With no id the login does not exist yet, so POST creates the login and
		# its profile together; with one, the login is already in the directory (the admin made it in
		# Authentik) and PUT attaches the profile to that pk. The email is the login's own address and
		# is editable in every mode — the backend patches Authentik (PUT) or makes the login with it
		# (POST) — so an account that was created without one, or with a typo, can be fixed from the
		# form. The role comes from the id's table on the backend, and is never sent by a PUT.
		completing = !Str.is_empty(model.completingProfileId)
		identity_fields =
			if completing {
				"\"id\":\"${model.completingProfileId}\",\"email\":\"${model.newUserEmail}\","
			} else {
				"\"role\":\"${model.newUserRole}\",\"email\":\"${model.newUserEmail}\","
			}
			# The password rides the create only, and only when the admin gave one: the backend treats an
			# absent field as a login without a password, which the row actions can set later.
			password_clause =
				if completing or Str.is_empty(model.newUserPassword) {
					""
				} else {
					",\"password\":\"${model.newUserPassword}\""
				}
			# role_title is a column of admin_profile only, and the form shows it only for the Admin
			# role — a carried-but-unwritable field is a 400 on the backend ("'role_title' is not a
			# column of student_profile"), so the payload has to mirror the form's own visibility.
			role_title_clause =
				if model.newUserRole == "Admin" {
					",\"role_title\":\"${model.newUserRoleTitle}\""
				} else {
					""
				}
			# A teacher's qualifications are the credentials record ids the picker selected: the
			# backend stores them as record links. Only the teacher profile declares the column, so
			# the clause mirrors the form's own visibility like role_title above (an empty selection
			# is sent as an empty array, which is how an edit clears the row's qualifications).
			qual_clause =
				if model.newUserRole == "Teacher" {
					ids_json = Str.join_with(model.newUserQualifications, "\",\"")
					if Str.is_empty(ids_json) { ",\"qualifications\":[]" } else { ",\"qualifications\":[\"${ids_json}\"]" }
				} else {
					""
				}
			payload = "{${identity_fields}\"first_name\":\"${model.newUserFirstName}\",\"middle_name\":\"${model.newUserMiddleName}\",\"surname\":\"${model.newUserSurname}\",\"date_of_birth\":\"${model.newUserDateOfBirth}\",\"class_level\":\"${model.newUserClassLevel}\",\"passport\":\"${model.newUserPassportKey}\"${role_title_clause}${qual_clause}${password_clause}}"
			req = {
				method: if completing { PUT } else { POST },
				uri: "${model.appOrigin}/api/users",
				headers: [
					{ name: "Authorization", value: "Bearer ${model.authToken}" },
					{ name: "Content-Type", value: "application/json" }
				],
				body: Str.to_utf8(payload),
				timeout_ms: NoTimeout,
			}
				(
					{ ..model, isSubmitting: Bool.True, submitResult: None, lastCredentials: None },
					[Http.request(req, |res| SubmitCompleted(res))]
				)
			}
		}
		# A row the directory lists without a profile: the form loads that login (its name and address are
		# shown, and are not the form's to edit), and the role comes from the tab the row was on.
		CompleteProfile(id, email) => (
			{ ..model,
				userFormOpen: Bool.True,
				completingProfileId: id,
				newUserRole: user_tab_role(model.activeUserTab),
				newUserFirstName: "",
				newUserMiddleName: "",
				newUserSurname: "",
				newUserEmail: email,
				newUserDateOfBirth: "",
				newUserClassLevel: "",
				newUserRoleTitle: "",
				newUserPassportKey: "",
				newUserPassword: "",
				newUserQualifications: [],
				qualSearch: "",
				userEditing: Bool.False,
				lastCredentials: None,
				submitResult: None,
			},
			[]
		)
		CancelCompleteProfile => ({ ..model, userFormOpen: Bool.False, completingProfileId: "", userEditing: Bool.False, resetPasswordId: "", resetPasswordEmail: "", lastCredentials: None, submitResult: None, newUserQualifications: [], qualSearch: "" }, [])
		# Open the form in add mode: the header's Add User button. Everything the completing and
		# editing arms set is cleared, so the modal opens empty.
		OpenUserForm => ({ ..model, userFormOpen: Bool.True, completingProfileId: "", userEditing: Bool.False, resetPasswordId: "", resetPasswordEmail: "", lastCredentials: None, submitResult: None, newUserQualifications: [], qualSearch: "" }, [])
		CloseUserForm => ({ ..model, userFormOpen: Bool.False, completingProfileId: "", userEditing: Bool.False, resetPasswordId: "", resetPasswordEmail: "", lastCredentials: None, submitResult: None, newUserQualifications: [], qualSearch: "" }, [])
		# Edit loads the row's own line into the form (same PUT as completing, prefilled from the row),
		# so an admin can change the school data of an account that already has it — a mis-typed name,
		# the wrong class level, a new passport.
		StartUserEdit(line) => {
			parts = Str.split_on(line, "|")
			part = |i| match List.get(parts, i) { Ok(v) => v, Err(_) => "" }
			# A teacher row's last field is its qualification ids, comma-joined by the page's formatter;
			# the edit form starts with exactly those selected. Any other role carries none.
			quals = List.keep_if(Str.split_on(part(13), ","), |q| !Str.is_empty(q))
			(
				{ ..model,
					userFormOpen: Bool.True,
					completingProfileId: part(0),
					newUserRole: user_tab_role(model.activeUserTab),
					newUserFirstName: part(6),
					newUserMiddleName: part(7),
					newUserSurname: part(8),
					newUserEmail: part(2),
					newUserDateOfBirth: part(9),
					newUserClassLevel: part(10),
					# role_title is a column of admin_profile only, so only an admin row can carry one; the
					# other tables' fixture rows can hold a stray flex value, which the form must not
					# prefill (a carried field the table cannot write is a 400 on the backend).
					newUserRoleTitle: if user_tab_role(model.activeUserTab) == "Admin" { part(11) } else { "" },
					newUserPassportKey: part(12),
					newUserPassword: "",
					newUserQualifications: if user_tab_role(model.activeUserTab) == "Teacher" { quals } else { [] },
					qualSearch: "",
					userEditing: Bool.True,
					lastCredentials: None,
					submitResult: None,
				},
				[]
			)
		}
		SubmitCompleted(res) => {
			# The same form, three outcomes: the message says which write it was.
			was_completing = !Str.is_empty(model.completingProfileId)
			was_editing = model.userEditing
			newResult : [None, Success(Str), Error(Str)]
			newResult = match res {
				Ok(response) => {
					if response.status == 200 {
						Success(
							if was_editing { "User updated" }
						else if was_completing { "Profile completed" }
						else { "User created" }
						)
					} else {
						# Failures answer {"error":"..."} with the validation text, or a write's own
						# {"error":"Database error","detail":"..."}; show what the backend said.
						Error(backend_error_message(Str.from_utf8_lossy(response.body)))
					}
				}
				Err(HttpErr(Timeout)) => Error("The request timed out")
				Err(HttpErr(NetworkError)) => Error("Could not reach the server")
			}
			# A create that carried a password hands it over once: the form is cleared right below (the
			# value is never stored anywhere), so capture the credentials here, before the clear.
			handoff : [None, Credentials(Str, Str)]
			handoff =
				if was_editing or was_completing {
					None
				} else {
					match newResult {
						Success(_) =>
							if Str.is_empty(model.newUserPassword) { None }
							else { Credentials(model.newUserEmail, model.newUserPassword) }
						_ => None
					}
				}
			# Refresh the role lists so the new account shows up without a manual reload — and, after a
			# completed profile, as a normal row rather than one waiting for its school data.
			refresh = match newResult {
				Success(_) => [
					Port.send("fetch_data", "/api/users?role=Student"),
					Port.send("fetch_data", "/api/users?role=Teacher"),
					Port.send("fetch_data", "/api/users?role=Parent"),
					Port.send("fetch_data", "/api/users?role=Admin"),
				]
				_ => []
			}
			({ ..model, isSubmitting: Bool.False, submitResult: newResult, completingProfileId: "", userEditing: Bool.False, userFormOpen: Bool.False, newUserPassword: "", lastCredentials: handoff, newUserFirstName: "", newUserMiddleName: "", newUserSurname: "", newUserEmail: "", newUserDateOfBirth: "", newUserClassLevel: "", newUserRoleTitle: "", newUserQualifications: [], qualSearch: "", assignSelectedEdges: [], assignSeeded: Bool.False, assignSearch: "", assignSaveResult: None }, refresh)
		}
		# --- A row's actions: deactivate and activate ---
		# The two toggles are the reverse of each other. Both refresh the lists when they land, so the
		# row's new state (an Inactive badge and No profile yet for a deactivate; the profile back and
		# the login enabled for an activate) shows without a reload.
		SubmitDeactivateUser(id) => {
			req = {
				method: DELETE,
				uri: "${model.appOrigin}/api/users",
				headers: [
					{ name: "Authorization", value: "Bearer ${model.authToken}" },
					{ name: "Content-Type", value: "application/json" }
				],
				body: Str.to_utf8("{\"id\":\"${id}\"}"),
				timeout_ms: NoTimeout,
			}
			(
				{ ..model, isSubmitting: Bool.True, submitResult: None },
				[Http.request(req, |res| UserToggleCompleted(Deactivate, res))]
			)
		}
		SubmitActivateUser(id) => {
			req = {
				method: POST,
				uri: "${model.appOrigin}/api/users/activate",
				headers: [
					{ name: "Authorization", value: "Bearer ${model.authToken}" },
					{ name: "Content-Type", value: "application/json" }
				],
				body: Str.to_utf8("{\"id\":\"${id}\"}"),
				timeout_ms: NoTimeout,
			}
			(
				{ ..model, isSubmitting: Bool.True, submitResult: None },
				[Http.request(req, |res| UserToggleCompleted(Activate, res))]
			)
		}
		UserToggleCompleted(action, res) => {
			verb = match action { Deactivate => "deleted" Activate => "activated" }
			newResult : [None, Success(Str), Error(Str)]
			newResult = match res {
				Ok(response) =>
					if response.status == 200 {
						Success("User ${verb}")
					} else {
						Error(backend_error_message(Str.from_utf8_lossy(response.body)))
					}
				Err(HttpErr(Timeout)) => Error("The request timed out")
				Err(HttpErr(NetworkError)) => Error("Could not reach the server")
			}
			# A bulk delete cleared the selection up front; a single row's delete leaves whatever
			# selection exists alone.
			refresh = match newResult {
				Success(_) => [
					Port.send("fetch_data", "/api/users?role=Student"),
					Port.send("fetch_data", "/api/users?role=Teacher"),
					Port.send("fetch_data", "/api/users?role=Parent"),
					Port.send("fetch_data", "/api/users?role=Admin"),
				]
				_ => []
			}
			({ ..model, isSubmitting: Bool.False, submitResult: newResult }, refresh)
		}
		# --- Reset a login's password (the row's Reset password action) ---
		OpenResetPassword(id, email) => (
			{ ..model,
				userFormOpen: Bool.True,
				resetPasswordId: id,
				resetPasswordEmail: email,
				newUserPassword: "",
				completingProfileId: "",
				userEditing: Bool.False,
				lastCredentials: None,
				submitResult: None,
			},
			[]
		)
		SubmitResetPassword => {
			if Str.is_empty(model.resetPasswordId) {
				({ ..model, submitResult: Error("Choose the row's Reset password action first") }, [])
			} else if Str.is_empty(model.newUserPassword) {
				({ ..model, submitResult: Error("Password is required") }, [])
			} else if !user_text_ok(model.newUserPassword) {
				({ ..model, isSubmitting: Bool.False, submitResult: Error("Values may not contain double quotes, backslashes, pipes or line breaks") }, [])
			} else {
				req = {
					method: POST,
					uri: "${model.appOrigin}/api/users/set-password",
					headers: [
						{ name: "Authorization", value: "Bearer ${model.authToken}" },
						{ name: "Content-Type", value: "application/json" }
					],
					body: Str.to_utf8("{\"id\":\"${model.resetPasswordId}\",\"password\":\"${model.newUserPassword}\"}"),
					timeout_ms: NoTimeout,
				}
				(
					{ ..model, isSubmitting: Bool.True, submitResult: None },
					[Http.request(req, |res| ResetPasswordCompleted(res))]
				)
			}
		}
		ResetPasswordCompleted(res) => {
			newResult : [None, Success(Str), Error(Str)]
			newResult = match res {
				Ok(response) =>
					if response.status == 200 {
						Success("Password updated")
					} else {
						Error(backend_error_message(Str.from_utf8_lossy(response.body)))
					}
				Err(HttpErr(Timeout)) => Error("The request timed out")
				Err(HttpErr(NetworkError)) => Error("Could not reach the server")
			}
			# The new password is handed over once, in the credentials panel, then never shown again.
			handoff : [None, Credentials(Str, Str)]
			handoff = match newResult {
				Success(_) =>
					if Str.is_empty(model.newUserPassword) { None }
					else { Credentials(model.resetPasswordEmail, model.newUserPassword) }
				_ => None
			}
			({ ..model, isSubmitting: Bool.False, submitResult: newResult, resetPasswordId: "", resetPasswordEmail: "", newUserPassword: "", userFormOpen: Bool.False, lastCredentials: handoff }, [])
		}
		# --- Bulk delete: tick rows, then remove the selection ---
		ToggleUserSelected(id) => {
			selected =
				if List.contains(model.selectedUserIds, id) {
					List.keep_if(model.selectedUserIds, |sid| sid != id)
				} else {
					List.append(model.selectedUserIds, id)
				}
			({ ..model, selectedUserIds: selected }, [])
		}
		ClearUserSelection => ({ ..model, selectedUserIds: [] }, [])
		DeleteSelectedUsers => {
			# One DELETE per selected id — the same request the row's Delete action makes — and the
			# selection is cleared up front so a row that answers 502 (a reachable login that could
			# not be disabled) still falls out of the next click's way.
			deletes = List.map(model.selectedUserIds, |id| {
				req = {
					method: DELETE,
					uri: "${model.appOrigin}/api/users",
					headers: [
						{ name: "Authorization", value: "Bearer ${model.authToken}" },
						{ name: "Content-Type", value: "application/json" }
					],
					body: Str.to_utf8("{\"id\":\"${id}\"}"),
					timeout_ms: NoTimeout,
				}
				Http.request(req, |res| UserToggleCompleted(Deactivate, res))
			})
			(
				{ ..model, selectedUserIds: [], isSubmitting: Bool.True, submitResult: None },
				deletes
			)
		}
		# Switching tabs fetches that tab's own list: the four lists are separate payloads, so a tab
		# never stays on its skeleton waiting for a fetch the previous tab started.
		SetUserTab(tab) => {
			url = match tab {
				Students => "/api/users?role=Student"
				Teachers => "/api/users?role=Teacher"
				Parents => "/api/users?role=Parent"
				Admins => "/api/users?role=Admin"
			}
			({ ..model, activeUserTab: tab }, [Port.send("fetch_data", url)])
		}
		GotSessionTermData(s) => ({ ..model, sessionTermData: s }, [])
		UpdateNewUserRole(s) => ({ ..model, newUserRole: s }, [])
		SetPassportKey(k) => ({ ..model, newUserPassportKey: k }, [])
		GotStudentsData(s) => ({ ..model, usersStudentsData: s }, [])
		GotTeachersData(s) => ({ ..model, usersTeachersData: s }, [])
		GotParentsData(s) => ({ ..model, usersParentsData: s }, [])
		GotAdminsData(s) => ({ ..model, usersAdminsData: s }, [])
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
		OpenTeacherSubject(id, name) => (
			{ ..model, selectedSubjectId: id, selectedSubjectName: name, selectedTermId: "", selectedTermName: "", selectedLessonId: "", teacherLessonsData: "", currentLessonContent: "" },
			[
				Port.send("push_state", "/teacher/lessons"),
				Port.send("fetch_data", "/api/teacher/lessons?subject_id=${id}"),
			]
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
