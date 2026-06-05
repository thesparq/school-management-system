import { adminProxy, mapErrorCodeToHttpStatus } from '$lib/server/golem';
import type { RequestHandler } from './$types';

const EDIT_PATH: Record<string, string> = {
	student: '/edit-student',
	teacher: '/edit-teacher',
	admin: '/edit-admin',
	parent: '/edit-parent'
};

export const POST: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user || !user.roles.includes('admin')) {
		return new Response(JSON.stringify({ error: { code: 'AUTH_FAILURE', message: 'Not authorized' } }), {
			status: 401, headers: { 'content-type': 'application/json' }
		});
	}

	const target_uuid = event.params.pk;
	if (!target_uuid) {
		return new Response(JSON.stringify({ error: { code: 'VALIDATION_ERROR', message: 'Missing target user id' } }), {
			status: 400, headers: { 'content-type': 'application/json' }
		});
	}

	const body = await event.request.json().catch(() => ({}));
	const { role, authentik_pk, username, email, password, display_name, surname, first_name,
		middle_name, class_level, passport_url, date_of_birth } = body;

	if (!authentik_pk || !username || !email || !role) {
		return new Response(JSON.stringify({ error: { code: 'VALIDATION_ERROR', message: 'Missing required fields' } }), {
			status: 400, headers: { 'content-type': 'application/json' }
		});
	}

	if (!EDIT_PATH[role]) {
		return new Response(JSON.stringify({ error: { code: 'VALIDATION_ERROR', message: 'Invalid role' } }), {
			status: 400, headers: { 'content-type': 'application/json' }
		});
	}

	const agentBody: Record<string, string | undefined> = {
		target_user_id: target_uuid,
		authentik_pk: String(authentik_pk),
		username,
		email,
		display_name: display_name || name || '',
		password: password || undefined,
		surname: surname || '',
		first_name: first_name || '',
		middle_name: middle_name || '',
		class_level: class_level || '',
		passport_url: passport_url || '',
		date_of_birth: date_of_birth || ''
	};

	const proxy = adminProxy(user);
	const result = await proxy(EDIT_PATH[role], undefined, 'POST', { body_json: JSON.stringify(agentBody) });

	if (result.error) {
		return new Response(JSON.stringify(result), {
			status: mapErrorCodeToHttpStatus(result.error.code),
			headers: { 'content-type': 'application/json' }
		});
	}

	return new Response(JSON.stringify({ data: { uuid: target_uuid } }), {
		status: 200, headers: { 'content-type': 'application/json' }
	});
};
