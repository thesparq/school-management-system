# Unit 5 — SvelteKit → Golem Proxy

## Goal

Create a SvelteKit API route at `/api/ping` that proxies to the Gateway Agent's `/gateway/ping` endpoint with a shared auth secret. Add a dashboard button that calls this route and displays the result, proving the end-to-end SvelteKit → Gateway Agent → Admin Agent proxy pattern works.

## Design

### Proxy Pattern

All SvelteKit-to-Golem calls go through a single `proxyToGateway()` helper in `src/lib/server/golem.ts`. Every request sends the shared auth key as the `X-Golem-Auth-Key` HTTP header. The Gateway Agent verifies this header before forwarding any request. Responses use the standard `{ data, error }` envelope defined in `code-standards.md`.

### Auth Secret — Golem Secrets (not .env for the agent)

The Gateway Agent retrieves the expected auth key at runtime from Golem's secrets store using `@config.Secret[String].get!()`. This means:

- The agent's source code never contains the key value.
- The key is set once per environment via `golem secret create` (production) or `secretDefaults` (local).
- Rotation: update `GOLEM_AUTH_KEY` in the SvelteKit host + redeploy, then `golem secret update-value authKey` on the Golem side — zero code changes, no downtime.

For **local development**, the key is provided via `secretDefaults` in `golem.yaml`:

```yaml
secretDefaults:
  local:
    authKey: "dev-auth-key-change-in-production"
```

For **production**, the key is set via the CLI:

```bash
golem secret create authKey --secret-type String --secret-value "<key>"
```

The SvelteKit backend reads `GOLEM_AUTH_KEY` from its own environment (`.env`, gitignored). The frontend `.env` is never committed; the CI/CD pipeline injects it at deploy time.

### Gateway Agent — Config + Auth Check

The Gateway Agent gains a `#derive.config` struct with the secret field. The constructor receives `@config.Config[GatewayConfig]`. Each HTTP endpoint that the agent exposes verifies the incoming `X-Golem-Auth-Key` header against the resolved secret before performing any work.

On mismatch, the method returns `"unauthorized"` immediately — no RPC to Admin Agent is attempted. This prevents unauthenticated requests from even touching the internal network.

### No Gateway Agent Changes Beyond Auth

The `ping` method's core logic remains unchanged (RPC to Admin Agent). Only the auth parameter and check are added. The `user_id` query parameter is included in the SvelteKit proxy call for future use but ignored by the Gateway Agent's ping (it will be wired up in Unit 7).

## Implementation

### 1. Add environment variables to `frontend/.env`

```
GOLEM_GATEWAY_URL="http://agents.localhost:9006"
GOLEM_AUTH_KEY="dev-auth-key-change-in-production"
```

- `GOLEM_GATEWAY_URL` — base URL of the local Golem server's HTTP API.
- `GOLEM_AUTH_KEY` — must be identical to the value in `secretDefaults.local.authKey` (or the Golem secret for the active environment). Use a UUID or 32+ character random hex string in real deployments.

### 2. Create `frontend/src/lib/server/golem.ts`

Shared helper module for all Golem proxy calls.

```ts
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
```

### 3. Update `agents/golem.yaml` — add `secretDefaults`

Add after the `httpApi` section:

```yaml
secretDefaults:
  local:
    authKey: "dev-auth-key-change-in-production"
```

### 4. Update `agents/app-agents/gateway_agent.mbt`

Add config struct, update constructor, add auth check to ping:

```moonbit
//|

///|
/// Stateless gatekeeper - ephemeral, fresh instance per HTTP request.
/// Checks the incoming X-Golem-Auth-Key header against the configured
/// secret before forwarding requests to internal agents.
#derive.agent("ephemeral")
#derive.mount("/gateway")
struct GatewayAgent {
  config : @config.Config[GatewayConfig]
}

//|

#derive.config
pub(all) struct GatewayConfig {
  auth_key : @config.Secret[String]
}

//|

///|
fn GatewayAgent::new(config : @config.Config[GatewayConfig]) -> GatewayAgent {
  { config, }
}

//|

///|
/// Proxies a ping to the Admin Agent via typed RPC.
/// Requires the correct X-Golem-Auth-Key header.
/// Returns admin online on success, admin unreachable on RPC failure.
#derive.endpoint(get="/ping")
pub fn GatewayAgent::ping(
  self : Self,
  #derive.header("x-golem-auth-key") incoming_key : String
) -> String {
  let expected = try self.config.value.auth_key.get!() catch { _ => return "auth error" }
  if incoming_key != expected { return "unauthorized" }

  try {
    AdminAgentClient::scoped(fn(admin) raise @common.AgentError {
      admin.ping()
    })
  } catch {
    _ => "admin unreachable"
  }
}

//|

///|
fn main {

}
```

### 5. Create `frontend/src/routes/api/ping/+server.ts`

```ts
import { proxyToGateway } from '$lib/server/golem';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async (event) => {
	const userId = event.locals.user?.id;
	if (!userId) {
		return new Response(
			JSON.stringify({ error: { code: 'UNAUTHENTICATED', message: 'Not authenticated.' } }),
			{ status: 401, headers: { 'content-type': 'application/json' } }
		);
	}

	const result = await proxyToGateway('/gateway/ping', userId);

	if (result.error) {
		return new Response(JSON.stringify(result), { status: 502, headers: { 'content-type': 'application/json' } });
	}

	return new Response(JSON.stringify(result), { status: 200, headers: { 'content-type': 'application/json' } });
};
```

### 6. Update `frontend/src/routes/(auth)/dashboard/+page.svelte`

Add a "Connection Status" card alongside the existing "Quick Actions" card. The card has a "Test Connection" button. On click it fetches `/api/ping` and displays the result.

```svelte
<script lang="ts">
	import type { PageData } from './$types';
	import { Card, CardContent, CardHeader, CardTitle } from '$lib/components/ui/card';
	import { Button } from '$lib/components/ui/button';

	let { data }: { data: PageData } = $props();

	let pingResult = $state<string | null>(null);
	let pingError = $state<string | null>(null);
	let isPinging = $state(false);

	async function testConnection() {
		isPinging = true;
		pingResult = null;
		pingError = null;

		try {
			const res = await fetch('/api/ping');
			const body = await res.json();
			if (body.data) {
				pingResult = body.data;
			} else {
				pingError = body.error?.message ?? 'Unknown error';
			}
		} catch {
			pingError = 'Network error — could not reach server.';
		} finally {
			isPinging = false;
		}
	}
</script>

<div class="mx-auto max-w-4xl space-y-6">
	<div>
		<h1 class="text-2xl font-display font-bold text-primary-700">
			Welcome, {data.user.name}
		</h1>
		<p class="mt-1 text-sm text-surface-700">
			{data.user.roles[0] ?? 'User'} dashboard
		</p>
	</div>

	<div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
		<Card>
			<CardHeader>
				<CardTitle class="text-base">Quick Actions</CardTitle>
			</CardHeader>
			<CardContent>
				<p class="text-sm text-surface-700">Dashboard widgets will appear here.</p>
			</CardContent>
		</Card>

		<Card>
			<CardHeader>
				<CardTitle class="text-base">Connection Status</CardTitle>
			</CardHeader>
			<CardContent class="space-y-3">
				<Button onclick={testConnection} disabled={isPinging}>
					{isPinging ? 'Testing...' : 'Test Connection'}
				</Button>

				{#if pingResult}
					<p class="text-sm text-success-500">Gateway: {pingResult}</p>
				{/if}

				{#if pingError}
					<p class="text-sm text-error-500">{pingError}</p>
				{/if}
			</CardContent>
		</Card>
	</div>
</div>
```

## Dependencies

| Item | Status | Purpose |
|---|---|---|
| `@config.Config` / `@config.Secret` | In `golem_sdk: 0.5.2` | Typed config with secret injection for Gateway Agent |
| `golem secret` CLI | Available | Set production auth key |
| `$env/dynamic/private` | Built into SvelteKit | Read `GOLEM_GATEWAY_URL` and `GOLEM_AUTH_KEY` server-side |

No new packages to install.

## Verification Checklist

- [ ] `moon check --target wasm` passes in `agents/` with zero errors
- [ ] `golem deploy --reset` succeeds with exit code 0
- [ ] `curl -H "X-Golem-Auth-Key: dev-auth-key-change-in-production" http://agents.localhost:9006/gateway/ping?user_id=test` returns `"admin online"`
- [ ] `curl -H "X-Golem-Auth-Key: wrong-key" http://agents.localhost:9006/gateway/ping?user_id=test` returns `"unauthorized"`
- [ ] `curl -H "X-Golem-Auth-Key: dev-auth-key-change-in-production" http://agents.localhost:9006/gateway/ping?user_id=test` without the header returns `"unauthorized"` (header defaults to empty string)
- [ ] `pnpm build` passes in `frontend/` with zero errors
- [ ] Dashboard shows "Connection Status" card with "Test Connection" button
- [ ] Clicking "Test Connection" while logged in shows `"admin online"` in green
- [ ] Clicking "Test Connection" after changing the frontend `.env` key (mismatched) shows error in red
- [ ] `proxyToGateway` helper is generic enough to reuse for future proxy routes
- [ ] Documentation updated: `docs/progress-tracker.md` reflects Unit 5 as completed
