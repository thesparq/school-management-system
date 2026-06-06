import { redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import type { Term, BreadcrumbItem } from '$lib/types';
import { proxyToStudent } from '$lib/server/golem';

export const load: PageServerLoad = async ({ params, locals }) => {
	const userId = locals.user?.id;
	if (!userId) redirect(302, '/');

	const subjectId = params.subjectId;

	const termsResult = await proxyToStudent(userId, '/terms');
	if (termsResult.error) {
		return { terms: [], subjectName: null, termsError: termsResult.error.message ?? 'Unknown error', breadcrumbs: [{ label: 'Subjects', href: '/' }, { label: 'Subject' }] };
	}

	let terms: Term[];
	try {
		terms = JSON.parse(termsResult.data);
	} catch {
		return { terms: [], subjectName: null, termsError: 'Invalid response from server.', breadcrumbs: [{ label: 'Subjects', href: '/' }, { label: 'Subject' }] };
	}

	let subjectName = 'Subject';
	const subjectsResult = await proxyToStudent(userId, '/subjects');
	if (!subjectsResult.error) {
		try {
			const subjects = JSON.parse(subjectsResult.data);
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
