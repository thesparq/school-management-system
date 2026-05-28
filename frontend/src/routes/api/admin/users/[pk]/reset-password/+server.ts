import { resetPassword } from '$lib/server/authentik';
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
	const targetPk = Number(event.params.pk);
	if (isNaN(targetPk) || targetPk < 1) {
		return new Response(
			JSON.stringify({ error: { code: 'VALIDATION_ERROR', message: 'Missing user pk' } }),
			{ status: 400, headers: { 'content-type': 'application/json' } }
		);
	}
	const body = await event.request.json().catch(() => ({}));
	const password: string = body.password;
	if (!password) {
		return new Response(
			JSON.stringify({ error: { code: 'VALIDATION_ERROR', message: 'Password is required' } }),
			{ status: 400, headers: { 'content-type': 'application/json' } }
		);
	}
	try {
		await resetPassword(targetPk, password);
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
