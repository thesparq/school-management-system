import type { Handle } from '@sveltejs/kit';
import { dev } from '$app/environment';
import { verifyJwt, refreshTokens } from '$lib/server/authentik';
import type { TokenResponse, JwtClaims } from '$lib/server/authentik';

const SECURE = !dev;

let inflightRefresh: Promise<TokenResponse | null> | null = null;

function setUser(
	event: import('@sveltejs/kit').RequestEvent,
	payload: JwtClaims
) {
	event.locals.user = {
		id: payload.sub ?? '',
		name: payload.name ?? payload.preferred_username ?? '',
		email: payload.email ?? '',
		roles: payload.groups ?? payload.roles ?? []
	};
}

export const handle: Handle = async ({ event, resolve }) => {
	event.locals.user = null;

	const jwt = event.cookies.get('session_jwt');

	if (jwt) {
		try {
			const payload = await verifyJwt(jwt);
			setUser(event, payload);
		} catch (err) {
			const isExpired = (err as { code?: string })?.code === 'ERR_JWT_EXPIRED';

			if (isExpired) {
				const refreshToken = event.cookies.get('refresh_token');
				if (refreshToken) {
					if (!inflightRefresh) {
						inflightRefresh = refreshTokens(refreshToken).finally(() => {
							inflightRefresh = null;
						});
					}
					const result = await inflightRefresh;

					if (result) {
						setUser(event, result.payload);

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
