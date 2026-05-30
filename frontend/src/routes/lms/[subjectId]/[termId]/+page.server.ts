import { redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import type { Lesson, BreadcrumbItem } from '$lib/types';

export const load: PageServerLoad = async ({ params, locals, fetch }) => {
  const userId = locals.user?.id;
  if (!userId) {
    redirect(302, '/');
  }

  const subjectId = params.subjectId;
  const termId = params.termId;

  const lessonsRes = await fetch(`/api/student/lessons?subject_id=${subjectId}&term_id=${termId}`);
  if (!lessonsRes.ok) {
    const err = await lessonsRes.json().catch(() => ({ error: { message: 'Failed to fetch lessons' } }));
    return { lessons: [], termName: null, lessonsError: err.error?.message ?? 'Unknown error', breadcrumbs: [{ label: 'LMS' }, { label: 'Subjects', href: '/' }, { label: 'Subject' }, { label: 'Term' }] };
  }

  let lessons: Lesson[];
  try {
    const lessonsJson = await lessonsRes.json();
    lessons = lessonsJson.data ?? [];
  } catch {
    return { lessons: [], termName: null, lessonsError: 'Invalid response from server.', breadcrumbs: [{ label: 'LMS' }, { label: 'Subjects', href: '/' }, { label: 'Subject' }, { label: 'Term' }] };
  }

  const first = lessons[0];
  const subjectName = first?.subject_name ?? 'Subject';
  const termName = first?.term_name ?? 'Term';

  return {
    lessons,
    termName,
    lessonsError: null,
    breadcrumbs: [
      { label: 'LMS' } as BreadcrumbItem,
      { label: 'Subjects', href: '/' } as BreadcrumbItem,
      { label: subjectName, href: `/lms/${subjectId}` } as BreadcrumbItem,
      { label: termName } as BreadcrumbItem
    ]
  };
};
