# Unit 14 — Auth Refresh Fixes: Race Condition, Client-Side 401, and Cookie Cleanup

## Goal

Fix three concrete bugs in the token refresh strategy: (1) concurrent requests during OIDC token rotation cause intermittent logouts, (2) client-side `fetch` calls have no automatic retry or redirect on session expiry, (3) the `session_jwt` cookie `maxAge` can be set to 60s when the JWT itself expires in less than 60s, causing an unnecessary verify→fail→refresh round-trip on every request. Also remove the unused `accessToken` field from `TokenResponse` and standardise the `SECURE` constant across all touched files.

## Design

### Fix #1 — Concurrent refresh deduplication in `hooks.server.ts`

**Problem**: Two browser tabs navigating simultaneously both have an expired JWT. Both call Authentik's token endpoint with the same refresh token. The first succeeds and rotates it. The second fails because the old token is now stale — the second request deletes both cookies, logging the user out.

**Solution**: Module-level `inflightRefresh` promise. Before calling `refreshTokens()`, check if a refresh is already in-flight. If so, await the same promise. This guarantees exactly one round-trip to Authentik regardless of how many concurrent requests hit the hook.

```
Requests R1 and R2 arrive simultaneously at hooks.server.ts:

  R1: inflightRefresh is null → set inflightRefresh = refreshTokens(token)
  R2: inflightRefresh is set → await the same promise

  Authentik receives ONE refresh call.
  R1 resolves, sets new cookies.
  R2 resolves with the same result, also sets new cookies.
  Zero concurrent logouts.
```

No new cookies needed — entirely in-memory within the Node.js process. The `.finally(() => inflightRefresh = null)` resets the guard so the next tab navigation starts fresh.

### Fix #2 — Client-side 401 interceptor (`apiFetch`)

**Problem**: The `/api/auth/refresh` endpoint exists but is never called from client code. Any `fetch()` from a `.svelte` file that returns 401 (e.g., dashboard "Test Connection" button after session expiry) shows a "Network error" message with no recovery path — the user must manually navigate to `/login`.

**Solution**: A new `apiFetch` wrapper in `frontend/src/lib/client/api.ts`. The wrapper:
1. Calls `fetch()` normally
2. If status is `401`, calls `POST /api/auth/refresh` (with module-level dedup so multiple components share one refresh)
3. If refresh succeeds → retries the original request with the new `session_jwt` cookie
4. If refresh fails → redirects `window.location.href` to `/?error=session_expired`

**Current scope**: Only the "Test Connection" button in `+page.svelte` uses client-side `fetch`. It gets migrated. All future `.svelte` `fetch` calls must use `apiFetch` by convention.

### Fix #3 — Cookie `maxAge` alignment to JWT expiry

**Problem**: `Math.max(result.payload.exp - now, 60)` floors `maxAge` to 60s even when the JWT expires in 30s (clock skew between Authentik and the server, or a short-lived token config). The cookie outlives the token, forcing a verify→fail→refresh round-trip on every request during those 30 seconds.

**Solution**: Replace `Math.max(..., 60)` with a ternary: `exp ? Math.max(exp - now, 0) : 3600` in all three locations (hooks.server.ts, callback, refresh route). If `maxAge` is 0, skip setting the cookie entirely — the token expires exactly now, but the payload was verified as valid for this request's duration.

### Fix #4 — Remove unused `accessToken` from `TokenResponse`

**Problem**: `TokenResponse.accessToken` is returned by `handleCallback` and `refreshTokens` but never consumed. It represents the OIDC `access_token` (used for calling Authentik's userinfo or resource server APIs). Since this app never calls Authentik admin APIs from client code, the field is dead code.

**Solution**: Remove `accessToken: string` from the `TokenResponse` interface. Destructure `access_token` as `_unused` in both `handleCallback` and `refreshTokens`.

### Fix #5 — Standardise `SECURE` constant

**Problem**: `hooks.server.ts` uses `const SECURE = !dev` (from Unit 13's `import { dev } from '$app/environment'`), but `callback/+server.ts` and `refresh/+server.ts` still use the old `const SECURE = process.env.NODE_ENV === 'production'`. During development, `process.env.NODE_ENV` may be undefined or `'development'` depending on the runtime, while `dev` is a compile-time constant from SvelteKit that is guaranteed correct in all environments.

**Solution**: In both `callback/+server.ts` and `refresh/+server.ts`, add `import { dev } from '$app/environment'` and change `SECURE` to `const SECURE = !dev`.

## Implementation

### 1. `frontend/src/hooks.server.ts` — Refresh dedup + maxAge + `setUser` helper

Replace the entire `handle` function body. Changes:

- Add `import type { TokenResponse, JwtClaims } from '$lib/server/authentik';`
- Add module-level variable (outside `handle`):
  ```typescript
  let inflightRefresh: Promise<TokenResponse | null> | null = null;
  ```
- In the refresh block, wrap `refreshTokens(refreshToken)` in dedup:
  ```typescript
  if (!inflightRefresh) {
    inflightRefresh = refreshTokens(refreshToken).finally(() => {
      inflightRefresh = null;
    });
  }
  const result = await inflightRefresh;
  ```
- Extract the duplicated `event.locals.user = { ... }` assignment into a `setUser(event, payload)` function to avoid repeating the four-field object in both the initial verify path and the refresh path.
- New `maxAge` calculation:
  ```typescript
  const maxAge = result.payload.exp
    ? Math.max(result.payload.exp - Math.floor(Date.now() / 1000), 0)
    : 3600;
  ```
- Guard `event.cookies.set('session_jwt', ...)` with:
  ```typescript
  if (maxAge > 0) {
    event.cookies.set('session_jwt', result.idToken, {
      httpOnly: true, sameSite: 'lax', path: '/',
      maxAge, secure: SECURE
    });
  }
  ```
  If `maxAge` is 0, the token is already expired — no cookie is written, but `locals.user` is still populated from the verified payload for the current request's lifetime.

- `SECURE` already uses `!dev` (unchanged). Verify it reads `import { dev } from '$app/environment'` and `const SECURE = !dev`.

**Complete file structure after changes:**

```
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
          // Deduplicate concurrent refresh attempts across parallel requests
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
```

### 2. `frontend/src/lib/client/api.ts` — New file

Create a new file at this path with the following content:

```typescript
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

    window.location.href = '/?error=session_expired';
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
```

No packages needed — uses native `fetch` (available in all modern browsers and SvelteKit's server runtime).

### 3. `frontend/src/routes/+page.svelte` — Migrate `testConnection` to `apiFetch`

- Add `import { apiFetch } from '$lib/client/api';` at the top of the `<script>` block (after the existing imports).
- In `testConnection()`, replace:
  ```typescript
  const res = await fetch('/api/ping');
  ```
  with:
  ```typescript
  const res = await apiFetch('/api/ping');
  ```
- The surrounding `try/catch` remains unchanged — `apiFetch` throws only when it triggers a redirect (unreachable from the catch after redirect, but harmless).

**Before (line ~32):**
```typescript
const res = await fetch('/api/ping');
const body = await res.json();
```

**After:**
```typescript
const res = await apiFetch('/api/ping');
const body = await res.json();
```

### 4. `frontend/src/routes/api/auth/callback/+server.ts` — maxAge + SECURE

- Add `import { dev } from '$app/environment';` at the top of the file (after existing imports).
- Replace `const SECURE = process.env.NODE_ENV === 'production';` with `const SECURE = !dev;`
- Replace the `maxAge` line (~line 24) with:
  ```typescript
  const maxAge = result.payload.exp
    ? Math.max(result.payload.exp - Math.floor(Date.now() / 1000), 0)
    : 3600;
  ```
- Wrap `event.cookies.set('session_jwt', ...)` in `if (maxAge > 0) { ... }`

**Before:**
```typescript
const SECURE = process.env.NODE_ENV === 'production';

// ... later ...
event.cookies.set('session_jwt', result.idToken, {
  httpOnly: true,
  sameSite: 'lax',
  path: '/',
  maxAge: Math.max(result.payload.exp ? result.payload.exp - Math.floor(Date.now() / 1000) : 3600, 60),
  secure: SECURE
});
```

**After:**
```typescript
const SECURE = !dev;

// ... later ...
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
```

### 5. `frontend/src/routes/api/auth/refresh/+server.ts` — maxAge + SECURE

- Add `import { dev } from '$app/environment';` at the top of the file.
- Replace `const SECURE = process.env.NODE_ENV === 'production';` with `const SECURE = !dev;`
- Same `maxAge` calculation change as callback.
- Same guard around `event.cookies.set('session_jwt', ...)`.

**Before (lines ~27-33):**
```typescript
event.cookies.set('session_jwt', result.idToken, {
  httpOnly: true,
  sameSite: 'lax',
  path: '/',
  maxAge: Math.max(result.payload.exp ? result.payload.exp - Math.floor(Date.now() / 1000) : 3600, 60),
  secure: SECURE
});
```

**After:**
```typescript
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
```

### 6. `frontend/src/lib/server/authentik.ts` — Remove `accessToken`

**6a. Update the `TokenResponse` interface** (around line 31):
- Remove `accessToken: string;` from the interface.

**Before:**
```typescript
interface TokenResponse {
  idToken: string;
  accessToken: string;
  refreshToken: string;
  payload: JwtClaims;
}
```

**After:**
```typescript
interface TokenResponse {
  idToken: string;
  refreshToken: string;
  payload: JwtClaims;
}
```

**6b. Update `handleCallback` return** (around line 142):
- Change the response destructure to drop `access_token`:
  ```typescript
  const { id_token, refresh_token, access_token: _unused } = await res.json();
  const idToken: string = id_token;
  ```
- Update the return value:
  ```typescript
  return {
    idToken,
    refreshToken: refresh_token,
    payload
  };
  ```

**Before:**
```typescript
const data = await res.json();
const idToken: string = data.id_token;
if (!idToken) { return null; }
try {
  const payload = await verifyJwt(idToken);
  return {
    idToken,
    accessToken: data.access_token,
    refreshToken: data.refresh_token,
    payload
  };
} catch { return null; }
```

**After:**
```typescript
const { id_token, refresh_token, access_token: _unused } = await res.json();
const idToken: string = id_token;
if (!idToken) { return null; }
try {
  const payload = await verifyJwt(idToken);
  return {
    idToken,
    refreshToken: refresh_token,
    payload
  };
} catch { return null; }
```

**6c. Update `refreshTokens` return** (around line 194):
- Same destructure pattern:
  ```typescript
  const { id_token, refresh_token, access_token: _unused } = await res.json();
  const idToken: string = id_token;
  ```
- Keep the fallback for `refresh_token`:
  ```typescript
  return {
    idToken,
    refreshToken: refresh_token ?? refreshToken,
    payload
  };
  ```

**Before:**
```typescript
const data = await res.json();
const idToken: string = data.id_token;
if (!idToken) { return null; }
try {
  const payload = await verifyJwt(idToken);
  return {
    idToken,
    accessToken: data.access_token,
    refreshToken: data.refresh_token ?? refreshToken,
    payload
  };
} catch { return null; }
```

**After:**
```typescript
const { id_token, refresh_token, access_token: _unused } = await res.json();
const idToken: string = id_token;
if (!idToken) { return null; }
try {
  const payload = await verifyJwt(idToken);
  return {
    idToken,
    refreshToken: refresh_token ?? refreshToken,
    payload
  };
} catch { return null; }
```

### 7. Update progress tracker + renumber build plan

**`docs/progress-tracker.md`**:
- Set Current Phase to "Unit 14 — Auth Refresh Fixes"
- Move the current "Next Up" to after this unit
- After implementation, add to Completed with summary of all five fixes.

**`docs/specs/00-build-plan.md`**:
- Renumber all units ≥ 14 by +1:
  - 14 → 15: Student Dashboard – Subject Cards
  - 15 → 16: Student Agent – Term & Lesson Lists
  - 16 → 17: Student LMS – Term & Lesson Browsing
  - 17 → 18: Student Agent – Lesson Content (Student View)
  - 18 → 19: Lesson Content Page with Side Navigation
  - 19 → 20: Teacher Agent – Initialization & Dashboard
  - 20 → 21: Teacher Agent – Term & Lesson Toggle
  - 21 → 22: Teacher Assignment Creation
  - 22 → 23: Student Assignment Display
  - 23 → 24: Student Assignment Submission
  - 24 → 25: Teacher Grading
  - 25 → 26: Admin Class & Teacher Management
  - 26 → 27: Polish

## Files Changed

| File | Change |
|---|---|
| `frontend/src/hooks.server.ts` | Fix #1: refresh dedup + Fix #3: maxAge + `setUser` helper |
| `frontend/src/lib/client/api.ts` | **New file**: `apiFetch` wrapper with module-level refresh dedup |
| `frontend/src/routes/+page.svelte` | Fix #2: migrate `testConnection` to `apiFetch` |
| `frontend/src/routes/api/auth/callback/+server.ts` | Fix #3: maxAge + Fix #5: `SECURE` |
| `frontend/src/routes/api/auth/refresh/+server.ts` | Fix #3: maxAge + Fix #5: `SECURE` |
| `frontend/src/lib/server/authentik.ts` | Fix #4: remove `accessToken` from `TokenResponse`, destructure in both functions |
| `docs/progress-tracker.md` | Add Unit 14 completion entry |
| `docs/specs/00-build-plan.md` | Renumber Units 14–26 → 15–27 |

## Dependencies

None. `apiFetch` uses native `fetch` (available in all modern browsers and SvelteKit's server runtime). All other changes are in existing files — no packages to install or update.

## Verification Checklist

### Build & Typecheck
- [ ] `pnpm build` succeeds with zero errors
- [ ] `pnpm check` passes with zero errors
- [ ] No TypeScript errors from removing `accessToken` field from `TokenResponse` interface
- [ ] No TypeScript errors from the new `setUser` helper function signature

### Fix #1 — Refresh dedup
- [ ] Normal login flow still works: callback → cookies set → dashboard loads at `/`
- [ ] Expired JWT + valid refresh token → cookie replaced silently, user stays on page
- [ ] Two browser tabs with expired JWTs navigating simultaneously → both land on `/`, neither logs out
- [ ] Expired JWT + expired refresh token → both cookies cleared, redirected to Authentik login (root layout guard)
- [ ] `inflightRefresh` resets to `null` after refresh completes (`.finally` fires)

### Fix #2 — Client-side 401 recovery
- [ ] "Test Connection" button on dashboard with valid session → returns `"admin online"` or current ping response
- [ ] "Test Connection" with expired JWT + valid refresh token → `apiFetch` refreshes silently, retries original request, shows success
- [ ] "Test Connection" with fully expired session (no valid refresh token) → redirected to `/?error=session_expired`

### Fix #3 — maxAge alignment
- [ ] `session_jwt` cookie `maxAge` is `exp - now` exactly (not floored to 60) in all three files
- [ ] If JWT `exp` is 5 seconds from now, cookie `maxAge` is 5 (was 60 before fix)
- [ ] If JWT `exp` is in the past (e.g., clock skew), no `session_jwt` cookie is written but `locals.user` is populated for the current request
- [ ] If JWT has no `exp` claim, `maxAge` defaults to 3600

### Fix #4 — accessToken removal
- [ ] `TokenResponse` interface has no `accessToken` field
- [ ] `handleCallback` returns object without `accessToken`
- [ ] `refreshTokens` returns object without `accessToken`
- [ ] No TypeScript errors in any file that imports or destructures `TokenResponse`

### Fix #5 — SECURE standardisation
- [ ] `callback/+server.ts` uses `import { dev } from '$app/environment'` and `const SECURE = !dev`
- [ ] `refresh/+server.ts` uses `import { dev } from '$app/environment'` and `const SECURE = !dev`
- [ ] `hooks.server.ts` already uses `!dev` pattern (no regression from Unit 13)

### Regression
- [ ] Authentik login flow (callback → redirect to `/`) works end-to-end with PKCE
- [ ] Logout (avatar dropdown → sign out → Authentik end_session → redirect to `/`) works
- [ ] Admin routes at `/admin/users/*` render correctly with sidebar/navbar
- [ ] Dashboard "Account Not Initialized" warning renders for uninitialized users
- [ ] Root `+layout.server.ts` correctly redirects unauthenticated users to Authentik (no regression from Unit 13)
- [ ] `docs/progress-tracker.md` updated with Unit 14 completion summary
- [ ] `docs/specs/00-build-plan.md` reflects Units 14–26 → 15–27 renumbering