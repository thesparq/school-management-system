//|

///|
#derive.golem_schema
struct ParentStudentInfo {
  id : String
  display_name : String
  class_level : String
  subject_count : Int
} derive(ToJson, FromJson)
