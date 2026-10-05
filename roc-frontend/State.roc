module [Model, Msg, init, update, Route, Role, AdminConfigTab, AdminUserTab]

import pf.Effect exposing [Effect]
import pf.Http
import pf.Port
import Auth

AdminConfigTab : [Terms, ClassLevels, Curriculum, ClassArms, Subjects]

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
	}

	(model, [
			Port.send("fetch_data", "/api/users?role=Student"),
		Port.send("fetch_data", "/api/users?role=Teacher"),
		Port.send("fetch_data", "/api/users?role=Parent"),
		Port.send("fetch_data", "/api/users?role=Admin"),
		Port.send("fetch_data", "/api/terms"),
		Port.send("fetch_data", "/api/subjects"),
		Port.send("fetch_data", "/api/teacher/lessons"),
	])
}

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UrlChanged(url) => {
			newRoute = parse_route(url)
			({ ..model, route: newRoute, mobileMenuOpen: Bool.False }, [])
		}
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
			({ ..model, activeConfigTab: tab }, [])
		UpdateNewUserEmail(s) =>
			({ ..model, newUserEmail: s }, [])
		GotUsersData(str) => ({ ..model, usersData: str, isLoading: Bool.False }, [])
		GotTermsData(str) => ({ ..model, termsData: str }, [])
		GotSubjectsData(str) => ({ ..model, subjectsData: str }, [])
		DataLoaded => ({ ..model, isLoading: Bool.False }, [])
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
						# The backend reports failures as {"error":"..."}; show that text.
						parts = Str.split_on(Str.from_utf8_lossy(response.body), "\"error\":\"")
						message = match List.get(parts, 1) {
							Ok(rest) =>
								match List.first(Str.split_on(rest, "\"")) {
									Ok(text) => text
									Err(_) => "Request failed"
								}
							Err(_) => "Request failed"
						}
						if Str.is_empty(message) { Error("Request failed") } else { Error(message) }
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
