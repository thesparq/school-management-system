import { redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import type { Lesson, TeacherClassGroup, BreadcrumbItem } from '$lib/types';

export const load: PageServerLoad = ({ params, locals, fetch }) => {
  const userId = locals.user?.id;
  if (!userId) redirect(302, '/');

  const classId = params.classId;
  const subjectId = params.subjectId;
  const termId = params.termId;

  const dataPromise = Promise.all([
    fetch(`/api/teacher/lessons?class_level_id=${classId}&subject_id=${subjectId}&term_id=${termId}`),
    fetch('/api/teacher/classes')
  ]).then(async ([lessonsRes, classesRes]) => {
    if (!lessonsRes.ok) {
      const err = await lessonsRes.json().catch(() => ({ error: { message: 'Failed to fetch lessons' } }));
      throw new Error(err.error?.message ?? 'Unknown error fetching lessons');
    }
    const lessonsJson = await lessonsRes.json();
    const lessons: Lesson[] = lessonsJson.data ?? [];
    
    const first = lessons[0];
    const termName = first?.term_name ?? 'Term';

    let classLevelName = 'Class';
    let subjectName = 'Subject';
    if (classesRes.ok) {
      const classesJson = await classesRes.json();
      const groups: TeacherClassGroup[] = classesJson.data ?? [];
      const match = groups.find((g: TeacherClassGroup) => g.class_level_id === classId);
      if (match) {
        classLevelName = match.class_level_name;
        const subjMatch = match.subjects.find(s => s.subject_id === subjectId);
        if (subjMatch) subjectName = subjMatch.subject_name;
      }
    }

    return { lessons, termName, classLevelName, subjectName };
  });

  return {
    classId,
    subjectId,
    termId,
    streamed: { dataPromise }
  };
};
