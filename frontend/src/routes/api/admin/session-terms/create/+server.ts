import { adminProxy, mapErrorCodeToHttpStatus } from '$lib/server/golem';
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

export const POST: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user) error(401, 'Not authenticated');
	if (!user.roles.includes('admin')) error(403, 'Forbidden');

	const body = await event.request.json().catch(() => null);
	if (!body || !body.session || !body.term_id) {
		return new Response(
			JSON.stringify({ error: { code: 'VALIDATION_ERROR', message: 'Session and term are required' } }),
			{ status: 400, headers: { 'content-type': 'application/json' } }
		);
	}

	const proxy = adminProxy(user);
	const result = await proxy('/create-session-term', undefined, 'POST', {
		body_json: JSON.stringify({
			session: body.session,
			term_id: body.term_id,
			active: body.active ?? false
		})
	});

	if (result.error) {
		return new Response(JSON.stringify(result), {
			status: mapErrorCodeToHttpStatus(result.error.code),
			headers: { 'content-type': 'application/json' }
		});
	}

	let data: unknown;
	try {
		data = JSON.parse(result.data);
	} catch {
		return new Response(
			JSON.stringify({ error: { code: 'INVALID_RESPONSE', message: 'Failed to parse agent response' } }),
			{ status: 502, headers: { 'content-type': 'application/json' } }
		);
	}

	return new Response(
		JSON.stringify({ data }),
		{ status: 201, headers: { 'content-type': 'application/json' } }
	);
};
