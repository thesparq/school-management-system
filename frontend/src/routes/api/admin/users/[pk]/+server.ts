import { deleteUser } from '$lib/server/authentik';
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

	try {
		await deleteUser(targetPk);
		return new Response(
			JSON.stringify({ data: { deleted: true } }),
			{ status: 200, headers: { 'content-type': 'application/json' } }
		);
	} catch (err) {
		const message = err instanceof Error ? err.message : 'Failed to delete user';
		return new Response(
			JSON.stringify({ error: { code: 'AUTHENTIK_ERROR', message } }),
			{ status: 502, headers: { 'content-type': 'application/json' } }
		);
	}
};
