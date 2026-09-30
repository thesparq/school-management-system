import { redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import type { Term, BreadcrumbItem } from '$lib/types';
import { proxyToStudent } from '$lib/server/golem';

export const load: PageServerLoad = ({ params, locals }) => {
	const userId = locals.user?.id;
	if (!userId) redirect(302, '/');

	const subjectId = params.subjectId;

	const dataPromise = Promise.all([
    proxyToStudent(userId, '/terms'),
    proxyToStudent(userId, '/subjects')
  ]).then(([termsResult, subjectsResult]) => {
    let subjectName = 'Subject';
    if (!subjectsResult.error) {
      try {
        const subjects = JSON.parse(subjectsResult.data);
        const match = Array.isArray(subjects) ? subjects.find((s: any) => s.id === subjectId) : null;
        if (match) subjectName = match.name;
      } catch { /* fallback */ }
    }

    const breadcrumbs = [
			{ label: 'Subjects', href: '/' } as BreadcrumbItem,
			{ label: subjectName } as BreadcrumbItem
		];

    if (termsResult.error) {
      return { terms: [], subjectName, termsError: termsResult.error.message ?? 'Unknown error', breadcrumbs };
    }

    try {
      const terms: Term[] = JSON.parse(termsResult.data);
      return { terms, subjectName, termsError: null, breadcrumbs };
    } catch {
      return { terms: [], subjectName, termsError: 'Invalid response from server.', breadcrumbs };
    }
  });

	return {
		streamed: { dataPromise }
	};
};
