//|

///|
#derive.golem_schema
struct SubjectInfo {
  id : String
  name : String
  code : String?
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct StudentProfile {
  surname : String
  first_name : String
  middle_name : String?
  display_name : String
  date_of_birth : String
  class_level : String
  passport : String
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct TermInfo {
  id : String
  name : String
  sort_order : Int
  active : Bool
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct LessonInfo {
  id : String
  topic_title : String?
  week : Int?
  active : Bool?
  subject_name : String?
  term_name : String?
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct LessonContent {
  id : String
  topic_title : String?
  week : Int?
  subject_name : String?
  term_name : String?
  objectives : String?
  content_sections : String?
  key_points : String?
  mcq_questions : String?
  theoretical_questions : String?
} derive(ToJson, FromJson)
