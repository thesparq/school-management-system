// Timetable engine models

///| Timetable day config embedded in Timetable
pub(all) struct TimetableDayConfig {
  day_of_week : String
  periods_count : Int
  excluded_periods : Array[Int]
} derive(ToJson, FromJson)

///| Map of subject IDs to custom tier values
pub(all) struct TierOverrides {
  overrides : Map[String, Int]
}

// Since MoonBit's FromJson for Map[String, Int] can be finicky if we receive a raw JSON object,
// we define custom conversion or just type it as Json and parse manually.
// For now, let's just use `Json` and parse it manually.

///| Timetable record
pub(all) struct Timetable {
  id : String
  name : String
  description : String?
  is_active : Bool
  session_term : String
  day_configs : Array[TimetableDayConfig]?
  tier_overrides : Json?
  created_at : String
  updated_at : String
} derive(ToJson, FromJson)

///| Output slot from the CSP Solver
pub(all) struct ScheduleSlot {
  id : String
  timetable : String
  class_level : String
  day_of_week : String
  period_number : Int
  subject_edge : String?
  teacher : String?
  is_excluded : Bool
  created_at : String
} derive(ToJson, FromJson)

///| Term-specific overrides for staff availability and subject assignments
pub(all) struct TimetableOverride {
  id : String
  timetable : String
  teacher : String
  is_participating : Bool
  is_absent_override : Bool?
  added_assignments : Array[String]
  removed_assignments : Array[String]
} derive(ToJson, FromJson)

///| Request to generate a timetable
pub(all) struct GenerateTimetableRequest {
  timetable_id : String
} derive(ToJson, FromJson)

///| Simple Subject with its default tier
pub(all) struct SubjectTierInfo {
  id : String
  default_tier : Int
} derive(ToJson, FromJson)

///| 
pub(all) struct ClassSubjectPair {
  id : String
  class_level : String
  subject : String
  default_tier : Int?
} derive(ToJson, FromJson)

///|
pub(all) struct TeacherAssignmentRecord {
  id : String
  teacher : String
  has_subject : String
  session_term : String
} derive(ToJson, FromJson)
