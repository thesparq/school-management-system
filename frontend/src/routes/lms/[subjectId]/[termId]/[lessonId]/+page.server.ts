import { redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import type { LessonContent, BreadcrumbItem } from '$lib/types';

export const load: PageServerLoad = async ({ params, locals, fetch }) => {
  const userId = locals.user?.id;
  if (!userId) {
    redirect(302, '/');
  }

  const { subjectId, termId, lessonId } = params;

  const dataPromise = Promise.all([
    fetch('/api/student/subjects'),
    fetch('/api/student/terms'),
    fetch(`/api/student/lesson?lesson_id=${encodeURIComponent(lessonId)}`)
  ]).then(async ([subjectsRes, termsRes, lessonRes]) => {
    let subjectName = 'Subject';
    let termName = 'Term';

    if (subjectsRes.ok) {
      try {
        const json = await subjectsRes.json();
        const subjects: { id: string; name: string }[] = json.data ?? [];
        const match = subjects.find((s) => s.id === subjectId);
        if (match) subjectName = match.name;
      } catch { /* fallback */ }
    }

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

    if (!lessonRes.ok) {
      const err = await lessonRes.json().catch(() => ({ error: { message: 'Failed to fetch lesson' } }));
      return { lesson: null, lessonError: err.error?.message ?? 'Unknown error', breadcrumbs };
    }
    
    const json = await lessonRes.json();
    const lesson: LessonContent | null = json.data ?? null;
    if (!lesson) {
      return { lesson: null, lessonError: 'Lesson not found.', breadcrumbs };
    }
    
    return { lesson, lessonError: null, breadcrumbs };
  }).catch(() => ({ lesson: null, lessonError: 'Failed to reach server.', breadcrumbs: [] }));

  return { streamed: { dataPromise } };
};
