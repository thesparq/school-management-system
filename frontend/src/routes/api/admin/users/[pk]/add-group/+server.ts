import { addUserToGroup } from '$lib/server/authentik';
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
	const userPkStr = event.params.pk;
	if (!userPkStr) {
		return new Response(
			JSON.stringify({ error: { code: 'VALIDATION_ERROR', message: 'Missing user pk' } }),
			{ status: 400, headers: { 'content-type': 'application/json' } }
		);
	}
	const userPk = parseInt(userPkStr, 10);
	if (isNaN(userPk)) {
		return new Response(
			JSON.stringify({ error: { code: 'VALIDATION_ERROR', message: 'Invalid user pk' } }),
			{ status: 400, headers: { 'content-type': 'application/json' } }
		);
	}
	const body = await event.request.json().catch(() => ({}));
	const groupUuid: string = body.group_pk;
	if (typeof groupUuid !== 'string') {
		return new Response(
			JSON.stringify({ error: { code: 'VALIDATION_ERROR', message: 'group_pk is required' } }),
			{ status: 400, headers: { 'content-type': 'application/json' } }
		);
	}
	try {
		await addUserToGroup(userPk, groupUuid);
		return new Response(
			JSON.stringify({ data: { success: true } }),
			{ status: 200, headers: { 'content-type': 'application/json' } }
		);
	} catch (err) {
		return new Response(
			JSON.stringify({ error: { code: 'AUTHENTIK_ERROR', message: err instanceof Error ? err.message : 'Failed to add group' } }),
			{ status: 502, headers: { 'content-type': 'application/json' } }
		);
	}
};
