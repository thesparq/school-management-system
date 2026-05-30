import { redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import type { LessonContent, BreadcrumbItem } from '$lib/types';

export const load: PageServerLoad = async ({ params, locals, fetch }) => {
  const userId = locals.user?.id;
  if (!userId) {
    redirect(302, '/');
  }

  const lessonId = params.lessonId;
  const breadcrumbs: BreadcrumbItem[] = [
    { label: 'LMS' },
    { label: 'Subjects', href: '/' },
    { label: 'Subject', href: `/lms/${params.subjectId}` },
    { label: 'Term', href: `/lms/${params.subjectId}/${params.termId}` },
    { label: 'Lesson' }
  ];

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

  return { streamed: { lesson: lessonPromise }, breadcrumbs };
};
