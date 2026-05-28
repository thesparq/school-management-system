import { proxyToGateway } from '$lib/server/golem';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user) {
		return new Response(
			JSON.stringify({ error: { code: 'UNAUTHORIZED', message: 'Not authenticated' } }),
			{ status: 401, headers: { 'content-type': 'application/json' } }
		);
	}
	if (!user.roles.includes('admin')) {
		return new Response(
			JSON.stringify({ error: { code: 'FORBIDDEN', message: 'Forbidden' } }),
			{ status: 403, headers: { 'content-type': 'application/json' } }
		);
	}

	const result = await proxyToGateway('/gateway/admin/initializations', user.id);

	if (result.error) {
		return new Response(JSON.stringify(result), {
			status: 502,
			headers: { 'content-type': 'application/json' }
		});
	}

	let pairs: [string, string][];
	try {
		pairs = JSON.parse(result.data);
	} catch {
		return new Response(
			JSON.stringify({ error: { code: 'PARSE_ERROR', message: 'Invalid response from gateway' } }),
			{ status: 502, headers: { 'content-type': 'application/json' } }
		);
	}
	const obj: Record<string, string> = {};
	for (const [uid, role] of pairs) {
		obj[uid] = role;
	}

	return new Response(
		JSON.stringify({ data: obj }),
		{ status: 200, headers: { 'content-type': 'application/json' } }
	);
};
