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
}
