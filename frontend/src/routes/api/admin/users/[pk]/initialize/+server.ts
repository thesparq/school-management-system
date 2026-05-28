import { proxyToGateway } from '$lib/server/golem';
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

	const targetUserId = event.params.pk;
	if (!targetUserId) {
		return new Response(
			JSON.stringify({ error: { code: 'VALIDATION_ERROR', message: 'Missing user id in request path' } }),
			{ status: 400, headers: { 'content-type': 'application/json' } }
		);
	}

	const body = await event.request.json().catch(() => ({}));
	const role: string = body.role || 'student';
	const classLevel: string | undefined = body.class_level;

	const extraParams: Record<string, string> = {
		target_user_id: targetUserId,
		role
	};
	if (classLevel) {
		extraParams.class_level = classLevel;
	}

	const result = await proxyToGateway('/gateway/admin/initialize', user.id, extraParams);

	if (result.error) {
		return new Response(JSON.stringify(result), {
			status: 502,
			headers: { 'content-type': 'application/json' }
		});
	}

	return new Response(
		JSON.stringify({ data: { initialized: true } }),
		{ status: 200, headers: { 'content-type': 'application/json' } }
	);
};
