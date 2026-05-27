# Progress Tracker

Update this file after every meaningful implementation change.

## Current Phase

- Unit 8: Admin Portal — Activation Actions (completed)

## Current Goal

- Unit 8 complete — Activate/Deactivate buttons on admin user list with optimistic updates. Dynamic status badges fetched from Admin Agent. Dashboard not-activated error page. `golem build`, `pnpm build`, `pnpm check` all pass with zero errors.

## Completed

- Unit 1: Frontend Foundation — SvelteKit configured with Tailwind v4, shadcn-svelte Button, design tokens from ui-context.md applied in `src/app.css`, Inter font loaded. Static landing page at `/` with branded heading and primary-blue button.
- Unit 6: Admin User List Page — `/admin/users` route with role-based guard (`locals.user.roles.includes('admin')`). `authentik.ts` extended with `fetchAllUsers()` (Bearer token auth, paginated, filters to internal users in admin/students/teachers groups). shadcn-svelte Table with Name, Email, "Pending" Status, empty Actions columns. Four states: loading skeletons, error Alert + Retry, empty guidance, data table. Sidebar conditional "Admin > Users" nav item using `child` snippet pattern. (`pnpm build` and `svelte-check` pass with zero errors.)
- Unit 8: Admin Portal — Activation Actions — Admin Agent adds `deactivate_user(user_id)` and `get_all_activations()`. Gateway Agent adds 4 new endpoints: `check-activation`, `admin/activate`, `admin/deactivate`, `admin/activations`. SvelteKit gains 4 new API routes: `/api/auth/status`, `/api/admin/activations`, `/api/admin/users/[pk]/activate`, `/api/admin/users/[pk]/deactivate`. Dashboard shows "Account Not Activated" error for inactive users (server load check via `/api/auth/status`). Admin users page fetches real activation statuses, shows dynamic Badge (Active/Deactivated/Pending), and Activate/Deactivate buttons with optimistic updates and rollback on error. `proxyToGateway` extended with optional `extraParams`. `parseActivations` helper added. (`golem build`, `pnpm build`, `pnpm check` all pass with zero errors.)
- Unit 7: Admin Agent Activation Methods — Admin Agent gains `activate_user(user_id, role, class_level?) -> Result[String, String]` and `is_user_active(user_id) -> ActivationStatus` using `#derive.golem_schema` types and Golem durable memory (agent struct fields). `ActivationStatus` enum: `NotFound`, `Active`, `Suspended`, `Deactivated`. Gateway Agent `/gateway/ping` gains `user_id` query param; checks activation before proxying, returns `"NOT_ACTIVATED"` for inactive users. `proxyToGateway` in `golem.ts` handles `NOT_ACTIVATED` string, returns structured `403` error. Context files updated: storage model changed from SQLite to agent struct fields. (`moon build --target wasm`, `pnpm build`, `pnpm check` all pass with zero errors.)
- Unit 2: Authentik Authentication — Stateless OIDC with Authentik as sole signing authority. Removed Better Auth, Drizzle ORM, SQLite, and all demo routes. Built OIDC helper module (`src/lib/server/authentik.ts`) with PKCE, JWKS verification, silent token refresh, and RP-Initiated Logout. Created `/login`, `/api/auth/login`, `/api/auth/callback`, `/api/auth/logout`, `/api/auth/refresh`, and `/dashboard` routes. CSRF protection on logout. (`pnpm build` and `svelte-check` pass with zero errors.)
- Unit 3: Dashboard Layout Shell — Protected `(auth)` route group with collapsible shadcn-svelte Sidebar, top navbar with SidebarTrigger + breadcrumb placeholder + avatar dropdown with logout, and content area. Dashboard page migrated into the group. Sidebar state persisted in localStorage. (`pnpm build` and `svelte-check` pass with zero errors.)
- Unit 4: Golem Agent Scaffolding — Consolidated from 4 separate WASM components into a single `app:agents` component (`app-agents/`). All four agent types defined: AdminAgent (durable singleton, RPC-only, `ping` → `"admin online"`), GatewayAgent (ephemeral, mount `/gateway`, `ping` → calls `AdminAgent.ping` via typed `AdminAgentClient::scoped(...)`), StudentAgent (durable, placeholder), TeacherAgent (durable, placeholder). Demo agents deleted. `curl /gateway/ping` returns `"admin online"`; `/admin/ping` returns 404.
- Unit 5: SvelteKit → Golem Proxy — Created `/api/ping` proxy route in SvelteKit (`src/routes/api/ping/+server.ts`). Shared proxy helper `src/lib/server/golem.ts` with `proxyToGateway(path, userId)` and `X-Golem-Auth-Key` auth. Gateway Agent updated with `#derive.config` + `@config.Secret[String]` for auth key verification (rejects unauthorized requests before AdminAgent RPC). `secretDefaults` in `golem.yaml` for local dev. Dashboard "Connection Status" card with "Test Connection" button. Extension method `AgentError::to_string` added for generated code compatibility.

## Next Up

- Unit 9: SurrealDB Connection & Normalization

## Recent Specs

- `docs/specs/03-dashboard-layout-shell.md` — Protected auth layout with collapsible shadcn-svelte Sidebar, navbar with breadcrumb + avatar dropdown, migrated dashboard page.
- `docs/specs/05-sveltekit-golem-proxy.md` — SvelteKit → Golem proxy with shared auth secret via Golem secrets.
- `docs/specs/06-admin-user-list-page.md` — Admin user list page with Authentik API via Bearer token, shadcn-svelte Table, role-based sidebar nav, group-based filtering.
- `docs/specs/07-admin-agent-activation-methods.md` — Admin Agent `activateUser` and `isUserActive` methods, Gateway Agent activation gate, proxy NOT_ACTIVATED handling.
- `docs/specs/08-admin-activation-actions.md` — Admin portal activate/deactivate buttons, dynamic status badges, optimistic updates, dashboard not-activated error page.

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
- Custom types used in agent method signatures use `#derive.golem_schema` (dot syntax, not parentheses). The `golem-sdk-tools agents` command generates `HasElementSchema`, `FromExtractor`, `FromElementValue`, and `ToElementValue` trait implementations for these types automatically.
- `Result[Unit, String]` cannot be used as an RPC return type because `Unit` does not implement Golem schema traits and the orphan rule prevents adding them from a foreign package. Use `Result[String, String]` instead, with `Ok("ok")` as success value.
- **Authentik admin API uses Bearer token (not OAuth2 Client Credentials):** The service account token is generated in Authentik and sent as `Authorization: Bearer <token>`. No username needed, no token caching/refresh logic — the token is self-contained.
- **Admin user list filters by group membership:** Users must belong to at least one of `admin`, `students`, or `teachers` groups (by name) to appear in the admin table. Group PKs are fetched from `GET /api/v3/core/groups/` and cross-referenced against each user's `groups` array.
- **`SidebarMenuButton` uses `child` snippet pattern instead of `asChild`:** The shadcn-svelte component accepts `{#snippet child({ props })}` for wrapping custom elements like `<a>`, mirroring the `DropdownMenuTrigger` pattern.
- **Activation status text protocol:** Admin Agent's `get_all_activations` returns `Array[(String, ActivationStatus)]`. The Gateway serializes it as newline-separated `user_id|status` lines (plain text, no JSON dependency). The SvelteKit `parseActivations` helper parses this format. This avoids adding a `@json` MoonBit dependency while keeping the interface simple.
- **Admin gateway endpoints skip activation check:** The `activate_admin`, `deactivate_admin`, and `list_activations` gateway endpoints only check `X-Golem-Auth-Key` (not admin activation). This avoids a bootstrapping problem — no activated admin exists yet to activate the first user. SvelteKit role authorization is the sole admin gate.
- **Use `golem deploy --reset` for development updates:** When the Golem server reports "UP-TO-DATE" despite code changes, `golem deploy --reset` forces the new WASM binary through. This is needed because the deploy's hash comparison may consider staging vs. deployed as identical during rapid iteration cycles.
- **Golem HTTP gateway wraps String returns in JSON quotes:** All `String` return values from agent methods are serialized as JSON strings (e.g., `"OK"` not `OK`). The `proxyToGateway` helper must `JSON.parse` the raw response before comparing against known strings like `"unauthorized"`, `"NOT_ACTIVATED"`, etc.
- **Authentik JWT `sub` must match API `uuid`:** User activation is keyed by UUID. The JWT `sub` claim (used as `event.locals.user.id`) must be the same UUID value that the Authentik API returns as `user.uuid`. If Authentik's OIDC provider is configured with a custom `sub` expression (e.g., `sha256(...)`), the JWT `sub` won't match the API `uuid`, causing activation checks to fail. Fix: set Authentik OIDC provider `sub` expression to `user.uuid`.

- `src/app.css` is the canonical CSS entry point. shadcn-svelte's generated `layout.css` was deleted and its contents merged into `app.css`.
- Better Auth was removed in favor of stateless OIDC with Authentik as the sole signing authority. JWT validation uses `jose` with Authentik's JWKS endpoint. No server-side sessions, no database in the frontend layer.
- Drizzle ORM and SQLite were removed entirely from the frontend; SvelteKit no longer has any database access.

## Session Notes

- Unit 3 implemented. Branch: `feat/03-dashboard-layout-shell`. All shadcn-svelte components (sidebar, avatar, dropdown-menu, breadcrumb, separator, sheet, tooltip, input, skeleton, card) installed. Old `src/routes/dashboard/` deleted.
- Unit 6 implemented. Branch: `feat/06-admin-user-list-page`. shadcn-svelte table, badge, alert installed. Authentik auth refactored from OAuth2 Client Credentials → Bearer token, then Basic auth → Bearer token. Group membership filter added (admin/students/teachers). Spec updated to reflect all changes.
- Unit 8 implemented. Branch: `feat/08-admin-activation-actions`. Admin Agent gains `deactivate_user` and `get_all_activations`. Gateway Agent gains 4 endpoints (admin activation check removed to avoid bootstrapping). 4 new SvelteKit API routes built. Dashboard not-activated state added. Admin page shows dynamic status badges and Activate/Deactivate buttons with optimistic updates. `proxyToGateway` extended with `extraParams` and `JSON.parse` for Golem's quoted-string responses. `parseActivations` helper added. Activation keyed by Authentik UUID (requires JWT `sub` = `user.uuid` in OIDC provider). (`golem build`, `pnpm build`, `pnpm check` all pass.)
