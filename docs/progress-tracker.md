# Progress Tracker

Update this file after every meaningful implementation change.

## Current Phase

- Unit 6: Admin User List Page (next up)

## Current Goal

- Unit 5 shipped — moving to Unit 6 next.

## Completed

- Unit 1: Frontend Foundation — SvelteKit configured with Tailwind v4, shadcn-svelte Button, design tokens from ui-context.md applied in `src/app.css`, Inter font loaded. Static landing page at `/` with branded heading and primary-blue button.
- Unit 2: Authentik Authentication — Stateless OIDC with Authentik as sole signing authority. Removed Better Auth, Drizzle ORM, SQLite, and all demo routes. Built OIDC helper module (`src/lib/server/authentik.ts`) with PKCE, JWKS verification, silent token refresh, and RP-Initiated Logout. Created `/login`, `/api/auth/login`, `/api/auth/callback`, `/api/auth/logout`, `/api/auth/refresh`, and `/dashboard` routes. CSRF protection on logout. (`pnpm build` and `svelte-check` pass with zero errors.)
- Unit 3: Dashboard Layout Shell — Protected `(auth)` route group with collapsible shadcn-svelte Sidebar, top navbar with SidebarTrigger + breadcrumb placeholder + avatar dropdown with logout, and content area. Dashboard page migrated into the group. Sidebar state persisted in localStorage. (`pnpm build` and `svelte-check` pass with zero errors.)
- Unit 4: Golem Agent Scaffolding — Consolidated from 4 separate WASM components into a single `app:agents` component (`app-agents/`). All four agent types defined: AdminAgent (durable singleton, RPC-only, `ping` → `"admin online"`), GatewayAgent (ephemeral, mount `/gateway`, `ping` → calls `AdminAgent.ping` via typed `AdminAgentClient::scoped(...)`), StudentAgent (durable, placeholder), TeacherAgent (durable, placeholder). Demo agents deleted. `curl /gateway/ping` returns `"admin online"`; `/admin/ping` returns 404.
- Unit 5: SvelteKit → Golem Proxy — Created `/api/ping` proxy route in SvelteKit (`src/routes/api/ping/+server.ts`). Shared proxy helper `src/lib/server/golem.ts` with `proxyToGateway(path, userId)` and `X-Golem-Auth-Key` auth. Gateway Agent updated with `#derive.config` + `@config.Secret[String]` for auth key verification (rejects unauthorized requests before AdminAgent RPC). `secretDefaults` in `golem.yaml` for local dev. Dashboard "Connection Status" card with "Test Connection" button. Extension method `AgentError::to_string` added for generated code compatibility.

## Next Up

- Unit 6: Admin User List Page

## Recent Specs

- `docs/specs/03-dashboard-layout-shell.md` — Protected auth layout with collapsible shadcn-svelte Sidebar, navbar with breadcrumb + avatar dropdown, migrated dashboard page.
- `docs/specs/05-sveltekit-golem-proxy.md` — SvelteKit → Golem proxy with shared auth secret via Golem secrets.

## Open Questions

- None.

## Architecture Decisions

- Dashboard layout uses shadcn-svelte Sidebar compound component (collapsible sidebar using Sheet on mobile). Sidebar open/close state persisted via localStorage.
- The `(auth)` route group pattern used for all protected routes — shared layout with auth guard ensures consistent authentication check and user data availability.
- `DropdownMenuTrigger` uses bits-ui's snippet-based child composition (`{#snippet child({ props })}`) rather than the deprecated `asChild` prop.
- All agents live in a single WASM component (`app:agents`, dir `app-agents/`). This enables typed intra-component RPC using `<AgentName>Client::scoped(...)` instead of raw `@rpc.AgentClient`. The `golem-sdk-tools agents` build step generates typed client stubs for all `#derive.agent` structs within the component.
- GatewayAgent uses `AdminAgentClient::scoped(fn(admin) { admin.ping() })` — the `scoped` pattern automatically handles client resource cleanup via `defer`, eliminating manual `drop()` calls.
- Empty structs in MoonBit use `StructName::{}` syntax — e.g., `fn AdminAgent::new() -> AdminAgent { AdminAgent::{} }`.
- Gateway Agent auth: `#derive.config` struct with `@config.Secret[String]` for the auth key, set via `secretDefaults` in `golem.yaml` (local) or `golem secret create` (production). The `#derive.endpoint_header("X-Golem-Auth-Key", "incoming_key")` annotation binds the HTTP header to a method parameter. The agent verifies the header against the resolved secret before any RPC.
- `golem-sdk-tools` 0.5.2 generates `e.to_string()` on `AgentError` types that lack `to_string()` — fixed by adding an extension method in `gateway_agent.mbt`.
- `proxyToGateway()` helper in `src/lib/server/golem.ts` is the single entry point for all SvelteKit-to-Golem proxy calls. Every future proxy route should use it.

- `src/app.css` is the canonical CSS entry point. shadcn-svelte's generated `layout.css` was deleted and its contents merged into `app.css`.
- Better Auth was removed in favor of stateless OIDC with Authentik as the sole signing authority. JWT validation uses `jose` with Authentik's JWKS endpoint. No server-side sessions, no database in the frontend layer.
- Drizzle ORM and SQLite were removed entirely from the frontend; SvelteKit no longer has any database access.

## Session Notes

- Unit 3 implemented. Branch: `feat/03-dashboard-layout-shell`. All shadcn-svelte components (sidebar, avatar, dropdown-menu, breadcrumb, separator, sheet, tooltip, input, skeleton, card) installed. Old `src/routes/dashboard/` deleted.
