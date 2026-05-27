import { proxyToGateway } from '$lib/server/golem';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async (event) => {
	const userId = event.locals.user?.id;
	if (!userId) {
		return new Response(
			JSON.stringify({ error: { code: 'UNAUTHENTICATED', message: 'Not authenticated.' } }),
			{ status: 401, headers: { 'content-type': 'application/json' } }
		);
	}

	// Admins use the singleton Admin Agent — no init check needed.
	const roles = event.locals.user?.roles ?? [];
	const path = roles.includes('admin') ? '/gateway/admin/ping' : '/gateway/ping';

	const result = await proxyToGateway(path, userId);

	if (result.error) {
		return new Response(JSON.stringify(result), { status: 502, headers: { 'content-type': 'application/json' } });
	}

	return new Response(JSON.stringify(result), { status: 200, headers: { 'content-type': 'application/json' } });
};
