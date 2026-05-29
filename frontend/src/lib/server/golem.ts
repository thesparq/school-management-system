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

function errorResult(code: string, message: string): ProxyResult {
	return { error: { code, message } };
}

function isErrMsg(text: string): ProxyResult | null {
	if (text === 'unauthorized') {
		return errorResult('UNAUTHORIZED', 'Request to backend was rejected (auth key mismatch).');
	}
	if (text === 'auth error') {
		return errorResult('AUTH_ERROR', 'Backend encountered an error reading its auth configuration.');
	}
	if (text === 'NOT_INITIALIZED') {
		return errorResult('NOT_INITIALIZED', 'Account not initialized. Please contact your school administrator.');
	}
	return null;
}

export async function proxyToGateway(
	path: string,
	userId: string,
	extraParams?: Record<string, string>
): Promise<ProxyResult> {
	let url = `${getGatewayUrl()}${path}?user_id=${encodeURIComponent(userId)}`;

	if (extraParams) {
		for (const [key, value] of Object.entries(extraParams)) {
			url += `&${encodeURIComponent(key)}=${encodeURIComponent(value)}`;
		}
	}

	try {
		const res = await fetch(url, {
			headers: {
				'X-Golem-Auth-Key': getAuthKey()
			}
		});

		const raw = await res.text();

		// Detect typed Ok/Err envelope from Result[T, String] Gateway returns
		try {
			const parsed = JSON.parse(raw);
			if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
				if ('Ok' in parsed) {
					return { data: JSON.stringify(parsed.Ok) };
				}
				if ('Err' in parsed && typeof parsed.Err === 'string') {
					const check = isErrMsg(parsed.Err as string);
					if (check) return check;
					return errorResult('GATEWAY_ERROR', parsed.Err as string);
				}
			}
		} catch {
			// Not valid JSON — fall through to legacy string handling
		}

		// Legacy string responses
		let text: string;
		try {
			const jsonParsed = JSON.parse(raw);
			text = typeof jsonParsed === 'string' ? jsonParsed : raw;
		} catch {
			text = raw;
		}

		const check = isErrMsg(text);
		if (check) return check;

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
