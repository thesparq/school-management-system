//|

///|
#derive.golem_schema
struct TeacherSubjectPair {
  edge_id : String
  class_level_id : String
  class_level_name : String
  subject_id : String
  subject_name : String
  subject_code : String?
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct TeacherClassGroup {
  class_level_id : String
  class_level_name : String
  subjects : Array[TeacherSubjectPair]
} derive(ToJson, FromJson)
