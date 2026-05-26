# Code Standards

## General

- **Keep modules small and single-purpose.** Every file in `shared/`, every agent component, and every SvelteKit route should have one clear responsibility. If a module does two unrelated things, split it.
- **Fix root causes, do not layer workarounds.** When a bug appears, trace it back to the source. Do not add compensating logic in the UI or proxy layer to paper over an agent or database issue.
- **Do not mix concerns across system boundaries.** SvelteKit code must never contain business logic that belongs in agents. Agents must never contain UI rendering logic. The shared MoonBit module may hold pure data types and validation, but never I/O or side effects.
- **Explicit is better than implicit.** All API contracts (WIT interfaces, HTTP endpoints) must be clearly typed. Default values and fallback behaviour must be documented. Relying on hidden Golem or SvelteKit behaviour without a comment is forbidden.
- **Fail fast at the boundary.** Validate all external input (HTTP request bodies, JWT claims, RPC payloads) at the point of entry. Do not let invalid data propagate into internal logic.

## MoonBit

- **Use strict types throughout.** Every function signature must declare concrete MoonBit types. Avoid `Json` or `Any` unless absolutely necessary at the system boundary; convert to a domain type immediately after parsing.
- **Validate and decode at every boundary.** When an agent receives data via WIT function arguments, HTTP responses from SurrealDB, or RPC responses, validate the shape and content before using it. Use pattern matching and return `Result` types to handle failures.
- **Shared types belong in `shared/`.** All domain types (user roles, lesson structures, assignment configurations, submission payloads) must be defined in the `shared` MoonBit package so that frontend and backend use a single source of truth.
- **WIT interfaces define the public contract.** Every agent component exposes its API through a `.wit` file. Never add an undocumented “backdoor” method. All RPC method names must match the WIT definition exactly.
- **Agents must never panic.** Handle all error paths gracefully. Return `Result` or a domain error variant. An unhandled exception in an agent causes the invocation to fail and may roll back the entire transaction.
- **Idempotent operations only.** All agent RPC methods that modify state must be safe to call multiple times with the same arguments. Use upsert semantics (`INSERT OR REPLACE`, `ON CONFLICT … DO UPDATE`) and check preconditions before mutating.

## SvelteKit (TypeScript / JavaScript)

- **Strict TypeScript is required.** The `tsconfig.json` must enable `"strict": true`. No `any` types except when interacting with an untyped third-party library; in that case, provide a narrow type assertion immediately.
- **Validate and parse request input before any logic runs.** In server-side hooks and API routes, use Zod or equivalent to validate query parameters, request bodies, and headers.
- **`hooks.server.ts` is the single auth gate.** All JWT validation, user ID extraction, and role checking must happen in the server hook. Individual routes may refine permissions but must never bypass the hook.
- **API routes are pure proxies.** A server endpoint in `src/routes/api/` must:
  1. Read the authenticated `user_id` from `locals`.
  2. Forward the request to the correct Golem agent endpoint with the `user_id` in the path.
  3. Return the agent’s response verbatim, preserving status codes and error bodies.
  4. Under no circumstances access a database or file system directly.
- **Never expose internal identifiers to the browser.** The `user_id` used to address agents, internal agent IDs, and SurrealDB record IDs must remain server-side. Only opaque, public-safe identifiers (like assignment IDs shown in the UI) may be sent to the client.
- **Use SvelteKit load functions for data fetching.** Page data should be fetched in `+page.server.ts` or `+layout.server.ts`, never from client-side `onMount` calls except for truly interactive, non-critical data.

## Styling

- **Use design tokens defined in `app.css`.** All colours, spacing, border radii, and fonts must be referenced via Tailwind utility classes that map to the project’s `@theme` tokens. Hardcoded hex values, pixel sizes, or arbitrary values (e.g. `bg-[#123abc]`) are forbidden.
- **Follow the semantic colour scale.** `primary-*` for main actions and navigation, `secondary-*` for highlights and badges, `success-*` for completion states, `error-*` for destructive actions or overdue indicators, and `surface-*` for backgrounds and cards. Never swap these meanings.
- **shadcn-svelte components are the foundation.** New UI elements should be built by composing existing shadcn-svelte primitives (Button, Card, Dialog, Table, etc.). Custom CSS is allowed only for layout refinements, not to recreate an existing component from scratch.
- **Dark mode must use Tailwind’s `dark:` variant.** Any component that changes appearance in dark mode should use the `dark:` modifier with the corresponding token. Never write separate dark-mode CSS files or duplicate components.
- **Responsive design uses the default breakpoints.** Build mobile-first. Use `sm:`, `md:`, `lg:`, and `xl:` prefixes as needed. The sidebar collapse at small screens is the standard pattern.

## API Routes (SvelteKit → Golem)

- **JWT validation is mandatory.** Every request to an API route must be checked by the server hook. If the token is missing, expired, or tampered with, the route must return `401 Unauthorized` before any proxy call.
- **Enforce auth and ownership before any mutation.** For any state-changing request (submission, grading, user activation), the route must verify the authenticated user’s role and, if relevant, that they own the resource or have explicit admin permission.
- **Return consistent, predictable response shapes.** Every API response must follow a standard envelope:
  ```json
  {
    "data": { ... }     // present on success
    "error": {           // present on failure
      "code": "ACTIVATION_REQUIRED",
      "message": "Account not activated. Please contact your school administrator."
    }
  }
  ```
You're right — my previous response was broken into multiple partial messages. Here is the complete `code-standards.md` file in one block.

```markdown
# Code Standards

## General

- **Keep modules small and single-purpose.** Every file in `shared/`, every agent component, and every SvelteKit route should have one clear responsibility. If a module does two unrelated things, split it.
- **Fix root causes, do not layer workarounds.** When a bug appears, trace it back to the source. Do not add compensating logic in the UI or proxy layer to paper over an agent or database issue.
- **Do not mix concerns across system boundaries.** SvelteKit code must never contain business logic that belongs in agents. Agents must never contain UI rendering logic. The shared MoonBit module may hold pure data types and validation, but never I/O or side effects.
- **Explicit is better than implicit.** All API contracts (WIT interfaces, HTTP endpoints) must be clearly typed. Default values and fallback behaviour must be documented. Relying on hidden Golem or SvelteKit behaviour without a comment is forbidden.
- **Fail fast at the boundary.** Validate all external input (HTTP request bodies, JWT claims, RPC payloads) at the point of entry. Do not let invalid data propagate into internal logic.

## MoonBit

- **Use strict types throughout.** Every function signature must declare concrete MoonBit types. Avoid `Json` or `Any` unless absolutely necessary at the system boundary; convert to a domain type immediately after parsing.
- **Validate and decode at every boundary.** When an agent receives data via WIT function arguments, HTTP responses from SurrealDB, or RPC responses, validate the shape and content before using it. Use pattern matching and return `Result` types to handle failures.
- **Shared types belong in `shared/`.** All domain types (user roles, lesson structures, assignment configurations, submission payloads) must be defined in the `shared` MoonBit package so that frontend and backend use a single source of truth.
- **WIT interfaces define the public contract.** Every agent component exposes its API through a `.wit` file. Never add an undocumented “backdoor” method. All RPC method names must match the WIT definition exactly.
- **Agents must never panic.** Handle all error paths gracefully. Return `Result` or a domain error variant. An unhandled exception in an agent causes the invocation to fail and may roll back the entire transaction.
- **Idempotent operations only.** All agent RPC methods that modify state must be safe to call multiple times with the same arguments. Use upsert semantics (`INSERT OR REPLACE`, `ON CONFLICT … DO UPDATE`) and check preconditions before mutating.

## SvelteKit (TypeScript / JavaScript)

- **Strict TypeScript is required.** The `tsconfig.json` must enable `"strict": true`. No `any` types except when interacting with an untyped third-party library; in that case, provide a narrow type assertion immediately.
- **Validate and parse request input before any logic runs.** In server-side hooks and API routes, use Zod or equivalent to validate query parameters, request bodies, and headers.
- **`hooks.server.ts` is the single auth gate.** All JWT validation, user ID extraction, and role checking must happen in the server hook. Individual routes may refine permissions but must never bypass the hook.
- **API routes are pure proxies.** A server endpoint in `src/routes/api/` must:
  1. Read the authenticated `user_id` from `locals`.
  2. Forward the request to the correct Golem agent endpoint with the `user_id` in the path.
  3. Return the agent’s response verbatim, preserving status codes and error bodies.
  4. Under no circumstances access a database or file system directly.
- **Never expose internal identifiers to the browser.** The `user_id` used to address agents, internal agent IDs, and SurrealDB record IDs must remain server-side. Only opaque, public-safe identifiers (like assignment IDs shown in the UI) may be sent to the client.
- **Use SvelteKit load functions for data fetching.** Page data should be fetched in `+page.server.ts` or `+layout.server.ts`, never from client-side `onMount` calls except for truly interactive, non-critical data.

## Styling

- **Use design tokens defined in `app.css`.** All colours, spacing, border radii, and fonts must be referenced via Tailwind utility classes that map to the project’s `@theme` tokens. Hardcoded hex values, pixel sizes, or arbitrary values (e.g. `bg-[#123abc]`) are forbidden.
- **Follow the semantic colour scale.** `primary-*` for main actions and navigation, `secondary-*` for highlights and badges, `success-*` for completion states, `error-*` for destructive actions or overdue indicators, and `surface-*` for backgrounds and cards. Never swap these meanings.
- **shadcn-svelte components are the foundation.** New UI elements should be built by composing existing shadcn-svelte primitives (Button, Card, Dialog, Table, etc.). Custom CSS is allowed only for layout refinements, not to recreate an existing component from scratch.
- **Dark mode must use Tailwind’s `dark:` variant.** Any component that changes appearance in dark mode should use the `dark:` modifier with the corresponding token. Never write separate dark-mode CSS files or duplicate components.
- **Responsive design uses the default breakpoints.** Build mobile-first. Use `sm:`, `md:`, `lg:`, and `xl:` prefixes as needed. The sidebar collapse at small screens is the standard pattern.

## API Routes (SvelteKit → Golem)

- **JWT validation is mandatory.** Every request to an API route must be checked by the server hook. If the token is missing, expired, or tampered with, the route must return `401 Unauthorized` before any proxy call.
- **Enforce auth and ownership before any mutation.** For any state-changing request (submission, grading, user activation), the route must verify the authenticated user’s role and, if relevant, that they own the resource or have explicit admin permission.
- **Return consistent, predictable response shapes.** Every API response must follow a standard envelope:
  ```json
  {
    "data": { ... }     // present on success
    "error": {           // present on failure
      "code": "ACTIVATION_REQUIRED",
      "message": "Account not activated. Please contact your school administrator."
    }
  }
  ```
  No other top-level keys. Status codes must be semantically correct.
- **Never bypass the Ephemeral Gateway.** All SvelteKit-to-Golem calls must target the gateway agent endpoint. Direct calls to a User Agent’s URL are forbidden, as they circumvent the activation check.

## Data and Storage

- **Agent-local state uses SQLite exclusively.** Every durable agent stores its structured data in its embedded SQLite database. The database file is the single source of truth for that agent’s state.
- **Schema migrations are mandatory on agent startup.** The agent’s initialisation code must read `PRAGMA user_version`, compare against the expected version, and run only the necessary migration steps within a transaction. Migrations must be idempotent.
- **Metadata belongs in the agent’s SQLite; lesson content belongs in SurrealDB.** User profiles, rosters, assignments, submissions, and grades are agent-local SQLite data. AI-generated lesson text, question banks, and media references are SurrealDB documents, cached by agents.
- **Do not store large content directly in the agent’s database.** Lesson content cached in SQLite is acceptable for performance, but the authoritative copy is in SurrealDB. The cache must have a TTL and a maximum size limit.
- **HTTP calls to SurrealDB must be deterministic.** Use Golem’s HTTP client so that responses are recorded in the operation log. On replay, the logged response is replayed instead of a new network call.
- **Cache invalidation follows a stale-while-revalidate pattern.** When cached lesson data exceeds its TTL, the agent returns the stale data immediately and triggers an asynchronous refresh. The next request benefits from the fresh data.

## File Organization

```
school-management/
├── moon.work                  # MoonBit workspace manifest
├── agents/                    # Golem backend — all agent components
│   ├── golem.yaml             # Root app manifest
│   ├── common-wit/            # Shared WIT dependencies (wit-deps)
│   ├── admin-agent/           # Durable Admin Agent (singleton)
│   ├── gateway-agent/         # Ephemeral Gateway Agent
│   ├── student-agent/         # Durable Student Agent (per-student)
│   └── teacher-agent/         # Durable Teacher Agent (per-teacher)
├── shared/                    # MoonBit library — shared types and pure logic
│   ├── moon.mod.json
│   └── src/
│       ├── types.mbt          # Domain types (User, Lesson, Assignment, etc.)
│       └── validation.mbt     # Shared validation functions
└── frontend/                  # SvelteKit application
    ├── package.json
    ├── svelte.config.js
    ├── vite.config.ts
    ├── src/
    │   ├── app.css            # Tailwind v4 @theme tokens
    │   ├── hooks.server.ts    # Auth and token validation
    │   ├── routes/
    │   │   ├── (auth)/        # Protected routes (dashboard, lms, admin)
    │   │   └── login/         # Public login redirect
    │   └── lib/
    │       ├── components/    # shadcn-svelte components
    │       └── utils.ts       # Small helper functions
    └── static/
```

**Rules for each directory:**

- `agents/`: Each subdirectory is a standalone Golem component with its own `golem.yaml`, `wit/`, and `src/`. They must not import sibling components directly; communication is exclusively via WIT-defined RPC.
- `shared/`: Contains only MoonBit modules that compile for both `wasm-gc` (Golem) and `js` (SvelteKit). No I/O, no filesystem, no network. Pure types and functions only.
- `frontend/src/routes/`: Follow SvelteKit conventions. Group routes by role inside `(auth)/`. Server endpoints go in `+page.server.ts` or `+server.ts` files. Client-side components belong in the `lib/` folder.
- `frontend/src/lib/components/`: Each shadcn-svelte component lives in its own file. Custom composition components go here as well. No business logic.
- `static/`: Assets like fonts and images. No generated content.
