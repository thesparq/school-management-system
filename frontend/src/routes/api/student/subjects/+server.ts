import { proxyToCoreApi, mapErrorCodeToHttpStatus } from '$lib/server/golem';
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
		const subjects = await getCached(
			'global-subjects',
			async () => {
				const result = await proxyToCoreApi(userId, '/student/subjects');
				if (result.error) {
					throw new Error(JSON.stringify(result));
				}
				return JSON.parse(result.data);
			},
			['subject-list']
		);

		return new Response(
			JSON.stringify({ data: subjects }),
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
