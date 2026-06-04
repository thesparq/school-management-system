import { redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import type { LessonContent, TeacherClassGroup, BreadcrumbItem } from '$lib/types';

export const load: PageServerLoad = async ({ params, locals, fetch }) => {
  const userId = locals.user?.id;
  if (!userId || !locals.user?.roles.includes('teacher')) {
    redirect(302, '/');
  }

  const { classId, subjectId, termId, lessonId } = params;

  const lessonPromise = fetch(`/api/student/lesson?lesson_id=${encodeURIComponent(lessonId)}`)
    .then(async (res) => {
      if (!res.ok) {
        const err = await res.json().catch(() => ({ error: { message: 'Failed to fetch lesson' } }));
        return { lesson: null, lessonError: err.error?.message ?? 'Unknown error' };
      }
      const json = await res.json();
      const lesson: LessonContent | null = json.data ?? null;
      if (!lesson) {
        return { lesson: null, lessonError: 'Lesson not found.' };
      }
      return { lesson, lessonError: null };
    })
    .catch(() => ({ lesson: null, lessonError: 'Failed to reach server.' }));

  let classLevelName = 'Class';
  let subjectName = 'Subject';
  let termName = 'Term';

  const classesRes = await fetch('/api/teacher/classes');
  if (classesRes.ok) {
    try {
      const classesJson = await classesRes.json();
      const groups: TeacherClassGroup[] = classesJson.data ?? [];
      const match = groups.find((g: TeacherClassGroup) => g.class_level_id === classId);
      if (match) {
        classLevelName = match.class_level_name;
        const subjMatch = match.subjects.find(s => s.subject_id === subjectId);
        if (subjMatch) subjectName = subjMatch.subject_name;
      }
    } catch { /* fallback */ }
  }

  const termsRes = await fetch('/api/teacher/terms');
  if (termsRes.ok) {
    try {
      const termsJson = await termsRes.json();
      const terms: { id: string; name: string }[] = termsJson.data ?? [];
      const termMatch = terms.find(t => t.id === termId);
      if (termMatch) termName = termMatch.name;
    } catch { /* fallback */ }
  }

  const breadcrumbs: BreadcrumbItem[] = [
    { label: 'My Classes', href: '/' },
    { label: classLevelName, href: `/my-classes/${classId}` },
    { label: subjectName, href: `/my-classes/${classId}/${subjectId}` },
    { label: termName, href: `/my-classes/${classId}/${subjectId}/${termId}` },
    { label: 'Lesson' }
  ];

  return { streamed: { lesson: lessonPromise }, breadcrumbs };
};
