import { adminProxy, mapErrorCodeToHttpStatus } from '$lib/server/golem';
import type { RequestHandler } from './$types';

export const POST: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user) {
		return new Response(
			JSON.stringify({ error: { code: 'UNAUTHORIZED', message: 'Not authenticated' } }),
			{ status: 401, headers: { 'content-type': 'application/json' } }
		);
	}
	if (!user.roles.includes('admin')) {
		return new Response(
			JSON.stringify({ error: { code: 'FORBIDDEN', message: 'Forbidden' } }),
			{ status: 403, headers: { 'content-type': 'application/json' } }
		);
	}

	const body = await event.request.json().catch(() => null);
	if (!body) {
		return new Response(
			JSON.stringify({ error: { code: 'VALIDATION_ERROR', message: 'Invalid JSON body' } }),
			{ status: 400, headers: { 'content-type': 'application/json' } }
		);
	}
	const { username, name, email, password, is_active = true, group_pk, role, class_level } = body;

	if (!username || !name || !email || !password || !role) {
		return new Response(
			JSON.stringify({ error: { code: 'VALIDATION_ERROR', message: 'Missing required fields' } }),
			{ status: 400, headers: { 'content-type': 'application/json' } }
		);
	}

	const proxy = adminProxy(user);
	const createBody = JSON.stringify({
		username, name, email, password, is_active,
		group_pk: group_pk || '',
		role,
		class_level: class_level || undefined
	});
	const result = await proxy('/create-user', undefined, 'POST', { body_json: createBody });

	if (result.error) {
		return new Response(JSON.stringify(result), {
			status: mapErrorCodeToHttpStatus(result.error.code),
			headers: { 'content-type': 'application/json' }
		});
	}

	try {
		const parsed = JSON.parse(result.data);
		const shaped = {
			pk: parsed.pk,
			uuid: parsed.uuid,
			username: parsed.username,
			name: parsed.name,
			email: parsed.email,
			groups: parsed.groups || [],
			is_active: parsed.is_active ?? true
		};
		return new Response(
			JSON.stringify({ data: shaped }),
			{ status: 201, headers: { 'content-type': 'application/json' } }
		);
	} catch {
		return new Response(
			JSON.stringify({ error: { code: 'PARSE_ERROR', message: 'Invalid Authentik response' } }),
			{ status: 502, headers: { 'content-type': 'application/json' } }
		);
	}
};
