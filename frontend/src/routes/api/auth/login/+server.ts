import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { generateAuthUrl } from '$lib/server/authentik';

const SECURE = process.env.NODE_ENV === 'production';

export const GET: RequestHandler = async (event) => {
	try {
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

		return json({ url });
	} catch (err) {
		return json(
			{ error: { code: 'AUTH_INIT_FAILED', message: 'Failed to initiate authentication' } },
			{ status: 500 }
		);
	}
};
