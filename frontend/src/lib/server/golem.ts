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

interface BackendError {
	code: string;
	message: string;
	detail?: string | null;
}

interface ProxySuccess {
	data: string;
	error?: never;
}

interface ProxyError {
	data?: never;
	error: { code: string; message: string };
}

export type ProxyResult = ProxySuccess | ProxyError;

function errorResult(code: string, message: string): ProxyResult {
	return { error: { code, message } };
}

function extractErrorFromBody(raw: string): BackendError | null {
	try {
		const parsed = JSON.parse(raw);

		// Format 1: Golem Err envelope {"Err": "<inner_json>"}
		if (parsed.Err && typeof parsed.Err === 'string') {
			try {
				const inner = JSON.parse(parsed.Err);
				if (inner.code) {
					return {
						code: inner.code,
						message: inner.message || inner.errors?.[0] || 'Unknown error',
						detail: inner.debug ?? null
					};
				}
			} catch {
				// inner wasn't valid JSON — use raw Err string
			}
			return { code: 'AGENT_ERROR', message: parsed.Err };
		}

		// Format 2: Top-level {"code":"...","errors":[...]}
		//           (Golem gateway errors + our new AppError format)
		if (parsed.code) {
			return {
				code: parsed.code,
				message: parsed.message || parsed.errors?.[0] || 'Unknown error',
				detail: parsed.debug ?? null
			};
		}

		// Format 3: Legacy nested {"error":{"code":"...","message":"..."}}
		if (parsed.error?.code) {
			return {
				code: parsed.error.code,
				message: parsed.error.message,
				detail: parsed.error.debug || parsed.error.detail || null
			};
		}
	} catch {
		// Not valid JSON
	}
	return null;
}

async function proxyFetch(url: string, method: string = 'GET', body?: Record<string, unknown>): Promise<ProxyResult> {
	try {
		const fetchInit: RequestInit = {
			method,
			headers: {
				'X-Golem-Auth-Key': getAuthKey()
			}
		};
		if (body) {
			fetchInit.headers = { ...fetchInit.headers, 'Content-Type': 'application/json' };
			fetchInit.body = JSON.stringify(body);
		}
		const res = await fetch(url, fetchInit);

		const raw = await res.text();

		// Gate 1: Any non-2xx response is always an error
		if (!res.ok) {
			const extracted = extractErrorFromBody(raw);
			if (extracted) return errorResult(extracted.code, extracted.message);
			return errorResult('GATEWAY_ERROR', raw);
		}

		// Gate 2: 2xx — parse Golem envelope
		try {
			const parsed = JSON.parse(raw);

			if (typeof parsed === 'string') {
				const extracted = extractErrorFromBody(parsed);
				if (extracted) return errorResult(extracted.code, extracted.message);
				return { data: parsed };
			}

			if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
				if ('Ok' in parsed) {
					const okValue = parsed.Ok;
					const data = typeof okValue === 'string' ? okValue : JSON.stringify(okValue);
					return { data };
				}
				if ('Err' in parsed) {
					const errValue = parsed.Err;
					const errText = typeof errValue === 'string' ? errValue : JSON.stringify(errValue);
					const extracted = extractErrorFromBody(errText);
					if (extracted) return errorResult(extracted.code, extracted.message);
					return errorResult('AGENT_ERROR', errText);
				}
			}
		} catch {
			// Not valid JSON — check as raw text below
		}

		// Gate 3: Defensive — 200 but body contains unrecognized error fields
		const extracted = extractErrorFromBody(raw);
		if (extracted) return errorResult(extracted.code, extracted.message);

		return { data: raw };
	} catch (err) {
		return {
			error: {
				code: 'PROXY_ERROR',
				message: err instanceof Error ? err.message : 'Failed to reach backend service.'
			}
		};
	}
}

function buildUrl(basePath: string, extraParams?: Record<string, string>): string {
	let url = `${getGatewayUrl()}${basePath}`;
	if (extraParams) {
		const sep = basePath.includes('?') ? '&' : '?';
		const parts: string[] = [];
		for (const [key, value] of Object.entries(extraParams)) {
			parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(value)}`);
		}
		url += sep + parts.join('&');
	}
	return url;
}

export function proxyToAdmin(adminId: string, path: string, extraParams?: Record<string, string>, method?: string, body?: Record<string, unknown>): Promise<ProxyResult> {
	return proxyFetch(buildUrl(`/admin/${encodeURIComponent(adminId)}${path}`, extraParams), method ?? 'GET', body);
}

export function adminProxy(user: { id: string }): (path: string, extraParams?: Record<string, string>, method?: string, body?: Record<string, unknown>) => Promise<ProxyResult> {
	return (path, extraParams, method, body) => proxyToAdmin(user.id, path, extraParams, method, body);
}

export function proxyToStudent(userId: string, path: string, extraParams?: Record<string, string>, method?: string, body?: Record<string, unknown>): Promise<ProxyResult> {
	return proxyFetch(buildUrl(`/student/${encodeURIComponent(userId)}${path}`, extraParams), method ?? 'GET', body);
}

export function proxyToTeacher(userId: string, path: string, extraParams?: Record<string, string>, method?: string, body?: Record<string, unknown>): Promise<ProxyResult> {
	return proxyFetch(buildUrl(`/teacher/${encodeURIComponent(userId)}${path}`, extraParams), method ?? 'GET', body);
}

export function mapErrorCodeToHttpStatus(code: string): number {
	switch (code) {
		case 'VALIDATION_ERROR': return 400;
		case 'AUTH_FAILURE': return 401;
		case 'NOT_FOUND': return 404;
		case 'ALREADY_EXISTS': return 409;
		case 'NOT_INITIALIZED': return 403;
		case 'AUTHENTIK_ERROR':
		case 'SURREALDB_ERROR':
		case 'GATEWAY_ERROR': return 502;
		case 'INTERNAL_ERROR': return 500;
		case 'PROXY_ERROR': return 503;
		default: return 502;
	}
}
