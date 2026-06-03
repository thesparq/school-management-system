import type { RequestHandler } from './$types';

export const GET: RequestHandler = async (event) => {
	const user = event.locals.user;
	if (!user) {
		return new Response(
			JSON.stringify({ error: { code: 'UNAUTHENTICATED', message: 'Not authenticated.' } }),
			{ status: 401, headers: { 'content-type': 'application/json' } }
		);
	}

	return new Response(
		JSON.stringify({ data: { authenticated: true } }),
		{ status: 200, headers: { 'content-type': 'application/json' } }
	);
};
