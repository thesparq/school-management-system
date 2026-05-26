# Progress Tracker

Update this file after every meaningful implementation change.

## Current Phase

- Dashboard Layout Shell (Unit 3)

## Current Goal

- Nothing started yet.

## Completed

- Unit 1: Frontend Foundation — SvelteKit configured with Tailwind v4, shadcn-svelte Button, design tokens from ui-context.md applied in `src/app.css`, Inter font loaded. Static landing page at `/` with branded heading and primary-blue button.
- Unit 2: Authentik Authentication — Stateless OIDC with Authentik as sole signing authority. Removed Better Auth, Drizzle ORM, SQLite, and all demo routes. Built OIDC helper module (`src/lib/server/authentik.ts`) with PKCE, JWKS verification, silent token refresh, and RP-Initiated Logout. Created `/login`, `/api/auth/login`, `/api/auth/callback`, `/api/auth/logout`, `/api/auth/refresh`, and `/dashboard` routes. CSR Fprotection on logout. (`pnpm build` and `svelte-check` pass with zero errors.)

## In Progress

- Unit 3: Dashboard Layout Shell

## Next Up

- Unit 4: Golem Agent Scaffolding

## Recent Specs

- `docs/specs/02-authentik-auth.md` — Stateless OIDC with Authentik, replacing Better Auth + Drizzle. Silent token refresh, RP-Initiated Logout.

## Open Questions

- None.

## Architecture Decisions

- `src/app.css` is the canonical CSS entry point. shadcn-svelte's generated `layout.css` was deleted and its contents merged into `app.css`.
- Better Auth was removed in favor of stateless OIDC with Authentik as the sole signing authority. JWT validation uses `jose` with Authentik's JWKS endpoint. No server-side sessions, no database in the frontend layer.
- Drizzle ORM and SQLite were removed entirely from the frontend; SvelteKit no longer has any database access.

## Session Notes

- Starting implementation of Unit 1.
