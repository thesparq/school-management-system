import { redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import type { Lesson, BreadcrumbItem } from '$lib/types';
import { proxyToStudent } from '$lib/server/golem';

async function resolveTermName(termId: string, userId: string): Promise<string> {
	try {
		const r = await proxyToStudent(userId, '/terms');
		if (r.error) return 'Term';
		const terms: { id: string; name: string }[] = JSON.parse(r.data);
		return terms.find((t) => t.id === termId)?.name ?? 'Term';
	} catch {
		return 'Term';
	}
}

async function resolveSubjectName(subjectId: string, userId: string): Promise<string> {
	try {
		const r = await proxyToStudent(userId, '/subjects');
		if (r.error) return 'Subject';
		const subjects: { id: string; name: string }[] = JSON.parse(r.data);
		return subjects.find((s) => s.id === subjectId)?.name ?? 'Subject';
	} catch {
		return 'Subject';
	}
}

export const load: PageServerLoad = ({ params, locals }) => {
	const userId = locals.user?.id;
	if (!userId) redirect(302, '/');

	const subjectId = params.subjectId;
	const termId = params.termId;

	const dataPromise = Promise.all([
		resolveSubjectName(subjectId, userId),
		resolveTermName(termId, userId),
    proxyToStudent(userId, '/lessons', { subject_id: subjectId, term_id: termId })
	]).then(([subjectName, termName, lessonsResult]) => {
    const breadcrumbs = [
			{ label: 'Subjects', href: '/' } as BreadcrumbItem,
			{ label: subjectName, href: `/lms/${subjectId}` } as BreadcrumbItem,
			{ label: termName } as BreadcrumbItem
		];

    if (lessonsResult.error) {
      return {
        lessons: [], termName, subjectName, breadcrumbs,
        lessonsError: lessonsResult.error.message ?? 'Unknown error',
      };
    }
    
    try {
      const lessons: Lesson[] = JSON.parse(lessonsResult.data);
      return { lessons, termName, subjectName, breadcrumbs, lessonsError: null };
    } catch {
      return { lessons: [], termName, subjectName, breadcrumbs, lessonsError: 'Invalid response.' };
    }
  });

	return {
		streamed: { dataPromise }
	};
};
