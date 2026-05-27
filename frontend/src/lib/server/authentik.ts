import { createRemoteJWKSet, jwtVerify, type JWTPayload } from 'jose';
import { env } from '$env/dynamic/private';

function getConfig() {
	if (!env.AUTHENTIK_ISSUER_URL || !env.AUTHENTIK_CLIENT_ID || !env.ORIGIN) {
		throw new Error(
			'Missing required environment variables: AUTHENTIK_ISSUER_URL, AUTHENTIK_CLIENT_ID, or ORIGIN'
		);
	}
	return {
		ISSUER_URL: env.AUTHENTIK_ISSUER_URL,
		CLIENT_ID: env.AUTHENTIK_CLIENT_ID,
		CLIENT_SECRET: env.AUTHENTIK_CLIENT_SECRET ?? '',
		ORIGIN: env.ORIGIN,
		REDIRECT_URI: `${env.ORIGIN}/api/auth/callback`
	};
}

interface OpenIdConfig {
	authorization_endpoint: string;
	token_endpoint: string;
	jwks_uri: string;
	end_session_endpoint: string;
	issuer: string;
}

interface TokenResponse {
	idToken: string;
	accessToken: string;
	refreshToken: string;
	payload: JwtClaims;
}

export interface JwtClaims extends JWTPayload {
	sub?: string;
	name?: string;
	preferred_username?: string;
	email?: string;
	groups?: string[];
	roles?: string[];
}

let openIdConfig: OpenIdConfig | null = null;
let openIdConfigFetchedAt = 0;

export async function getOpenIdConfig(): Promise<OpenIdConfig> {
	const now = Date.now();
	if (openIdConfig && now - openIdConfigFetchedAt < 3600_000) {
		return openIdConfig;
	}

	const res = await fetch(`${getConfig().ISSUER_URL}/.well-known/openid-configuration`);
	if (!res.ok) {
		throw new Error(`Failed to fetch OpenID configuration: ${res.status}`);
	}

	const data = await res.json();
	openIdConfig = {
		authorization_endpoint: data.authorization_endpoint,
		token_endpoint: data.token_endpoint,
		jwks_uri: data.jwks_uri,
		end_session_endpoint: data.end_session_endpoint,
		issuer: data.issuer
	};
	openIdConfigFetchedAt = now;
	return openIdConfig;
}

let jwks: ReturnType<typeof createRemoteJWKSet> | null = null;

export async function getJwks(): Promise<ReturnType<typeof createRemoteJWKSet>> {
	if (jwks) return jwks;
	const config = await getOpenIdConfig();
	jwks = createRemoteJWKSet(new URL(config.jwks_uri));
	return jwks;
}

export async function generateAuthUrl(): Promise<{
	url: string;
	state: string;
	codeVerifier: string;
}> {
	const config = await getOpenIdConfig();
	const state = crypto.randomUUID();
	const codeVerifier = generateCodeVerifier();
	const codeChallenge = await generateCodeChallenge(codeVerifier);

	const cfg = getConfig();
	const params = new URLSearchParams({
		response_type: 'code',
		client_id: cfg.CLIENT_ID,
		redirect_uri: cfg.REDIRECT_URI,
		scope: 'openid profile email',
		state,
		code_challenge_method: 'S256',
		code_challenge: codeChallenge
	});

	return {
		url: `${config.authorization_endpoint}?${params.toString()}`,
		state,
		codeVerifier
	};
}

export async function handleCallback(
	code: string,
	state: string,
	codeVerifier: string,
	expectedState: string
): Promise<TokenResponse | null> {
	if (state !== expectedState) {
		return null;
	}

	const cfg = getConfig();
	const config = await getOpenIdConfig();
	const body = new URLSearchParams({
		grant_type: 'authorization_code',
		code,
		redirect_uri: cfg.REDIRECT_URI,
		code_verifier: codeVerifier,
		client_id: cfg.CLIENT_ID
	});

	if (cfg.CLIENT_SECRET) {
		body.set('client_secret', cfg.CLIENT_SECRET);
	}

	const res = await fetch(config.token_endpoint, {
		method: 'POST',
		headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
		body: body.toString()
	});

	if (!res.ok) {
		return null;
	}

	const data = await res.json();
	const idToken: string = data.id_token;
	if (!idToken) {
		return null;
	}

	try {
		const payload = await verifyJwt(idToken);
		return {
			idToken,
			accessToken: data.access_token,
			refreshToken: data.refresh_token,
			payload
		};
	} catch {
		return null;
	}
}

export async function verifyJwt(jwt: string): Promise<JwtClaims> {
	const cfg = getConfig();
	const config = await getOpenIdConfig();
	const JWKS = await getJwks();
	const { payload } = await jwtVerify(jwt, JWKS, {
		issuer: config.issuer,
		audience: cfg.CLIENT_ID
	});
	return payload as JwtClaims;
}

export async function refreshTokens(
	refreshToken: string
): Promise<TokenResponse | null> {
	const cfg = getConfig();
	const config = await getOpenIdConfig();
	const body = new URLSearchParams({
		grant_type: 'refresh_token',
		refresh_token: refreshToken,
		client_id: cfg.CLIENT_ID
	});

	if (cfg.CLIENT_SECRET) {
		body.set('client_secret', cfg.CLIENT_SECRET);
	}

	const res = await fetch(config.token_endpoint, {
		method: 'POST',
		headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
		body: body.toString()
	});

	if (!res.ok) {
		return null;
	}

	const data = await res.json();
	const idToken: string = data.id_token;
	if (!idToken) {
		return null;
	}

	try {
		const payload = await verifyJwt(idToken);
		return {
			idToken,
			accessToken: data.access_token,
			refreshToken: data.refresh_token ?? refreshToken,
			payload
		};
	} catch {
		return null;
	}
}

export async function getEndSessionUrl(idToken: string): Promise<string> {
	const config = await getOpenIdConfig();
	const params = new URLSearchParams({
		id_token_hint: idToken,
		post_logout_redirect_uri: `${getConfig().ORIGIN}/login`
	});
	return `${config.end_session_endpoint}?${params.toString()}`;
}

// ─── Admin API ───────────────────────────────────────────────

export interface AuthentikUser {
	pk: number;
	uuid: string;
	username: string;
	name: string;
	email: string;
	type: 'internal' | 'service_account' | 'external';
	groups: number[];
}

interface AuthentikGroup {
	pk: number;
	name: string;
}

interface AuthentikPaginatedResponse {
	results: AuthentikUser[];
	next: string | null;
	previous: string | null;
	count: number;
}

async function getTargetGroupPks(): Promise<Set<number>> {
	const host = env.AUTHENTIK_HOST;
	const token = env.AUTHENTIK_SERVICE_ACCOUNT_TOKEN;
	if (!host || !token) return new Set();

	const targetNames = ['admin', 'students', 'teachers'];
	const targetPks = new Set<number>();

	let nextUrl: string | null = `https://${host}/api/v3/core/groups/?page_size=100`;

	while (nextUrl) {
		const res = await fetch(nextUrl, {
			headers: { authorization: `Bearer ${token}` }
		});
		if (!res.ok) break;

		const page: { results: AuthentikGroup[]; next: string | null } = await res.json();
		for (const group of page.results) {
			if (targetNames.includes(group.name.toLowerCase())) {
				targetPks.add(group.pk);
			}
		}
		nextUrl = page.next;
	}

	return targetPks;
}

export async function fetchAllUsers(): Promise<AuthentikUser[]> {
	const host = env.AUTHENTIK_HOST;
	const token = env.AUTHENTIK_SERVICE_ACCOUNT_TOKEN;
	if (!host || !token) {
		throw new Error('Missing AUTHENTIK_HOST or AUTHENTIK_SERVICE_ACCOUNT_TOKEN');
	}

	const allUsers: AuthentikUser[] = [];
	let nextUrl: string | null = `https://${host}/api/v3/core/users/?page_size=100`;

	while (nextUrl) {
		const res = await fetch(nextUrl, {
			headers: { authorization: `Bearer ${token}` }
		});

		if (!res.ok) {
			const text = await res.text();
			throw new Error(
				`Authentik API returned ${res.status} — check service account permissions. ${text}`
			);
		}

		const page: AuthentikPaginatedResponse = await res.json();
		allUsers.push(...page.results.filter((u) => u.type === 'internal'));
		nextUrl = page.next;
	}

	const targetPks = await getTargetGroupPks();
	if (targetPks.size === 0) return [];

	return allUsers.filter((u) => (u.groups ?? []).some((g) => targetPks.has(g)));
}

function generateCodeVerifier(): string {
	const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
	let result = '';
	const array = new Uint8Array(64);
	crypto.getRandomValues(array);
	for (const byte of array) {
		result += chars[byte % chars.length];
	}
	return result;
}

async function generateCodeChallenge(verifier: string): Promise<string> {
	const encoder = new TextEncoder();
	const data = encoder.encode(verifier);
	const digest = await crypto.subtle.digest('SHA-256', data);
	return base64UrlEncode(new Uint8Array(digest));
}

function base64UrlEncode(bytes: Uint8Array): string {
	let binary = '';
	for (const byte of bytes) {
		binary += String.fromCharCode(byte);
	}
	return btoa(binary)
		.replace(/\+/g, '-')
		.replace(/\//g, '_')
		.replace(/=+$/, '');
}
