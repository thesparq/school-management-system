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

	const classSubjectId = event.url.searchParams.get('class_subject_id');
	if (!classSubjectId) {
		return new Response(
			JSON.stringify({ error: { code: 'BAD_REQUEST', message: 'Missing class_subject_id query parameter.' } }),
			{ status: 400, headers: { 'content-type': 'application/json' } }
		);
	}

	const result = await proxyToGateway('/gateway/student/lessons', userId, { class_subject_id: classSubjectId });

	if (result.error) {
		const status = result.error.code === 'NOT_ACTIVATED' ? 403 : 502;
		return new Response(JSON.stringify(result), { status, headers: { 'content-type': 'application/json' } });
	}

	let lessons: unknown;
	try {
		lessons = JSON.parse(result.data);
	} catch {
		return new Response(
			JSON.stringify({ error: { code: 'INVALID_RESPONSE', message: 'Failed to parse gateway response' } }),
			{ status: 502, headers: { 'content-type': 'application/json' } }
		);
	}

	return new Response(
		JSON.stringify({ data: lessons }),
		{ status: 200, headers: { 'content-type': 'application/json' } }
	);
};
