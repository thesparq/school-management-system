module [Model, Msg, init, update, Route, Role, route_path, AdminConfigTab, AdminUserTab, ListState, list_state, catalog_field, admin_catalog_permissions, admin_catalog_types, caller_has_permission, can_manage_admin_rights, admin_type_permissions, admin_default_type]

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
	Settings,
	NotFound,
]

Role : [Admin, Teacher, Student, Parent, Unauthenticated]

# The address a route lives at. One place, because two readers need the same answer: the
# navigation pushes it (`NavigateTo`) and the views put it on the links themselves
# (`UI.link`/`UI.sidebar_nav_item`), so what the browser shows on hover, what Ctrl-click opens in
# a second tab and what the app pushes on a click are the same URL.
route_path : Route -> Str
route_path = |route| {
        match route {
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
                Settings => "/settings"
                NotFound => "/404"
        }
}

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
	    # The navbar bell's dropdown: open state the same way the avatar menu's is, and the page's
	    # JS-serialized toast history ("kind|title|message" per line) rendered from here rather than
	    # written into this node's DOM directly — that bypassed the vdom's own tracking of this
	    # subtree and corrupted later patches (see www/index.html's formatNotifications).
	    notificationsOpen : Bool,
	    notificationsData : Str,
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
	# The dashboard's cards: one "key|value" line per number the backend answered, keyed by what it
	# counts (students, teachers, classes, subjects, pending_grades, assessments, assignments). The
	# view owns the labels, so a number the backend does not send simply shows a dash.
	dashboardData : Str,
	# A parent dashboard's children: one "name|class" line each, fed by /api/parent/children.
	parentChildrenData : Str,
	# Whether this login owes a password change before it may do anything, and why: the payload is
	# /api/me/password-state, "required|reason", and the backend refuses every other route while it stands
	# (a password an administrator chose — at creation or at a reset — has to be replaced first). The page
	# holds itself to the same rule: Settings is the only page until the change is made.
	passwordStateData : Str,
	passwordRequired : Bool,
	passwordReason : Str,
	newPassword : Str,
	confirmPassword : Str,
	# The password they signed in with. Asked only when nothing is owed: a change the person chose has to
	# prove it, and Authentik is the only party that can check one (see `password_check!` in main.roc).
	        currentPassword : Str,
	        # The school's record of this person, for the Settings page's read-only card: one "key|value" line per
	        # fact (`/api/me/profile`, fetched by the page when Settings renders). The view owns the labels, the
	        # same division the dashboard's cards use.
	        profileData : Str,
	        passwordResult : [None, Success(Str), Error(Str)],
	        newUserDateOfBirth : Str,
	        newUserClassLevel : Str,
	        # An administrator's own two facts, and the catalog they come from. `adminTypesData` is
	        # /api/admin-types: one line per permission ("perm|key|label|hint") and one per type
	        # ("type|key|label|hint|tick,tick"), fetched for an admin on boot so the form can open on a type
	        # rather than on an empty picker. `adminRightsData` is the caller's *own* rights
	        # (/api/admin-rights, "is_super|key,key"): the sidebar shows only what it allows, and the form's
	        # picker and ticks are read-only without `permissions.manage`, which is what the backend asks for
	        # any payload that sets either.
	        adminTypesData : Str,
	        adminRightsData : Str,
	        newUserAdminType : Str,
	        newUserPermissions : List(Str),
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
	# The class level of the pair a teacher is browsing (My Classes carries it on the card). It is
	# what scopes the lesson picker to one class's curriculum: the list is filtered by the
	# class-subject edge, not by the subject alone, which would match that subject in every class
	# level and show one "Week N" row per class.
	teacherClassId : Str,
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
	        # Which stage of school the new class level is (primary / junior / senior), or "" for none: the
	        # lesson generator reads this to write senior lessons as senior lessons.
	        newClassLevelTier : Str,
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
	    # The fourth editable column a row can carry: a class level's stage (`tier`). Every other section's
	    # editor uses one to three fields, and the unused ones sit empty.
	    editField4 : Str,
	# The teacher's own class-subject pairs (My Classes cards), the full catalog fed to the Assign
	# dialog and the admin LMS, and one teacher's current pairs (the dialog's badges).
	teacherClassesData : Str,
	subjectPairsData : Str,
	teacherAssignmentsData : Str,
	# The qualifications catalog and the teacher form's selection of it.
	credentialsData : Str,
	newUserQualifications : List(Str),
	qualSearch : Str,
	# The teacher form's date of employment, and the parent form's linked students (with the
	# students search box).
	newUserDateEmployed : Str,
	newUserLinkedStudents : List(Str),
	linkedSearch : Str,
	# The teacher form's own class-subject picker: the edge ids it is showing, its search box, and
	# whether that list is the teacher's real set (`false` until the edit form's fetch answers, which
	# is what stops Save writing an empty set over a teacher's assignments).
	formPairs : List(Str),
	formPairsSearch : Str,
	formPairsSeeded : Bool,
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
	# Escape, wherever the focus is: the app's own subscription (see app.roc). It backs out of the
	# transient layer — the topmost thing that is open over the page: a modal, then the avatar menu,
	# the bell, the phone's sidebar — which is the keyboard's way to do what a click outside or on the
	# backdrop does.
	EscapePressed,
	ToggleTheme,
	    ToggleMobileMenu,
	    # The avatar menu: toggled by the avatar, and closed by a click anywhere outside it (the page's
	    # own listener sends CloseUserMenu) so it never stays open behind a navigation.
	    ToggleUserMenu,
	    CloseUserMenu,
	    # The notifications bell: the same toggle/outside-click-close pair as the avatar menu, plus
	    # the page's serialized toast history arriving through the usual data bridge, and Clear all.
	    ToggleNotifications,
	    CloseNotifications,
	    GotNotificationsData(Str),
	    ClearNotifications,
	TestConnectionClicked,
	PingCompleted([Success(Str), Error(Str)]),
	UpdateNewUserFirstName(Str),
	UpdateNewUserMiddleName(Str),
	UpdateNewUserSurname(Str),
	UpdateNewUserDateOfBirth(Str),
	        UpdateNewUserClassLevel(Str),
	        # The admin form's own two controls: the type the school gives an administrator (the picker) and the
	        # permissions that ride with it (each tick can be taken off or put back).
	        UpdateNewUserAdminType(Str),
	        ToggleNewUserPermission(Str),
	        GotAdminTypesData(Str),
	        GotAdminRightsData(Str),
	        # The password-change screen: the state the backend answers, the two fields, and the write.
	        GotPasswordState(Str),
	        UpdateNewPassword(Str),
	        UpdateConfirmPassword(Str),
	        UpdateCurrentPassword(Str),
	        GotProfileData(Str),
	        SubmitPasswordChange,
	        PasswordChangeCompleted(Try(Http.Response, [HttpErr([Timeout, NetworkError])])),
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
	   GotDashboardData(Str),
	   GotParentChildrenData(Str),
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
	        # A My Classes card: open the lesson picker scoped to that class-subject pair (its lessons are
	        # the teacher's own, filtered by the edge the card carried — the subject alone would match the
	        # same subject in every class level).
	        OpenTeacherSubject(Str, Str, Str),
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
	        UpdateNewClassLevelTier(Str),
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
	        UpdateEditField4(Str),
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
	UpdateNewUserDateEmployed(Str),
	AddLinkedStudent(Str),
	RemoveLinkedStudent(Str),
	UpdateLinkedSearch(Str),
	# The teacher form's class-subject picker, and the fetch that seeds it when editing.
	AddFormPair(Str),
	RemoveFormPair(Str),
	UpdateFormPairsSearch(Str),
	GotFormPairsData(Str),
	# The admin LMS drill-down: class -> subject -> term -> lessons -> lesson content. Every step is
	# its own URL (?class=…, then &subject=…, &term=…, &lesson=…), so the browser's back/forward walks
	# the drill and a reload at depth comes back to the same step. The breadcrumb's links name the
	# step they land on (the crumb for a level is that level's message), so each one goes to its own
	# level rather than just one step up.
	SelectAdminClass(Str, Str),
	BackAdminClasses,
	SelectAdminSubject(Str, Str),
	BackAdminSubjects,
	SelectAdminTerm(Str, Str),
	OpenAdminLesson(Str),
	BackAdminTerms,
	BackAdminLessons,
	GotAdminLmsTermsData(Str),
	GotAdminLmsLessonsData(Str),
	GotAdminLmsClassesData(Str),
]

	    parse_route = |url| {
	            # The query string is state, not routing: `?id=` names the lesson, `?class=`/`?subject=`/`?term=`
	            # the LMS step, and the app reads them from the URL itself. Matching the whole URL meant any
	            # link carrying one — a lesson's own `?id=`, the LMS drill, the teacher's `?id=` — fell through
	            # to NotFound, so a reload of a lesson page rendered the 404 view instead of the lesson.
	            path = match List.first(Str.split_on(url, "?")) { Ok(only_path) => only_path, Err(_) => url }

	            match path {
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
	                    "/settings" => Settings
	                    "/" => Dashboard
	                    _ => NotFound
	            }
	    }

	# One query parameter of a URL target ("?class=A&subject=B" -> "A"), the same reading the
	# backend's query_param uses (values carry no percent-encoding here — the app builds them).
	query_value = |url, name| {
		match List.get(Str.split_on(url, "${name}="), 1) {
			Ok(rest) => match List.first(Str.split_on(rest, "&")) { Ok(value) => value, Err(_) => "" }
			Err(_) => ""
		}
	}

	# The admin LMS state stored in the URL's query string, read back on a direct load or a
	# back/forward: class -> subject -> term -> lesson, each optional and each deeper than the last.
	lms_from_query = |url| {
		{
			class_id: query_value(url, "class"),
			subject_id: query_value(url, "subject"),
			term_id: query_value(url, "term"),
			lesson_id: query_value(url, "lesson"),
		}
	}

	# The fetches a restored drill-down step needs: the deeper steps drop the shallower loaded lists,
	# so each step refetches exactly what it shows (the lessons for a term, the content for a lesson) —
	# plus the three lists that carry the names behind the ids. A reload (or a link) at depth restores
	# the ids from the URL and not the names, and the breadcrumb and headings read the names, so they
	# are asked for at every depth rather than only by the step that shows them.
	lms_history_effects = |state| {
		names = [
			Port.send("fetch_data", "/api/class_levels?admin_lms=1"),
			Port.send("fetch_data", "/api/class-subjects"),
			Port.send("fetch_data", "/api/student/terms?admin_lms=1"),
		]

		step =
			if !Str.is_empty(state.lesson_id) {
				[Port.send("fetch_data", "/api/student/lesson?lesson_id=${state.lesson_id}")]
			} else if !Str.is_empty(state.term_id) {
				[Port.send("fetch_data", "/api/teacher/lessons?class_id=${state.class_id}&subject_id=${state.subject_id}&term_id=${state.term_id}&admin_lms=1")]
			} else if !Str.is_empty(state.subject_id) {
				[Port.send("fetch_data", "/api/student/terms?admin_lms=1")]
			} else {
				[]
			}

		List.concat(names, step)
	}

	# The model half of the same restore.
	lms_model_from_query = |model, state| {
		{ ..model,
			adminLmsClassId: state.class_id,
			adminLmsSubjectId: state.subject_id,
			adminLmsTermId: state.term_id,
			selectedLessonId: state.lesson_id,
			currentLessonContent: "",
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
	# A direct load (or reload) of the admin LMS drill-down restores its depth from the URL's query
	# string; for every other route this reads empty query params and comes back all blank.
	initialLmsState = lms_from_query(pathStr)
	# The lesson a lesson page names in its URL. The student's drill-down decides what to show from its
	# own state, which is empty on a load — so without this a reload (or a shared link) of a lesson page
	# rendered "No subject selected" and the lesson panel the page then fills was never there.
	initialLessonId = if initialRoute == StudentLesson { query_value(pathStr, "id") } else { initialLmsState.lesson_id }

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
		            notificationsOpen: Bool.False,
		            notificationsData: "",
		sessionTermData: "",
		dashboardData: "",
		parentChildrenData: "",
		passwordStateData: "",
		passwordRequired: Bool.False,
		passwordReason: "",
		newPassword: "",
		confirmPassword: "",
		currentPassword: "",
		profileData: "",
		passwordResult: None,
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
		                adminTypesData: "",
		                adminRightsData: "",
		                newUserAdminType: "",
		                newUserPermissions: [],
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
		teacherClassId: "",
		selectedTermId: "",
		selectedTermName: "",
		selectedLessonId: initialLessonId,
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
		                newClassLevelTier: "",
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
		            editField4: "",
		teacherClassesData: "",
		subjectPairsData: "",
		teacherAssignmentsData: "",
		credentialsData: "",
		newUserQualifications: [],
		qualSearch: "",
		newUserDateEmployed: "",
		newUserLinkedStudents: [],
		linkedSearch: "",
		formPairs: [],
		formPairsSearch: "",
		formPairsSeeded: Bool.False,
		assignDialogOpen: Bool.False,
		assignTeacherId: "",
		assignSelectedEdges: [],
		assignSearch: "",
		assignSaveResult: None,
		assignSeeded: Bool.False,
		adminLmsClassId: initialLmsState.class_id,
		adminLmsClassName: "",
		adminLmsSubjectId: initialLmsState.subject_id,
		adminLmsSubjectName: "",
		adminLmsTermId: initialLmsState.term_id,
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
			                        # The caller's own rights and the admin catalog: the sidebar draws every admin route
			                        # from the first, so it is fetched wherever an admin can land directly (this branch,
			                        # the LMS one below, and the role branch further down).
			                        Port.send("fetch_data", "/api/admin-rights"),
			                        Port.send("fetch_data", "/api/admin-types"),
			                        Port.send("fetch_data", "/api/subjects"),
			Port.send("fetch_data", "/api/teacher/lessons"),
			Port.send("fetch_data", "/api/terms"),
			Port.send("fetch_data", "/api/class_levels?all=true"),
			Port.send("fetch_data", "/api/curriculum?all=true"),
			Port.send("fetch_data", "/api/session_terms"),
			Port.send("fetch_data", "/api/subjects?all=true"),
			Port.send("fetch_data", "/api/credentials"),
		]
		# A direct load (or reload) of the drill-down at depth restores its state from the URL (the
		# model fields above already carry the ids; this just adds the fetches that depth needs).
		                AdminLMS => List.concat(lms_history_effects(initialLmsState), [
		                        Port.send("fetch_data", "/api/class_levels?admin_lms=1"),
		                        Port.send("fetch_data", "/api/class-subjects"),
		                        Port.send("fetch_data", "/api/student/terms?admin_lms=1"),
		                        # The sidebar's own two (see the configuration branch above).
		                        Port.send("fetch_data", "/api/admin-rights"),
		                        Port.send("fetch_data", "/api/admin-types"),
		                ])
			                _ => match initialRole {
		                                    Admin => [
		                                            Port.send("fetch_data", "/api/users?role=Student"),
		                                            Port.send("fetch_data", "/api/users?role=Teacher"),
		                                            Port.send("fetch_data", "/api/users?role=Parent"),
		                                            Port.send("fetch_data", "/api/users?role=Admin"),
		                                            # The admin form's own catalog and the caller's own rights: the
		                                            # sidebar reads the second before it draws a screen the backend
		                                            # would refuse, and the form reads both.
		                                            Port.send("fetch_data", "/api/admin-types"),
		                                            Port.send("fetch_data", "/api/admin-rights"),
		                                            Port.send("fetch_data", "/api/subjects"),
		                                            Port.send("fetch_data", "/api/teacher/lessons"),
		                                            Port.send("fetch_data", "/api/teacher/classes"),
		                                            Port.send("fetch_data", "/api/class_levels"),
		                                            Port.send("fetch_data", "/api/credentials"),
		                                            Port.send("fetch_data", "/api/class-subjects"),
		                                            Port.send("fetch_data", "/api/class_levels?admin_lms=1"),
		                                            Port.send("fetch_data", "/api/student/terms?admin_lms=1"),
		                                            Port.send("fetch_data", "/api/dashboard"),
		                                    ]
		                                    Teacher => [
		                                            Port.send("fetch_data", "/api/subjects"),
		                                            Port.send("fetch_data", "/api/teacher/lessons"),
		                                            Port.send("fetch_data", "/api/teacher/classes"),
		                                            Port.send("fetch_data", "/api/dashboard"),
		                                    ]
		                                    Student => [
		                                            Port.send("fetch_data", "/api/subjects"),
		                                            Port.send("fetch_data", "/api/dashboard"),
		                                    ]
		                                    Parent => [
		                                            Port.send("fetch_data", "/api/dashboard"),
		                                            Port.send("fetch_data", "/api/parent/children"),
		                                    ]
		                        _ => []
		                }
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

# --- An administrator's type and permissions: the catalog, and the caller's own rights --------------

# The catalog's own lines: /api/admin-types answers one "perm|key|label|hint" line per permission and one
# "type|key|label|hint|tick,tick" line per type. The view renders the first as the checkboxes and the second
# as the type picker, so the two readers below are the only place that knows the shape.
admin_catalog_permissions = |data| List.keep_if(Str.split_on(data, "\n"), |line| Str.starts_with(line, "perm|"))
admin_catalog_types = |data| List.keep_if(Str.split_on(data, "\n"), |line| Str.starts_with(line, "type|"))

# One field of a catalog line, by index; index 0 is the line's own kind ("perm" or "type").
catalog_field = |line, index| match List.get(Str.split_on(line, "|"), index) {
        Ok(value) => value
        Err(_) => ""
}

# The ticks a type starts on, as the catalog writes them (comma-joined). A recursive scan rather than
# `keep_if` + `first`: that pair miscompiles in this Roc.
admin_type_ticks = |data, kind| {
        look = |remaining| match remaining {
                [] => ""
                [line, .. as rest] => if catalog_field(line, 1) == kind { catalog_field(line, 4) } else { look(rest) }
        }

        look(admin_catalog_types(data))
}

# The same, as the list the model holds and the payload sends.
admin_type_permissions = |data, kind| {
        joined = admin_type_ticks(data, kind)

        if Str.is_empty(joined) { [] } else { List.keep_if(Str.split_on(joined, ","), |key| !Str.is_empty(key)) }
}

# The type a fresh admin form starts on: the one the catalog gives the fewest ticks, so clicking Add and
# Save without touching the panel hands out the school's narrowest seat rather than its widest. Super Admin
# is every permission, so it is never the default; with no catalog yet there is no type to start on and the
# form waits for the fetch (GotAdminTypesData seeds it).
admin_default_type = |data| {
        count_ticks = |kind| {
                joined = admin_type_ticks(data, kind)
                if Str.is_empty(joined) { 0 } else { List.len(Str.split_on(joined, ",")) }
        }

        look = |remaining, best, best_count| match remaining {
                [] => best
                [line, .. as rest] => {
                        kind = catalog_field(line, 1)
                        count = count_ticks(kind)

                        if Str.is_empty(best) or count < best_count {
                                look(rest, kind, count)
                        } else {
                                look(rest, best, best_count)
                        }
                }
        }

        look(admin_catalog_types(data), "", 0)
}

# Whether the caller's own rights hold one permission — the question the sidebar asks before showing a screen
# the backend would refuse. `adminRightsData` is /api/admin-rights' answer, "is_super|key,key". An answer that
# has not arrived yet, or a request that failed, reads as "everything": the backend is the authority that
# refuses, and hiding the school's own screens from a super admin whose one request hiccuped is the worse
# failure of the two.
caller_has_permission = |model, key| {
        match list_state(model.adminRightsData) {
                Ready([line, ..]) => {
                        parts = Str.split_on(line, "|")
                        is_super = match List.get(parts, 0) { Ok(value) => value == "true", Err(_) => Bool.False }
                        granted = match List.get(parts, 1) { Ok(value) => value, Err(_) => "" }

                        is_super or List.contains(List.keep_if(Str.split_on(granted, ","), |granted_key| !Str.is_empty(granted_key)), key)
                }
                _ => Bool.True,
        }
}

# Whether this caller may set an administrator's type and ticks: the permission that owns them, which is what
# the backend asks for and what makes the form's own panel read-only for anyone else.
can_manage_admin_rights = |model| caller_has_permission(model, "permissions.manage")

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
		                ClassLevels => "{\"name\":\"${model.newClassLevelName}\",\"code\":\"${model.newClassLevelCode}\"${new_tier_field(model.newClassLevelTier)}}"
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
		            ClassLevels => "${id_field}${json_text_field("name", model.editField1)}${json_text_field("code", model.editField2)}${json_text_field("age_range", model.editField3)}${tier_clause(model.editField4)}}"
		SessionTerms => "${id_field}${json_text_field("session_name", model.editField1)}${json_text_field("term", model.editField2)}}"
		# A curriculum link has no editable column — it is linked or not — so the views only ever
		# offer its toggle; this branch keeps the match exhaustive.
		Curriculum => "${id_field}}"
		# A qualification's only editable column is its name.
		Credentials => "${id_field}${json_text_field("name", model.editField1)}}"
	}

	{ endpoint: config_endpoint(tab), payload }
}

# The class level's stage in an update payload. "Not set" reaches the backend as the word `none`, which
# it writes as NONE (the column's empty value, `db/schema-v13`); an empty string means the editor never
# touched it, so the patch leaves the column alone.
tier_clause = |value| {
	if Str.is_empty(value) {
		""
	} else {
		",\"tier\":\"${value}\""
	}
}

# The stage of a *new* class level: "Not set" and the untouched form both mean the row is created without
# one (the column allows NONE), so neither sends a value.
new_tier_field = |value| {
	if Str.is_empty(value) or value == "none" {
		""
	} else {
		",\"tier\":\"${value}\""
	}
}

# Leaving edit mode, after a save or a cancel. Only one row is open at a time.
config_edit_cleared = |model| {
	    { ..model, editId: "", editField1: "", editField2: "", editField3: "", editField4: "" }
}

# A successful create clears only its own form.
config_form_cleared = |model, tab| {
	match tab {
		Terms => { ..model, newTermName: "", newTermSortOrder: "" }
		Subjects => { ..model, newSubjectName: "", newSubjectCode: "" }
		        ClassLevels => { ..model, newClassLevelName: "", newClassLevelCode: "", newClassLevelTier: "" }
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

# One notification for the page's toast/bell system: kind, title and message, as a
# newline-delimited port value (".\n"). The page never rebuilds messages from these parts.
notify : Str, Str, Str -> Effect(Msg)
notify = |kind, title, message| {
	Port.send("notify", "${kind}\n${title}\n${message}")
}

# The success/error notification pair for a finished write, to be added to the arm's effects.
notification_for : [None, Success(Str), Error(Str)], Str -> List(Effect(Msg))
notification_for = |result, title| {
	match result {
		Success(msg) => [notify("success", title, msg)]
		Error(msg) => [notify("error", title, msg)]
		None => []
	}
}

# The page's own gate, in front of every message: while a password change is owed, Settings is the only
# page (the backend refuses every other route anyway, so navigating would land on a shell of errors).
# Signing out, and the write that meets the requirement, still go through.
update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg| {
	is_navigation = match msg {
		NavigateTo(_) => Bool.True
		UrlChanged(_) => Bool.True
		_ => Bool.False
	}

	if model.passwordRequired and is_navigation and model.route != Settings {
		({ ..model, route: Settings, mobileMenuOpen: Bool.False }, [Port.send("push_state", route_path(Settings))])
	} else {
		dispatch(model, msg)
	}
}

# Closers the page and the keyboard share. Both modals are closed from their own ✕/Cancel and
# from Escape (see the EscapePressed arm), and the two have to leave the model in the same state:
# every draft the modal carried goes with it, so opening it again starts fresh.

# The user form's modal: create, complete-profile, edit and reset-password all live in it, so the
# fields, the seat the pairs picker seeded itself from and the once-only credentials panel all go
# with it.
close_user_form = |model| {
        { ..model, userFormOpen: Bool.False, formPairs: [], formPairsSearch: "", formPairsSeeded: Bool.False, completingProfileId: "", userEditing: Bool.False, resetPasswordId: "", resetPasswordEmail: "", lastCredentials: None, submitResult: None, newUserQualifications: [], qualSearch: "", newUserDateEmployed: "", newUserLinkedStudents: [], linkedSearch: "" }
}

# The teacher's Assign dialog: the badges, the search box and the last save's answer all belong to
# the dialog, and the next open seeds itself from the teacher's own pairs again.
close_assign_dialog = |model| {
        { ..model, assignDialogOpen: Bool.False, assignTeacherId: "", assignSelectedEdges: [], assignSeeded: Bool.False, assignSearch: "", assignSaveResult: None }
}

dispatch : Model, Msg -> (Model, List(Effect(Msg)))
dispatch = |model, msg|
	match msg {
		UrlChanged(url) => {
			newRoute = parse_route(url)
			# A lesson page's own lesson, read from its URL: back/forward onto one has to land on that
			# lesson (every other route leaves the field as it was).
			studentLessonId = if newRoute == StudentLesson { query_value(url, "id") } else { model.selectedLessonId }
			# Back/forward through the admin LMS drill: the URL carries the step, restore it and
			# refetch what that step shows.
			if newRoute == AdminLMS {
				lms_state = lms_from_query(url)
				(lms_model_from_query({ ..model, route: newRoute, mobileMenuOpen: Bool.False }, lms_state), lms_history_effects(lms_state))
			} else {
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
					StudentSubjects => [
						Port.send("fetch_data", "/api/subjects"),
					]
					_ => []
				}
				({ ..model, route: newRoute, mobileMenuOpen: Bool.False, selectedLessonId: studentLessonId }, fetches)
			}
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
			                                Port.send("push_state", route_path(AdminUserManagement)),
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
				Port.send("push_state", route_path(AdminLMS)),
				Port.send("fetch_data", "/api/class_levels?admin_lms=1"),
				Port.send("fetch_data", "/api/class-subjects"),
				Port.send("fetch_data", "/api/student/terms?admin_lms=1"),
			]
		)
		NavigateTo(StudentSubjects) => (
			{ ..model, route: StudentSubjects, mobileMenuOpen: Bool.False, selectedSubjectId: "", selectedSubjectName: "", selectedTermId: "", selectedTermName: "", selectedLessonId: "", studentTermsData: "", studentLessonsData: "", currentLessonContent: "" },
			[
				Port.send("push_state", route_path(StudentSubjects)),
				# The list's payload can be dropped when the boot fetch answered before this page's
				# hidden input existed — refetch on entry, like the admin pages do, so a first
				# navigation after a login never strands the list on its skeleton.
				Port.send("fetch_data", "/api/subjects"),
			]
		)
		NavigateTo(AdminConfigurationHub) => (
			{ ..model, route: AdminConfigurationHub, mobileMenuOpen: Bool.False },
			[
				Port.send("push_state", route_path(AdminConfigurationHub)),
				Port.send("fetch_data", "/api/terms"),
				Port.send("fetch_data", "/api/subjects"),
				Port.send("fetch_data", "/api/subjects?all=true"),
				Port.send("fetch_data", "/api/class_levels?all=true"),
				Port.send("fetch_data", "/api/curriculum?all=true"),
				Port.send("fetch_data", "/api/session_terms"),
				Port.send("fetch_data", "/api/credentials"),
			]
		)
		# The dashboard's numbers are counts, so they are refetched on every visit rather than shown
		# as they were when the page booted; the boot list carries the same fetch for a direct load.
		NavigateTo(Dashboard) => (
			{ ..model, route: Dashboard, mobileMenuOpen: Bool.False },
			# A parent's dashboard also lists their children, so that fetch rides the same navigation.
			if model.role == Parent {
				[Port.send("push_state", route_path(Dashboard)), Port.send("fetch_data", "/api/dashboard"), Port.send("fetch_data", "/api/parent/children")]
			} else {
				[Port.send("push_state", route_path(Dashboard)), Port.send("fetch_data", "/api/dashboard")]
			}
		)
		NavigateTo(route) => {
			({ ..model, route: route, mobileMenuOpen: Bool.False }, [Port.send("push_state", route_path(route))])
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
		            ToggleNotifications => ({ ..model, notificationsOpen: !(model.notificationsOpen) }, [])
		            CloseNotifications => ({ ..model, notificationsOpen: Bool.False }, [])
           # Escape is the keyboard's way out of whatever is layered over the page, in the order
           # the layers sit: a modal first (the user form or the teacher's Assign dialog), then
           # the avatar menu, the bell's panel and the phone's sidebar. Nothing open means nothing
           # to do. A write in flight keeps its modal — the same rule the modal's own ✕ button has
           # (`isSubmitting` disables it), so Escape can never drop a request someone is waiting
           # on.
           EscapePressed => {
                   if model.userFormOpen and !model.isSubmitting {
                           (close_user_form(model), [])
                   } else if model.assignDialogOpen {
                           (close_assign_dialog(model), [])
                   } else if model.userMenuOpen {
                           ({ ..model, userMenuOpen: Bool.False }, [])
                   } else if model.notificationsOpen {
                           ({ ..model, notificationsOpen: Bool.False }, [])
                   } else if model.mobileMenuOpen {
                           ({ ..model, mobileMenuOpen: Bool.False }, [])
                   } else {
                           (model, [])
                   }
           }
		            GotNotificationsData(s) => ({ ..model, notificationsData: s }, [])
		            ClearNotifications => ({ ..model, notificationsData: "", notificationsOpen: Bool.False }, [Port.send("clear_notifications", "")])
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
		                # The type sets the ticks, which are then each editable on its own: the model holds the ticks
		                # because they are what the save sends and the backend enforces.
		                UpdateNewUserAdminType(kind) =>
		                        ({ ..model, newUserAdminType: kind, newUserPermissions: admin_type_permissions(model.adminTypesData, kind) }, [])
		                ToggleNewUserPermission(key) => (
		                        { ..model,
		                                newUserPermissions: if List.contains(model.newUserPermissions, key) {
		                                        List.keep_if(model.newUserPermissions, |ticked| ticked != key)
		                                } else {
		                                        List.append(model.newUserPermissions, key)
		                                }
		                        },
		                        []
		                )
		                # The catalog can land while the form is already open on an Admin row. A fresh create that has
		                # no type yet then starts on the catalog's narrowest type with its ticks; an edit keeps the
		                # row's own two (the row prefilled them), which is why the seed asks whether this is a create.
		                GotAdminTypesData(s) => {
		                        seed = model.userFormOpen and !model.userEditing and model.newUserRole == "Admin" and Str.is_empty(model.newUserAdminType)
		                        kind = if seed { admin_default_type(s) } else { model.newUserAdminType }
		                        (
		                                { ..model,
		                                        adminTypesData: s,
		                                        newUserAdminType: kind,
		                                        newUserPermissions: if seed { admin_type_permissions(s, kind) } else { model.newUserPermissions },
		                                },
		                                []
		                        )
		                }
		                GotAdminRightsData(s) => ({ ..model, adminRightsData: s }, [])
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
		           CloseTeacherAssign => (close_assign_dialog(model), [])
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
			({ ..model, assignSaveResult: newResult }, List.concat(notification_for(newResult, "Teacher assignments"), refreshes))
		}
		# --- The teacher form's qualifications picker ---
		AddQualification(id) => ({ ..model, newUserQualifications: List.append(model.newUserQualifications, id), qualSearch: "" }, [])
		RemoveQualification(id) => ({ ..model, newUserQualifications: List.keep_if(model.newUserQualifications, |q| q != id) }, [])
		UpdateQualSearch(s) => ({ ..model, qualSearch: s }, [])
		UpdateNewUserDateEmployed(s) => ({ ..model, newUserDateEmployed: s }, [])
		AddLinkedStudent(id) => ({ ..model, newUserLinkedStudents: List.append(model.newUserLinkedStudents, id), linkedSearch: "" }, [])
		RemoveLinkedStudent(id) => ({ ..model, newUserLinkedStudents: List.keep_if(model.newUserLinkedStudents, |s| s != id) }, [])
		UpdateLinkedSearch(s) => ({ ..model, linkedSearch: s }, [])
		AddFormPair(edge) => ({ ..model, formPairs: List.append(model.formPairs, edge), formPairsSearch: "" }, [])
		RemoveFormPair(edge) => ({ ..model, formPairs: List.keep_if(model.formPairs, |p| p != edge) }, [])
		UpdateFormPairsSearch(s) => ({ ..model, formPairsSearch: s }, [])
		# The teacher's current pairs, as the picker's starting set. Their order in the payload is the
		# order the catalog answered in, which is the order the badges show.
		GotFormPairsData(s) => ({ ..model, formPairs: List.keep_if(List.map(Str.split_on(s, "\n"), |line| match List.get(Str.split_on(line, "|"), 0) { Ok(edge) => edge, Err(_) => "" }), |edge| !Str.is_empty(edge)), formPairsSeeded: Bool.True }, [])
		# --- The admin LMS drill-down: each step is a history entry (?class/?subject/?term/?lesson),
		# so the browser's back/forward walks the drill instead of leaving the page. Each crumb's
		# message navigates to its own level and drops the deeper state, so the crumb labelled with a
		# level lands on that level (and browser back, restoring from the URL, walks up one at a time).
		SelectAdminClass(id, name) => (
			{ ..model, adminLmsClassId: id, adminLmsClassName: name, adminLmsSubjectId: "", adminLmsSubjectName: "", adminLmsTermId: "", adminLmsTermName: "", adminLmsLessonsData: "", currentLessonContent: "" },
			[Port.send("push_state", "/admin/lms?class=${id}")]
		)
		BackAdminClasses => (
			{ ..model, adminLmsClassId: "", adminLmsClassName: "", adminLmsSubjectId: "", adminLmsSubjectName: "", adminLmsTermId: "", adminLmsTermName: "", adminLmsLessonsData: "", selectedLessonId: "", currentLessonContent: "" },
			[
				Port.send("push_state", route_path(AdminLMS)),
				Port.send("fetch_data", "/api/class_levels?admin_lms=1"),
				Port.send("fetch_data", "/api/class-subjects"),
				Port.send("fetch_data", "/api/student/terms?admin_lms=1"),
			]
		)
		BackAdminSubjects => (
			{ ..model, adminLmsSubjectId: "", adminLmsSubjectName: "", adminLmsTermId: "", adminLmsTermName: "", adminLmsLessonsData: "", selectedLessonId: "", currentLessonContent: "" },
			[
				Port.send("push_state", "/admin/lms?class=${model.adminLmsClassId}"),
				Port.send("fetch_data", "/api/class-subjects"),
			]
		)
		SelectAdminSubject(id, name) => (
			{ ..model, adminLmsSubjectId: id, adminLmsSubjectName: name, adminLmsTermId: "", adminLmsTermName: "", adminLmsLessonsData: "", currentLessonContent: "" },
			[
				Port.send("push_state", "/admin/lms?class=${model.adminLmsClassId}&subject=${id}"),
				Port.send("fetch_data", "/api/student/terms?admin_lms=1"),
			]
		)
		BackAdminTerms => (
			{ ..model, adminLmsTermId: "", adminLmsTermName: "", adminLmsLessonsData: "", selectedLessonId: "", currentLessonContent: "" },
			[
				Port.send("push_state", "/admin/lms?class=${model.adminLmsClassId}&subject=${model.adminLmsSubjectId}"),
				Port.send("fetch_data", "/api/student/terms?admin_lms=1"),
			]
		)
		SelectAdminTerm(id, name) => (
			{ ..model, adminLmsTermId: id, adminLmsTermName: name, adminLmsLessonsData: "", currentLessonContent: "" },
			[
				Port.send("push_state", "/admin/lms?class=${model.adminLmsClassId}&subject=${model.adminLmsSubjectId}&term=${id}"),
				Port.send("fetch_data", "/api/teacher/lessons?class_id=${model.adminLmsClassId}&subject_id=${model.adminLmsSubjectId}&term_id=${id}&admin_lms=1"),
			]
		)
		OpenAdminLesson(id) => (
			{ ..model, selectedLessonId: id, currentLessonContent: "" },
			[
				Port.send("push_state", "/admin/lms?class=${model.adminLmsClassId}&subject=${model.adminLmsSubjectId}&term=${model.adminLmsTermId}&lesson=${id}"),
				Port.send("fetch_data", "/api/student/lesson?lesson_id=${id}"),
			]
		)
		BackAdminLessons => (
			{ ..model, selectedLessonId: "", currentLessonContent: "" },
			[
				Port.send("push_state", "/admin/lms?class=${model.adminLmsClassId}&subject=${model.adminLmsSubjectId}&term=${model.adminLmsTermId}"),
				Port.send("fetch_data", "/api/teacher/lessons?class_id=${model.adminLmsClassId}&subject_id=${model.adminLmsSubjectId}&term_id=${model.adminLmsTermId}&admin_lms=1"),
			]
		)
		UpdateNewTermName(s) => ({ ..model, newTermName: s }, [])
		UpdateNewTermSortOrder(s) => ({ ..model, newTermSortOrder: s }, [])
		UpdateNewSubjectName(s) => ({ ..model, newSubjectName: s }, [])
		UpdateNewSubjectCode(s) => ({ ..model, newSubjectCode: s }, [])
		                UpdateNewClassLevelName(s) => ({ ..model, newClassLevelName: s }, [])
		                UpdateNewClassLevelCode(s) => ({ ..model, newClassLevelCode: s }, [])
		                UpdateNewClassLevelTier(s) => ({ ..model, newClassLevelTier: s }, [])
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
			({ ..cleared, isConfigSubmitting: Bool.False, configSubmitResult: newResult }, List.concat(notification_for(newResult, config_section_label(tab)), refreshes))
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
					                    # A class level's line carries its stage last (`id|name|code|age_range|active|tier`);
					                    # every other row's line is shorter and this reads "".
					                    editField4: config_part(parts, 5),
				},
				[]
			)
		}
		CancelConfigEdit => (config_edit_cleared(model), [])
		            UpdateEditField1(s) => ({ ..model, editField1: s }, [])
		            UpdateEditField2(s) => ({ ..model, editField2: s }, [])
		            UpdateEditField3(s) => ({ ..model, editField3: s }, [])
		            UpdateEditField4(s) => ({ ..model, editField4: s }, [])
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
			({ ..closed, isConfigSubmitting: Bool.False, configSubmitResult: newResult }, List.concat(notification_for(newResult, config_section_label(tab)), refreshes))
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
			({ ..model, isConfigSubmitting: Bool.False, configSubmitResult: newResult }, List.concat(notification_for(newResult, config_section_label(tab)), refreshes))
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
			                        # An admin's type and ticks ride the form's own panel: sent as a pair, so what the
			                        # backend stores is what the panel showed. They are left out entirely for a caller who
			                        # may not decide rights — the backend refuses a payload that speaks about them, and the
			                        # panel is read-only for such a caller, so a name edit still has to land.
			                        admin_rights_clause =
			                                if model.newUserRole == "Admin" and can_manage_admin_rights(model) {
			                                        ticks = Str.join_with(List.map(model.newUserPermissions, |key| "\"${key}\""), ",")
			                                        ",\"admin_type\":\"${model.newUserAdminType}\",\"permissions\":[${ticks}]"
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
			# The teacher's date of employment (YYYY-MM-DD) and a parent's linked students, each
			# only when the form's role can carry the column.
			date_clause =
				if model.newUserRole == "Teacher" and !Str.is_empty(model.newUserDateEmployed) {
					",\"date_employed\":\"${model.newUserDateEmployed}\""
				} else {
					""
				}
			# A teacher's class-subject pairs: the edge ids the form's picker holds, sent as the whole set
			# (the save replaces it for the active session term). Withheld while the edit form is still
			# reading the teacher's current pairs, so an empty picker can never clear them.
			pairs_clause =
				if model.newUserRole == "Teacher" and model.formPairsSeeded {
					items = List.map(model.formPairs, |edge| "{\"edge_id\":\"${edge}\"}")
					",\"pairs\":[${Str.join_with(items, ",")}]"
				} else {
					""
				}
			students_clause =
				if model.newUserRole == "Parent" {
					ids_json = Str.join_with(model.newUserLinkedStudents, "\",\"")
					if Str.is_empty(ids_json) { ",\"students\":[]" } else { ",\"students\":[\"${ids_json}\"]" }
				} else {
					""
				}
			                        payload = "{${identity_fields}\"first_name\":\"${model.newUserFirstName}\",\"middle_name\":\"${model.newUserMiddleName}\",\"surname\":\"${model.newUserSurname}\",\"date_of_birth\":\"${model.newUserDateOfBirth}\",\"class_level\":\"${model.newUserClassLevel}\",\"passport\":\"${model.newUserPassportKey}\"${admin_rights_clause}${qual_clause}${date_clause}${pairs_clause}${students_clause}${password_clause}}"
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
		                CompleteProfile(id, email) => {
		                        # Agreeing to give a profile to a login the directory lists is a create in effect, so the
		                        # admin panel starts where a fresh admin form does (see OpenUserForm).
		                        kind = admin_default_type(model.adminTypesData)
		                        (
		                                { ..model,
		                                        userFormOpen: Bool.True,
		                                        formPairs: [],
		                                        formPairsSearch: "",
		                                        formPairsSeeded: Bool.True,
		                                        completingProfileId: id,
		                                        newUserRole: user_tab_role(model.activeUserTab),
		                                        newUserFirstName: "",
		                                        newUserMiddleName: "",
		                                        newUserSurname: "",
		                                        newUserEmail: email,
		                                        newUserDateOfBirth: "",
		                                        newUserClassLevel: "",
		                                        newUserAdminType: kind,
		                                        newUserPermissions: admin_type_permissions(model.adminTypesData, kind),
		                                        newUserPassportKey: "",
		                                        newUserPassword: "",
		                                        newUserQualifications: [],
		                                        qualSearch: "",
		                                        newUserDateEmployed: "",
		                                        newUserLinkedStudents: [],
		                                        linkedSearch: "",
		                                        userEditing: Bool.False,
		                                        lastCredentials: None,
		                                        submitResult: None,
		                                },
		                                # The parent form's linked-students picker reads the student listing, so it is fetched
		                                # whenever a form can show it.
		                                [Port.send("fetch_data", "/api/users?role=Student")]
		                        )
		                }
		CancelCompleteProfile => ({ ..model, userFormOpen: Bool.False, completingProfileId: "", userEditing: Bool.False, resetPasswordId: "", resetPasswordEmail: "", lastCredentials: None, submitResult: None, newUserQualifications: [], qualSearch: "", newUserDateEmployed: "", newUserLinkedStudents: [], linkedSearch: "" }, [])
		                # Open the form in add mode: the header's Add User button. Everything the completing and
		                # editing modes set is cleared, so the modal opens empty — and the role starts on the tab the
		                # admin is looking at, because the fields that follow the picker (a teacher's date employed and
		                # qualifications, a parent's children, an admin's type and ticks) are otherwise invisible until it
		                # is touched: opening from the Teachers tab on the default "Student" read as a student's form.
		                OpenUserForm => {
		                        # A fresh administrator starts on the catalog's narrowest type with its ticks, so the panel
		                        # is truthful for a save that never touches it — and a create cannot inherit what an earlier
		                        # edit left in the model. The catalog is re-fetched with the form, so an open form never
		                        # depends on the boot fetch having landed.
		                        kind = admin_default_type(model.adminTypesData)
		                        (
		                                { ..model, userFormOpen: Bool.True, newUserRole: user_tab_role(model.activeUserTab), newUserAdminType: kind, newUserPermissions: admin_type_permissions(model.adminTypesData, kind), formPairs: [], formPairsSearch: "", formPairsSeeded: Bool.True, completingProfileId: "", userEditing: Bool.False, resetPasswordId: "", resetPasswordEmail: "", lastCredentials: None, submitResult: None, newUserQualifications: [], qualSearch: "", newUserDateEmployed: "", newUserLinkedStudents: [], linkedSearch: "" },
		                                [Port.send("fetch_data", "/api/users?role=Student"), Port.send("fetch_data", "/api/admin-types")]
		                        )
		                }
		           CloseUserForm => (close_user_form(model), [])
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
					                                        # An admin row's own type and ticks, read from the two fields the listing
					                                        # appends after the class name — every other role's rows carry none. The form
					                                        # starts from the row rather than from the type's own defaults, so an edit
					                                        # that only fixes a name cannot silently reset what the school set.
					                                        newUserAdminType: if user_tab_role(model.activeUserTab) == "Admin" { part(17) } else { "" },
					                                        newUserPermissions: if user_tab_role(model.activeUserTab) == "Admin" {
					                                                List.keep_if(Str.split_on(part(18), ","), |key| !Str.is_empty(key))
					                                        } else {
					                                                []
					                                        },
					newUserPassportKey: part(12),
					newUserPassword: "",
					newUserQualifications: if user_tab_role(model.activeUserTab) == "Teacher" { quals } else { [] },
					qualSearch: "",
					# The last two role-specific fields: a teacher's date of employment, a parent's
					# linked student ids (comma-joined by the page's formatter).
					newUserDateEmployed: if user_tab_role(model.activeUserTab) == "Teacher" { part(14) } else { "" },
					newUserLinkedStudents: if user_tab_role(model.activeUserTab) == "Parent" { List.keep_if(Str.split_on(part(15), ","), |s| !Str.is_empty(s)) } else { [] },
					linkedSearch: "",
					# The form's own pairs picker: for a teacher it starts empty and unseeded, the fetch
					# below fills it, and Save waits for it (user_form_waiting) — saving an empty picker
					# would clear the assignments it is meant to be showing.
					formPairs: [],
					formPairsSearch: "",
					formPairsSeeded: !(user_tab_role(model.activeUserTab) == "Teacher"),
					userEditing: Bool.True,
					lastCredentials: None,
					submitResult: None,
				},
				                                # The edit form's pickers read their catalogs: the student listing for a parent's
				                                # linked students, the credentials catalog for a teacher's qualifications, and the
				                                # admin catalog for an administrator's type and ticks.
				                                [
				                                        Port.send("fetch_data", "/api/users?role=Student"),
				                                        Port.send("fetch_data", "/api/credentials"),
				                                        Port.send("fetch_data", "/api/admin-types"),
					# The teacher's pairs, for the form's picker. `for=form` keeps them out of the Assign
					# dialog's own payload, which the same endpoint feeds.
					Port.send("fetch_data", "/api/teacher-assignments?teacher_id=${part(0)}&for=form"),
				]
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
			                        ({ ..model, isSubmitting: Bool.False, submitResult: newResult, completingProfileId: "", userEditing: Bool.False, userFormOpen: Bool.False, newUserPassword: "", lastCredentials: handoff, newUserFirstName: "", newUserMiddleName: "", newUserSurname: "", newUserEmail: "", newUserDateOfBirth: "", newUserClassLevel: "", newUserAdminType: "", newUserPermissions: [], newUserQualifications: [], qualSearch: "", newUserDateEmployed: "", newUserLinkedStudents: [], linkedSearch: "", assignSelectedEdges: [], assignSeeded: Bool.False, assignSearch: "", assignSaveResult: None }, List.concat(notification_for(newResult, "User management"), refresh))
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
			({ ..model, isSubmitting: Bool.False, submitResult: newResult }, List.concat(notification_for(newResult, "User management"), refresh))
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
			({ ..model, isSubmitting: Bool.False, submitResult: newResult, resetPasswordId: "", resetPasswordEmail: "", newUserPassword: "", userFormOpen: Bool.False, lastCredentials: handoff }, List.concat(notification_for(newResult, "Password"), []))
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
		           GotDashboardData(s) => ({ ..model, dashboardData: s }, [])
           GotParentChildrenData(s) => ({ ..model, parentChildrenData: s }, [])

           # The backend answered whether a password change is owed. While it is, the page is Settings and
           # nothing else: the shell hides its navigation (app.roc) and every navigation is held here.
           GotPasswordState(s) => {
           	parts = Str.split_on(s, "\n")
           	line = match List.get(parts, 1) { Ok(value) => value, Err(_) => "" }
           	fields = Str.split_on(line, "|")
           	required = match List.get(fields, 0) { Ok(value) => value == "true", Err(_) => Bool.False }
           	reason = match List.get(fields, 1) { Ok(value) => value, Err(_) => "" }
           
           	# The state only ever *arrives* here; the route follows it, and a login with nothing owed
           	# stays exactly where it is.
           	if required and model.route != Settings {
           		({ ..model, passwordStateData: s, passwordRequired: required, passwordReason: reason, route: Settings }, [Port.send("push_state", route_path(Settings))])
           	} else {
           		({ ..model, passwordStateData: s, passwordRequired: required, passwordReason: reason }, [])
           	}
           }
           UpdateNewPassword(s) => ({ ..model, newPassword: s }, [])
           UpdateConfirmPassword(s) => ({ ..model, confirmPassword: s }, [])
           UpdateCurrentPassword(s) => ({ ..model, currentPassword: s }, []),
           GotProfileData(s) => ({ ..model, profileData: s }, []),
           SubmitPasswordChange => {
           	# The rules the backend enforces, said here first so the form answers without a round trip;
           	# the backend checks them again and its own message is what the form shows when it refuses.
           	problem =
           		if Str.is_empty(model.newPassword) {
           			"Choose a password"
           		} else if Str.count_utf8_bytes(model.newPassword) < 8 {
           			"The password must be at least 8 characters"
           		} else if Str.count_utf8_bytes(model.newPassword) > 72 {
           			"The password must be at most 72 characters"
           		} else if Str.contains(model.newPassword, "\n") or Str.contains(model.newPassword, "\r") {
           			"The password may not contain line breaks"
           		} else if model.newPassword != model.confirmPassword {
           			"The two passwords do not match"
           			} else if !model.passwordRequired and Str.is_empty(model.currentPassword) {
           				# Nothing is owed, so this is a change the person chose: it has to prove the current password.
           				"Enter your current password"
           			} else {
           			""
           		}
           
           	if !Str.is_empty(problem) {
           		({ ..model, passwordResult: Error(problem) }, [])
           	} else {
		                        # The password is sent in the body and never kept: the backend hands it to Authentik and
		                        # answers; nothing here stores it beyond the keystrokes. `current` rides along only when
		                        # it was asked for (and typed): the backend verifies it against Authentik first.
		                        current_clause = if Str.is_empty(model.currentPassword) { "" } else { ",\"current\":\"${model.currentPassword}\"" }
		                        req = {
		                                method: POST,
		                                uri: "${model.appOrigin}/api/me/password",
		                                headers: [
		                                        { name: "Authorization", value: "Bearer ${model.authToken}" },
		                                        { name: "Content-Type", value: "application/json" }
		                                ],
		                                body: Str.to_utf8("{\"password\":\"${model.newPassword}\"${current_clause}}"),
		                                timeout_ms: NoTimeout,
		                        }
           		({ ..model, isSubmitting: Bool.True, passwordResult: None }, [Http.request(req, |res| PasswordChangeCompleted(res))])
           	}
           }
           PasswordChangeCompleted(res) => {
           	result : [None, Success(Str), Error(Str)]
           	result = match res {
           		Ok(response) =>
           			if response.status == 200 {
           				Success("Your password is set. You can use the school system now.")
           			} else {
           				Error(backend_error_message(Str.from_utf8_lossy(response.body)))
           			}
           		Err(HttpErr(Timeout)) => Error("The request timed out")
           		Err(HttpErr(NetworkError)) => Error("Could not reach the server")
           	}
           
           	# A success clears the requirement here too, so the shell comes back without waiting for the
           	# next state fetch; a failure keeps everything as it was so the form can be corrected.
           	cleared = match result {
           		Success(_) => Bool.True
           		Error(_) => Bool.False
           		None => Bool.False
           	}
           
           	({ ..model, isSubmitting: Bool.False, passwordResult: result, passwordRequired: if cleared { Bool.False } else { model.passwordRequired }, newPassword: if cleared { "" } else { model.newPassword }, confirmPassword: if cleared { "" } else { model.confirmPassword }, currentPassword: if cleared { "" } else { model.currentPassword } }, [])
           }
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
				Port.send("push_state", route_path(StudentLesson)),
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
			# The lesson goes in the URL as the teacher's does, so the page can be reloaded or shared and
			# still open on the same lesson (the viewer reads ?id= on the way in).
			[
				Port.send("push_state", "/student/lesson?id=${id}"),
				Port.send("fetch_data", "/api/student/lesson?lesson_id=${id}"),
			]
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
		OpenTeacherSubject(class_id, subject_id, subject_name) => (
			{ ..model, route: TeacherLessonViewer, teacherClassId: class_id, selectedSubjectId: subject_id, selectedSubjectName: subject_name, selectedTermId: "", selectedTermName: "", selectedLessonId: "", teacherLessonsData: "", currentLessonContent: "" },
			[
				Port.send("push_state", route_path(TeacherLessonViewer)),
				Port.send("fetch_data", "/api/teacher/lessons?class_id=${class_id}&subject_id=${subject_id}"),
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
			[Port.send("push_state", route_path(StudentSubjects))]
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
