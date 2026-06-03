import { json, type Handle } from '@sveltejs/kit';
import { dev } from '$app/environment';
import { verifyJwt, refreshTokens, generateAuthUrl } from '$lib/server/authentik';
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

function setAuthCookies(
	event: import('@sveltejs/kit').RequestEvent,
	result: TokenResponse
) {
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
}

function clearAuthCookies(event: import('@sveltejs/kit').RequestEvent) {
	event.cookies.delete('session_jwt', { path: '/' });
	event.cookies.delete('refresh_token', { path: '/' });
}

async function attemptRefresh(
	event: import('@sveltejs/kit').RequestEvent
): Promise<boolean> {
	const refreshToken = event.cookies.get('refresh_token');
	if (!refreshToken) return false;

	if (!inflightRefresh) {
		inflightRefresh = refreshTokens(refreshToken).then((result) => {
			setTimeout(() => { inflightRefresh = null; }, 3000);
			return result;
		});
	}

	const result = await inflightRefresh;
	if (!result) return false;

	setUser(event, result.payload);
	setAuthCookies(event, result);
	return true;
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
				const refreshed = await attemptRefresh(event);
				if (!refreshed) clearAuthCookies(event);
			} else {
				// Non-expiry error (network blip, JWKS fetch failure, issuer mismatch, etc.)
				// Attempt refresh — Authentik's token endpoint may still accept the refresh token
				const refreshed = await attemptRefresh(event);
				if (!refreshed) clearAuthCookies(event);
			}
		}
	}

	// JWT missing but refresh token present: silently get a new JWT
	if (!event.locals.user) {
		const refreshed = await attemptRefresh(event);
		if (refreshed) {
			// User is now authenticated via the new JWT
		} else {
			clearAuthCookies(event);
		}
	}

	// Protected API routes: redirect to Authentik if still unauthenticated
	if (!event.locals.user) {
		const path = event.url.pathname;
		const isProtectedApi =
			path.startsWith('/api/') &&
			!path.startsWith('/api/auth/') &&
			path !== '/api/ping';

		if (isProtectedApi) {
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
			event.cookies.set('oauth_redirect', event.url.pathname, {
				httpOnly: false,
				sameSite: 'lax',
				path: '/',
				maxAge: 300,
				secure: SECURE
			});
			return json(
				{ error: { code: 'UNAUTHENTICATED', redirectUrl: url } },
				{ status: 401 }
			);
		}
	}

	return resolve(event);
};
