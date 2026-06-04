//|

///|
#derive.golem_schema
enum CacheData {
  Profile(StudentProfile)
  Subjects(Array[SubjectInfo])
  Terms(Array[TermInfo])
  Lessons(Array[LessonInfo])
  LessonContent(LessonContent)
  ClassGroups(Array[TeacherClassGroup])
  ActiveSessionTerm(String)
  SessionTerms(String)
}

///|
#derive.golem_schema
struct CacheItem {
  data : CacheData
  fetched_at : UInt64
}

///|
const CACHE_TTL : UInt64 = 600
