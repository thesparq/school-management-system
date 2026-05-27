import { removeUserFromGroup } from '$lib/server/authentik';
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

export const POST: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user) error(401, 'Not authenticated');
	if (!user.roles.includes('admin')) error(403, 'Forbidden');
	const userPkStr = event.params.uuid;
	if (!userPkStr) error(400, 'Missing user pk');
	const userPk = parseInt(userPkStr, 10);
	if (isNaN(userPk)) error(400, 'Invalid user pk');
	const body = await event.request.json().catch(() => ({}));
	const groupUuid: string = body.group_pk;
	if (typeof groupUuid !== 'string') {
		return new Response(
			JSON.stringify({ error: { code: 'VALIDATION_ERROR', message: 'group_pk is required' } }),
			{ status: 400, headers: { 'content-type': 'application/json' } }
		);
	}
	try {
		await removeUserFromGroup(userPk, groupUuid);
		return new Response(
			JSON.stringify({ data: { success: true } }),
			{ status: 200, headers: { 'content-type': 'application/json' } }
		);
	} catch (err) {
		return new Response(
			JSON.stringify({ error: { code: 'AUTHENTIK_ERROR', message: err instanceof Error ? err.message : 'Failed to remove group' } }),
			{ status: 502, headers: { 'content-type': 'application/json' } }
		);
	}
};
