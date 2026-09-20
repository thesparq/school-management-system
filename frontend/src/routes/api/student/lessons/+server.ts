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

	const subjectId = event.url.searchParams.get('subject_id');
	const termId = event.url.searchParams.get('term_id');
	if (!subjectId || !termId) {
		return new Response(
			JSON.stringify({ error: { code: 'BAD_REQUEST', message: 'Missing subject_id or term_id query parameter.' } }),
			{ status: 400, headers: { 'content-type': 'application/json' } }
		);
	}

	try {
		const lessons = await getCached(
			`lessons-${subjectId}-${termId}`,
			async () => {
				const result = await proxyToCoreApi(userId, '/student/lessons', { subject_id: subjectId, term_id: termId });
				if (result.error) {
					throw new Error(JSON.stringify(result));
				}
				return JSON.parse(result.data);
			},
			[`lesson-list`]
		);

		return new Response(
			JSON.stringify({ data: lessons }),
			{ status: 200, headers: { 'content-type': 'application/json' } }
		);
	} catch (e: any) {
		let result;
		try {
			result = JSON.parse(e.message);
			return new Response(JSON.stringify(result), { status: mapErrorCodeToHttpStatus(result.error.code), headers: { 'content-type': 'application/json' } });
		} catch {
			return new Response(
				JSON.stringify({ error: { code: 'INVALID_RESPONSE', message: 'Failed to parse agent response' } }),
				{ status: 502, headers: { 'content-type': 'application/json' } }
			);
		}
	}
};
