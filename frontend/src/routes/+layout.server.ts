import { redirect } from '@sveltejs/kit';
import { dev } from '$app/environment';
import type { LayoutServerLoad } from './$types';
import { generateAuthUrl } from '$lib/server/authentik';

const SECURE = !dev;

export const load: LayoutServerLoad = async (event) => {
	if (!event.locals.user) {
		const { url, state, codeVerifier } = await generateAuthUrl();

		event.cookies.set('oauth_state', state, {
			httpOnly: true,
			sameSite: 'lax',
			path: '/api/auth/callback',
			maxAge: 300,
			secure: SECURE
		});

		event.cookies.set('oauth_code_verifier', codeVerifier, {
			httpOnly: true,
			sameSite: 'lax',
			path: '/api/auth/callback',
			maxAge: 300,
			secure: SECURE
		});

		redirect(302, url);
	}

	return { user: event.locals.user };
};
