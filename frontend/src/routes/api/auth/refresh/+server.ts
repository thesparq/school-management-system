import { json } from '@sveltejs/kit';
import { dev } from '$app/environment';
import type { RequestHandler } from './$types';
import { refreshTokens } from '$lib/server/authentik';

const SECURE = !dev;

export const POST: RequestHandler = async (event) => {
	const refreshToken = event.cookies.get('refresh_token');
	if (!refreshToken) {
		return json({ error: { code: 'NO_REFRESH_TOKEN' } }, { status: 401 });
	}

	const result = await refreshTokens(refreshToken);
	if (!result) {
		event.cookies.delete('session_jwt', { path: '/' });
		event.cookies.delete('refresh_token', { path: '/' });
		return json({ error: { code: 'REFRESH_FAILED' } }, { status: 401 });
	}

	const maxAge = result.payload.exp
		? Math.max(result.payload.exp - Math.floor(Date.now() / 1000), 0)
		: 3600;

	if (maxAge > 0) {
		event.cookies.set('session_jwt', result.idToken, {
			httpOnly: true,
			sameSite: 'lax',
			path: '/',
			maxAge,
			secure: SECURE
		});
	}

	event.cookies.set('refresh_token', result.refreshToken, {
		httpOnly: true,
		sameSite: 'strict',
		path: '/',
		maxAge: 2_592_000,
		secure: SECURE
	});

	return json({ success: true });
};
