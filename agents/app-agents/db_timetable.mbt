///| DB functions for the Timetable engine

pub fn db_admin_fetch_timetable(
  config : SharedConfig,
  timetable_id : String,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "SELECT *, meta::id(id) as id FROM type::thing('timetables', $timetable_id)",
    bindings={ "timetable_id": timetable_id },
  )
}

pub fn db_admin_clear_schedule_slots(
  config : SharedConfig,
  timetable_id : String,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "DELETE schedule_slots WHERE timetable = type::thing('timetables', $timetable_id)",
    bindings={ "timetable_id": timetable_id },
  )
}

pub fn db_admin_fetch_timetable_overrides(
  config : SharedConfig,
  timetable_id : String,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "SELECT *, meta::id(id) as id FROM timetable_overrides WHERE timetable = type::thing('timetables', $timetable_id)",
    bindings={ "timetable_id": timetable_id },
  )
}

pub fn db_admin_fetch_has_subject_tiers(
  config : SharedConfig,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "SELECT meta::id(id) as id, default_tier, meta::id(in) as class_level, meta::id(out) as subject FROM has_subject",
  )
}

pub fn db_admin_fetch_all_teachers(
  config : SharedConfig,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "SELECT *, meta::id(id) as id FROM teacher_profile WHERE is_active = true AND deleted_at IS NONE",
  )
}

pub fn db_admin_fetch_all_classes(
  config : SharedConfig,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "SELECT *, meta::id(id) as id FROM class_levels ORDER BY sort_order ASC",
  )
}

pub fn db_admin_fetch_all_teaches(
  config : SharedConfig,
  session_term : String,
) -> Result[Array[Json], AppError] {
  surreal_query(
    config,
    "SELECT meta::id(id) as id, meta::id(in) as teacher, meta::id(out) as has_subject, meta::id(session_term) as session_term FROM teaches WHERE session_term = type::thing('session_term', $term) AND deleted_at IS NONE",
    bindings={ "term": session_term },
  )
}

pub fn db_admin_bulk_insert_schedule_slots(
  config : SharedConfig,
  slots : Array[ScheduleSlot],
) -> Result[Array[Json], AppError] {
  if slots.length() == 0 {
    return Ok([])
  }
  
  let mut query = "INSERT INTO schedule_slots ["
  let mut i = 0
  while i < slots.length() {
    let slot = slots[i]
    let mut obj = "\\{"
    obj += "\"timetable\": type::thing('timetables', \"\{slot.timetable}\"), "
    obj += "\"class_level\": type::thing('class_levels', \"\{slot.class_level}\"), "
    obj += "\"day_of_week\": \"\{slot.day_of_week}\", "
    obj += "\"period_number\": \{slot.period_number}, "
    
    if slot.is_excluded {
      obj += "\"is_excluded\": true"
    } else {
      obj += "\"is_excluded\": false"
    }
    
    match slot.subject_edge {
      Some(sub) => obj += ", \"subject_edge\": type::thing('has_subject', \"\{sub}\")"
      None => ()
    }
    
    match slot.teacher {
      Some(t) => obj += ", \"teacher\": type::thing('teacher_profile', \"\{t}\")"
      None => ()
    }
    
    obj += "\\}"
    
    if i < slots.length() - 1 {
      query += obj + ", "
    } else {
      query += obj
    }
    i += 1
  }
  query += "]"
  
  surreal_query(config, query)
}
