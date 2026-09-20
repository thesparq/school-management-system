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

	const lessonId = event.url.searchParams.get('lesson_id');
	if (!lessonId) {
		return new Response(
			JSON.stringify({ error: { code: 'BAD_REQUEST', message: 'Missing lesson_id query parameter.' } }),
			{ status: 400, headers: { 'content-type': 'application/json' } }
		);
	}

	try {
		const lesson = await getCached(
			`lesson-${lessonId}`,
			async () => {
				const result = await proxyToStudent(userId, '/lesson', { lesson_id: lessonId });
				if (result.error) {
					throw new Error(JSON.stringify(result));
				}
				return JSON.parse(result.data);
			},
			[`lesson-${lessonId}`]
		);

		return new Response(
			JSON.stringify({ data: lesson }),
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
