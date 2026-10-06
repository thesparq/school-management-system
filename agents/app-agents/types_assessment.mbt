//|
// Types for Assessments & Grading System

///|
#derive.golem_schema
struct AssessmentQuestion {
  question_index : Int
  question_type : String
  question_text : String
  option_a : String?
  option_b : String?
  option_c : String?
  correct_answer : String?
  allocated_mark : Int
  source_question_index : Int
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct LessonAssessmentInfo {
  id : String
  lesson : String
  title : String
  description : String?
  questions : Array[AssessmentQuestion]
  total_mark : Int
  max_resubmissions : Int
  deadline : String?
  active : Bool
  scheduled_at : String?
  created_at : String
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct GeneralAssessmentInfo {
  id : String
  session_term : String
  subject : String
  title : String
  description : String?
  percentage_weight : Int
  questions : Array[AssessmentQuestion]?
  compositions : Array[CompositionInfo]?
  total_mark : Int
  max_resubmissions : Int
  deadline : String?
  active : Bool
  scheduled_at : String?
  created_at : String
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct CompositionInfo {
  id : String
  lesson_assessment : String
  lesson_assessment_title : String?
  lesson_assessment_total_mark : Int?
  weight_pct : Float
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct SubmissionAnswer {
  question_index : Int
  answer_type : String
  answer_text : String
  allocated_mark : Int
  scored_mark : Int?
  correct : Bool?
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct SubmissionInfo {
  id : String
  assessment_type : String
  assessment_id : String
  student : String
  student_name : String?
  iteration : Int
  status : String
  submitted_at : String
  answers : Array[SubmissionAnswer]
  total_mark : Int
  scored_mark : Int?
  grade_released_at : String?
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct CompositionGradeBreakdown {
  lesson_assessment_title : String
  scored_pct : Float?
  weight_pct : Float
  graded : Bool
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct CompositionGradeResult {
  total_scored_pct : Float?
  total_weight_pct : Float
  breakdown : Array[CompositionGradeBreakdown]
  all_graded : Bool
} derive(ToJson, FromJson)

///|
#derive.golem_schema
struct PercentageSummary {
  current : Int
  remaining : Int
} derive(ToJson, FromJson)
