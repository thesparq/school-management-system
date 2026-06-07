import { proxyToParent, mapErrorCodeToHttpStatus } from '$lib/server/golem';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user || !user.roles.includes('parent')) {
		return new Response(JSON.stringify({ error: { code: 'AUTH_FAILURE', message: 'Not authorized' } }), {
			status: 401, headers: { 'content-type': 'application/json' }
		});
	}

	const result = await proxyToParent(user.id, '/my-students');

	if (result.error) {
		const status = mapErrorCodeToHttpStatus(result.error.code);
		return new Response(JSON.stringify(result), { status, headers: { 'content-type': 'application/json' } });
	}

	try {
		const parsed = JSON.parse(result.data);
		if (!Array.isArray(parsed)) {
			console.warn('Parent my-students API returned non-array data:', typeof parsed);
		}
		return new Response(JSON.stringify({ data: Array.isArray(parsed) ? parsed : [] }), {
			status: 200, headers: { 'content-type': 'application/json' }
		});
	} catch {
		console.error('Failed to parse parent my-students response:', result.data);
		return new Response(JSON.stringify({ error: { code: 'INTERNAL_ERROR', message: 'Invalid response format' } }), {
			status: 500, headers: { 'content-type': 'application/json' }
		});
	}
};
