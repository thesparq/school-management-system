import { adminProxy, mapErrorCodeToHttpStatus } from '$lib/server/golem';
import type { RequestHandler } from './$types';

const DELETE_PATH: Record<string, string> = {
	student: '/delete-student',
	teacher: '/delete-teacher',
	admin: '/delete-admin',
	parent: '/delete-parent'
};

export const DELETE: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user || !user.roles.includes('admin')) {
		return new Response(JSON.stringify({ error: { code: 'AUTH_FAILURE', message: 'Not authorized' } }), {
			status: 401, headers: { 'content-type': 'application/json' }
		});
	}

	const authentik_pk = event.params.pk;
	const uuid = event.url.searchParams.get('uuid');
	const role = event.url.searchParams.get('role');

	if (!authentik_pk || !uuid || !role || !DELETE_PATH[role]) {
		return new Response(JSON.stringify({ error: { code: 'VALIDATION_ERROR', message: 'pk, uuid, and valid role are required' } }), {
			status: 400, headers: { 'content-type': 'application/json' }
		});
	}

	const proxy = adminProxy(user);
	const result = await proxy(DELETE_PATH[role], undefined, 'POST', {
		body_json: JSON.stringify({ authentik_pk: Number(authentik_pk), target_user_id: uuid })
	});

	if (result.error) {
		return new Response(JSON.stringify(result), {
			status: mapErrorCodeToHttpStatus(result.error.code),
			headers: { 'content-type': 'application/json' }
		});
	}

	return new Response(JSON.stringify({ data: { uuid } }), {
		status: 200, headers: { 'content-type': 'application/json' }
	});
};
