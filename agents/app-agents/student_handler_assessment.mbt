///|
fn try_activate_if_scheduled(
  config : SharedConfig,
  table : String,
  id : String,
  scheduled_at : String?,
  active : Bool,
) -> Unit {
  if !active {
    match scheduled_at {
      Some(s) =>
        if s != "" {
          let _ = db_toggle_assessment_active(config, table, id, true)
        }
      None => ()
    }
  }
}

///|
pub fn student_fetch_lesson_assessments(
  config : SharedConfig,
  student_id : String,
  lesson_id : String,
) -> Result[Array[LessonAssessmentInfo], AppError] {
  let arr = match db_fetch_lesson_assessments(config, lesson_id) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  let items : Array[LessonAssessmentInfo] = []
  for row in arr {
    let json_str = row.stringify()
    match parse_lesson_assessment_json(json_str) {
      Ok(la) => {
        try_activate_if_scheduled(
          config,
          "lesson_assessments",
          la.id,
          la.scheduled_at,
          la.active,
        )
        if la.active {
          items.push(la)
        }
      }
      Err(_) => ()
    }
  }
  Ok(items)
}

///|
pub fn student_fetch_general_assessments(
  config : SharedConfig,
  student_id : String,
  session_term_id : String,
  subject_id : String,
) -> Result[Array[GeneralAssessmentInfo], AppError] {
  let arr = match
    db_fetch_general_assessments(config, session_term_id, subject_id) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  let items : Array[GeneralAssessmentInfo] = []
  for row in arr {
    match parse_general_assessment_json(row.stringify()) {
      Ok(ga) => {
        try_activate_if_scheduled(
          config,
          "general_assessments",
          ga.id,
          ga.scheduled_at,
          ga.active,
        )
        let comps = match db_fetch_compositions(config, ga.id) {
          Ok(ca) => ca
          Err(_) => []
        }
        let comp_infos : Array[CompositionInfo] = []
        for comp in comps {
          match parse_composition_json(comp.stringify()) {
            Ok(ci) => comp_infos.push(ci)
            Err(_) => ()
          }
        }
        if ga.active {
          let result_ga = if comp_infos.length() > 0 {
            GeneralAssessmentInfo::{
              id: ga.id,
              session_term: ga.session_term,
              subject: ga.subject,
              title: ga.title,
              description: ga.description,
              percentage_weight: ga.percentage_weight,
              questions: ga.questions,
              compositions: Some(comp_infos),
              total_mark: ga.total_mark,
              max_resubmissions: ga.max_resubmissions,
              deadline: ga.deadline,
              active: ga.active,
              scheduled_at: ga.scheduled_at,
              created_at: ga.created_at,
            }
          } else {
            ga
          }
          items.push(result_ga)
        }
      }
      Err(_) => ()
    }
  }
  Ok(items)
}

///|
pub fn student_submit_assessment(
  config : SharedConfig,
  student_id : String,
  body_json : String,
) -> Result[SubmissionInfo, AppError] {
  let val = @json.parse(body_json) catch {
    _ => return Err(validation_error("Invalid JSON body"))
  }
  let obj = match val {
    Object(o) => o
    _ => return Err(validation_error("Body must be an object"))
  }
  let assessment_type = match obj.get("assessment_type") {
    Some(String(s)) => s
    _ => return Err(validation_error("assessment_type required"))
  }
  let assessment_id = match obj.get("assessment_id") {
    Some(String(s)) => s
    _ => return Err(validation_error("assessment_id required"))
  }
  let answers_raw = match obj.get("answers") {
    Some(Array(a)) => a
    _ => return Err(validation_error("answers required"))
  }

  let table = if assessment_type == "lesson" {
    "lesson_assessments"
  } else {
    "general_assessments"
  }
  let assessment_arr = match
    db_fetch_assessment_by_id(config, table, assessment_id) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  if assessment_arr.length() == 0 {
    return Err(not_found_error("Assessment"))
  }
  let assessment_obj = match assessment_arr[0] {
    Object(o) => o
    _ =>
      return Err(AppError::{
        code: InternalError,
        message: "Invalid assessment data",
        debug: None,
      })
  }
  let active = match assessment_obj.get("active") {
    Some(True) => true
    Some(False) => false
    _ => false
  }
  if !active {
    return Err(validation_error("Assessment is not active"))
  }

  let existing_arr = match
    db_fetch_submission(config, student_id, assessment_type, assessment_id) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  let existing_sub_json = if existing_arr.length() > 0 {
    Some(existing_arr[0])
  } else {
    None
  }
  let max_resub = match assessment_obj.get("max_resubmissions") {
    Some(Number(n, ..)) => n.to_int()
    _ => 0
  }

  let existing_id = match existing_sub_json {
    Some(Object(o)) =>
      match o.get("id") {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
  let current_iter = match existing_sub_json {
    Some(Object(o)) =>
      match o.get("iteration") {
        Some(Number(n, ..)) => n.to_int()
        _ => 0
      }
    _ => 0
  }

  if existing_id != "" {
    if max_resub != -1 && current_iter >= max_resub {
      return Err(resubmission_limit_error())
    }
    let released = match existing_sub_json {
      Some(Object(o)) =>
        match o.get("grade_released_at") {
          Some(String(s)) if s != "" => true
          _ => false
        }
      _ => false
    }
    if released {
      return Err(
        validation_error("Cannot resubmit after grades have been released"),
      )
    }
  }
  let iteration = if existing_id != "" { current_iter + 1 } else { 1 }

  let mut scored_mark = 0
  let mut all_mcq_scored = true
  let parsed_answers : Array[SubmissionAnswer] = []

  let assessment_questions = match assessment_obj.get("questions") {
    Some(Array(a)) => a
    _ => []
  }

  for item in answers_raw {
    match item {
      Object(ao) => {
        let qi = match ao.get("question_index") {
          Some(Number(n, ..)) => n.to_int()
          _ => 0
        }
        let atype = match ao.get("answer_type") {
          Some(String(s)) => s
          _ => ""
        }
        let text = match ao.get("answer_text") {
          Some(String(s)) => s
          _ => ""
        }
        let am = match ao.get("allocated_mark") {
          Some(Number(n, ..)) => n.to_int()
          _ => 0
        }
        let mut correct_answer : String? = None
        for aq in assessment_questions {
          match aq {
            Object(aqo) => {
              let aqi = match aqo.get("question_index") {
                Some(Number(n, ..)) => n.to_int()
                _ => -1
              }
              if aqi == qi {
                correct_answer = match aqo.get("correct_answer") {
                  Some(String(s)) => Some(s)
                  _ => None
                }
              }
            }
            _ => ()
          }
        }

        if atype == "mcq" {
          match correct_answer {
            Some(ca) => {
              let is_correct = text == ca
              let sm = if is_correct { am } else { 0 }
              parsed_answers.push(SubmissionAnswer::{
                question_index: qi,
                answer_type: "mcq",
                answer_text: text,
                allocated_mark: am,
                scored_mark: Some(sm),
                correct: Some(is_correct),
              })
              if is_correct {
                scored_mark += am
              }
            }
            None => {
              parsed_answers.push(SubmissionAnswer::{
                question_index: qi,
                answer_type: "mcq",
                answer_text: text,
                allocated_mark: am,
                scored_mark: None,
                correct: None,
              })
              all_mcq_scored = false
            }
          }
        } else {
          parsed_answers.push(SubmissionAnswer::{
            question_index: qi,
            answer_type: "theoretical",
            answer_text: text,
            allocated_mark: am,
            scored_mark: None,
            correct: None,
          })
        }
      }
      _ => ()
    }
  }

  let total_mark = match assessment_obj.get("total_mark") {
    Some(Number(n, ..)) => n.to_int()
    _ => 0
  }

  let scored_str = if all_mcq_scored { scored_mark.to_string() } else { "" }

  let answers_json = parsed_answers.to_json().stringify()
  let result = match
    db_upsert_submission(
      config, existing_id, assessment_type, assessment_id, student_id, iteration,
      "submitted", answers_json, total_mark, scored_str, "",
    ) {
    Ok(arr) => arr
    Err(e) => return Err(e)
  }
  if result.length() == 0 {
    return Err(validation_error("Failed to create submission"))
  }
  parse_submission_json(result[0].stringify())
}

///|
pub fn student_fetch_my_grades(
  config : SharedConfig,
  student_id : String,
  assessment_type : String,
  assessment_id : String,
) -> Result[SubmissionInfo?, AppError] {
  let arr = match
    db_fetch_submission(config, student_id, assessment_type, assessment_id) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  if arr.length() == 0 {
    return Ok(None)
  }
  let sub = match parse_submission_json(arr[0].stringify()) {
    Ok(s) => s
    Err(e) => return Err(e)
  }
  if sub.grade_released_at == None {
    // Return metadata only, no grades
    let hidden = SubmissionInfo::{
      id: sub.id,
      assessment_type: sub.assessment_type,
      assessment_id: sub.assessment_id,
      student: sub.student,
      student_name: sub.student_name,
      iteration: sub.iteration,
      status: sub.status,
      submitted_at: sub.submitted_at,
      answers: [],
      total_mark: sub.total_mark,
      scored_mark: None,
      grade_released_at: None,
    }
    Ok(Some(hidden))
  } else {
    Ok(Some(sub))
  }
}

///|
pub fn compute_composition_grade(
  config : SharedConfig,
  student_id : String,
  ga_id : String,
) -> Result[CompositionGradeResult, AppError] {
  let comps_arr = match db_fetch_compositions(config, ga_id) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  let mut total_scored = Float::from_double(0.0)
  let mut total_weight = Float::from_double(0.0)
  let breakdown : Array[CompositionGradeBreakdown] = []
  let mut all_graded = true

  for comp_item in comps_arr {
    let comp = match parse_composition_json(comp_item.stringify()) {
      Ok(c) => c
      Err(e) => return Err(e)
    }
    let la_arr = match
      db_fetch_assessment_by_id(
        config,
        "lesson_assessments",
        comp.lesson_assessment,
      ) {
      Ok(a) => a
      Err(e) => return Err(e)
    }
    let la_title = if la_arr.length() > 0 {
      match la_arr[0] {
        Object(o) =>
          match o.get("title") {
            Some(String(s)) => s
            _ => "Unknown"
          }
        _ => "Unknown"
      }
    } else {
      "Unknown"
    }

    let sub_arr = match
      db_fetch_submission(config, student_id, "lesson", comp.lesson_assessment) {
      Ok(a) => a
      Err(e) => return Err(e)
    }

    if sub_arr.length() > 0 {
      let sub = match parse_submission_json(sub_arr[0].stringify()) {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      if sub.grade_released_at != None {
        match sub.scored_mark {
          Some(sm) =>
            if sub.total_mark > 0 {
              let sm_d = Float::from_double(sm.to_double())
              let tm_d = Float::from_double(sub.total_mark.to_double())
              let pct = sm_d / tm_d * comp.weight_pct
              total_scored += pct
              total_weight += comp.weight_pct
              breakdown.push(CompositionGradeBreakdown::{
                lesson_assessment_title: la_title,
                scored_pct: Some(pct),
                weight_pct: comp.weight_pct,
                graded: true,
              })
            } else {
              total_weight += comp.weight_pct
              breakdown.push(CompositionGradeBreakdown::{
                lesson_assessment_title: la_title,
                scored_pct: Some(Float::from_double(0.0)),
                weight_pct: comp.weight_pct,
                graded: true,
              })
            }
          None => {
            total_weight += comp.weight_pct
            breakdown.push(CompositionGradeBreakdown::{
              lesson_assessment_title: la_title,
              scored_pct: Some(Float::from_double(0.0)),
              weight_pct: comp.weight_pct,
              graded: true,
            })
          }
        }
      } else {
        all_graded = false
        breakdown.push(CompositionGradeBreakdown::{
          lesson_assessment_title: la_title,
          scored_pct: None,
          weight_pct: comp.weight_pct,
          graded: false,
        })
      }
    } else {
      total_weight += comp.weight_pct
      breakdown.push(CompositionGradeBreakdown::{
        lesson_assessment_title: la_title,
        scored_pct: Some(Float::from_double(0.0)),
        weight_pct: comp.weight_pct,
        graded: true,
      })
    }
  }

  let total_scored_pct = if all_graded { Some(total_scored) } else { None }
  Ok(CompositionGradeResult::{
    total_scored_pct,
    total_weight_pct: total_weight,
    breakdown,
    all_graded,
  })
}

///|
pub fn student_get_active_session_term(
  config : SharedConfig,
) -> Result[String, AppError] {
  let arr = match db_fetch_active_session_term(config) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  if arr.length() > 0 {
    Ok(arr[0].stringify())
  } else {
    Err(not_found_error("Active session term"))
  }
}
