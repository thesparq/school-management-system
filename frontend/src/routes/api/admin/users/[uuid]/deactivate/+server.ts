import { proxyToGateway } from '$lib/server/golem';
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

export const POST: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user) error(401, 'Not authenticated');
	if (!user.roles.includes('admin')) error(403, 'Forbidden');

	const targetUserId = event.params.uuid;
	if (!targetUserId) error(400, 'Missing uuid in request path');

	const result = await proxyToGateway('/gateway/admin/deactivate', user.id, {
		target_user_id: targetUserId
	});

	if (result.error) {
		return new Response(JSON.stringify(result), {
			status: 502,
			headers: { 'content-type': 'application/json' }
		});
	}

	return new Response(
		JSON.stringify({ data: { deactivated: true } }),
		{ status: 200, headers: { 'content-type': 'application/json' } }
	);
};
