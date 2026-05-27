import { resetPassword } from '$lib/server/authentik';
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

export const POST: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user) error(401, 'Not authenticated');
	if (!user.roles.includes('admin')) error(403, 'Forbidden');
	const targetUuid = event.params.uuid;
	if (!targetUuid) error(400, 'Missing uuid');
	const body = await event.request.json().catch(() => ({}));
	const password: string = body.password;
	if (!password) {
		return new Response(
			JSON.stringify({ error: { code: 'VALIDATION_ERROR', message: 'Password is required' } }),
			{ status: 400, headers: { 'content-type': 'application/json' } }
		);
	}
	try {
		await resetPassword(targetUuid, password);
		return new Response(
			JSON.stringify({ data: { success: true } }),
			{ status: 200, headers: { 'content-type': 'application/json' } }
		);
	} catch (err) {
		return new Response(
			JSON.stringify({ error: { code: 'AUTHENTIK_ERROR', message: err instanceof Error ? err.message : 'Failed to reset password' } }),
			{ status: 502, headers: { 'content-type': 'application/json' } }
		);
	}
};
