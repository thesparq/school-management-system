import { adminProxy, mapErrorCodeToHttpStatus } from '$lib/server/golem';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user || !user.roles.includes('admin')) {
		return new Response(JSON.stringify({ error: { code: 'AUTH_FAILURE', message: 'Not authorized' } }), {
			status: 401, headers: { 'content-type': 'application/json' }
		});
	}

	const proxy = adminProxy(user);
	const result = await proxy('/students/list');

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
