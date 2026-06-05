//|

///|
#derive.golem_schema
struct ClassLevelInfo {
  id : String
  name : String
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct StudentProfileInfo {
  id : String
  surname : String
  first_name : String
  middle_name : String?
  display_name : String
  date_of_birth : String
  class_enrolled : String
  current_class : String
  passport : String
  created_at : String
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct TeacherProfileInfo {
  id : String
  surname : String
  first_name : String
  middle_name : String?
  display_name : String
  qualifications : Array[String]?
  date_employed : String?
  passport : String
  created_at : String
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct AdminProfileInfo {
  id : String
  surname : String
  first_name : String
  middle_name : String?
  display_name : String
  role_title : String?
  passport : String
  created_at : String
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct ParentProfileInfo {
  id : String
  name : String
  display_name : String
  students : Array[String]
  passport : String
  created_at : String
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct CredentialInfo {
  id : String
  name : String
  active : Bool
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct CreateUserResponse {
  pk : Int
  uuid : String
  username : String
  name : String
  email : String
  is_active : Bool
  groups : Array[String]
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct SessionTermDetail {
  id : String
  session : String
  term_name : String
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct SessionTermInfo {
  id : String
  session : String
  term_name : String
  active : Bool
  created_at : String
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct TermSimple {
  id : String
  name : String
  active : Bool
  sort_order : Int
} derive(ToJson, FromJson)
