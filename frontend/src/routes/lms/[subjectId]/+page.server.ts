import { redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import type { Term, BreadcrumbItem } from '$lib/types';

export const load: PageServerLoad = async ({ params, locals, fetch }) => {
  const userId = locals.user?.id;
  if (!userId) {
    redirect(302, '/');
  }

  const subjectId = params.subjectId;

  const termsRes = await fetch('/api/student/terms');
  if (!termsRes.ok) {
    const err = await termsRes.json().catch(() => ({ error: { message: 'Failed to fetch terms' } }));
    return { terms: [], subjectName: null, termsError: err.error?.message ?? 'Unknown error', breadcrumbs: [{ label: 'Subjects', href: '/' }, { label: 'Subject' }] };
  }

  let terms: Term[];
  try {
    const termsJson = await termsRes.json();
    terms = termsJson.data ?? [];
  } catch {
    return { terms: [], subjectName: null, termsError: 'Invalid response from server.', breadcrumbs: [{ label: 'Subjects', href: '/' }, { label: 'Subject' }] };
  }

  let subjectName = 'Subject';
  const subjectsRes = await fetch('/api/student/subjects');
  if (subjectsRes.ok) {
    try {
      const subjectsJson = await subjectsRes.json();
      const subjects = subjectsJson.data ?? [];
      const match = Array.isArray(subjects) ? subjects.find((s: any) => s.id === subjectId) : null;
      if (match) subjectName = match.name;
    } catch { /* fallback */ }
  }

  return {
    terms,
    subjectName,
    termsError: null,
    breadcrumbs: [
      { label: 'Subjects', href: '/' } as BreadcrumbItem,
      { label: subjectName } as BreadcrumbItem
    ]
  };
};
