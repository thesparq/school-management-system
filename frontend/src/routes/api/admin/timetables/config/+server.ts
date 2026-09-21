import { adminProxy } from '$lib/server/golem';
import type { RequestHandler } from './$types';

export const PUT: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user || !user.roles.includes('admin')) {
		return new Response(JSON.stringify({ error: { code: 'FORBIDDEN' } }), { status: 403 });
	}

	const proxy = adminProxy(user);
	const body = await event.request.json();
	const result = await proxy('/timetables/config', {
		method: 'PUT',
		body: JSON.stringify(body)
	});

	if (result.error) {
		return new Response(JSON.stringify(result), { status: 502 });
	}

	return new Response(JSON.stringify({ data: result.data }), { status: 200, headers: { 'content-type': 'application/json' } });
};
