import { redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import type { Term, TeacherClassGroup, BreadcrumbItem } from '$lib/types';

export const load: PageServerLoad = async ({ params, locals, fetch }) => {
  const userId = locals.user?.id;
  if (!userId) redirect(302, '/');

  const classId = params.classId;

  const termsRes = await fetch('/api/teacher/terms');
  if (!termsRes.ok) {
    const err = await termsRes.json().catch(() => ({ error: { message: 'Failed to fetch terms' } }));
    return { terms: [], subjectName: null, termsError: err.error?.message ?? 'Unknown error', breadcrumbs: [{ label: 'My Classes', href: '/' }, { label: 'Class' }, { label: 'Subject' }] };
  }

  let terms: Term[];
  try {
    const termsJson = await termsRes.json();
    terms = termsJson.data ?? [];
  } catch {
    return { terms: [], subjectName: null, termsError: 'Invalid response from server.', breadcrumbs: [{ label: 'My Classes', href: '/' }, { label: 'Class' }, { label: 'Subject' }] };
  }

  // Look up class and subject names from teacher's class data
  let subjectName = 'Subject';
  let classLevelName = 'Class';
  const classesRes = await fetch('/api/teacher/classes');
  if (classesRes.ok) {
    try {
      const classesJson = await classesRes.json();
      const groups: TeacherClassGroup[] = classesJson.data ?? [];
      const match = groups.find((g: TeacherClassGroup) => g.class_level_id === classId);
      if (match) {
        classLevelName = match.class_level_name;
        const subjMatch = match.subjects.find(s => s.subject_id === params.subjectId);
        if (subjMatch) subjectName = subjMatch.subject_name;
      }
    } catch { /* fallback */ }
  }

  return {
    terms,
    subjectName,
    termsError: null,
    breadcrumbs: [
      { label: 'My Classes', href: '/' } as BreadcrumbItem,
      { label: classLevelName, href: `/my-classes/${classId}` } as BreadcrumbItem,
      { label: subjectName } as BreadcrumbItem
    ]
  };
};
