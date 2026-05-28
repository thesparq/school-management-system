import type { Handle } from '@sveltejs/kit';
import { dev } from '$app/environment';
import { verifyJwt, refreshTokens } from '$lib/server/authentik';

const SECURE = !dev;

export const handle: Handle = async ({ event, resolve }) => {
	event.locals.user = null;

	const jwt = event.cookies.get('session_jwt');

	if (jwt) {
		try {
			const payload = await verifyJwt(jwt);
			event.locals.user = {
				id: payload.sub ?? '',
				name: payload.name ?? payload.preferred_username ?? '',
				email: payload.email ?? '',
				roles: payload.groups ?? payload.roles ?? []
			};
		} catch (err) {
			const isExpired = (err as { code?: string })?.code === 'ERR_JWT_EXPIRED';

			if (isExpired) {
				const refreshToken = event.cookies.get('refresh_token');
				if (refreshToken) {
					const result = await refreshTokens(refreshToken);
					if (result) {
						event.locals.user = {
							id: result.payload.sub ?? '',
							name: result.payload.name ?? result.payload.preferred_username ?? '',
							email: result.payload.email ?? '',
							roles: result.payload.groups ?? result.payload.roles ?? []
						};

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
					} else {
						event.cookies.delete('session_jwt', { path: '/' });
						event.cookies.delete('refresh_token', { path: '/' });
					}
				} else {
					event.cookies.delete('session_jwt', { path: '/' });
				}
			} else {
				event.cookies.delete('session_jwt', { path: '/' });
				event.cookies.delete('refresh_token', { path: '/' });
			}
		}
	}

	return resolve(event);
};
