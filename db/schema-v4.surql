-- Schema V4: Timetable CSP Engine (Phoenix Allocator)

-- 1. Add `default_tier` to `has_subject` edge
-- Defines if a subject is globally considered Core (3), Important (2), or Elective (1)
DEFINE FIELD default_tier ON has_subject TYPE int DEFAULT 1;

-- 2. Define `timetables` table
DEFINE TABLE timetables SCHEMAFULL;
DEFINE FIELD name ON timetables TYPE string;
DEFINE FIELD description ON timetables TYPE option<string>;
DEFINE FIELD is_active ON timetables TYPE bool DEFAULT false;
DEFINE FIELD session_term ON timetables TYPE record<session_term>;
DEFINE FIELD created_at ON timetables TYPE datetime DEFAULT time::now();
DEFINE FIELD updated_at ON timetables TYPE datetime DEFAULT time::now();

-- `day_configs` is an array of objects
DEFINE FIELD day_configs ON timetables TYPE option<array<object>>;
DEFINE FIELD day_configs.*.day_of_week ON timetables TYPE string ASSERT $value INSIDE ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
DEFINE FIELD day_configs.*.periods_count ON timetables TYPE int ASSERT $value > 0 AND $value <= 15;
DEFINE FIELD day_configs.*.excluded_periods ON timetables TYPE array<int>;

-- `tier_overrides` is a dynamic object where keys are `has_subject` IDs (as strings) and values are ints.
DEFINE FIELD tier_overrides ON timetables TYPE object DEFAULT {};

-- 3. Define `schedule_slots` table
-- This stores the deterministic output of the CSP solver
DEFINE TABLE schedule_slots SCHEMAFULL;
DEFINE FIELD timetable ON schedule_slots TYPE record<timetables>;
DEFINE FIELD class_level ON schedule_slots TYPE record<class_levels>;
DEFINE FIELD day_of_week ON schedule_slots TYPE string ASSERT $value INSIDE ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
DEFINE FIELD period_number ON schedule_slots TYPE int;
DEFINE FIELD subject_edge ON schedule_slots TYPE option<record<has_subject>>;
DEFINE FIELD teacher ON schedule_slots TYPE option<record<teacher_profile>>;
DEFINE FIELD is_excluded ON schedule_slots TYPE bool DEFAULT false;
DEFINE FIELD created_at ON schedule_slots TYPE datetime DEFAULT time::now();

-- Fast lookup index for grid rendering
DEFINE INDEX idx_schedule_slots_grid ON schedule_slots COLUMNS timetable, class_level, day_of_week, period_number UNIQUE;

-- 4. Define `timetable_overrides` table
-- Tracks term-specific overrides for staff availability and subject assignments
DEFINE TABLE timetable_overrides SCHEMAFULL;
DEFINE FIELD timetable ON timetable_overrides TYPE record<timetables>;
DEFINE FIELD teacher ON timetable_overrides TYPE record<teacher_profile>;
DEFINE FIELD is_participating ON timetable_overrides TYPE bool DEFAULT true;
DEFINE FIELD is_absent_override ON timetable_overrides TYPE option<bool>;
-- Arrays of relations added or removed for this specific timetable
DEFINE FIELD added_assignments ON timetable_overrides TYPE array<record<has_subject>> DEFAULT [];
DEFINE FIELD removed_assignments ON timetable_overrides TYPE array<record<has_subject>> DEFAULT [];

-- Fast lookup index
DEFINE INDEX idx_timetable_overrides_lookup ON timetable_overrides COLUMNS timetable, teacher UNIQUE;
