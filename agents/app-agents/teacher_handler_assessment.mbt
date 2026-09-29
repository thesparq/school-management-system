///|
fn parse_assessment_questions(
  json_arr : Array[Json],
) -> Array[AssessmentQuestion]? {
  let questions : Array[AssessmentQuestion] = []
  for item in json_arr {
    match item {
      Object(obj) => {
        let qi = match obj.get("question_index") {
          Some(Number(n, ..)) => n.to_int()
          _ => continue
        }
        let question_type = match obj.get("question_type") {
          Some(String(s)) => s
          _ => continue
        }
        let question_text = match obj.get("question_text") {
          Some(String(s)) => s
          _ => continue
        }
        let option_a = match obj.get("option_a") {
          Some(String(s)) => Some(s)
          _ => None
        }
        let option_b = match obj.get("option_b") {
          Some(String(s)) => Some(s)
          _ => None
        }
        let option_c = match obj.get("option_c") {
          Some(String(s)) => Some(s)
          _ => None
        }
        let correct_answer = match obj.get("correct_answer") {
          Some(String(s)) => Some(s)
          _ => None
        }
        let allocated_mark = match obj.get("allocated_mark") {
          Some(Number(n, ..)) => n.to_int()
          _ => 1
        }
        let source_question_index = match obj.get("source_question_index") {
          Some(Number(n, ..)) => n.to_int()
          _ => qi
        }
        questions.push(AssessmentQuestion::{
          question_index: qi,
          question_type,
          question_text,
          option_a,
          option_b,
          option_c,
          correct_answer,
          allocated_mark,
          source_question_index,
        })
      }
      _ => ()
    }
  }
  if questions.length() > 0 {
    Some(questions)
  } else {
    None
  }
}

///|
fn parse_questions_from_json(json_val : Json) -> Array[AssessmentQuestion] {
  match json_val {
    Array(arr) =>
      match parse_assessment_questions(arr) {
        Some(q) => q
        None => []
      }
    _ => []
  }
}

///|
fn parse_lesson_assessment_json(
  json_str : String,
) -> Result[LessonAssessmentInfo, AppError] {
  let val = @json.parse(json_str) catch {
    _ => return Err(validation_error("Failed to parse assessment response"))
  }
  let obj = match val {
    Object(o) => o
    _ => return Err(validation_error("Unexpected assessment response format"))
  }
  let id = match obj.get("id") {
    Some(String(s)) => s
    _ => ""
  }
  let lesson = match obj.get("lesson") {
    Some(String(s)) => s
    Some(Object(o)) => {
      let lid = match o.get("id") {
        Some(String(s)) => s
        _ => ""
      }
      lid
    }
    _ => ""
  }
  let title = match obj.get("title") {
    Some(String(s)) => s
    _ => ""
  }
  let desc = match obj.get("description") {
    Some(String(s)) => Some(s)
    _ => None
  }
  let questions = match obj.get("questions") {
    Some(arr_val) => parse_questions_from_json(arr_val)
    _ => []
  }
  let total_mark = match obj.get("total_mark") {
    Some(Number(n, ..)) => n.to_int()
    _ => 0
  }
  let max_resub = match obj.get("max_resubmissions") {
    Some(Number(n, ..)) => n.to_int()
    _ => 0
  }
  let deadline = match obj.get("deadline") {
    Some(String(s)) => Some(s)
    _ => None
  }
  let active = match obj.get("active") {
    Some(True) => true
    _ => false
  }
  let scheduled_at = match obj.get("scheduled_at") {
    Some(String(s)) => Some(s)
    _ => None
  }
  let created_at = match obj.get("created_at") {
    Some(String(s)) => s
    _ => ""
  }
  Ok(LessonAssessmentInfo::{
    id,
    lesson,
    title,
    description: desc,
    questions,
    total_mark,
    max_resubmissions: max_resub,
    deadline,
    active,
    scheduled_at,
    created_at,
  })
}

///|
fn parse_general_assessment_json(
  json_str : String,
) -> Result[GeneralAssessmentInfo, AppError] {
  let val = @json.parse(json_str) catch {
    _ => return Err(validation_error("Failed to parse assessment response"))
  }
  let obj = match val {
    Object(o) => o
    _ => return Err(validation_error("Unexpected assessment response format"))
  }
  let id = match obj.get("id") {
    Some(String(s)) => s
    _ => ""
  }
  let session_term = match obj.get("session_term") {
    Some(String(s)) => s
    Some(Object(o)) => {
      let sid = match o.get("id") {
        Some(String(s)) => s
        _ => ""
      }
      sid
    }
    _ => ""
  }
  let subject = match obj.get("subject") {
    Some(String(s)) => s
    Some(Object(o)) => {
      let sid = match o.get("id") {
        Some(String(s)) => s
        _ => ""
      }
      sid
    }
    _ => ""
  }
  let title = match obj.get("title") {
    Some(String(s)) => s
    _ => ""
  }
  let desc = match obj.get("description") {
    Some(String(s)) => Some(s)
    _ => None
  }
  let percentage_weight = match obj.get("percentage_weight") {
    Some(Number(n, ..)) => n.to_int()
    _ => 0
  }
  let questions_opt = match obj.get("questions") {
    Some(arr_val) => Some(parse_questions_from_json(arr_val))
    _ => None
  }
  let total_mark = match obj.get("total_mark") {
    Some(Number(n, ..)) => n.to_int()
    _ => 0
  }
  let max_resub = match obj.get("max_resubmissions") {
    Some(Number(n, ..)) => n.to_int()
    _ => 0
  }
  let deadline = match obj.get("deadline") {
    Some(String(s)) => Some(s)
    _ => None
  }
  let active = match obj.get("active") {
    Some(True) => true
    _ => false
  }
  let scheduled_at = match obj.get("scheduled_at") {
    Some(String(s)) => Some(s)
    _ => None
  }
  let created_at = match obj.get("created_at") {
    Some(String(s)) => s
    _ => ""
  }
  Ok(GeneralAssessmentInfo::{
    id,
    session_term,
    subject,
    title,
    description: desc,
    percentage_weight,
    questions: questions_opt,
    compositions: None,
    total_mark,
    max_resubmissions: max_resub,
    deadline,
    active,
    scheduled_at,
    created_at,
  })
}

///|
fn parse_composition_json(
  json_str : String,
) -> Result[CompositionInfo, AppError] {
  let val = @json.parse(json_str) catch {
    _ => return Err(validation_error("Failed to parse composition response"))
  }
  let obj = match val {
    Object(o) => o
    _ => return Err(validation_error("Unexpected composition response format"))
  }
  let id = match obj.get("id") {
    Some(String(s)) => s
    _ => ""
  }
  let lesson_assessment = match obj.get("lesson_assessment") {
    Some(String(s)) => s
    Some(Object(o)) => {
      let lid = match o.get("id") {
        Some(String(s)) => s
        _ => ""
      }
      lid
    }
    _ => ""
  }
  let la_title = match obj.get("lesson_assessment_title") {
    Some(String(s)) => Some(s)
    _ => None
  }
  let la_total_mark = match obj.get("lesson_assessment_total_mark") {
    Some(Number(n, ..)) => Some(n.to_int())
    _ => None
  }
  let weight_pct = match obj.get("weight_pct") {
    Some(Number(d, ..)) => Float::from_double(d)
    _ => 0.0
  }
  Ok(CompositionInfo::{
    id,
    lesson_assessment,
    lesson_assessment_title: la_title,
    lesson_assessment_total_mark: la_total_mark,
    weight_pct,
  })
}

///|
fn parse_submission_json(json_str : String) -> Result[SubmissionInfo, AppError] {
  let val = @json.parse(json_str) catch {
    _ => return Err(validation_error("Failed to parse submission response"))
  }
  let obj = match val {
    Object(o) => o
    _ => return Err(validation_error("Unexpected submission response format"))
  }
  let id = match obj.get("id") {
    Some(String(s)) => s
    _ => ""
  }
  let assessment_type = match obj.get("assessment_type") {
    Some(String(s)) => s
    _ => ""
  }
  let assessment_id = match obj.get("assessment_id") {
    Some(String(s)) => s
    _ => ""
  }
  let student_val = match obj.get("student") {
    Some(String(s)) => s
    Some(Object(o)) => {
      let sid = match o.get("id") {
        Some(String(s)) => s
        _ => ""
      }
      sid
    }
    _ => ""
  }
  let student_name = match obj.get("student_name") {
    Some(String(s)) => Some(s)
    _ => None
  }
  let iteration = match obj.get("iteration") {
    Some(Number(n, ..)) => n.to_int()
    _ => 1
  }
  let status = match obj.get("status") {
    Some(String(s)) => s
    _ => "pending"
  }
  let submitted_at = match obj.get("submitted_at") {
    Some(String(s)) => s
    _ => ""
  }
  let total_mark = match obj.get("total_mark") {
    Some(Number(n, ..)) => n.to_int()
    _ => 0
  }
  let scored_mark = match obj.get("scored_mark") {
    Some(Number(n, ..)) => Some(n.to_int())
    _ => None
  }
  let grade_released_at = match obj.get("grade_released_at") {
    Some(String(s)) => Some(s)
    _ => None
  }
  let answers_arr = match obj.get("answers") {
    Some(Array(a)) => {
      let items : Array[SubmissionAnswer] = []
      for item in a {
        match item {
          Object(ao) => {
            let qidx = match ao.get("question_index") {
              Some(Number(n, ..)) => n.to_int()
              _ => continue
            }
            let atype = match ao.get("answer_type") {
              Some(String(s)) => s
              _ => continue
            }
            let atext = match ao.get("answer_text") {
              Some(String(s)) => s
              _ => continue
            }
            let amark = match ao.get("allocated_mark") {
              Some(Number(n, ..)) => n.to_int()
              _ => 1
            }
            let smark = match ao.get("scored_mark") {
              Some(Number(n, ..)) => Some(n.to_int())
              _ => None
            }
            let correct = match ao.get("correct") {
              Some(True) => Some(true)
              Some(False) => Some(false)
              _ => None
            }
            items.push(SubmissionAnswer::{
              question_index: qidx,
              answer_type: atype,
              answer_text: atext,
              allocated_mark: amark,
              scored_mark: smark,
              correct,
            })
          }
          _ => ()
        }
      }
      items
    }
    _ => []
  }
  Ok(SubmissionInfo::{
    id,
    assessment_type,
    assessment_id,
    student: student_val,
    student_name,
    iteration,
    status,
    submitted_at,
    answers: answers_arr,
    total_mark,
    scored_mark,
    grade_released_at,
  })
}

///|
pub fn teacher_create_lesson_assessment(
  config : SharedConfig,
  body_json : String,
) -> Result[LessonAssessmentInfo, AppError] {
  let val = @json.parse(body_json) catch {
    _ => return Err(validation_error("Invalid JSON body"))
  }
  let obj = match val {
    Object(o) => o
    _ => return Err(validation_error("Body must be an object"))
  }
  let lesson_id = match obj.get("lesson_id") {
    Some(String(s)) => s
    _ => return Err(validation_error("lesson_id required"))
  }
  let title = match obj.get("title") {
    Some(String(s)) => s
    _ => return Err(validation_error("title required"))
  }
  let description = match obj.get("description") {
    Some(String(s)) => Some(s)
    _ => None
  }
  let questions_raw = match obj.get("questions") {
    Some(Array(a)) => a
    _ => return Err(validation_error("questions required"))
  }
  let questions = match parse_assessment_questions(questions_raw) {
    Some(q) => q
    _ => return Err(validation_error("Invalid questions array"))
  }
  let total_mark = match obj.get("total_mark") {
    Some(Number(n, ..)) => n.to_int()
    _ => {
      let mut sum = 0
      for q in questions {
        sum += q.allocated_mark
      }
      sum
    }
  }
  let max_resub = match obj.get("max_resubmissions") {
    Some(Number(n, ..)) => n.to_int()
    _ => 0
  }
  let deadline = match obj.get("deadline") {
    Some(String(s)) => s
    _ => ""
  }
  let scheduled_at = match obj.get("scheduled_at") {
    Some(String(s)) => s
    _ => ""
  }
  let teacher_id = match obj.get("teacher_id") {
    Some(String(s)) => s
    _ => return Err(validation_error("teacher_id required"))
  }
  let desc_str = match description {
    Some(d) => d
    _ => ""
  }
  let q_json = questions.to_json().stringify()
  let result = match
    db_create_lesson_assessment(
      config, lesson_id, title, desc_str, q_json, total_mark, max_resub, deadline,
      scheduled_at, teacher_id,
    ) {
    Ok(arr) => arr
    Err(e) => return Err(e)
  }
  if result.length() == 0 {
    return Err(validation_error("Failed to create lesson assessment"))
  }
  parse_lesson_assessment_json(result[0].stringify())
}

///|
pub fn teacher_create_general_assessment(
  config : SharedConfig,
  body_json : String,
) -> Result[GeneralAssessmentInfo, AppError] {
  let val = @json.parse(body_json) catch {
    _ => return Err(validation_error("Invalid JSON body"))
  }
  let obj = match val {
    Object(o) => o
    _ => return Err(validation_error("Body must be an object"))
  }
  let session_term_id = match obj.get("session_term_id") {
    Some(String(s)) => s
    _ => return Err(validation_error("session_term_id required"))
  }
  let subject_id = match obj.get("subject_id") {
    Some(String(s)) => s
    _ => return Err(validation_error("subject_id required"))
  }
  let title = match obj.get("title") {
    Some(String(s)) => s
    _ => return Err(validation_error("title required"))
  }
  let description = match obj.get("description") {
    Some(String(s)) => Some(s)
    _ => None
  }
  let percentage_weight = match obj.get("percentage_weight") {
    Some(Number(n, ..)) => n.to_int()
    _ => 0
  }
  let teacher_id = match obj.get("teacher_id") {
    Some(String(s)) => s
    _ => return Err(validation_error("teacher_id required"))
  }
  let total_mark = match obj.get("total_mark") {
    Some(Number(n, ..)) => n.to_int()
    _ => 0
  }
  let max_resub = match obj.get("max_resubmissions") {
    Some(Number(n, ..)) => n.to_int()
    _ => 0
  }
  let deadline = match obj.get("deadline") {
    Some(String(s)) => s
    _ => ""
  }
  let scheduled_at = match obj.get("scheduled_at") {
    Some(String(s)) => s
    _ => ""
  }
  let desc_str = match description {
    Some(d) => d
    _ => ""
  }

  let questions_json = match obj.get("questions") {
    Some(Array(a)) => {
      let qs = match parse_assessment_questions(a) {
        Some(q) => q
        _ => return Err(validation_error("Invalid questions array"))
      }
      qs.to_json().stringify()
    }
    _ => ""
  }

  let compositions_to_create : Array[(String, Float)] = []
  match obj.get("compositions") {
    Some(Array(a)) => {
      let mut total_w = 0.0
      for item in a {
        match item {
          Object(c_obj) => {
            let cid = match c_obj.get("lesson_assessment") {
              Some(String(s)) => s
              _ => return Err(validation_error("Missing lesson_assessment id in composition"))
            }
            let weight = match c_obj.get("weight_pct") {
              Some(Number(n)) => n
              _ => return Err(validation_error("Missing weight_pct in composition"))
            }
            total_w = total_w + weight
            compositions_to_create.push((cid, Float::from_double(weight)))
          }
          _ => ()
        }
      }
      if compositions_to_create.length() > 0 && total_w != 100.0 {
        return Err(validation_error("Composition weights must sum to exactly 100"))
      }
    }
    _ => ()
  }
  let has_compositions = compositions_to_create.length() > 0

  // Verify total percentage weight for this term/subject doesn't exceed 100
  let existing_gas = match db_fetch_general_assessments(config, session_term_id, subject_id) {
    Ok(arr) => arr
    Err(e) => return Err(e)
  }
  let mut current_total_weight = 0
  for row in existing_gas {
    match row.as_object() {
      Some(o) => {
        match o.get("percentage_weight") {
          Some(Number(w)) => current_total_weight = current_total_weight + w.to_int()
          _ => ()
        }
      }
      _ => ()
    }
  }
  if current_total_weight + percentage_weight > 100 {
    return Err(validation_error("Total percentage weight for assessments in this term exceeds 100%"))
  }

  let result = match
    db_create_general_assessment(
      config, session_term_id, subject_id, title, desc_str, percentage_weight, questions_json,
      total_mark, max_resub, deadline, scheduled_at, teacher_id,
    ) {
    Ok(arr) => arr
    Err(e) => return Err(e)
  }
  if result.length() == 0 {
    return Err(validation_error("Failed to create general assessment"))
  }
  let ga = match parse_general_assessment_json(result[0].stringify()) {
    Ok(g) => g
    Err(e) => return Err(e)
  }

  if has_compositions {
    for comp in compositions_to_create {
      match db_create_composition(config, ga.id, comp.0, comp.1) {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
    }
  }
  if has_compositions {
    let comps = match db_fetch_compositions(config, ga.id) {
      Ok(arr) => arr
      Err(e) => return Err(e)
    }
    let comp_infos : Array[CompositionInfo] = []
    for row in comps {
      match parse_composition_json(row.stringify()) {
        Ok(ci) => comp_infos.push(ci)
        Err(_) => ()
      }
    }
    let result_ga = GeneralAssessmentInfo::{
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
    Ok(result_ga)
  } else {
    Ok(ga)
  }
}

///|
pub fn teacher_fetch_lesson_assessments(
  config : SharedConfig,
  lesson_id : String,
) -> Result[Array[LessonAssessmentInfo], AppError] {
  let arr = match db_fetch_lesson_assessments(config, lesson_id) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  let items : Array[LessonAssessmentInfo] = []
  for row in arr {
    match parse_lesson_assessment_json(row.stringify()) {
      Ok(item) => items.push(item)
      Err(_) => ()
    }
  }
  Ok(items)
}

///|
pub fn teacher_fetch_general_assessments(
  config : SharedConfig,
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
      Err(_) => ()
    }
  }
  Ok(items)
}

///|
pub fn teacher_fetch_submissions(
  config : SharedConfig,
  assessment_type : String,
  assessment_id : String,
) -> Result[Array[SubmissionInfo], AppError] {
  let arr = match
    db_fetch_submissions_for_assessment(config, assessment_type, assessment_id) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  let items : Array[SubmissionInfo] = []
  for row in arr {
    match parse_submission_json(row.stringify()) {
      Ok(si) => items.push(si)
      Err(_) => ()
    }
  }
  Ok(items)
}

///|
pub fn teacher_grade_submission(
  config : SharedConfig,
  body_json : String,
) -> Result[SubmissionInfo, AppError] {
  let val = @json.parse(body_json) catch {
    _ => return Err(validation_error("Invalid JSON body"))
  }
  let obj = match val {
    Object(o) => o
    _ => return Err(validation_error("Body must be an object"))
  }
  let submission_id = match obj.get("submission_id") {
    Some(String(s)) => s
    _ => return Err(validation_error("submission_id required"))
  }
  let answers_raw = match obj.get("answers") {
    Some(Array(a)) => a
    _ => return Err(validation_error("answers required"))
  }
  let mut scored = 0
  for item in answers_raw {
    match item {
      Object(ao) => {
        let sm = match ao.get("scored_mark") {
          Some(Number(n, ..)) => n.to_int()
          _ => 0
        }
        scored += sm
      }
      _ => ()
    }
  }
  match db_update_submission_marks(config, submission_id, scored) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  match db_fetch_submission_by_id(config, submission_id) {
    Ok(arr) =>
      if arr.length() > 0 {
        parse_submission_json(arr[0].stringify())
      } else {
        Err(not_found_error("Submission"))
      }
    Err(e) => Err(e)
  }
}

///|
pub fn teacher_release_grades(
  config : SharedConfig,
  submission_id : String,
) -> Result[SubmissionInfo, AppError] {
  match db_release_grades(config, submission_id) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  match db_fetch_submission_by_id(config, submission_id) {
    Ok(arr) =>
      if arr.length() > 0 {
        parse_submission_json(arr[0].stringify())
      } else {
        Err(not_found_error("Submission"))
      }
    Err(e) => Err(e)
  }
}

///|
pub fn teacher_toggle_assessment(
  config : SharedConfig,
  assessment_type : String,
  assessment_id : String,
  active : Bool,
) -> Result[String, AppError] {
  let table = if assessment_type == "lesson" {
    "lesson_assessments"
  } else {
    "general_assessments"
  }
  match db_toggle_assessment_active(config, table, assessment_id, active) {
    Ok(_) => Ok("ok")
    Err(e) => Err(e)
  }
}

///|
pub fn teacher_get_percentage_summary(
  config : SharedConfig,
  session_term_id : String,
  subject_id : String,
) -> Result[PercentageSummary, AppError] {
  let arr = match
    db_sum_percentage_weights(config, session_term_id, subject_id, "") {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  let current = if arr.length() > 0 {
    match arr[0] {
      Object(obj) =>
        match obj.get("total") {
          Some(Number(n, ..)) => n.to_int()
          _ => 0
        }
      _ => 0
    }
  } else {
    0
  }
  let remaining = if 100 - current > 0 { 100 - current } else { 0 }
  Ok(PercentageSummary::{ current, remaining })
}

///|
pub fn teacher_manual_grade(
  config : SharedConfig,
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
  let student_id = match obj.get("student_id") {
    Some(String(s)) => s
    _ => return Err(validation_error("student_id required"))
  }
  let scored_mark = match obj.get("scored_mark") {
    Some(Number(n, ..)) => n.to_int()
    _ => return Err(validation_error("scored_mark required"))
  }

  // Fetch assessment total mark
  let total_mark = match assessment_type {
    "lesson" => {
      let arr = match db_fetch_assessment_by_id(config, "lesson_assessments", assessment_id) {
        Ok(a) => a
        Err(e) => return Err(e)
      }
      if arr.length() == 0 { return Err(not_found_error("Lesson Assessment")) }
      match parse_lesson_assessment_json(arr[0].stringify()) {
        Ok(la) => la.total_mark
        Err(e) => return Err(e)
      }
    }
    "general" => {
      let arr = match db_fetch_assessment_by_id(config, "general_assessments", assessment_id) {
        Ok(a) => a
        Err(e) => return Err(e)
      }
      if arr.length() == 0 { return Err(not_found_error("General Assessment")) }
      match parse_general_assessment_json(arr[0].stringify()) {
        Ok(ga) => ga.total_mark
        Err(e) => return Err(e)
      }
    }
    _ => return Err(validation_error("Invalid assessment_type"))
  }

  if scored_mark < 0 || scored_mark > total_mark {
    return Err(validation_error("Scored mark must be between 0 and \{total_mark}"))
  }

  let existing = match db_fetch_submission(config, student_id, assessment_type, assessment_id) {
    Ok(arr) => if arr.length() > 0 { Some(arr[0]) } else { None }
    Err(e) => return Err(e)
  }

  let existing_id = match existing {
    Some(Object(o)) => {
      match o.get("id") {
        Some(String(s)) => s
        _ => ""
      }
    }
    _ => ""
  }
  let iter = match existing {
    Some(Object(o)) => {
      match o.get("iteration") {
        Some(Number(n, ..)) => n.to_int()
        _ => 1
      }
    }
    _ => 1
  }

  // Upsert
  let result = match db_upsert_submission(
    config, existing_id, assessment_type, assessment_id, student_id, iter, "graded", "[]", total_mark, scored_mark.to_string(), "time::now()"
  ) {
    Ok(arr) => arr
    Err(e) => return Err(e)
  }
  if result.length() == 0 {
    return Err(validation_error("Failed to upsert submission"))
  }
  
  let sub_id = match result[0].as_object() {
    Some(o) => {
      match o.get("id") {
        Some(String(s)) => s
        _ => return Err(validation_error("Failed to extract ID"))
      }
    }
    _ => return Err(validation_error("Result is not object"))
  }
  
  match db_release_grades(config, sub_id) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }

  match db_fetch_submission_by_id(config, sub_id) {
    Ok(arr) =>
      if arr.length() > 0 {
        parse_submission_json(arr[0].stringify())
      } else {
        Err(validation_error("Failed to fetch updated submission"))
      }
    Err(e) => Err(e)
  }
}

///|
pub fn teacher_fetch_students_in_class(
  config : SharedConfig,
  class_id : String,
) -> Result[Array[StudentProfileInfo], AppError] {
  let arr = match surreal_query(
    config,
    "SELECT meta::id(id) AS id, surname, first_name, middle_name, display_name, date_of_birth, current_class, class_enrolled, passport, created_at FROM student_profile WHERE current_class = type::record('class_levels', $cl) OR current_class = type::record('class_arms', $cl)",
    bindings={ "cl": class_id.replace_all(old="class_levels:", new="").replace_all(old="class_arms:", new="") },
  ) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  
  let items : Array[StudentProfileInfo] = []
  for item in arr {
    match item {
      Object(o) =>
        items.push(StudentProfileInfo::{
          id: match o.get("id") { Some(String(s)) => s
            _ => "" },
          surname: match o.get("surname") { Some(String(s)) => s
            _ => "" },
          first_name: match o.get("first_name") { Some(String(s)) => s
            _ => "" },
          middle_name: match o.get("middle_name") { Some(String(s)) => Some(s)
            _ => None },
          display_name: match o.get("display_name") { Some(String(s)) => s
            _ => "" },
          date_of_birth: match o.get("date_of_birth") { Some(String(s)) => s
            _ => "" },
          current_class: match o.get("current_class") { Some(String(s)) => s
            _ => "" },
          class_enrolled: match o.get("class_enrolled") { Some(String(s)) => s
            _ => "" },
          class_name: "",
          created_at: match o.get("created_at") { Some(String(s)) => s
            _ => "" },
          passport: match o.get("passport") { Some(String(s)) => s
            _ => "" }
        })
      _ => ()
    }
  }
  Ok(items)
}
