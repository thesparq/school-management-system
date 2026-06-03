import { proxyToAdmin } from '$lib/server/golem';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async (event) => {
	const adminId = event.locals.user?.id ?? 'ping';
	const result = await proxyToAdmin(adminId, '/ping');

	if (result.error) {
		return new Response(JSON.stringify(result), { status: 502, headers: { 'content-type': 'application/json' } });
	}

	return new Response(JSON.stringify(result), { status: 200, headers: { 'content-type': 'application/json' } });
};
