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

	const result = await proxyToGateway('/gateway/student/terms', userId);

	if (result.error) {
		const status = result.error.code === 'NOT_ACTIVATED' ? 403 : 502;
		return new Response(JSON.stringify(result), { status, headers: { 'content-type': 'application/json' } });
	}

	let terms: unknown;
	try {
		terms = JSON.parse(result.data);
	} catch {
		return new Response(
			JSON.stringify({ error: { code: 'INVALID_RESPONSE', message: 'Failed to parse gateway response' } }),
			{ status: 502, headers: { 'content-type': 'application/json' } }
		);
	}

	return new Response(
		JSON.stringify({ data: terms }),
		{ status: 200, headers: { 'content-type': 'application/json' } }
	);
};
