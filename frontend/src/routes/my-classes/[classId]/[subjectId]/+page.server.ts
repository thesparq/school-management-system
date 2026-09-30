import { redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import type { Term, TeacherClassGroup, BreadcrumbItem } from '$lib/types';

export const load: PageServerLoad = ({ params, locals, fetch }) => {
  const userId = locals.user?.id;
  if (!userId) redirect(302, '/');

  const classId = params.classId;
  const subjectId = params.subjectId;

  const dataPromise = Promise.all([
    fetch('/api/teacher/terms'),
    fetch('/api/teacher/classes')
  ]).then(async ([termsRes, classesRes]) => {
    let terms: Term[] = [];
    if (!termsRes.ok) {
      const err = await termsRes.json().catch(() => ({ error: { message: 'Failed to fetch terms' } }));
      throw new Error(err.error?.message ?? 'Unknown error fetching terms');
    }
    const termsJson = await termsRes.json();
    terms = termsJson.data ?? [];

    let subjectName = 'Subject';
    let classLevelName = 'Class';
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
    
    return { terms, subjectName, classLevelName };
  });

  return {
    classId,
    subjectId,
    streamed: { dataPromise }
  };
};
