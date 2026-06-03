import { proxyToStudent, mapErrorCodeToHttpStatus } from '$lib/server/golem';
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

	const result = await proxyToStudent(userId, '/lesson', { lesson_id: lessonId });

	if (result.error) {
		return new Response(JSON.stringify(result), { status: mapErrorCodeToHttpStatus(result.error.code), headers: { 'content-type': 'application/json' } });
	}

	let lesson: unknown;
	try {
		lesson = JSON.parse(result.data);
	} catch {
		return new Response(
			JSON.stringify({ error: { code: 'INVALID_RESPONSE', message: 'Failed to parse agent response' } }),
			{ status: 502, headers: { 'content-type': 'application/json' } }
		);
	}

	return new Response(
		JSON.stringify({ data: lesson }),
		{ status: 200, headers: { 'content-type': 'application/json' } }
	);
};
