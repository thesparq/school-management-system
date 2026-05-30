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

	const lessonId = event.url.searchParams.get('lesson_id');
	if (!lessonId) {
		return new Response(
			JSON.stringify({ error: { code: 'BAD_REQUEST', message: 'Missing lesson_id query parameter.' } }),
			{ status: 400, headers: { 'content-type': 'application/json' } }
		);
	}

	const result = await proxyToGateway('/gateway/student/lesson', userId, { lesson_id: lessonId });

	if (result.error) {
		const status = result.error.code === 'NOT_INITIALIZED' ? 403 : 502;
		return new Response(JSON.stringify(result), { status, headers: { 'content-type': 'application/json' } });
	}

	let lesson: unknown;
	try {
		lesson = JSON.parse(result.data);
	} catch {
		return new Response(
			JSON.stringify({ error: { code: 'INVALID_RESPONSE', message: 'Failed to parse gateway response' } }),
			{ status: 502, headers: { 'content-type': 'application/json' } }
		);
	}

	return new Response(
		JSON.stringify({ data: lesson }),
		{ status: 200, headers: { 'content-type': 'application/json' } }
	);
};
