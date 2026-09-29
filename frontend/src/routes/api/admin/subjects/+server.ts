import { adminProxy, mapErrorCodeToHttpStatus } from '$lib/server/golem';
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

export const GET: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user) error(401, 'Not authenticated');
	if (!user.roles.includes('admin')) error(403, 'Forbidden');

	const proxy = adminProxy(user, event.request.signal);
	const result = await proxy('/subjects');

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
		{ status: 200, headers: { 'content-type': 'application/json' } }
	);
};

export const POST: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user) error(401, 'Not authenticated');
	if (!user.roles.includes('admin')) error(403, 'Forbidden');

	const body = await event.request.json().catch(() => ({}));
	const proxy = adminProxy(user, event.request.signal);
	const result = await proxy('/subjects', undefined, 'POST', body);

	if (result.error) {
		return new Response(JSON.stringify(result), {
			status: mapErrorCodeToHttpStatus(result.error.code),
			headers: { 'content-type': 'application/json' }
		});
	}

	return new Response(JSON.stringify({ data: 'ok' }), { status: 200, headers: { 'content-type': 'application/json' } });
};
