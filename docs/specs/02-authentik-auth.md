# Unit 2 — Authentik Authentication (Stateless OIDC)

## Goal

Replace Better Auth with a stateless OpenID Connect flow. SvelteKit redirects unauthenticated users to Authentik, receives a JWT via the OIDC Authorization Code + PKCE flow, and validates it on every request against Authentik's JWKS endpoint. The JWT is the sole credential — no server-side sessions, no database. Tokens are silently refreshed when expired using a refresh token cookie. Logout calls Authentik's RP-Initiated Logout endpoint.

## Design

### Auth Flow

```
[Browser] → /login → 302 to Authentik /authorize?response_type=code&...
[Authentik] → 302 to /api/auth/callback?code=...&state=...
[API endpoint] Exchanges code at Authentik's token_endpoint
[API endpoint] Verifies ID token JWT signature via JWKS
[API endpoint] Sets session_jwt + refresh_token cookies, redirects to /dashboard
[Every request] hooks.server.ts verifies session_jwt; if expired, silently refreshes
```

### Cookies

| Cookie | Value | HTTP-only | SameSite | Max-Age |
|---|---|---|---|---|
| `session_jwt` | Authentik ID token (JWT) | Yes | Lax | ID token `exp` - `now`, floored to min 60s |
| `refresh_token` | Authentik refresh token | Yes | Strict | 30 days (2_592_000s) |
| `oauth_state` | CSRF state for login | Yes | Lax | 5 min (300s) |
| `oauth_code_verifier` | PKCE code verifier | Yes | Lax | 5 min (300s) |

### Token Refresh (hooks.server.ts)

```
if session_jwt cookie exists:
  try verify(session_jwt, JWKS)
  if valid → set locals.user, continue
  if expired → read refresh_token cookie
    POST authentik_token_endpoint { grant_type: refresh_token, refresh_token }
    if success → verify new ID token, update both cookies, set locals.user
    if fail → clear both cookies, locals.user = null
  if invalid signature → clear both cookies, locals.user = null
```

### Routes

| Path | Access | Method | What it does |
|---|---|---|---|
| `/login` | Public | GET | If logged in → redirect to `/dashboard`. Else → render "Sign in with Authentik" button. |
| `/api/auth/login` | Public | GET | Generates Authentik authorize URL with PKCE + state, sets temp cookies, returns the URL as JSON. |
| `/api/auth/callback` | Public | GET | Reads `code`, `state` from query. Validates against `oauth_state` cookie. Exchanges code. Verifies ID token via JWKS. Sets `session_jwt` + `refresh_token`. Clears temp cookies. Redirects to `/dashboard`. |
| `/dashboard` | Protected | GET | Shows `Hello, {user.name}` + logout button. Redirects to `/login` if unauthenticated. |
| `/api/auth/logout` | Any | POST | Calls Authentik's `end_session_endpoint` with `id_token_hint`. Clears all auth cookies. Returns logout URL as JSON for client redirect. |
| `/api/auth/refresh` | Internal | POST | Available for explicit client-side token refresh if needed. Not used by hooks.server.ts, which calls `refreshTokens()` directly. Exchanges `refresh_token` cookie for new tokens at Authentik's token endpoint. |

### Protected Route Pattern

Every protected page or layout uses:
```ts
// +page.server.ts or +layout.server.ts
import { redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = (event) => {
  if (!event.locals.user) {
    redirect(302, '/login');
  }
  return { user: event.locals.user };
};
```

## Implementation

### 1. Remove Better Auth + Drizzle

```bash
pnpm remove better-auth @better-auth/cli better-sqlite3 drizzle-orm drizzle-kit @types/better-sqlite3
```

**Delete these files and directories:**
- `src/lib/server/auth.ts`
- `src/lib/server/db/` (entire directory)
- `src/routes/demo/` (entire directory)
- `drizzle.config.ts`
- `local.db`

**Remove from package.json scripts:**
- `db:push`
- `db:generate`
- `db:migrate`
- `db:studio`
- `auth:schema`

### 2. Add dependency

```bash
pnpm add jose
```

### 3. Environment variables (`frontend/.env` and `frontend/.env.example`)

```
ORIGIN="http://localhost:5173"
AUTHENTIK_ISSUER_URL="https://auth.example.com/application/o/school-management"
AUTHENTIK_CLIENT_ID=""
AUTHENTIK_CLIENT_SECRET=""
```

`AUTHENTIK_CLIENT_SECRET` is optional — PKCE works without it. The redirect URI is computed as `${ORIGIN}/api/auth/callback`.

### 4. `src/lib/server/authentik.ts` — OIDC Helper Module

One module, exported functions:

```ts
/** Lazily validates env vars on first call. Throws at runtime if AUTHENTIK_ISSUER_URL, AUTHENTIK_CLIENT_ID, or ORIGIN are missing. */
function getConfig(): { ISSUER_URL: string; CLIENT_ID: string; CLIENT_SECRET: string; ORIGIN: string; REDIRECT_URI: string }

/** Fetches and caches Authentik's OpenID configuration (/.well-known/openid-configuration). Cache TTL: 1 hour in memory. */
export async function getOpenIdConfig(): Promise<OpenIdConfig>

/** Returns a `jose` JWKS key set from the discovered jwks_uri (fetched from OpenID config, not hardcoded). Cached in module variable. */
export async function getJwks(): Promise<ReturnType<typeof createRemoteJWKSet>>

/** Generates an Authentik authorize URL with PKCE. Returns { url, state, codeVerifier }. */
export async function generateAuthUrl(): Promise<{ url: string; state: string; codeVerifier: string }>

/** Exchanges the authorization code for tokens. Validates ID token (signature, iss, aud, exp). Returns the verified payload + raw tokens, or null on failure. */
export async function handleCallback(
  code: string,
  state: string,
  codeVerifier: string,
  expectedState: string
): Promise<TokenResponse | null>

/** Verifies a JWT string against Authentik's JWKS. Returns the decoded payload. Throws on verification failure — `ERR_JWT_EXPIRED` for expired tokens, other errors for invalid signatures/issuer/audience. */
export async function verifyJwt(jwt: string): Promise<JwtClaims>

/** Refreshes tokens using a refresh token. Returns new tokens + verified ID token payload, or null. */
export async function refreshTokens(refreshToken: string): Promise<TokenResponse | null>

/** Builds Authentik's RP-Initiated Logout URL with id_token_hint and post_logout_redirect_uri. */
export async function getEndSessionUrl(idToken: string): Promise<string>
```

**Implementation notes:**
- `getOpenIdConfig` fetches `{ISSUER_URL}/.well-known/openid-configuration` once, caches at module level with timestamp. Re-fetches after 3600s.
- `getJwks` fetches `jwks_uri` from the OpenID discovery document (not hardcoded) and delegates to `jose.createRemoteJWKSet()`.
- `generateAuthUrl` uses Web Crypto's `crypto.subtle.digest('SHA-256', ...)` for PKCE challenge (base64url-encoded). State is a random UUID.
- `handleCallback`: Validates state match first, then POSTs `application/x-www-form-urlencoded` to token_endpoint with `grant_type=authorization_code`, `code`, `redirect_uri`, `code_verifier`, `client_id` (and `client_secret` if non-empty). Verifies ID token via `jose.jwtVerify()` which validates signature (JWKS), issuer (`iss`), audience (`aud`), and expiry (`exp`). Catches verifyJwt errors and returns null.
- `handleCallback` also verifies state match (`state === expectedState`) before exchanging.
- `verifyJwt` throws on any verification failure. Callers use try/catch and discriminate `err.code === 'ERR_JWT_EXPIRED'` from other errors.
- `handleCallback` and `refreshTokens` wrap `verifyJwt` in try/catch and return null on failure.
- `refreshTokens`: POSTs to token_endpoint with `grant_type=refresh_token`, `refresh_token`, `client_id`. Returns new tokens + verified ID token.
- `getEndSessionUrl`: Looks up `end_session_endpoint` from OpenID config, appends `id_token_hint=<jwt>` and `post_logout_redirect_uri=${ORIGIN}/login`.
- `getConfig()` validates all required env vars lazily at call time (not at module import), so build-time bundling works without the env vars being present.

### 5. `src/hooks.server.ts` — Auth Gate

```ts
import type { Handle } from '@sveltejs/kit';
import { verifyJwt, refreshTokens } from '$lib/server/authentik';

const SECURE = process.env.NODE_ENV === 'production';

export const handle: Handle = async ({ event, resolve }) => {
  event.locals.user = null;

  const jwt = event.cookies.get('session_jwt');

  if (jwt) {
    try {
      const payload = await verifyJwt(jwt);
      event.locals.user = {
        id: payload.sub ?? '',
        name: payload.name ?? payload.preferred_username ?? '',
        email: payload.email ?? '',
        roles: payload.groups ?? payload.roles ?? []
      };
    } catch (err) {
      const isExpired = (err as { code?: string })?.code === 'ERR_JWT_EXPIRED';

      if (isExpired) {
        const refreshToken = event.cookies.get('refresh_token');
        if (refreshToken) {
          const result = await refreshTokens(refreshToken);
          if (result) {
            event.locals.user = {
              id: result.payload.sub ?? '',
              name: result.payload.name ?? result.payload.preferred_username ?? '',
              email: result.payload.email ?? '',
              roles: result.payload.groups ?? result.payload.roles ?? []
            };

            event.cookies.set('session_jwt', result.idToken, {
              httpOnly: true, sameSite: 'lax', path: '/',
              maxAge: Math.max(result.payload.exp ? result.payload.exp - Math.floor(Date.now() / 1000) : 3600, 60),
              secure: SECURE
            });

            event.cookies.set('refresh_token', result.refreshToken, {
              httpOnly: true, sameSite: 'strict', path: '/',
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

**JWT verification uses try/catch with error discrimination:** `verifyJwt()` throws on failure. Only `ERR_JWT_EXPIRED` triggers a refresh attempt. Invalid signature, wrong issuer, or tampered tokens clear all cookies immediately — no wasted refresh call.

### 6. `src/routes/login/+page.server.ts`

```ts
import { redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = (event) => {
  if (event.locals.user) {
    redirect(302, '/dashboard');
  }
  return {};
};
```

### 7. `src/routes/login/+page.svelte`

- Centered card on surface-50 background
- School logo/heading "School Management System"
- "Sign in with Authentik" button (shadcn `Button`, primary-500)
- On click: `fetch('/api/auth/login')` → `res.json()` → `window.location.href = data.url`
- Loading state on button after click
- Error state if the fetch fails

### 8. `src/routes/api/auth/login/+server.ts`

```ts
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { generateAuthUrl } from '$lib/server/authentik';

export const GET: RequestHandler = async (event) => {
  const { url, state, codeVerifier } = await generateAuthUrl();
  event.cookies.set('oauth_state', state, {
    httpOnly: true, sameSite: 'lax', path: '/api/auth/callback', maxAge: 300,
    secure: process.env.NODE_ENV === 'production'
  });
  event.cookies.set('oauth_code_verifier', codeVerifier, {
    httpOnly: true, sameSite: 'lax', path: '/api/auth/callback', maxAge: 300,
    secure: process.env.NODE_ENV === 'production'
  });
  return json({ url });
};
```

### 9. `src/routes/api/auth/callback/+server.ts`

```ts
import { redirect } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { handleCallback } from '$lib/server/authentik';

export const GET: RequestHandler = async (event) => {
  const code = event.url.searchParams.get('code');
  const state = event.url.searchParams.get('state');
  const expectedState = event.cookies.get('oauth_state');
  const codeVerifier = event.cookies.get('oauth_code_verifier');

  if (!code || !state || !expectedState || !codeVerifier) {
    redirect(302, '/login?error=invalid_callback');
  }

  const result = await handleCallback(code, state, codeVerifier, expectedState);
  if (!result) {
    redirect(302, '/login?error=auth_failed');
  }

  // Set session and refresh cookies
  event.cookies.set('session_jwt', result.idToken, {
    httpOnly: true, sameSite: 'lax', path: '/',
    maxAge: Math.max(result.payload.exp ? result.payload.exp - Math.floor(Date.now() / 1000) : 3600, 60),
    secure: process.env.NODE_ENV === 'production'
  });
  event.cookies.set('refresh_token', result.refreshToken, {
    httpOnly: true, sameSite: 'strict', path: '/',
    maxAge: 2_592_000,
    secure: process.env.NODE_ENV === 'production'
  });

  // Clear temp cookies
  event.cookies.delete('oauth_state', { path: '/api/auth/callback' });
  event.cookies.delete('oauth_code_verifier', { path: '/api/auth/callback' });

  redirect(302, '/dashboard');
};
```

### 10. `src/routes/api/auth/logout/+server.ts`

```ts
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getEndSessionUrl } from '$lib/server/authentik';

export const POST: RequestHandler = async (event) => {
  const idToken = event.cookies.get('session_jwt') ?? '';
  const url = await getEndSessionUrl(idToken);

  event.cookies.delete('session_jwt', { path: '/' });
  event.cookies.delete('refresh_token', { path: '/' });

  return json({ url });
};
```

### 11. `src/routes/api/auth/refresh/+server.ts`

```ts
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { refreshTokens } from '$lib/server/authentik';

const SECURE = process.env.NODE_ENV === 'production';

export const GET: RequestHandler = async (event) => {
  const refreshToken = event.cookies.get('refresh_token');
  if (!refreshToken) {
    return json({ error: { code: 'NO_REFRESH_TOKEN' } }, { status: 401 });
  }

  const result = await refreshTokens(refreshToken);
  if (!result) {
    event.cookies.delete('session_jwt', { path: '/' });
    event.cookies.delete('refresh_token', { path: '/' });
    return json({ error: { code: 'REFRESH_FAILED' } }, { status: 401 });
  }

  event.cookies.set('session_jwt', result.idToken, {
    httpOnly: true, sameSite: 'lax', path: '/',
    maxAge: Math.max(result.payload.exp ? result.payload.exp - Math.floor(Date.now() / 1000) : 3600, 60),
    secure: SECURE
  });
  event.cookies.set('refresh_token', result.refreshToken, {
    httpOnly: true, sameSite: 'strict', path: '/',
    maxAge: 2_592_000,
    secure: SECURE
  });

  return json({ success: true });
};
```

### 12. `src/routes/dashboard/+page.server.ts`

```ts
import { redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = (event) => {
  if (!event.locals.user) {
    redirect(302, '/login');
  }
  return { user: event.locals.user };
};
```

### 13. `src/routes/dashboard/+page.svelte`

```svelte
<script lang="ts">
  import { Button } from '$lib/components/ui/button';
  import type { PageData } from './$types';

  let { data }: { data: PageData } = $props();

  let isLoggingOut = $state(false);
  let error = $state('');

  async function handleLogout() {
    if (isLoggingOut) return;
    isLoggingOut = true;
    error = '';

    try {
      const res = await fetch('/api/auth/logout', { method: 'POST' });
      if (!res.ok) {
        error = 'Logout failed. Please try again.';
        isLoggingOut = false;
        return;
      }
      const body = await res.json();
      if (body.url) {
        window.location.href = body.url;
      }
    } catch {
      error = 'An error occurred during logout. Please try again.';
      isLoggingOut = false;
    }
  }
</script>

<div class="flex min-h-screen items-center justify-center">
  <div class="text-center">
    <h1 class="text-2xl font-display font-bold text-primary-700">
      Hello, {data.user.name}
    </h1>
    <p class="mt-1 text-sm text-surface-700">{data.user.email}</p>

    {#if error}
      <p class="mt-4 text-sm text-error-500">{error}</p>
    {/if}

    <div class="mt-6">
      <Button onclick={handleLogout} variant="outline" disabled={isLoggingOut}>
        {isLoggingOut ? 'Signing out...' : 'Sign out'}
      </Button>
    </div>
  </div>
</div>
```

### 14. `src/app.d.ts`

```ts
declare global {
  namespace App {
    interface User {
      id: string;
      name: string;
      email: string;
      roles: string[];
    }
    interface Locals {
      user: User | null;
    }
  }
}

export {};
```

### 15. `src/lib/utils.ts`

Update to remove any drizzle/better-auth related helpers. Keep `cn()` for shadcn-svelte component styling.

### 16. `src/routes/+layout.svelte`

No changes needed — the root layout from Unit 1 should remain.

## Dependencies

### Add

| Package | Version | Purpose |
|---|---|---|
| `jose` | latest | JWKS endpoint client, JWT verification, JWT utilities |

### Remove

| Package | Reason |
|---|---|
| `better-auth` | Replaced by manual OIDC flow |
| `@better-auth/cli` | No longer needed |
| `better-sqlite3` | No database in frontend layer |
| `drizzle-orm` | No SQLite access from SvelteKit |
| `drizzle-kit` | No migrations needed |
| `@types/better-sqlite3` | No SQLite types needed |

### Keep

These are still required by shadcn-svelte and SvelteKit:
- `clsx`, `tailwind-merge` — used by shadcn's `cn()` utility
- All Tailwind v4 tooling from Unit 1
- All SvelteKit tooling from Unit 1

## Verification Checklist

- [ ] `pnpm build` succeeds with zero errors
- [ ] `pnpm check` (svelte-check) passes with zero errors
- [ ] Guest visits `/dashboard` → redirected to `/login`
- [ ] `/login` shows a branded "Sign in with Authentik" button
- [ ] Clicking button redirects to Authentik's `/authorize` URL with `code_challenge`, `state`, `client_id`, `redirect_uri` in query params
- [ ] After Authentik login, browser lands at `/api/auth/callback?code=...&state=...`
- [ ] Callback sets `session_jwt` and `refresh_token` HTTP-only cookies, redirects to `/dashboard`
- [ ] `/dashboard` shows `Hello, <name>` with the correct display name from Authentik
- [ ] Refreshing `/dashboard` still shows the user (JWT validated via JWKS on each request)
- [ ] Deleting `session_jwt` cookie only → token silently refreshed from `refresh_token` cookie; still on `/dashboard`
- [ ] Deleting both cookies → redirected to `/login`
- [ ] Setting both cookies with invalid values (tampered JWT) → `locals.user = null`, redirected to `/login` (no refresh attempt for invalid signature)
- [ ] `event.locals.user` is initialized to `null` when no JWT is present (not `undefined`)
- [ ] `refresh_token` cookie has `maxAge: 2_592_000` (30 days), not a session cookie
- [ ] `session_jwt` cookie `maxAge` is wrapped in `Math.max(..., 60)` to prevent zero/negative values
- [ ] Clicking "Sign out" → calls Authentik's `end_session_endpoint`, clears cookies, redirects to `/login` via Authentik
- [ ] No remaining files from Better Auth or Drizzle (`src/lib/server/auth.ts`, `src/lib/server/db/`, `src/routes/demo/`, `drizzle.config.ts`, `local.db`)
- [ ] `package.json` scripts have no `db:` or `auth:` entries
- [ ] `src/app.d.ts` defines `App.User` and `App.Locals` as specified
- [ ] Auth API responses use `{ url }` for redirect endpoints, `{ success: true }` for refresh, and `{ error: { code, message? } }` for errors
