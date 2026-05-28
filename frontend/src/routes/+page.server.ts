import { proxyToGateway } from '$lib/server/golem';
import type { PageServerLoad } from './$types';
import type { Subject } from '$lib/types';

export const load: PageServerLoad = async (event) => {
	const user = event.locals.user;
	if (!user) return { initialized: true, subjects: null, subjectsError: null };

	if (user.roles.includes('admin')) {
		return { initialized: true, subjects: null, subjectsError: null };
	}

	const initResult = await proxyToGateway('/gateway/check-initialization', user.id);
	if (initResult.error?.code === 'NOT_INITIALIZED') {
		return { initialized: false, subjects: null, subjectsError: null };
	}

	if (!user.roles.includes('students')) {
		return { initialized: true, subjects: null, subjectsError: null };
	}

	let subjects: Subject[] | null = null;
	let subjectsError: string | null = null;

	try {
		const subjResult = await proxyToGateway('/gateway/student/subjects', user.id);
		if (subjResult.error) {
			subjectsError = subjResult.error.message;
		} else {
			const parsed = JSON.parse(subjResult.data);
			subjects = Array.isArray(parsed) ? parsed : [];
		}
	} catch {
		subjectsError = 'Failed to reach backend service.';
	}

	return { initialized: true, subjects, subjectsError };
};
