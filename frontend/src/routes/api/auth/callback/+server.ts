import { redirect } from '@sveltejs/kit';
import { dev } from '$app/environment';
import type { RequestHandler } from './$types';
import { handleCallback } from '$lib/server/authentik';

const SECURE = !dev;

export const GET: RequestHandler = async (event) => {
	const code = event.url.searchParams.get('code');
	const state = event.url.searchParams.get('state');
	const expectedState = event.cookies.get('oauth_state');
	const codeVerifier = event.cookies.get('oauth_code_verifier');

	if (!code || !state || !expectedState || !codeVerifier) {
		redirect(302, '/?error=invalid_callback');
	}

	const result = await handleCallback(code, state, codeVerifier, expectedState);

	if (!result) {
		redirect(302, '/?error=auth_failed');
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

	event.cookies.delete('oauth_state', { path: '/api/auth/callback' });
	event.cookies.delete('oauth_code_verifier', { path: '/api/auth/callback' });

	const oauthRedirect = event.cookies.get('oauth_redirect') || '/';
	event.cookies.delete('oauth_redirect', { path: '/' });

	const isRelativePath = oauthRedirect.startsWith('/') && !oauthRedirect.startsWith('//');
	const safeRedirect = isRelativePath ? oauthRedirect : '/';

	redirect(302, safeRedirect);
};
