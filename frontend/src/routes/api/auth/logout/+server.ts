import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getEndSessionUrl } from '$lib/server/authentik';

export const POST: RequestHandler = async (event) => {
	if (!event.request.headers.get('X-Requested-With')) {
		return json({ error: { code: 'INVALID_REQUEST' } }, { status: 403 });
	}

	const idToken = event.cookies.get('session_jwt') ?? '';
	const url = await getEndSessionUrl(idToken);

	event.cookies.delete('session_jwt', { path: '/' });
	event.cookies.delete('refresh_token', { path: '/' });

	return json({ url });
};
