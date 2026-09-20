type CacheEntry = {
	value: any;
	expiresAt: number;
	tags: string[];
};

const cache = new Map<string, CacheEntry>();
const pendingRequests = new Map<string, Promise<any>>();

/**
 * Gets a value from the cache, or fetches it using the provided fetcher function.
 * Implements request coalescing to prevent cache stampedes.
 *
 * @param key The unique cache key.
 * @param fetcher The function to fetch the data if it's not in the cache.
 * @param tags Tags to associate with this cache entry for bulk invalidation.
 * @param ttlMs Time-to-live in milliseconds (default: 1 hour).
 */
export async function getCached<T>(
	key: string,
	fetcher: () => Promise<T>,
	tags: string[] = [],
	ttlMs: number = 3600000 // 1 hour default
): Promise<T> {
	const now = Date.now();
	const entry = cache.get(key);

	if (entry && entry.expiresAt > now) {
		return entry.value as T;
	}

	if (entry && entry.expiresAt <= now) {
		cache.delete(key);
	}

	// Request Coalescing: if a request for this key is already in flight, wait for it.
	if (pendingRequests.has(key)) {
		return pendingRequests.get(key) as Promise<T>;
	}

	const promise = fetcher().then((value) => {
		cache.set(key, {
			value,
			expiresAt: Date.now() + ttlMs,
			tags
		});
		pendingRequests.delete(key);
		return value;
	}).catch((err) => {
		pendingRequests.delete(key);
		throw err;
	});

	pendingRequests.set(key, promise);
	return promise;
}

/**
 * Invalidates all cache entries that match the given tag.
 * @param tag The tag to invalidate.
 */
export function invalidateByTag(tag: string): void {
	for (const [key, entry] of cache.entries()) {
		if (entry.tags.includes(tag)) {
			cache.delete(key);
		}
	}
}

/**
 * Invalidates a specific cache key.
 * @param key The key to invalidate.
 */
export function invalidateByKey(key: string): void {
	cache.delete(key);
}
