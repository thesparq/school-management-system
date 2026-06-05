import { adminProxy, mapErrorCodeToHttpStatus } from '$lib/server/golem';
import type { RequestHandler } from './$types';

const ROLE_PATH: Record<string, string> = {
	student: '/create-student',
	teacher: '/create-teacher',
	admin: '/create-admin',
	parent: '/create-parent'
};

export const POST: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user || !user.roles.includes('admin')) {
		return new Response(JSON.stringify({ error: { code: 'AUTH_FAILURE', message: 'Not authorized' } }), {
			status: 401, headers: { 'content-type': 'application/json' }
		});
	}

	const body = await event.request.json().catch(() => null);
	if (!body) {
		return new Response(JSON.stringify({ error: { code: 'VALIDATION_ERROR', message: 'Invalid JSON body' } }), {
			status: 400, headers: { 'content-type': 'application/json' }
		});
	}

	const role = body.role;
	if (!role || !ROLE_PATH[role]) {
		return new Response(JSON.stringify({ error: { code: 'VALIDATION_ERROR', message: 'Valid role is required' } }), {
			status: 400, headers: { 'content-type': 'application/json' }
		});
	}

	const proxy = adminProxy(user);
	const result = await proxy(ROLE_PATH[role], undefined, 'POST', { body_json: JSON.stringify(body) });

	if (result.error) {
		return new Response(JSON.stringify(result), {
			status: mapErrorCodeToHttpStatus(result.error.code),
			headers: { 'content-type': 'application/json' }
		});
	}

	try {
		const parsed = JSON.parse(result.data);
		const shaped = {
			pk: parsed.pk, uuid: parsed.uuid, username: parsed.username,
			name: parsed.name, email: parsed.email,
			groups: parsed.groups || [], is_active: parsed.is_active ?? true
		};
		return new Response(JSON.stringify({ data: shaped }), {
			status: 201, headers: { 'content-type': 'application/json' }
		});
	} catch {
		return new Response(JSON.stringify({ error: { code: 'PARSE_ERROR', message: 'Invalid response' } }), {
			status: 502, headers: { 'content-type': 'application/json' }
		});
	}
};
