import { adminProxy, mapErrorCodeToHttpStatus } from '$lib/server/golem';
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

export const GET: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user || !user.roles.includes('admin')) {
		return new Response(JSON.stringify({ error: { code: 'AUTH_FAILURE', message: 'Not authorized' } }), {
			status: 401, headers: { 'content-type': 'application/json' }
		});
	}

	const proxy = adminProxy(user);
	const result = await proxy('/credentials');

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

export const POST: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user) error(401, 'Not authenticated');
	if (!user.roles.includes('admin')) error(403, 'Forbidden');

	const body = await event.request.json().catch(() => null);
	if (!body || !body.name) {
		return new Response(
			JSON.stringify({ error: { code: 'VALIDATION_ERROR', message: 'Name is required' } }),
			{ status: 400, headers: { 'content-type': 'application/json' } }
		);
	}

	const proxy = adminProxy(user);
	const result = await proxy('/create-credential', { name: body.name }, 'POST');

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
