# Architecture

## Stack

| Layer | Technology | Version | Role |
| :--- | :--- | :--- | :--- |
| Identity Provider | Authentik | 2025.12+ | OIDC authentication, JWT issuance, user directory, admin API for user lifecycle management |
| Frontend Framework | SvelteKit | ~2.50 | Server-side rendering, routing, UI server, and the sole authentication proxy to the backend |
| Styling | Tailwind CSS | v4.x | Utility-first CSS via the CSS-first `@theme` directive (no `tailwind.config.js`); Oxide engine for fast builds |
| Component Library | shadcn-svelte | latest | Copy-paste UI primitives (Button, Card, Dialog, Table, Sidebar, Breadcrumb, etc.) built on Svelte 5 runes and Tailwind v4 |
| Shared Logic Language | MoonBit | v0.9.x | All business logic, data transformations, validation, and type definitions; compiled to JavaScript (frontend) and WASM (backend) from a single codebase |
| Frontend Integration | vite-plugin-moonbit | v0.2.1 | Enables `import { … } from "mbt:…"` in SvelteKit; auto-starts `moon build --watch` in development; supports JS and WASM-GC backends, monorepo workspaces, HMR, and source maps |
| Backend Compute | Golem Cloud | v1.5.3 | Durable agent runtime; agents compiled from MoonBit to WASM components with WIT interfaces; provides transactional durable execution, exactly-once worker-to-worker RPC, idle-to-zero suspend/resume, and built-in HTTP API gateway |
| Agent-local Storage | Agent Struct Fields (Durable Memory) | Golem op‑log | State stored in agent struct fields, persisted by Golem's durable execution op‑log; survives restarts and replays without external databases |
| Content Database | SurrealDB | 3.0 | Multi-model document/graph/vector database storing AI-generated lesson content; agents access it via HTTP using `golemcloud/golem_sdk/http` |

## Monorepo Structure & Tooling Setup

The project is organised as a single monorepo with three top‑level directories. MoonBit’s workspace feature (`moon.work`) is used so that the shared module is available to both the `agents` and `frontend` modules, and `vite-plugin-moonbit` resolves `mbt:shared/…` imports at build time.

```
school-management/
├── moon.work                    # Workspace manifest
├── agents/                      # Golem backend
│   ├── moon.mod.json
│   ├── golem.yaml               # Root app manifest
│   ├── app-agents/              # Single component — all agent types
│   │   ├── moon.pkg             # Package config (merged imports, is-main)
│   │   ├── admin_agent.mbt      # Durable Admin Agent (singleton)
│   │   ├── gateway_agent.mbt    # Ephemeral Gateway Agent
│   │   ├── student_agent.mbt    # Durable Student Agent (per-student)
│   │   └── teacher_agent.mbt    # Durable Teacher Agent (per-teacher)
│   └── common-wit/              # Shared WIT dependencies
│       └── deps/                # wit-deps output
├── shared/                      # MoonBit shared library
│   ├── moon.mod.json
│   ├── moon.pkg.json
│   └── src/
│       ├── types.mbt            # Shared domain types
│       ├── validation.mbt       # Shared validation logic
│       └── ...
└── frontend/                    # SvelteKit application
    ├── package.json
    ├── svelte.config.js
    ├── vite.config.ts
    ├── src/
    │   ├── app.css              # Tailwind v4 @theme + @import
    │   ├── hooks.server.ts      # Authentik JWT validation
    │   ├── routes/
    │   │   ├── +layout.svelte   # Root layout (sidebar, nav, breadcrumbs)
    │   │   ├── +page.svelte     # Root page (LMS subjects for students, dashboard for admins)
    │   │   ├── lms/             # LMS routes (subjects → terms → lessons)
    │   │   ├── admin/           # Admin routes (user management)
    │   │   └── api/             # Proxy routes to Golem gateway
    │   └── lib/
    │       ├── components/      # shadcn-svelte components
    │       └── utils.ts
    └── static/
```

### Initial Setup Commands

**1. Install CLI tools:**

```bash
# MoonBit toolchain
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash

# Golem CLI (via cargo)
cargo install golem-cli

# SvelteKit project scaffolding
npx sv create frontend
```

**2. Initialise the MoonBit workspace:**

```bash
# Create the shared module
moon new shared --lib

# Create the agents module
moon new agents --lib

# Initialise workspace and register both members
moon work init shared agents
```

This produces a `moon.work` file:

```toml
members = ["./shared", "./agents"]
```

Each agent component is a Golem application component within the `agents` workspace member, defined by its own `golem.yaml`.

**3. Create Golem application and agent components:**

```bash
cd agents
golem new --template moonbit --component-name app:agents .
```

The scaffold produces a `app-agents/` directory. All four agent types (Admin, Gateway, Student, Teacher) live in this single component, sharing one WASM binary and one set of generated typed RPC clients. This enables type-safe agent-to-agent calls using `<AgentName>Client::scoped(...)` without cross-component bridging.

The `golem new --template moonbit` command scaffolds a MoonBit Golem component with:
- `golem.yaml` – per-component manifest with build profiles and WIT directories
- `wit/` – WIT interface definitions for the component's API
- `moon.pkg.json` – MoonBit package configuration with Golem SDK dependencies
- `src/main.mbt` – agent entry point

**4. Set up the frontend:**

```bash
cd frontend
npx sv add tailwindcss
npx shadcn-svelte@latest init
pnpm add -D vite-plugin-moonbit
```

Configure `vite.config.ts`:

```ts
import { defineConfig } from 'vite';
import { sveltekit } from '@sveltejs/kit/vite';
import { moonbit } from 'vite-plugin-moonbit';

export default defineConfig({
  plugins: [
    moonbit({
      root: '..',        // monorepo root (contains moon.work)
      target: 'js',       // JavaScript backend for SvelteKit
      watch: true,        // auto moon build --watch in dev
    }),
    sveltekit()
  ]
});
```

**5. Build and deploy the Golem application:**

```bash
cd agents
golem app build
golem deploy --cloud
```

The Golem CLI's `app build` command compiles all MoonBit components to WASM, processes WIT bindings, and links worker-to-worker RPC stubs. `golem deploy` atomically deploys all components to Golem Cloud.

## System Boundaries

Every line of code lives in one of three security domains. A request never skips a domain or calls backwards.

### Frontend (SvelteKit — `frontend/`)

- **Rendering**: Svelte 5 components with runes (`$state`, `$derived`, `$effect`); shadcn-svelte primitives; Tailwind CSS v4 utilities configured via `@theme` in `app.css`.
- **Server-side hooks** (`src/hooks.server.ts`): Validates the Authentik JWT on every request using Authentik's JWKS endpoint, extracts the internal `user_id` and roles, and stores them in `locals` for downstream load functions and actions.
- **API routes** (`src/routes/api/`): Thin proxy handlers. They read `user_id` from `locals`, construct a request to the Golem API Gateway (targeting the Ephemeral Gateway Agent), and return the response. They never query a database.
- **MoonBit modules**: Imported via `mbt:shared/…` prefix. Used for shared validation, data transformations, and type definitions that must be identical on both frontend and backend. The `vite-plugin-moonbit` plugin resolves these imports from the workspace `_build/` directory.
- **No database credentials, no Golem internal addresses, and no internal agent IDs are ever exposed to the browser.**

### Backend Proxy (SvelteKit server — same process, logical boundary)

- **Authentik token validation**: Uses Authentik's JWKS endpoint (RS256-signed JWTs) with cached public keys.
- **User ID extraction**: Reads the `sub` claim and maps it to the internal stable user identifier.
- **Golem API Gateway calls**: All calls are server-to-server over HTTPS. The gateway URL and any service-level credentials are stored in environment variables on the SvelteKit host.
- **Network firewall**: Only the SvelteKit server's static IP is whitelisted to reach the Golem API Gateway. Golem's built-in OIDC support is **not** used; all auth is handled by the SvelteKit proxy.

### Golem Cloud Backend (agents — `agents/`)

All agents are defined in the single `app:agents` component (`app-agents/`). They share one WASM binary, and the `golem-sdk-tools agents` step generates typed RPC clients for every agent type so intra-component calls use `<AgentName>Client::scoped(...)` with full type safety.

| Agent Type | Mode | Instances | Responsibility |
| :--- | :--- | :--- | :--- |
| **Ephemeral Gateway Agent** (`GatewayAgent`) | Ephemeral | One per HTTP request | Stateless gatekeeper. Checks activation status via Admin Agent RPC, then forwards the request to the target User Agent or returns an error. The sole HTTP-facing agent. **Does not hold SurrealDB credentials** — only Admin, Student, and Teacher agents query the database via the internal `surreal_client` helper. |
| **Admin Agent** (`AdminAgent`) | Durable | One (singleton) | Central registry (receptionist), user initialization orchestrator, gatekeeper for user agent creation, relationship manager, and long-running task dispatcher. Tracks initialization state only — activation/deactivation is handled by SvelteKit via Authentik API. Accessed via RPC only (no HTTP mount). |
| **Student Agent** (`StudentAgent`) | Durable | One per student | Owns all student state: class, subjects, cached lesson metadata, assignment configurations, submissions, and grades. |
| **Teacher Agent** (`TeacherAgent`) | Durable | One per teacher | Owns teacher state: assigned classes/subjects, class rosters, assignment definitions, submission inbox (projection), and grading records. |

### SurrealDB

- **Accessed only by Golem agents** via HTTP using the `golemcloud/golem_sdk/http` package with HTTP Basic Auth.
- Stores canonical entity data: user profiles (`user_profile`), teacher assignments (`teacher_assignment`), curriculum structure (`has_subject`), lesson content (`lessons`), and future assignment/submission/grade records.
- Golem automatically persists all outgoing HTTP requests and responses in the agent's operation log. On replay, the response is read from the log rather than re-executing the network call, ensuring deterministic behaviour.

## Storage Model

### SurrealDB — Schema v2 (Idiomatic Graph/Document)

The database uses SurrealDB's idiomatic multi-model approach. Navigation fields are strictly typed (`SCHEMAFULL` with `ASSERT $value != NONE`), while content payloads are loosely typed as `array` to accommodate AI output drift. A `TYPE RELATION` graph edge replaces the relational junction table.

**Lookup tables (meaningful record IDs, no `active` field):**

| Table | Key Fields | Purpose |
|---|---|---|
| `subjects` | `name` (unique), `code?` | All curriculum subjects (e.g., "Basic Science", "Mathematics") |
| `class_levels` | `name` (unique), `age_range?` | All class/year levels (e.g., "Primary 1", "JSS 1") |
| `terms` | `name` (unique), `sort_order`, `active` | Academic terms: "First Term" (1), "Second Term" (2), "Third Term" (3) |

**Graph edge — `has_subject` (`TYPE RELATION`):**

Defines which subjects belong to which class as a native SurrealDB edge. Enables graph traversal without JOINs.

| Field | Type | Notes |
|---|---|---|
| `in` | `record<class_levels>` | Auto-generated by `TYPE RELATION FROM class_levels` |
| `out` | `record<subjects>` | Auto-generated by `TYPE RELATION TO subjects` |
| `active` | `bool` | Default `true`. Toggle to hide a subject for a class. |

Unique index on `COLUMNS in, out` prevents duplicate edges. Index on `in` accelerates dashboard query.

**`user_profile` table (SCHEMAFULL, new):**

Replaces `AdminAgent.initialized_users` and `StudentAgent.profile`. Single user metadata table for all roles.

| Field | Type | Notes |
|---|---|---|
| `auth_id` | `string` | Authentik `sub` claim (UUID). Unique. |
| `role` | `string` | `"admin"`, `"teacher"`, or `"student"` |
| `class_level` | `option<string>` | Record ID (e.g. `"class_levels:jss_1"`). Only for students. |
| `created_at` | `datetime` | When the user agent was initialized |
| `updated_at` | `option<datetime>` | Last profile update |
| `deleted_at` | `option<datetime>` | Soft-delete timestamp |

Unique index on `auth_id` prevents duplicates.

**`teacher_assignment` table (SCHEMAFULL, new):**

Replaces `AdminAgent.teacher_assignments`. Maps teacher → class_level → subject. Supports multiple teachers per class-subject pair via separate rows.

| Field | Type | Notes |
|---|---|---|
| `teacher_id` | `string` | Teacher's auth_id |
| `class_level_id` | `string` | Record ID (e.g. `"class_levels:jss_1"`) |
| `subject_id` | `string` | Record ID (e.g. `"subjects:basic_science"`) |
| `assigned_at` | `datetime` | When this assignment was created |
| `deleted_at` | `option<datetime>` | Soft-delete timestamp |

Unique index on `(teacher_id, class_level_id, subject_id)` prevents duplicate assignments for the same teacher.

**`lessons` table (SCHEMAFULL, renamed from `lesson_content`):**

| Navigation Field | Type | Notes |
|---|---|---|
| `class_subject` | `record<has_subject>` | FK to the edge — guarantees the class-subject pair is registered |
| `term` | `record<terms>` | FK to the terms table |
| `week` | `int` | Week number within the term (1-based) |
| `topic_title` | `string` | Lesson title |
| `active` | `bool` | Default `true`. Toggle to hide a lesson. |
| `duration_mins` | `int` | Lesson duration in minutes |

Content fields (`objectives`, `content_sections`, `key_points`, `lesson_steps`, `mcq_questions`, `theoretical_questions`, `materials`, `prior_knowledge`, `success_criteria`, `extension_activities`, `textbook_references`) and string fields (`introduction`, `conclusion`, `formative_assessment`, `summative_assessment`, `remediation`, `teacher_tips`) are typed as `FLEXIBLE TYPE array<object>` / `string` — the MoonBit agent code is the real validation layer. `FLEXIBLE` prevents SCHEMAFULL from silently stripping nested object properties when no explicit `field.*.property` definitions exist.

**Indexes:**

| Index | Fields | Purpose |
|---|---|---|
| `idx_cl_name` | `name` (unique) | Class-level lookup by name (drives dot-traversal queries) |
| `idx_hs_unique` | `in, out` (unique) | Prevent duplicate class-subject edges |
| `idx_hs_in` | `in` | Lookup: find all has_subject edges for a class |
| `idx_lessons_nav` | `class_subject, term, week` | Lesson navigation: lessons for a given subject+term |
| `idx_lessons_term` | `class_subject, term` | Which terms have lessons for a subject |

**Deprecation note:** The original `lesson_content` table remains intact for legacy systems. All new queries target `lessons`. After all legacy consumers are migrated, `lesson_content` can be dropped.

Agents query via HTTP using the `surreal_client` module (`agents/app-agents/surreal_client.mbt`), which wraps WASI HTTP POST requests to `https://{host}/sql` with HTTP Basic Auth (`username:password` base64-encoded). Namespace and database are sent as `surreal-ns` / `surreal-db` headers.

A shared `SurrealConfig` struct defines all 5 connection parameters as Golem secrets:

```moonbit
#derive.config
pub(all) struct SurrealConfig {
  host      : @config.Secret[String]
  ns        : @config.Secret[String]
  database  : @config.Secret[String]
  username  : @config.Secret[String]
  password  : @config.Secret[String]
}
```

`SurrealConfig` is used by all agents that need SurrealDB access (`StudentAgent`, `TeacherAgent`, future `AdminAgent` SurrealDB methods). Each agent gets one `@config.Config[SurrealConfig]` field injected via its constructor. The `surreal_query(config, sql)` function resolves all 5 secrets internally with proper `match`-based error handling — no `.unwrap()` panics on network operations.

Only **Admin Agent**, **Student Agent**, and **Teacher Agent** hold SurrealDB credentials. The **Gateway Agent** never stores DB credentials — its `/gateway/db-test` endpoint calls `StudentAgentClient::scoped(fn(student) { student.test_db() })` via typed RPC.

### Agent Durable State

Every durable agent stores its state in MoonBit struct fields. Golem's durable
execution op‑log persists these fields across restarts and replays — no external
database, no migration scripts. New fields are added with safe defaults.

Following the **Two Layers, Clear Separation** principle (see Architecture Principles below), agent durable state is reserved for in-progress work and active session context. Completed facts and canonical entity data live in SurrealDB.

**Admin Agent struct fields:**

| Field | MoonBit Type | Purpose | Storage |
| :--- | :--- | :--- | :--- |
| `config` | `@config.Config[SurrealConfig]` | Injected DB credentials | Secret |
| *(removed)* | — | `initialized_users` → `user_profile` table | DB |
| *(removed)* | — | `teacher_assignments` → `teacher_assignment` table | DB |

**Student Agent struct fields:**

| Field | MoonBit Type | Purpose | Strategy |
| :--- | :--- | :--- | :--- |
| *(removed)* | — | `profile` → `user_profile` table | DB |
| `subject_cache` | `SubjectCache?` | Cached subject list (TTL 600s) | TTL cache (Rule 4B) |
| `terms_cache` | `Map[String, TermCacheEntry]` | Cached terms per class level (TTL 600s) | TTL cache (Rule 4B) |
| `lessons_cache` | `Map[String, LessonCacheEntry]` | Cached lessons per key (TTL 600s) | TTL cache (Rule 4B) |
| `edge_cache` | `Map[String, EdgeCacheEntry]` | Cached `has_subject` edge IDs | Pre-populated on init |
| `lesson_cache` | `Map[String, LessonContentCache]` | Cached full lesson content (TTL 600s) | TTL cache (Rule 4B) |

**Teacher Agent struct fields:**

| Field | MoonBit Type | Purpose | Strategy |
| :--- | :--- | :--- | :--- |
| `class_groups` | `Map[String, TeacherClassGroup]` | Grouped class-subject cache | Push invalidation (Rule 4A) — cleared via `invalidate_cache()` RPC, re-reads from DB |
| *(not yet moved)* | — | `rosters`, `assignments`, `submission_inbox`, `grading` | Still in agent state (future DB migration) |

### Agent Memory Cache

Each durable agent maintains an in-memory cache (backed by Golem's durable memory) for frequently accessed data: subject lists, term lists, lesson metadata, and `has_subject` edge record IDs. Cache entries have a single configurable TTL (default: 600 seconds). On cache miss or TTL expiry, the next request fetches fresh data from SurrealDB. Subsequent requests within the TTL window read from cache — instant.

## Auth & Access Model

### Authentication Flow

```
Browser → SvelteKit (no session) → Redirect to Authentik /authorize
Authentik → Browser (JWT in HTTP-only cookie)
Browser → SvelteKit (with JWT) → hooks.server.ts validates JWT → extracts user_id + roles
```

- JWT validation uses Authentik's public signing keys (fetched from the JWKS endpoint and cached).
- No server-side sessions. The JWT is the sole credential.
- Tokens are short-lived (15–60 minute access tokens) with refresh token rotation.
- The `user_id` is extracted server-side and stored in `locals`; it is **never** exposed to the browser.

### Authorization (Role-Based Access)

Roles are embedded in the Authentik JWT claims. SvelteKit checks roles in `hooks.server.ts` and in per-route `+page.server.ts` load functions:

| Role | Allowed Routes |
| :--- | :--- |
| `student` | `/lms/*`, `/assignments/*`, `/grades/*` |
| `teacher` | `/my-classes/*`, `/lms/*` (teaching view), `/assignments/*` (grading view), `/students/*` |
| `admin` | `/admin/*` (user management, content management) |
| `parent` | Future |

### Agent-Level Access Control

After SvelteKit validates the JWT, it proxies the request to the Golem API Gateway, targeting the Ephemeral Gateway Agent and passing `user_id` as a path parameter:

1. **Ephemeral Gateway Agent** calls `AdminAgent.is_user_initialized(user_id)` via RPC.
2. If initialized, the gateway forwards the request to the target User Agent.
3. If not initialized, the gateway returns `"NOT_INITIALIZED"` which SvelteKit translates to `403 Forbidden` with the message "Account not initialized. Please contact your school administrator."
4. Authentik activation/deactivation is handled entirely by SvelteKit API routes (`/api/admin/users/[uuid]/activate-authentik` and `deactivate-authentik`), not by Golem agents.

This gatekeeper pattern ensures that a user agent can **never** be implicitly created by an unauthorized request. An agent exists only after an admin explicitly initializes the user.

### Network-Level Security

- Only the SvelteKit server's static IP is whitelisted to reach the Golem API Gateway.
- Golem's built-in OIDC support is **not** used; all auth is handled by the SvelteKit proxy.
- **Authentik Admin API** is accessed server-to-server using a service account Bearer token (`AUTHENTIK_SERVICE_ACCOUNT_TOKEN`). The token is sent as `Authorization: Bearer <token>` to `https://{AUTHENTIK_HOST}/api/v3/core/users/`. No OAuth2 flow, no token caching — the token is self-contained.
- The admin user list filters users to only those belonging to `admin`, `students`, or `teachers` groups (by group name). Group PKs are fetched from `GET /api/v3/core/groups/` and cross-referenced against each user's `groups` array.
- Agent-to-agent RPCs happen entirely within Golem's secure infrastructure; they are not exposed to the public internet.

## AI & Background Task Models

### Assignment Push (Fire-and-Forget)

When a teacher creates or updates an assignment, the Teacher Agent pushes the configuration to all students in the class:

1. Teacher Agent receives `configureAssignment` from the UI (via SvelteKit → Gateway → Teacher Agent).
2. Teacher Agent stores the assignment in its struct fields.
3. Teacher Agent iterates over its roster (obtained from Admin Agent during initialisation) and issues `StudentAgent.addOrUpdateAssignment(config)` as fire-and-forget RPCs.
4. The teacher UI receives a success response immediately.
5. Golem guarantees exactly-once delivery of each RPC. If a student agent is temporarily unreachable, delivery is retried with backoff.

Deadline enforcement happens at two levels:
- **Client-side (Student Agent)**: Checks `now > deadline` before sending the submission RPC. Returns immediate error if expired.
- **Server-side (Teacher Agent)**: Checks deadline again upon receipt. This is the authoritative check and handles clock skew.

The SvelteKit UI renders a deadline clock for students based on the deadline timestamp provided by the Teacher Agent.

### Long-Running Admin Tasks (Promise-Based)

For operations that may take significant time (future: bulk AI content generation), the Admin Agent uses a promise pattern:

1. Admin triggers the task in the UI.
2. SvelteKit calls `AdminAgent.startBackgroundTask(params)`.
3. The Admin Agent creates a Golem Promise, spawns an ephemeral forked agent (clone of the Admin Agent with current state), and fires a forget RPC to execute the work.
4. The Admin Agent immediately returns the `promise_id` to the UI.
5. The UI polls `AdminAgent.getPromiseResult(promise_id)` until the work completes.

Agent forking is efficient because Golem forks from the latest snapshot — it does not replay the entire operation log. Forking is deferred for MVP and will be introduced only when bulk operations are needed.

### Content Caching

Subject lists, term lists, lesson content, and edge record IDs are cached in each agent's in-memory maps with a configurable TTL (default: 600 seconds). On cache miss or TTL expiry, the next request fetches fresh data from SurrealDB. No background refresh — the edge cache is pre-populated during initialization, so lesson queries never need graph traversal after init.

## Architecture Principles

### Rule 1: Two Layers, Clear Separation

**SurrealDB owns facts. Agents own work in progress.**

| Store in SurrealDB | Store in Agent Durable State |
|---|---|
| Any data a human admin would care about | In-progress job state (step N of M) |
| Anything another agent needs to query | Current draft not yet committed |
| Completed operation outputs | Active session context |
| User profiles, assignments, enrollments | Retry counters, backoff state |
| Grades, lessons, curriculum structure | In-progress quiz answers |

**The test:** If this agent was deleted and recreated, would data be lost that the school cares about?
- Yes → it belongs in SurrealDB
- No → it can live in agent state

### Rule 2: Group DB Write + Agent Notification as an Atomic Operation

Use `with_atomic_operation` to wrap the DB write and the fan-out notification together.
This ensures that if the agent crashes between the two, both are replayed together on recovery.

### Rule 3: Every Agent Initialises from SurrealDB

Every agent must have a `reconcile()`/`init()` function that rebuilds its state from SurrealDB.
Agent recreation is never a crisis because entity data was never owned by the agent.

### Rule 4: Three Cache Strategies — Choose Per Data Type

Every cached field must have an explicit strategy:
- **Strategy A: Push Invalidation (Strong Consistency)** — Writer sends targeted RPC to affected agents after the DB write. Use when staleness is unacceptable.
- **Strategy B: TTL (Eventual Consistency)** — Agent re-queries after a time interval. Use when data changes rarely.
- **Strategy C: No Cache (Always Fresh)** — Query SurrealDB on every access. Use when data must be maximally fresh.

| Data Type | Strategy | Reason |
|---|---|---|
| Teacher assignment for a class | Push (A) | Admin action, immediate consistency |
| Student class assignment | Push (A) | Admin action, affects student immediately |
| Subject/Term/Lesson metadata | TTL (B) | Changes once per term |
| Lesson content | TTL (B) | Large, occasional access |

### Rule 5: Fan-Out via Parallel Durable RPC

When a change affects multiple agents, query SurrealDB for affected IDs, construct worker IDs
deterministically, fire parallel fire-and-forget calls. Discard the list after. Never store it.

### Rule 6: Deterministic Worker IDs — No Registries

Worker IDs are always constructed from entity IDs. Never store lists of agent IDs in other agents.
Never use Golem's worker enumeration API in application logic.

### Rule 7: RPC for Work, DB for Data

Use agent-to-agent RPC to request computation or send notifications.
Use SurrealDB directly to read entity data another agent wrote.

### Rule 8: Identity (Authentik) + Profile (SurrealDB)

Authentik owns authentication only. SurrealDB owns domain metadata.
The bridge is the `sub` claim from the JWT token.

### Rule 9: Soft Deletes Everywhere

Never hard-delete records. Set `deleted_at`. All queries filter `deleted_at IS NONE`.

### Rule 10: None is Valid State

After a deletion and cache invalidation, the next cache miss returns `None` from SurrealDB.
Design all data access to handle `None` gracefully — it means "does not currently exist."

## Invariants

These rules must never be violated by any code change, refactor, or new feature.

1. **SvelteKit never accesses SurrealDB or any agent-local storage.** All data flows through Golem agents. The SvelteKit backend is a pure proxy and has no database credentials.

2. **No durable User Agent is created without an explicit admin initialization.** The Ephemeral Gateway Agent must always check `AdminAgent.is_user_initialized(user_id)` before forwarding a request to a User Agent. Implicit agent creation via Golem's default behaviour is blocked by the gatekeeper.

3. **SurrealDB is the single source of truth for entity data.** User profiles, teacher assignments, and class rosters are stored in `user_profile` and `teacher_assignment` tables. Agent durable memory holds only ephemeral cache and in-progress work.

4. **Every durable agent writes its own profile to SurrealDB on initialization.** The Admin Agent fires RPC to create the User Agent; the User Agent writes its own `user_profile` record. The Admin Agent never writes profiles directly.

5. **Assignment deadlines are enforced authoritatively by the Teacher Agent.** The Student Agent performs a local check for immediate user feedback, but the Teacher Agent's timestamp comparison on receipt is the final word. The Teacher Agent's clock is the authority.

6. **Student-to-Teacher submission RPCs are sent directly, not routed through the Admin Agent or a central queue.** The Student Agent discovers the `teacher_id` via `AdminAgent.getTeacherFor(student_id, subject_id)` and caches it, then communicates directly with the Teacher Agent for all assignment operations.

7. **All agent-to-agent RPCs that modify state must be idempotent or use exactly-once semantics.** Golem's RPC provides exactly-once delivery, but method implementations should be safe to retry (e.g., upsert semantics, not blind insert).

8. **DB writes inside `with_atomic_operation` must be idempotent.** Because the block may replay on crash recovery, use upsert semantics (`ON DUPLICATE KEY UPDATE`, `UPDATE ... SET deleted_at`, etc.) — never plain inserts without duplicate checks.

9. **All records use soft deletes.** Every entity table has a `deleted_at` field. All application queries filter `WHERE deleted_at IS NONE`.

## Communication Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                       SvelteKit Server                             │
│  ┌──────────┐  ┌──────────────┐  ┌─────────────────────────────┐ │
│  │  Routes   │  │ hooks.server │  │  API Proxy (server-side)     │ │
│  │  (pages)  │  │ (JWT check)  │  │  → Golem API Gateway         │ │
│  └──────────┘  └──────────────┘  └─────────────────────────────┘ │
└──────────────────────┬───────────────────────────────────────────┘
                       │ HTTPS (IP-whitelisted)
                       ▼
┌──────────────────────────────────────────────────────────────────┐
│                     Golem API Gateway                              │
│  Routes HTTP requests to agents based on golem.yaml API            │
│  definitions. Phantoms ephemeral agents per request.               │
└──────────────────────┬───────────────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────────────┐
│               Ephemeral Gateway Agent (stateless)                  │
               │  1. AdminAgent.is_user_initialized(user_id)? ──▶ Admin Agent (RPC)  │
│  2. If initialized: forward to User Agent (RPC)                    │
│  3. If not: "NOT_INITIALIZED" → SvelteKit returns 403              │
└──────────────────────┬───────────────────────────────────────────┘
                       │ (RPC, internal)
         ┌─────────────┼─────────────┐
         ▼             ▼             ▼
   ┌──────────┐ ┌──────────┐ ┌──────────┐
   │  Admin    │ │ Student  │ │ Teacher  │
   │  Agent    │ │  Agent   │ │  Agent   │
   │(durable) │ │(durable) │ │(durable) │
   └────┬─────┘ └────┬─────┘ └────┬─────┘
        │            │            │
        │   RPC      │   RPC      │   RPC
        │◄──────────►│◄──────────►│◄──────────►
        │  (registry │  (submit   │  (push configs,
        │   lookup)  │   assign.) │   push grades)
        │            │            │
        │         HTTP (cached)   │
        │            │            │
        ▼            ▼            ▼
   ┌─────────────────────────────────────┐
   │             SurrealDB               │
   │        (Lesson Content)             │
   └─────────────────────────────────────┘
```

## Key Design Patterns

| Pattern | Implementation |
| :--- | :--- |
| **DB-Backed Facts** | User profiles, teacher assignments, and class rosters live in SurrealDB tables (`user_profile`, `teacher_assignment`). Agents read from DB directly; writes go through the orchestrating agent. |
| **Cache with Explicit Strategy** | Every cached field uses one of three strategies: Push Invalidation (Rule 4A), TTL (Rule 4B), or No Cache (Rule 4C). Strategy is declared per data type. |
| **Deterministic Worker IDs** | Worker IDs are computed from entity IDs (`"teacher-{auth_id}"`, `"student-{auth_id}"`). No agent holds a registry of other agents. |
| **Gatekeeper** | Ephemeral Gateway Agent prevents implicit user agent creation and blocks requests before they reach a User Agent. Init check queries `user_profile` table via AdminAgent RPC. |
| **Direct Actor Communication** | After discovery via the Admin Agent, Student Agents communicate directly with Teacher Agents for submissions and grading. |
| **Fire-and-Forget with Promises** | Long-running admin tasks (future) use fire-and-forget RPCs to ephemeral forked agents with a Promise handle for polling results. |
| **Simple TTL Caching** | Subject lists, term lists, lesson metadata, and edge record IDs are cached in-memory with a configurable TTL (default: 600s). On cache miss or TTL expiry, the next request fetches fresh data from SurrealDB — no background refresh. |
| **Dot-Traversal Queries** | SurrealQL uses dot-traversal (`class_subject.in.name = $class_level`) instead of nested `IN (SELECT ...)` subqueries. This lets the query planner leverage the `idx_cl_name` index on `class_levels(name)` for O(1) lookup. Applied in all subject and lesson queries. |
| **Edge ID Pre-Population** | During student initialization, a single query returns both subject metadata and the `has_subject` edge record ID. The edge ID is cached per student (`edge_cache: Map[String, EdgeCacheEntry]`), enabling lesson queries to use the trivial indexed path `WHERE class_subject = $hs_id AND term = $term_id` — never the dot-traversal path after init. |
| **Soft Deletes** | Every entity table has a `deleted_at` field. All queries filter `WHERE deleted_at IS NONE`. Hard deletes are never used. |
