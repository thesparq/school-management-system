export interface Subject {
  id: string;
  name: string;
  code: string | null;
}

export interface Term {
  id: string;
  name: string;
  sort_order: number;
  active: boolean;
}

export interface Lesson {
  id: string;
  topic_title: string | null;
  week: number | null;
  active?: boolean;
  subject_name: string | null;
  term_name: string | null;
}

export interface LessonContent {
  id: string;
  topic_title: string | null;
  week: number | null;
  subject_name: string | null;
  term_name: string | null;
  objectives: string | null;
  content_sections: string | null;
  key_points: string | null;
  mcq_questions: string | null;
  theoretical_questions: string | null;
}

export interface McqQuestion {
  question: string;
  option_a: string;
  option_b: string;
  option_c: string;
  explanation: string;
  correct_answer: string;
}

export interface TheoreticalQuestion {
  question: string;
  answer: string;
}

export interface LessonObjective {
  objective: string;
  taxonomy_level: string;
}

export interface SubPoint {
  sub_number: string;
  text: string;
}

export interface LessonContentSection {
  header: string;
  body: string;
  section_number: number;
  sub_points: SubPoint[];
}

export interface TeacherSubjectPair {
  edge_id: string;
  class_level_id: string;
  class_level_name: string;
  subject_id: string;
  subject_name: string;
  subject_code: string | null;
}

export interface TeacherClassGroup {
  class_level_id: string;
  class_level_name: string;
  subjects: TeacherSubjectPair[];
}

export interface BreadcrumbItem {
  label: string;
  href?: string;
}

export interface CredentialInfo {
	id: string;
	name: string;
	active: boolean;
}

export interface StudentListItem {
	id: string;
	display_name: string;
}

export interface AssessmentQuestion {
	question_index: number;
	question_type: string;
	question_text: string;
	option_a: string | null;
	option_b: string | null;
	option_c: string | null;
	correct_answer: string | null;
	allocated_mark: number;
	source_question_index: number;
}

export interface LessonAssessmentInfo {
	id: string;
	lesson: string;
	title: string;
	description: string | null;
	questions: AssessmentQuestion[];
	total_mark: number;
	max_resubmissions: number;
	deadline: string | null;
	active: boolean;
	scheduled_at: string | null;
	created_at: string;
}

export interface CompositionInfo {
	id: string;
	lesson_assessment: string;
	lesson_assessment_title: string | null;
	lesson_assessment_total_mark: number | null;
	weight_pct: number;
}

export interface GeneralAssessmentInfo {
	id: string;
	session_term: string;
	subject: string;
	title: string;
	description: string | null;
	percentage_weight: number;
	questions: AssessmentQuestion[] | null;
	compositions: CompositionInfo[] | null;
	total_mark: number;
	max_resubmissions: number;
	deadline: string | null;
	active: boolean;
	scheduled_at: string | null;
	created_at: string;
}

export interface SubmissionAnswer {
	question_index: number;
	answer_type: string;
	answer_text: string;
	allocated_mark: number;
	scored_mark: number | null;
	correct: boolean | null;
}

export interface SubmissionInfo {
	id: string;
	assessment_type: string;
	assessment_id: string;
	student: string;
	student_name: string | null;
	iteration: number;
	status: string;
	submitted_at: string;
	answers: SubmissionAnswer[];
	total_mark: number;
	scored_mark: number | null;
	grade_released_at: string | null;
}

export interface CompositionGradeBreakdown {
	lesson_assessment_title: string;
	scored_pct: number | null;
	weight_pct: number;
	graded: boolean;
}

export interface CompositionGradeResult {
	total_scored_pct: number | null;
	total_weight_pct: number;
	breakdown: CompositionGradeBreakdown[];
	all_graded: boolean;
}

export interface PercentageSummary {
	current: number;
	remaining: number;
}
