import { adminProxy, mapErrorCodeToHttpStatus } from '$lib/server/golem';
import type { RequestHandler } from './$types';

export const DELETE: RequestHandler = async (event) => {
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

	const targetPk = Number(event.params.pk);
	if (isNaN(targetPk) || targetPk < 1) {
		return new Response(
			JSON.stringify({ error: { code: 'VALIDATION_ERROR', message: 'Missing user pk' } }),
			{ status: 400, headers: { 'content-type': 'application/json' } }
		);
	}

	const targetUuid = event.url.searchParams.get('uuid');
	if (!targetUuid) {
		return new Response(
			JSON.stringify({ error: { code: 'VALIDATION_ERROR', message: 'Missing uuid query param' } }),
			{ status: 400, headers: { 'content-type': 'application/json' } }
		);
	}

	const proxy = adminProxy(user);
	const agentBody = JSON.stringify({
		authentik_pk: targetPk,
		target_user_id: targetUuid
	});
	const result = await proxy('/delete-user', undefined, 'POST', { body_json: agentBody });

	if (result.error) {
		return new Response(JSON.stringify(result), {
			status: mapErrorCodeToHttpStatus(result.error.code),
			headers: { 'content-type': 'application/json' }
		});
	}

	return new Response(
		JSON.stringify({ data: { deleted: true } }),
		{ status: 200, headers: { 'content-type': 'application/json' } }
	);
};
