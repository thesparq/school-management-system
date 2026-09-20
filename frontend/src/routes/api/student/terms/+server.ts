import { proxyToStudent, mapErrorCodeToHttpStatus } from '$lib/server/golem';
import { getCached } from '$lib/server/cache';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async (event) => {
	const userId = event.locals.user?.id;
	if (!userId) {
		return new Response(
			JSON.stringify({ error: { code: 'UNAUTHENTICATED', message: 'Not authenticated.' } }),
			{ status: 401, headers: { 'content-type': 'application/json' } }
		);
	}

	try {
		const terms = await getCached(
			'global-terms',
			async () => {
				const result = await proxyToStudent(userId, '/terms');
				if (result.error) {
					throw new Error(JSON.stringify(result));
				}
				return JSON.parse(result.data);
			},
			['term-list']
		);

		return new Response(
			JSON.stringify({ data: terms }),
			{ status: 200, headers: { 'content-type': 'application/json' } }
		);
	} catch (e: any) {
		let result;
		try {
			result = JSON.parse(e.message);
			return new Response(JSON.stringify(result), { status: mapErrorCodeToHttpStatus(result.error.code), headers: { 'content-type': 'application/json' } });
		} catch {
			return new Response(
				JSON.stringify({ error: { code: 'INVALID_RESPONSE', message: 'Failed to parse gateway response' } }),
				{ status: 502, headers: { 'content-type': 'application/json' } }
			);
		}
	}
};
