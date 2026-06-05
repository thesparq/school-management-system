import { proxyToParent, mapErrorCodeToHttpStatus } from '$lib/server/golem';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user || !user.roles.includes('parent')) {
		return new Response(JSON.stringify({ error: { code: 'AUTH_FAILURE', message: 'Not authorized' } }), {
			status: 401, headers: { 'content-type': 'application/json' }
		});
	}

	const studentId = event.url.searchParams.get('student_id') || '';
	const result = await proxyToParent(user.id, '/student-subjects', { student_id: studentId });

	if (result.error) {
		return new Response(JSON.stringify(result), {
			status: mapErrorCodeToHttpStatus(result.error.code),
			headers: { 'content-type': 'application/json' }
		});
	}

	try {
		const parsed = JSON.parse(result.data);
		return new Response(JSON.stringify({ data: Array.isArray(parsed) ? parsed : [] }), {
			status: 200, headers: { 'content-type': 'application/json' }
		});
	} catch {
		return new Response(JSON.stringify({ data: [] }), {
			status: 200, headers: { 'content-type': 'application/json' }
		});
	}
};
