import { redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import type { Lesson, BreadcrumbItem } from '$lib/types';

async function resolveTermName(termId: string, fetch: typeof globalThis.fetch): Promise<string> {
	try {
		const res = await fetch('/api/student/terms');
		if (!res.ok) return 'Term';
		const json = await res.json();
		const terms: { id: string; name: string }[] = json.data ?? [];
		const match = terms.find((t) => t.id === termId);
		return match?.name ?? 'Term';
	} catch {
		return 'Term';
	}
}

async function resolveSubjectName(subjectId: string, fetch: typeof globalThis.fetch): Promise<string> {
	try {
		const res = await fetch('/api/student/subjects');
		if (!res.ok) return 'Subject';
		const json = await res.json();
		const subjects: { id: string; name: string }[] = json.data ?? [];
		const match = subjects.find((s) => s.id === subjectId);
		return match?.name ?? 'Subject';
	} catch {
		return 'Subject';
	}
}

export const load: PageServerLoad = async ({ params, locals, fetch }) => {
	const userId = locals.user?.id;
	if (!userId) {
		redirect(302, '/');
	}

	const subjectId = params.subjectId;
	const termId = params.termId;

	const [subjectName, termName] = await Promise.all([
		resolveSubjectName(subjectId, fetch),
		resolveTermName(termId, fetch)
	]);

	const lessonsRes = await fetch(`/api/student/lessons?subject_id=${subjectId}&term_id=${termId}`);
	if (!lessonsRes.ok) {
		const err = await lessonsRes.json().catch(() => ({ error: { message: 'Failed to fetch lessons' } }));
		return {
			lessons: [],
			termName,
			lessonsError: err.error?.message ?? 'Unknown error',
			breadcrumbs: [
				{ label: 'Subjects', href: '/' } as BreadcrumbItem,
				{ label: subjectName, href: `/lms/${subjectId}` } as BreadcrumbItem,
				{ label: termName } as BreadcrumbItem
			]
		};
	}

	let lessons: Lesson[];
	try {
		const lessonsJson = await lessonsRes.json();
		lessons = lessonsJson.data ?? [];
	} catch {
		return {
			lessons: [],
			termName,
			lessonsError: 'Invalid response from server.',
			breadcrumbs: [
				{ label: 'Subjects', href: '/' } as BreadcrumbItem,
				{ label: subjectName, href: `/lms/${subjectId}` } as BreadcrumbItem,
				{ label: termName } as BreadcrumbItem
			]
		};
	}

	return {
		lessons,
		termName,
		lessonsError: null,
		breadcrumbs: [
			{ label: 'Subjects', href: '/' } as BreadcrumbItem,
			{ label: 'Subjects', href: '/' } as BreadcrumbItem,
			{ label: subjectName, href: `/lms/${subjectId}` } as BreadcrumbItem,
			{ label: termName } as BreadcrumbItem
		]
	};
};
