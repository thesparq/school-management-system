import { adminProxy, mapErrorCodeToHttpStatus } from '$lib/server/golem';
import type { RequestHandler } from './$types';

export const POST: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user) {
		return new Response(
			JSON.stringify({ error: { code: 'UNAUTHENTICATED', message: 'Not authenticated.' } }),
			{ status: 401, headers: { 'content-type': 'application/json' } }
		);
	}
	if (!user.roles.includes('admin')) {
		return new Response(
			JSON.stringify({ error: { code: 'FORBIDDEN', message: 'Forbidden' } }),
			{ status: 403, headers: { 'content-type': 'application/json' } }
		);
	}

	const body = await event.request.json().catch(() => ({}));
	const { term_id, active } = body;
	if (!term_id || typeof active !== 'boolean') {
		return new Response(
			JSON.stringify({ error: { code: 'BAD_REQUEST', message: 'Missing term_id or active.' } }),
			{ status: 400, headers: { 'content-type': 'application/json' } }
		);
	}

	const proxy = adminProxy(user);
	const result = await proxy('/toggle-term-active', { term_id, active: String(active) }, 'POST');

	if (result.error) {
		return new Response(JSON.stringify(result), {
			status: mapErrorCodeToHttpStatus(result.error.code),
			headers: { 'content-type': 'application/json' }
		});
	}

	return new Response(
		JSON.stringify({ data: { success: true } }),
		{ status: 200, headers: { 'content-type': 'application/json' } }
	);
};
