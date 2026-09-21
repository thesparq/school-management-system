import { adminProxy } from '$lib/server/golem';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user || !user.roles.includes('admin')) {
		return new Response(JSON.stringify({ error: { code: 'FORBIDDEN' } }), { status: 403 });
	}

	const proxy = adminProxy(user);
	const result = await proxy('/timetables');

	if (result.error) {
		return new Response(JSON.stringify(result), { status: 502 });
	}

	let timetables: unknown;
	try {
		timetables = JSON.parse(result.data);
		// some strings in MoonBit responses come back double-stringified, or as array
		if (typeof timetables === 'string') timetables = JSON.parse(timetables);
	} catch {
		return new Response(JSON.stringify({ error: { code: 'INVALID_RESPONSE' } }), { status: 502 });
	}

	return new Response(JSON.stringify({ data: timetables }), { status: 200, headers: { 'content-type': 'application/json' } });
};
