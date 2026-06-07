import { adminProxy, mapErrorCodeToHttpStatus } from '$lib/server/golem';
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

export const DELETE: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user) error(401, 'Not authenticated');
	if (!user.roles.includes('admin')) error(403, 'Forbidden');

	const id = event.params.id;
	if (!id) {
		return new Response(
			JSON.stringify({ error: { code: 'VALIDATION_ERROR', message: 'id is required' } }),
			{ status: 400, headers: { 'content-type': 'application/json' } }
		);
	}

	const proxy = adminProxy(user);
	const result = await proxy('/delete-credential', {}, 'POST', { id });

	if (result.error) {
		return new Response(JSON.stringify(result), {
			status: mapErrorCodeToHttpStatus(result.error.code),
			headers: { 'content-type': 'application/json' }
		});
	}

	return new Response(
		JSON.stringify({ success: true }),
		{ status: 200, headers: { 'content-type': 'application/json' } }
	);
};
