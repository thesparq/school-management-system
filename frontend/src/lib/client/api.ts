// ── Client-side fetch wrapper with automatic token refresh ──

let refreshPromise: Promise<boolean> | null = null;

export async function apiFetch(
	input: RequestInfo | URL,
	init?: RequestInit
): Promise<Response> {
	const res = await fetch(input, init);

	if (res.status === 401) {
		if (!refreshPromise) {
			refreshPromise = doRefresh().finally(() => {
				refreshPromise = null;
			});
		}
		const refreshed = await refreshPromise;

		if (refreshed) {
			return fetch(input, init);
		}

		window.location.href = '/';
		throw new Error('Session expired');
	}

	return res;
}

async function doRefresh(): Promise<boolean> {
	try {
		const cRes = await fetch('/api/auth/refresh', { method: 'POST' });
		return cRes.ok;
	} catch {
		return false;
	}
}
