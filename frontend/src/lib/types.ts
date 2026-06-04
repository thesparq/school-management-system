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
