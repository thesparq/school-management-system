///| Timetable CSP Engine for MoonBit

pub fn admin_generate_timetable(
  config : SharedConfig,
  timetable_id : String,
) -> Result[String, AppError] {
  // 1. Clear existing slots
  match db_admin_clear_schedule_slots(config, timetable_id) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }

  // 2. Fetch the timetable
  let res_timetable = match db_admin_fetch_timetable(config, timetable_id) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  if res_timetable.length() == 0 {
    return Err(AppError::{ code: NotFound, message: "Timetable not found", debug: None })
  }
  
  let timetable : Timetable = @json.from_json(res_timetable[0]) catch {
    _ => return Err(AppError::{ code: InternalError, message: "Failed to parse timetable", debug: None })
  }
  let session_term = timetable.session_term
  
  let day_configs = match timetable.day_configs {
    Some(cfg) => cfg
    None => return Err(AppError::{ code: ValidationError, message: "No day configs found", debug: None })
  }

  // 3. Fetch dependencies
  let overrides_json = match db_admin_fetch_timetable_overrides(config, timetable_id) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let overrides : Array[TimetableOverride] = match parse_result_array_internal(overrides_json) {
    Ok(v) => v
    Err(e) => return Err(e)
  }

  let tiers_json = match db_admin_fetch_has_subject_tiers(config) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let tiers : Array[ClassSubjectPair] = match parse_result_array_internal(tiers_json) {
    Ok(v) => v
    Err(e) => return Err(e)
  }

  let teachers_json = match db_admin_fetch_all_teachers(config) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let all_teachers : Array[TeacherProfileInfo] = match parse_result_array_internal(teachers_json) {
    Ok(v) => v
    Err(e) => return Err(e)
  }

  let classes_json = match db_admin_fetch_all_classes(config) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let classes : Array[ClassLevelInfo] = match parse_result_array_internal(classes_json) {
    Ok(v) => v
    Err(e) => return Err(e)
  }

  let teaches_json = match db_admin_fetch_all_teaches(config, session_term) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let master_assignments : Array[TeacherAssignmentRecord] = match parse_result_array_internal(teaches_json) {
    Ok(v) => v
    Err(e) => return Err(e)
  }

  // Maps for efficient lookups
  // subject_edge ID -> Default Tier
  let subject_tiers : Map[String, Int] = Map::new()
  for t in tiers {
    subject_tiers.set(t.id, t.default_tier.or(1))
  }
  
  // Apply overrides
  // We parse timetable.tier_overrides which is Json object Map
  match timetable.tier_overrides {
    Some(Object(map)) => {
      for pair in map {
        let key = pair.0
        match pair.1 {
          Number(n) => {
            subject_tiers.set(key, n.to_int())
          }
          _ => ()
        }
      }
    }
    _ => ()
  }

  // subject_edge ID -> Array[Teacher ID]
  let subject_teachers : Map[String, Array[String]] = Map::new()
  for assign in master_assignments {
    // Check if teacher is absent in overrides
    let mut is_absent = false
    for o in overrides {
      if o.teacher == assign.teacher && o.is_participating == false {
        is_absent = true
      }
    }
    if not(is_absent) {
      match subject_teachers.get(assign.has_subject) {
        Some(arr) => arr.push(assign.teacher)
        None => subject_teachers.set(assign.has_subject, [assign.teacher])
      }
    }
  }

  // Teacher unavailable periods (teacher_id + "_" + day + "_" + period_num)
  let teacher_unavail : Map[String, Bool] = Map::new()
  
  // CSP Tracking
  // "{teacher_id}_{day}_{period}" -> bool
  let teacher_busy : Map[String, Bool] = Map::new()
  
  // "{teacher_id}" -> int
  let teacher_workload : Map[String, Int] = Map::new()
  
  // "{cohort}_{day}_{subject}" -> bool
  let cohort_daily_subjects : Map[String, Bool] = Map::new()
  
  // "{class_id}_{day}_{subject_edge}" -> int
  let class_daily_subject_count : Map[String, Int] = Map::new()

  let output_slots : Array[ScheduleSlot] = []

  for class in classes {
    // Collect subjects for this class
    let class_subs : Array[ClassSubjectPair] = []
    for edge in tiers { // edge represents a has_subject link
      if edge.class_level == class.id {
        class_subs.push(ClassSubjectPair::{
          id: edge.id,
          class_level: edge.class_level,
          subject: edge.subject,
          default_tier: Some(subject_tiers.get(edge.id).or(1))
        })
      }
    }
    
    if class_subs.length() == 0 {
      continue
    }

    let cohort_base = if class.name.length() > 3 {
      class.name.substring(end=3) // Extract 'JSS' or 'SS1' etc
    } else {
      class.name
    }

    // Set weekly targets
    let target_periods : Map[String, Int] = Map::new()
    for cs in class_subs {
      let tier = subject_tiers.get(cs.id).or(1)
      let target = match tier {
        3 => 3
        2 => 1
        1 => 1
        _ => if tier > 0 { tier } else { 1 }
      }
      target_periods.set(cs.id, target)
    }

    for cfg in day_configs {
      let day = cfg.day_of_week
      let periods_count = cfg.periods_count
      
      let excluded = Map::new()
      for ex in cfg.excluded_periods {
        excluded.set(ex, true)
      }
      
      let early_cutoff = if periods_count / 2 > 1 { periods_count / 2 } else { 1 }

      let mut period_num = 1
      while period_num <= periods_count {
        let slot_id = "slot_\{class.id}_\{day}_\{period_num}"
        
        if excluded.get(period_num).or(false) {
          output_slots.push(ScheduleSlot::{
            id: slot_id,
            timetable: timetable_id,
            class_level: class.id,
            day_of_week: day,
            period_number: period_num,
            subject_edge: None,
            teacher: None,
            is_excluded: true,
            created_at: "",
          })
          period_num += 1
          continue
        }

        // Candidates (subject_edge, teacher_id, current_workload, daily_count, arm_sync_bonus, score)
        // Since MoonBit doesn't have tuples of size 6, let's define a local struct
        // But we can't define struct inside fn in MoonBit.
        // We'll define it outside. For now let's just use an array and map to keep it simple, or define it above.
        // I will use an Array[Candidate].
        
        let candidates : Array[Candidate] = []

        for cs in class_subs {
          let remaining = target_periods.get(cs.id).or(0)
          if remaining <= 0 { continue }
          
          let daily_count = class_daily_subject_count.get("\{class.id}_\{day}_\{cs.id}").or(0)
          
          match subject_teachers.get(cs.id) {
            Some(t_ids) => {
              for t_id in t_ids {
                // Check if blocked
                let is_blocked = teacher_unavail.get("\{t_id}_\{day}_\{period_num}").or(false)
                let is_busy = teacher_busy.get("\{t_id}_\{day}_\{period_num}").or(false)
                
                if not(is_blocked) && not(is_busy) {
                  let workload = teacher_workload.get(t_id).or(0)
                  let is_arm_matched = cohort_daily_subjects.get("\{cohort_base}_\{day}_\{cs.subject}").or(false)
                  
                  let tier_val = cs.default_tier.or(1)
                  let tier_penalty = if period_num <= early_cutoff {
                    3 - tier_val
                  } else {
                    tier_val
                  }
                  
                  let arm_sync_bonus = if is_arm_matched { -150 } else { 0 }
                  
                  let score = (daily_count * 500) + arm_sync_bonus + (workload * 5) + tier_penalty
                  
                  candidates.push(Candidate::{
                    subject_id: cs.id,
                    teacher_id: t_id,
                    subject_base_id: cs.subject,
                    score: score
                  })
                }
              }
            }
            None => ()
          }
        }

        if candidates.length() > 0 {
          // Sort by score ascending
          candidates.sort_by(fn(a, b) { a.score.compare(b.score) })
          let selected = candidates[0]
          
          output_slots.push(ScheduleSlot::{
            id: slot_id,
            timetable: timetable_id,
            class_level: class.id,
            day_of_week: day,
            period_number: period_num,
            subject_edge: Some(selected.subject_id),
            teacher: Some(selected.teacher_id),
            is_excluded: false,
            created_at: "",
          })
          
          let old_rem = target_periods.get(selected.subject_id).or(0)
          target_periods.set(selected.subject_id, old_rem - 1)
          
          let old_wl = teacher_workload.get(selected.teacher_id).or(0)
          teacher_workload.set(selected.teacher_id, old_wl + 1)
          
          let old_dc = class_daily_subject_count.get("\{class.id}_\{day}_\{selected.subject_id}").or(0)
          class_daily_subject_count.set("\{class.id}_\{day}_\{selected.subject_id}", old_dc + 1)
          
          cohort_daily_subjects.set("\{cohort_base}_\{day}_\{selected.subject_base_id}", true)
          teacher_busy.set("\{selected.teacher_id}_\{day}_\{period_num}", true)
        } else {
          output_slots.push(ScheduleSlot::{
            id: slot_id,
            timetable: timetable_id,
            class_level: class.id,
            day_of_week: day,
            period_number: period_num,
            subject_edge: None,
            teacher: None,
            is_excluded: false,
            created_at: "",
          })
        }
        
        period_num += 1
      }
    }
  }

  // Finally, bulk insert
  match db_admin_bulk_insert_schedule_slots(config, output_slots) {
    Ok(_) => Ok("Timetable generated successfully with \{output_slots.length()} slots.")
    Err(e) => Err(e)
  }
}

// A generic internal helper to deserialize since we are in the same package
fn parse_result_array_internal[T : @json.FromJson](
  arr : Array[Json]
) -> Result[Array[T], AppError] {
  let res : Array[T] = []
  for item in arr {
    let parsed : T = @json.from_json(item) catch {
      _ => return Err(
        AppError::{
          code: InternalError,
          message: "Failed to deserialize JSON array element",
          debug: None,
        }
      )
    }
    res.push(parsed)
  }
  Ok(res)
}

struct Candidate {
  subject_id : String
  teacher_id : String
  subject_base_id : String
  score : Int
}
