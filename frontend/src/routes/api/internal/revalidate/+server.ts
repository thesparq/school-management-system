import { invalidateByTag } from '$lib/server/cache';
import type { RequestHandler } from './$types';

export const POST: RequestHandler = async (event) => {
	// In a real production scenario, you should validate an internal secret key here
	// to prevent external users from arbitrarily invalidating the cache.
	// Example:
	// const secret = event.request.headers.get('x-revalidate-secret');
	// if (secret !== process.env.REVALIDATE_SECRET) return new Response('Unauthorized', { status: 401 });

	const tag = event.url.searchParams.get('tag');

	if (!tag) {
		return new Response(
			JSON.stringify({ error: 'Missing tag parameter' }),
			{ status: 400, headers: { 'content-type': 'application/json' } }
		);
	}

	invalidateByTag(tag);

	return new Response(
		JSON.stringify({ success: true, message: `Invalidated cache for tag: ${tag}` }),
		{ status: 200, headers: { 'content-type': 'application/json' } }
	);
};
