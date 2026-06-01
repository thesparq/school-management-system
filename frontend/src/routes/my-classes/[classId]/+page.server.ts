import { redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import type { TeacherClassGroup, BreadcrumbItem } from '$lib/types';

export const load: PageServerLoad = async ({ params, locals, fetch }) => {
  const userId = locals.user?.id;
  if (!userId) redirect(302, '/');

  const classId = params.classId;

  const classesRes = await fetch('/api/teacher/classes');
  if (!classesRes.ok) {
    const err = await classesRes.json().catch(() => ({ error: { message: 'Failed to fetch classes' } }));
    return { subjects: [], classLevelName: null, subjectsError: err.error?.message ?? 'Unknown error', breadcrumbs: [{ label: 'My Classes', href: '/' }, { label: 'Class' }] };
  }

  let classGroup: TeacherClassGroup | null = null;
  let classLevelName = 'Class';
  try {
    const json = await classesRes.json();
    const groups: TeacherClassGroup[] = json.data ?? [];
    const match = groups.find((g: TeacherClassGroup) => g.class_level_id === classId);
    if (match) {
      classGroup = match;
      classLevelName = match.class_level_name;
    }
  } catch {
    // fallthrough
  }

  if (!classGroup) {
    return { subjects: [], classLevelName, subjectsError: 'Class not found.', breadcrumbs: [{ label: 'My Classes', href: '/' }, { label: classLevelName }] };
  }

  return {
    subjects: classGroup.subjects,
    classLevelName,
    subjectsError: null,
    breadcrumbs: [
      { label: 'My Classes', href: '/' } as BreadcrumbItem,
      { label: classLevelName } as BreadcrumbItem
    ]
  };
};
