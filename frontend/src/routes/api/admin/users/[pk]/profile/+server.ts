import { adminProxy, mapErrorCodeToHttpStatus } from '$lib/server/golem.js';
import type { RequestHandler } from './$types.js';

export const GET: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user) {
		return new Response(
			JSON.stringify({ error: { code: 'UNAUTHENTICATED', message: 'Not authenticated.' } }),
			{ status: 401, headers: { 'content-type': 'application/json' } }
		);
	}
	if (!user.roles.includes('admin')) {
		return new Response(
			JSON.stringify({ error: { code: 'FORBIDDEN', message: 'Forbidden.' } }),
			{ status: 403, headers: { 'content-type': 'application/json' } }
		);
	}

	const targetUuid = event.params.pk;
	if (!targetUuid) {
		return new Response(
			JSON.stringify({ error: { code: 'VALIDATION_ERROR', message: 'Missing target user pk.' } }),
			{ status: 400, headers: { 'content-type': 'application/json' } }
		);
	}

	const proxy = adminProxy(user);
	const result = await proxy('/get-profile', { target_user_id: targetUuid });

	if (result.error) {
		return new Response(JSON.stringify(result), {
			status: mapErrorCodeToHttpStatus(result.error.code),
			headers: { 'content-type': 'application/json' } 
		});
	}

	let profile: unknown = null;
	try {
		const parsed = JSON.parse(result.data);
		if (parsed && typeof parsed === 'object' && parsed.auth_id) {
			profile = parsed;
		}
	} catch {
		// result is empty or invalid JSON
	}

	return new Response(
		JSON.stringify({ data: profile }),
		{ status: 200, headers: { 'content-type': 'application/json' } }
	);
};
