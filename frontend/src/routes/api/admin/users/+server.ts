import { createUser, resetPassword } from '$lib/server/authentik';
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

	const body = await event.request.json();
	const { username, name, email, password, is_active = true, group_pk } = body;

	if (!username || !name || !email || !password) {
		return new Response(
			JSON.stringify({ error: { code: 'VALIDATION_ERROR', message: 'Missing required fields' } }),
			{ status: 400, headers: { 'content-type': 'application/json' } }
		);
	}

	try {
		const created = await createUser({
			username,
			name,
			email,
			password,
			is_active,
			groups: group_pk ? [group_pk] : []
		});

		await resetPassword(created.pk, password);

		const result = {
			pk: created.pk,
			uuid: created.uuid,
			username: created.username,
			name: created.name,
			email: created.email,
			groups: created.groups || [],
			is_active: created.is_active
		};

		return new Response(
			JSON.stringify({ data: result }),
			{ status: 201, headers: { 'content-type': 'application/json' } }
		);
	} catch (err) {
		return new Response(
			JSON.stringify({ error: { code: 'AUTHENTIK_ERROR', message: err instanceof Error ? err.message : 'Failed to create user' } }),
			{ status: 502, headers: { 'content-type': 'application/json' } }
		);
	}
};
