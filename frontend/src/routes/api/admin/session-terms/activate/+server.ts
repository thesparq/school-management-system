import { adminProxy, mapErrorCodeToHttpStatus } from '$lib/server/golem';
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

export const POST: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user) error(401, 'Not authenticated');
	if (!user.roles.includes('admin')) error(403, 'Forbidden');

	const sessionTermId = event.url.searchParams.get('session_term_id');
	if (!sessionTermId) {
		return new Response(
			JSON.stringify({ error: { code: 'VALIDATION_ERROR', message: 'Missing session_term_id' } }),
			{ status: 400, headers: { 'content-type': 'application/json' } }
		);
	}

	const proxy = adminProxy(user);
	const result = await proxy('/activate-session-term', { session_term_id: sessionTermId }, 'POST');

	if (result.error) {
		return new Response(JSON.stringify(result), {
			status: mapErrorCodeToHttpStatus(result.error.code),
			headers: { 'content-type': 'application/json' }
		});
	}

	return new Response(
		JSON.stringify({ data: { activated: true } }),
		{ status: 200, headers: { 'content-type': 'application/json' } }
	);
};
