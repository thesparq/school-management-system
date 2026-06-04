import { redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import type { LessonContent, BreadcrumbItem } from '$lib/types';

export const load: PageServerLoad = async ({ params, locals, fetch }) => {
  const userId = locals.user?.id;
  if (!userId) {
    redirect(302, '/');
  }

  const { subjectId, termId, lessonId } = params;

  // Resolve names for breadcrumbs
  let subjectName = 'Subject';
  let termName = 'Term';

  const subjectsRes = await fetch('/api/student/subjects');
  if (subjectsRes.ok) {
    try {
      const json = await subjectsRes.json();
      const subjects: { id: string; name: string }[] = json.data ?? [];
      const match = subjects.find((s) => s.id === subjectId);
      if (match) subjectName = match.name;
    } catch { /* fallback */ }
  }

  const termsRes = await fetch('/api/student/terms');
  if (termsRes.ok) {
    try {
      const json = await termsRes.json();
      const terms: { id: string; name: string }[] = json.data ?? [];
      const match = terms.find((t) => t.id === termId);
      if (match) termName = match.name;
    } catch { /* fallback */ }
  }

  const breadcrumbs: BreadcrumbItem[] = [
    { label: 'Subjects', href: '/' },
    { label: subjectName, href: `/lms/${subjectId}` },
    { label: termName, href: `/lms/${subjectId}/${termId}` },
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
