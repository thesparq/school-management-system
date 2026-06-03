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

function parseStructuredError(text: string): BackendError | null {
	try {
		const parsed = JSON.parse(text);
		if (parsed && typeof parsed === 'object' && !Array.isArray(parsed) && parsed.error) {
			return {
				code: parsed.error.code || 'UNKNOWN_ERROR',
				message: parsed.error.message || 'An unknown error occurred.',
				detail: parsed.error.detail ?? null
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

		// Golem envelope: { "Ok": "..." } or { "Err": "..." }
		try {
			const parsed = JSON.parse(raw);

			if (typeof parsed === 'string') {
				const structured = parseStructuredError(parsed);
				if (structured) return errorResult(structured.code, structured.message);
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
					const structured = parseStructuredError(errText);
					if (structured) {
						return errorResult(structured.code, structured.message);
					}
					return errorResult('GATEWAY_ERROR', errText);
				}
			}
		} catch {
			// Not valid JSON — check raw text
			const structured = parseStructuredError(raw);
			if (structured) {
				return errorResult(structured.code, structured.message);
			}
		}

		// Legacy: raw text as data (strings from non-Result endpoints like ping)
		const structured = parseStructuredError(raw);
		if (structured) {
			return errorResult(structured.code, structured.message);
		}

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
