import { proxyToGateway } from '$lib/server/golem';
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

export const POST: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user) error(401, 'Not authenticated');
	if (!user.roles.includes('admin')) error(403, 'Forbidden');

	const targetUserId = event.params.uuid;
	if (!targetUserId) error(400, 'Missing uuid in request path');

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

	const result = await proxyToGateway('/gateway/admin/activate', user.id, extraParams);

	if (result.error) {
		return new Response(JSON.stringify(result), {
			status: 502,
			headers: { 'content-type': 'application/json' }
		});
	}

	return new Response(
		JSON.stringify({ data: { activated: true } }),
		{ status: 200, headers: { 'content-type': 'application/json' } }
	);
};
