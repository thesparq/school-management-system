import { activateUser } from '$lib/server/authentik';
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

export const POST: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user) error(401, 'Not authenticated');
	if (!user.roles.includes('admin')) error(403, 'Forbidden');
	const targetUuid = event.params.uuid;
	if (!targetUuid) error(400, 'Missing uuid');
	try {
		await activateUser(targetUuid);
		return new Response(
			JSON.stringify({ data: { activated: true } }),
			{ status: 200, headers: { 'content-type': 'application/json' } }
		);
	} catch (err) {
		return new Response(
			JSON.stringify({ error: { code: 'AUTHENTIK_ERROR', message: err instanceof Error ? err.message : 'Failed to activate user' } }),
			{ status: 502, headers: { 'content-type': 'application/json' } }
		);
	}
};
