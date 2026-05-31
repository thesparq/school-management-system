import { redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import type { Lesson, TeacherClassGroup, BreadcrumbItem } from '$lib/types';

export const load: PageServerLoad = async ({ params, locals, fetch }) => {
  const userId = locals.user?.id;
  if (!userId) redirect(302, '/');

  const classId = params.classId;
  const subjectId = params.subjectId;
  const termId = params.termId;

  const lessonsRes = await fetch(`/api/teacher/lessons?class_level_id=${classId}&subject_id=${subjectId}&term_id=${termId}`);
  if (!lessonsRes.ok) {
    const err = await lessonsRes.json().catch(() => ({ error: { message: 'Failed to fetch lessons' } }));
    return { lessons: [], termName: null, lessonsError: err.error?.message ?? 'Unknown error', breadcrumbs: [{ label: 'My Classes', href: '/' }, { label: 'Class' }, { label: 'Subject' }, { label: 'Term' }] };
  }

  let lessons: Lesson[];
  try {
    const lessonsJson = await lessonsRes.json();
    lessons = lessonsJson.data ?? [];
  } catch {
    return { lessons: [], termName: null, lessonsError: 'Invalid response from server.', breadcrumbs: [{ label: 'My Classes', href: '/' }, { label: 'Class' }, { label: 'Subject' }, { label: 'Term' }] };
  }

  const first = lessons[0];
  const termName = first?.term_name ?? 'Term';

  // Look up names for breadcrumbs
  let classLevelName = 'Class';
  let subjectName = 'Subject';
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

  return {
    lessons,
    termName,
    lessonsError: null,
    breadcrumbs: [
      { label: 'My Classes', href: '/' } as BreadcrumbItem,
      { label: classLevelName, href: `/my-classes/${classId}` } as BreadcrumbItem,
      { label: subjectName, href: `/my-classes/${classId}/${subjectId}` } as BreadcrumbItem,
      { label: termName } as BreadcrumbItem
    ]
  };
};
