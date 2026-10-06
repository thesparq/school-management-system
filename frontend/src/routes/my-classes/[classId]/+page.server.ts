import { redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import type { TeacherClassGroup, BreadcrumbItem } from '$lib/types';

export const load: PageServerLoad = ({ params, locals, fetch }) => {
  const userId = locals.user?.id;
  if (!userId) redirect(302, '/');

  const classId = params.classId;

  const classDataPromise = fetch('/api/teacher/classes').then(async (res) => {
    if (!res.ok) {
      const err = await res.json().catch(() => ({ error: { message: 'Failed to fetch classes' } }));
      throw new Error(err.error?.message ?? 'Unknown error');
    }
    const json = await res.json();
    const groups: TeacherClassGroup[] = json.data ?? [];
    const match = groups.find((g: TeacherClassGroup) => g.class_level_id === classId);
    if (!match) throw new Error('Class not found.');
    return match;
  });

  return {
    classId,
    streamed: { classDataPromise }
  };
};
