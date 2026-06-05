import { adminProxy, mapErrorCodeToHttpStatus } from '$lib/server/golem';
import type { RequestHandler } from './$types';

export const POST: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user) {
		return new Response(
			JSON.stringify({ error: { code: 'UNAUTHENTICATED', message: 'Not authenticated' } }),
			{ status: 401, headers: { 'content-type': 'application/json' } }
		);
	}
	if (!user.roles.includes('admin')) {
		return new Response(
			JSON.stringify({ error: { code: 'FORBIDDEN', message: 'Forbidden' } }),
			{ status: 403, headers: { 'content-type': 'application/json' } }
		);
	}

	const targetUuid = event.params.pk;
	if (!targetUuid) {
		return new Response(
			JSON.stringify({ error: { code: 'VALIDATION_ERROR', message: 'Missing target user id' } }),
			{ status: 400, headers: { 'content-type': 'application/json' } }
		);
	}

	const body = await event.request.json().catch(() => ({}));
	const { authentikPk, username, name, email, password, role, class_level } = body;

	if (!authentikPk || !username || !name || !email || !role) {
		return new Response(
			JSON.stringify({ error: { code: 'VALIDATION_ERROR', message: 'Missing required fields' } }),
			{ status: 400, headers: { 'content-type': 'application/json' } }
		);
	}

	// Group PK resolution now happens in the backend agent.
	// Send role name; the agent resolves the Authentik group PK.
	const proxy = adminProxy(user);
	const agentBody = JSON.stringify({
		target_user_id: targetUuid,
		authentik_pk: authentikPk,
		username,
		name,
		email,
		password: password || undefined,
		role,
		class_level: class_level || undefined
	});

	const result = await proxy('/edit-user', undefined, 'POST', { body_json: agentBody });

	if (result.error) {
		return new Response(JSON.stringify(result), {
			status: mapErrorCodeToHttpStatus(result.error.code),
			headers: { 'content-type': 'application/json' }
		});
  } else {
    console.log(result.data)
	}

	return new Response(
		JSON.stringify({ data: { uuid: targetUuid } }),
		{ status: 200, headers: { 'content-type': 'application/json' } }
	);
};
