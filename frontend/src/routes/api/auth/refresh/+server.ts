import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { refreshTokens } from '$lib/server/authentik';

const SECURE = process.env.NODE_ENV === 'production';

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

	event.cookies.set('session_jwt', result.idToken, {
		httpOnly: true,
		sameSite: 'lax',
		path: '/',
		maxAge: Math.max(result.payload.exp ? result.payload.exp - Math.floor(Date.now() / 1000) : 3600, 60),
		secure: SECURE
	});

	event.cookies.set('refresh_token', result.refreshToken, {
		httpOnly: true,
		sameSite: 'strict',
		path: '/',
		maxAge: 2_592_000,
		secure: SECURE
	});

	return json({ success: true });
};
