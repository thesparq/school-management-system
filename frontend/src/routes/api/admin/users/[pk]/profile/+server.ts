import { adminProxy, mapErrorCodeToHttpStatus } from '$lib/server/golem';
import type { RequestHandler } from './$types';

const PROFILE_PATH: Record<string, string> = {
	student: '/get-student-profile',
	teacher: '/get-teacher-profile',
	admin: '/get-admin-profile',
	parent: '/get-parent-profile'
};

export const GET: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user || !user.roles.includes('admin')) {
		return new Response(JSON.stringify({ error: { code: 'AUTH_FAILURE', message: 'Not authorized' } }), {
			status: 401, headers: { 'content-type': 'application/json' }
		});
	}

	const target_uuid = event.params.pk;
	const role = event.url.searchParams.get('role') || 'student';

	if (!target_uuid || !PROFILE_PATH[role]) {
		return new Response(JSON.stringify({ error: { code: 'VALIDATION_ERROR', message: 'Valid uuid and role required' } }), {
			status: 400, headers: { 'content-type': 'application/json' }
		});
	}

	const proxy = adminProxy(user);
	const result = await proxy(PROFILE_PATH[role], { target_user_id: target_uuid });

	if (result.error) {
		return new Response(JSON.stringify(result), {
			status: mapErrorCodeToHttpStatus(result.error.code),
			headers: { 'content-type': 'application/json' }
		});
	}

	try {
		const parsed = JSON.parse(result.data);
		return new Response(JSON.stringify({ data: parsed }), {
			status: 200, headers: { 'content-type': 'application/json' }
		});
	} catch {
		return new Response(JSON.stringify({ data: null }), {
			status: 200, headers: { 'content-type': 'application/json' }
		});
	}
};
