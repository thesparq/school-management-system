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
- **Prefer shadcn semantic tokens for UI surfaces.** Use `text-foreground`/`text-muted-foreground`/`bg-background`/`bg-muted`/`bg-accent`/`border-border`/`text-destructive`/`bg-destructive` for all UI elements. Avoid raw theme color classes (`text-surface-*`, `bg-white`, `bg-surface-*`, `border-surface-*`, `text-error-*`, `bg-error-*`) in component templates.
- **Follow the semantic colour scale.** `primary-*` for main actions and navigation, `secondary-*` for highlights and badges, `success-*` for completion states, `error-*` for destructive actions or overdue indicators, and `surface-*` for backgrounds and cards. Never swap these meanings.
- **shadcn-svelte components are the foundation.** New UI elements should be built by composing existing shadcn-svelte primitives (Button, Card, Dialog, Table, etc.). Custom CSS is allowed only for layout refinements, not to recreate an existing component from scratch.
- **Dark mode must use Tailwind’s `dark:` variant.** Any component that changes appearance in dark mode should use the `dark:` modifier with the corresponding token. Never write separate dark-mode CSS files or duplicate components. A sync `<script>` in `app.html` applies the `dark` class before first paint to prevent flash.
- **Responsive design uses the default breakpoints.** Build mobile-first. Use `sm:`, `md:`, `lg:`, and `xl:` prefixes as needed. The sidebar collapse at small screens is the standard pattern.
- **Global cursor classes:** `@layer base` in `app.css` applies `cursor-pointer` to all buttons, links, checkboxes, radio buttons, and selects; `cursor-not-allowed` to disabled elements.

## API Routes (SvelteKit → Golem)

- **JWT validation is mandatory.** Every request to an API route must be checked by the server hook. If the token is missing, expired, or tampered with, the route must return `401 Unauthorized` before any proxy call.
- **Map error codes to HTTP statuses.** Use `mapErrorCodeToHttpStatus()` from `golem.ts` to convert backend `AppError` codes to proper HTTP status codes. Never hardcode `502` for all errors.
- **Structured errors only.** All agent methods return structured JSON errors (`{"error":{"code":"...","message":"..."}}`). The proxy layer must parse these and propagate the code + message to the frontend. Never pass raw error strings through.


## Data and Storage

- **SurrealDB owns facts. Agents own work in progress.** Entity data (user profiles, teacher assignments, class rosters, grades, lessons) lives in SurrealDB. Agent durable state is reserved for in-progress work and cache.
- **Every cache must declare its strategy.** Choose between Push Invalidation (Rule 4A), TTL (Rule 4B), or No Cache (Rule 4C). Document the strategy in the struct field comment.
- **Do not store canonical entity data in agent struct fields.** The SSOT is always SurrealDB. Agent state fields are ephemeral cache or in-progress work only.
- **HTTP calls to SurrealDB must be deterministic.** Use Golem's HTTP client so that responses are recorded in the operation log. On replay, the logged response is replayed instead of a new network call.
- **Cache TTL with synchronous refresh.** When cached data exceeds its TTL, the next request waits for a fresh fetch from SurrealDB. No background refresh.
- **DB writes that are atomic with notifications must use `with_atomic_operation`.** When a DB write and a fan-out RPC must happen together, wrap them so crash recovery replays both.
- **All DB writes inside `with_atomic_operation` must be idempotent.** Use upsert semantics (`ON DUPLICATE KEY UPDATE`, `UPDATE ... SET deleted_at`) — never plain inserts.
- **Soft deletes everywhere.** Every table has a `deleted_at` field. All queries filter `deleted_at IS NONE`. Never hard-delete records.
- **Agent recreation is never a crisis.** Because entity data lives in DB, any agent can be rebuilt via `init()`/`reconcile()` reading from SurrealDB.

## Cache Convention

Every cache operation must follow this reactive pattern. There are exactly three blocks for every cached data type. The pattern is identical across all agents — only the cache key, `CacheData` variant, and DB query differ.

### Cache Contract

| State | Behavior |
|-------|----------|
| No cache key | Full fetch from DB |
| Cache hit + TTL valid + non-empty | Return cached data immediately |
| Cache hit + TTL expired | Fall through to DB query |
| DB returns rows | Cache the typed result, return `Ok(data)` |
| DB returns empty `[]` or error | **Never cache** — return `Err(AppError)` |
| Cache invalidation | Delete cache key entirely (parent keys cascade to children) |

### Code Pattern

Every cached data method follows this exact structure. Copy the template and replace `Variant`, `cache_key`, SQL, and error message.

**READ (cache hit check):**
```moonbit
  let now = @wallClock.now().seconds
  let cache_key = "<descriptive key>"   // may include dynamic parts
  let cached = self.caches.get(cache_key)
  match cached {
    Some(item) if now - item.fetched_at < CACHE_TTL =>
      match item.data {
        Variant(arr) if arr.length() > 0 => return Ok(arr)
        _ => ()   // fall through to DB
      }
    _ => ()       // fall through to DB
  }
```

**FETCH (DB query — goes between READ and WRITE):**
```moonbit
  let sql = "<SurrealQL query here>"
  let result_arr = match surreal_query(self.config.value, sql) {
    Ok(arr) => arr
    Err(_) => {
      // Stale-fallback: serve cached data on DB error
      match cached {
        Some(item) =>
          match item.data {
            Variant(arr) if arr.length() > 0 => return Ok(arr)
            _ => ()
          }
        _ => ()
      }
      return Err(AppError::{
        code: SurrealDBError,
        message: "Failed to query <description> from database",
        detail: None,
      }.to_json_string())
    }
  }
  // ... build results array from result_arr ...
```

**WRITE (cache and return — after building results array):**
```moonbit
  if results.length() == 0 {
    return Err(AppError::{
      code: NotFound,
      message: "<User-facing message>",
      detail: None,
    }.to_json_string())
  }
  self.caches.set(cache_key, CacheItem::{
    data: Variant(results),
    fetched_at: now,
  })
  Ok(results)
```

### Cache Invalidation — Parent-Child Dependency

Every agent's `invalidate_cache` endpoint declares dependencies using backbone keys. When a backbone key is invalidated, all dependent caches are also cleared:

```moonbit
pub fn Agent::invalidate_cache(self, incoming_key, key) -> String {
  match require_auth(self.config.value, incoming_key) {
    Err(e) => return e.to_json_string()
    Ok(_) => ()
  }
  if key == "all" || key == "<backbone_key>" {
    self.caches = Map::new()   // clear all dependent caches
  } else {
    self.caches.remove(key)     // targeted removal
  }
  "OK"
}
```

| Agent | Backbone Key | Effect |
|-------|-------------|--------|
| Student | `"profile"` | Clears all caches (profile, subjects, terms, lessons) |
| Teacher | `"class_groups"` | Clears all caches |

### Invariants

- **Empty results never cached.** All cache writes are guarded by `results.length() > 0`.
- **Stale-fallback always has a length guard.** Even when serving stale cache on DB error, the guard `if arr.length() > 0` must be present.
- **No negative caching.** Failed queries never write a `CacheData::Empty` sentinel or any negative state.
- **TTL is always 600 seconds** (`CACHE_TTL : UInt64 = 600` in `cache_types.mbt`). All `fetched_at` timestamps come from `@wallClock.now().seconds`.
- **`CacheItem` has exactly two fields:** `data : CacheData` and `fetched_at : UInt64`. No `invalidated` field (invalidation = key deletion).

## File Organization

```
school-management/
├── moon.work                  # MoonBit workspace manifest
├── agents/                    # Golem backend — single component
│   ├── golem.yaml             # Root app manifest
│   ├── app-agents/            # All agent types in one WASM component
│   │   ├── moon.pkg           # Package config (is-main, merged imports)
│   │   ├── main.mbt            # Entry point
│   │   ├── errors.mbt          # AppError, ErrorCode, structured error types
│   │   ├── config.mbt          # SharedConfig, SurrealCfg, AuthentikCfg
│   │   ├── http_client.mbt     # Shared WASI HTTP request/response helper
│   │   ├── auth.mbt            # require_auth() helper
│   │   ├── validation.mbt      # Input validation functions (email, password, role, etc.)
│   │   ├── surreal_client.mbt  # SurrealDB HTTP client (queries /sql endpoint)
│   │   ├── authentik_client.mbt # Authentik REST API client (user CRUD, groups)
│   │   ├── cache_types.mbt     # CacheData enum, CacheItem struct, CACHE_TTL
│   │   ├── admin_agent.mbt     # Durable Admin Agent (singleton, HTTP)
│   │   ├── student_agent.mbt  # Durable Student Agent (per-student, HTTP)
│   │   └── teacher_agent.mbt  # Durable Teacher Agent (per-teacher, HTTP)
│   └── common-wit/            # Shared WIT dependencies (wit-deps)
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
    │   │   ├── +layout.svelte # Root layout (sidebar, nav, breadcrumbs)
    │   │   ├── +page.svelte   # Root page (LMS subjects for students, My Classes for teachers, dashboard for admins)
    │   │   ├── lms/           # Student LMS routes (subjects → terms → lessons)
    │   │   │   └── [subjectId]/
    │   │   │       └── [termId]/
    │   │   │           └── [lessonId]/
    │   │   │               └── +page.svelte   # Wrapper → LessonPage
    │   │   ├── my-classes/    # Teacher class browsing
    │   │   │   └── [classId]/
    │   │   │       └── [subjectId]/
    │   │   │           └── [termId]/
    │   │   │               ├── +page.svelte
    │   │   │               └── [lessonId]/
    │   │   │                   └── +page.svelte   # Wrapper → LessonPage
    │   │   ├── admin/         # Admin routes (user management, configuration)
    │   │   │   ├── users/
    │   │   │   └── configuration/
    │   │   │       └── session-terms/
    │   │   └── api/           # Proxy routes to Golem gateway
    │   └── lib/
    │       ├── components/    # shadcn-svelte components + LessonPage.svelte + SidebarLogo.svelte + PageHeader.svelte
    │       │   └── ui/skeleton/
    │       │       └── PageSkeleton.svelte  # Reusable loading skeleton (list/grid/card)
    │       └── utils.ts       # Small helper functions
    └── static/
```

**Rules for each directory:**

- `agents/`: A single `app-agents/` component holds all agent types and shared modules sharing one WASM binary. All files share the same MoonBit package namespace so typed RPC clients are generated for every agent and usable by every other agent. Shared modules (`errors.mbt`, `config.mbt`, `http_client.mbt`, `auth.mbt`, `validation.mbt`, `surreal_client.mbt`, `authentik_client.mbt`, `cache_types.mbt`) are co-located in the same directory — MoonBit does not require separate directories for code organization within a package. Agent-to-agent RPC uses the idiomatic `<AgentName>Client::scoped(...)` pattern.
- `shared/`: Contains only MoonBit modules that compile for both `wasm-gc` (Golem) and `js` (SvelteKit). No I/O, no filesystem, no network. Pure types and functions only.
- `frontend/src/routes/`: Follow SvelteKit conventions. Routes are organised by feature/role. Server endpoints go in `+page.server.ts` or `+server.ts` files. Client-side components belong in the `lib/` folder.
- `frontend/src/lib/components/`: Each shadcn-svelte component lives in its own file. Custom composition components go here as well. No business logic.
- `static/`: Assets like fonts and images. No generated content.

## UI Feedback Conventions

Choose the right feedback channel based on context:

| Channel | When | Component |
|---------|------|-----------|
| **Toast** | Transient operation feedback (create/edit/delete/activate success or failure) | `addToast(variant, title, desc)` |
| **StatusCard** | Persistent page-level state (empty data, error loading, not initialized, warnings) | `<StatusCard variant="error" ...>` |
| **Inline error** | Form validation errors close to the input | `<p class="text-error-500">{error}</p>` |

### Toast Usage

```typescript
import { addToast } from '$lib/stores/toast';

addToast('success', 'User created', 'John Doe (jdoe)');
addToast('error', 'Save failed', err.message);
addToast('warning', 'Stale data', 'Refresh to see latest changes.');
addToast('info', 'User activated', 'jdoe is now active.');
```

Four variants: `success` (green), `info` (blue), `warning` (amber), `error` (red). Default duration: 5000ms. Progress bar pauses on hover. Auto-dismiss on expiry or manual close.

**Do NOT use** `alert()`, `confirm()`, or raw `window.alert` in production code. Use toast for all operational feedback.
