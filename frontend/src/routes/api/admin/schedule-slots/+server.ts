import { adminProxy } from '$lib/server/golem';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user || !user.roles.includes('admin')) {
		return new Response(JSON.stringify({ error: { code: 'FORBIDDEN' } }), { status: 403 });
	}

	const timetableId = event.url.searchParams.get('timetable_id');
	if (!timetableId) {
		return new Response(JSON.stringify({ error: { code: 'BAD_REQUEST', message: 'Missing timetable_id' } }), { status: 400 });
	}

	const proxy = adminProxy(user);
	const result = await proxy(`/schedule-slots?timetableId=${encodeURIComponent(timetableId)}`);

	if (result.error) {
		return new Response(JSON.stringify(result), { status: 502 });
	}

	let slots: unknown;
	try {
		slots = JSON.parse(result.data);
		if (typeof slots === 'string') slots = JSON.parse(slots);
	} catch {
		return new Response(JSON.stringify({ error: { code: 'INVALID_RESPONSE' } }), { status: 502 });
	}

	return new Response(JSON.stringify({ data: slots }), { status: 200, headers: { 'content-type': 'application/json' } });
};
