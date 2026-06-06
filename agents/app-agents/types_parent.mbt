//|

///|
#derive.golem_schema
struct ParentStudentInfo {
  id : String
  display_name : String
  current_class : String
  subject_count : Int
} derive(ToJson, FromJson)
