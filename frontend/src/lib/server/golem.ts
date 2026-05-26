import { env } from '$env/dynamic/private';

let gatewayUrl: string | null = null;
let authKey: string | null = null;

function getGatewayUrl(): string {
	if (gatewayUrl) return gatewayUrl;
	if (!env.GOLEM_GATEWAY_URL) {
		throw new Error('Missing GOLEM_GATEWAY_URL environment variable');
	}
	gatewayUrl = env.GOLEM_GATEWAY_URL.replace(/\/+$/, '');
	return gatewayUrl;
}

function getAuthKey(): string {
	if (authKey) return authKey;
	if (!env.GOLEM_AUTH_KEY) {
		throw new Error('Missing GOLEM_AUTH_KEY environment variable');
	}
	authKey = env.GOLEM_AUTH_KEY;
	return authKey;
}

interface ProxySuccess {
	data: string;
	error?: never;
}

interface ProxyError {
	data?: never;
	error: { code: string; message: string };
}

type ProxyResult = ProxySuccess | ProxyError;

export async function proxyToGateway(
	path: string,
	userId: string
): Promise<ProxyResult> {
	const url = `${getGatewayUrl()}${path}?user_id=${encodeURIComponent(userId)}`;

	try {
		const res = await fetch(url, {
			headers: {
				'X-Golem-Auth-Key': getAuthKey()
			}
		});

		const text = await res.text();

		if (text === 'unauthorized') {
			return {
				error: {
					code: 'UNAUTHORIZED',
					message: 'Request to backend was rejected (auth key mismatch).'
				}
			};
		}

		if (text === 'auth error') {
			return {
				error: {
					code: 'AUTH_ERROR',
					message: 'Backend encountered an error reading its auth configuration.'
				}
			};
		}

		return { data: text };
	} catch (err) {
		return {
			error: {
				code: 'PROXY_ERROR',
				message: err instanceof Error ? err.message : 'Failed to reach backend service.'
			}
		};
	}
}
