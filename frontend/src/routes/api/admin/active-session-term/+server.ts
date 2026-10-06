import { proxyToCoreApi, mapErrorCodeToHttpStatus } from '$lib/server/golem';
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

let activeSessionCache: { data: any, expires: number } | null = null;

export const GET: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user) error(401, 'Not authenticated');

	if (activeSessionCache && Date.now() < activeSessionCache.expires) {
		return new Response(JSON.stringify({ data: activeSessionCache.data }), {
			status: 200, headers: { 'content-type': 'application/json' }
		});
	}

	// Use proxyToCoreApi to bypass AdminAgent worker lock concurrency issues
	const result = await proxyToCoreApi(user.id, '/student/active-session-term');

	if (result.error) {
		return new Response(JSON.stringify(result), {
			status: mapErrorCodeToHttpStatus(result.error.code),
			headers: { 'content-type': 'application/json' }
		});
	}

	let data: unknown;
	try {
		data = JSON.parse(result.data);
		// Cache for 60 seconds
		activeSessionCache = { data, expires: Date.now() + 60000 };
	} catch {
		return new Response(
			JSON.stringify({ error: { code: 'INVALID_RESPONSE', message: 'Failed to parse gateway response' } }),
			{ status: 502, headers: { 'content-type': 'application/json' } }
		);
	}

	return new Response(
		JSON.stringify({ data }),
		{ status: 200, headers: { 'content-type': 'application/json' } }
	);
};
