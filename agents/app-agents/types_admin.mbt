//|

///|
#derive.golem_schema
struct ClassLevelInfo {
  id : String
  name : String
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct UserProfileInfo {
  auth_id : String
  role : String
  class_level : String
  created_at : String
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
} derive(ToJson, FromJson)
