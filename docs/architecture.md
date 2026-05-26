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
| Agent-local Storage | SQLite (embedded) | via Golem filesystem | Structured, queryable durable state inside every durable agent; schema versioned and migrated idempotently; no network overhead |
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
    │   │   ├── (auth)/          # Protected routes
    │   │   │   ├── +layout.svelte
    │   │   │   ├── dashboard/
    │   │   │   ├── lms/
    │   │   │   └── admin/
    │   │   └── login/
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
| **Ephemeral Gateway Agent** (`GatewayAgent`) | Ephemeral | One per HTTP request | Stateless gatekeeper. Checks activation status via Admin Agent RPC, then forwards the request to the target User Agent or returns an error. The sole HTTP-facing agent. |
| **Admin Agent** (`AdminAgent`) | Durable | One (singleton) | Central registry (receptionist), user activation orchestrator, relationship manager, and long-running task dispatcher. Accessed via RPC only (no HTTP mount). |
| **Student Agent** (`StudentAgent`) | Durable | One per student | Owns all student state: class, subjects, cached lesson metadata, assignment configurations, submissions, and grades. |
| **Teacher Agent** (`TeacherAgent`) | Durable | One per teacher | Owns teacher state: assigned classes/subjects, class rosters, assignment definitions, submission inbox (projection), and grading records. |

### SurrealDB

- **Accessed only by Golem agents** via HTTP using the `golemcloud/golem_sdk/http` package.
- Stores lesson content documents. No user state, no submissions, no grades.
- Golem automatically persists all outgoing HTTP requests and responses in the agent's operation log. On replay, the response is read from the log rather than re-executing the network call, ensuring deterministic behaviour.

## Storage Model

### SurrealDB — Lesson Content

One document per lesson. The schema is the AI-generated lesson record with fields: `id`, `source_id`, `active`, `age_range`, `class_level`, `subject`, `term`, `week`, `topic_title`, `duration_mins`, `objectives[]`, `prior_knowledge[]`, `materials[]`, `key_points[]`, `success_criteria[]`, `content_sections[]` (each with `section_number`, `header`, `body`, `sub_points[]`), `mcq_questions[]` (each with `question`, `option_a`–`option_c`, `correct_answer`, `explanation`), `theoretical_questions[]` (each with `question`, `parts[]`, `model_answer`, `marking_scheme`), `lesson_steps[]`, `introduction`, `conclusion`, `teacher_tips`, `remediation`, etc.

Agents read these documents, cache them, and present them. Teachers do not modify the documents directly in the MVP; they select questions from the existing banks.

### Agent-local SQLite — User State

Every durable agent (Admin, Student, Teacher) embeds an SQLite database via Golem's filesystem access. The database is opened on agent startup and migrations run idempotently before any request is processed.

**Admin Agent tables:**

| Table | Key columns | Purpose |
| :--- | :--- | :--- |
| `activated_users` | `user_id TEXT PRIMARY KEY, role TEXT, status TEXT, class_level TEXT, activated_at TEXT` | Master list of all activated users and their status |
| `teacher_assignments` | `teacher_id TEXT, subject TEXT, class_level TEXT, PRIMARY KEY (teacher_id, subject, class_level)` | Which teacher teaches which subject to which class |
| `class_rosters` | `student_id TEXT PRIMARY KEY, class_level TEXT` | Which class each student belongs to |

**Student Agent tables:**

| Table | Key columns | Purpose |
| :--- | :--- | :--- |
| `profile` | `class_level TEXT` | Student's current class |
| `subjects` | `subject_name TEXT PRIMARY KEY` | Subjects for student's class |
| `assignments` | `assignment_id TEXT PRIMARY KEY, lesson_id TEXT, subject TEXT, term TEXT, selected_question_ids TEXT, deadline TEXT, status TEXT, teacher_id TEXT` | Active and past assignment configs; `selected_question_ids` is a JSON array |
| `submissions` | `assignment_id TEXT PRIMARY KEY, answers TEXT, submitted_at TEXT, version INTEGER` | Student's submitted answers; `answers` is a JSON blob |
| `grades` | `assignment_id TEXT PRIMARY KEY, score REAL, feedback TEXT, graded_at TEXT, teacher_id TEXT` | Grades and feedback received |
| `lesson_cache` | `lesson_id TEXT PRIMARY KEY, content TEXT, cached_at TEXT` | Cached lesson content with TTL |

**Teacher Agent tables:**

| Table | Key columns | Purpose |
| :--- | :--- | :--- |
| `my_classes` | `class_level TEXT, subject TEXT, PRIMARY KEY (class_level, subject)` | Classes and subjects the teacher is assigned to |
| `rosters` | `student_id TEXT, class_level TEXT, PRIMARY KEY (student_id, class_level)` | Students in each of the teacher's classes |
| `assignments` | `assignment_id TEXT PRIMARY KEY, lesson_id TEXT, class_level TEXT, subject TEXT, selected_question_ids TEXT, deadline TEXT, status TEXT` | Assignment definitions created by the teacher |
| `submission_inbox` | `assignment_id TEXT, student_id TEXT, answers TEXT, submitted_at TEXT, version INTEGER, PRIMARY KEY (assignment_id, student_id)` | Projection of student submissions for grading |
| `grading` | `assignment_id TEXT, student_id TEXT, score REAL, feedback TEXT, graded_at TEXT, PRIMARY KEY (assignment_id, student_id)` | Grading records pushed back to students |

### Agent Memory Cache

In addition to SQLite, each durable agent maintains an in-memory cache (backed by Golem's durable memory) for frequently accessed data: subject lists, term lists, active lesson metadata, and lesson content. Cache entries have a configurable TTL (default: 5 minutes for lesson content; 10 minutes for lesson lists). On TTL expiry, the agent schedules a background refresh from SurrealDB. Subsequent user requests read from memory or SQLite, both of which are instant.

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

1. **Ephemeral Gateway Agent** calls `AdminAgent.isUserActive(user_id)` via RPC.
2. If `active`, the gateway forwards the request to the target User Agent.
3. If `suspended` or `deactivated`, the gateway returns `403 Forbidden` with the message "Account not activated. Please contact your school administrator."
4. If not found in the Admin Agent's registry, the gateway returns `403 Forbidden`.

This gatekeeper pattern ensures that a user agent can **never** be implicitly created by an unauthorized request. An agent exists only after an admin explicitly activates the user.

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
2. Teacher Agent stores the assignment in its SQLite.
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

Lesson content fetched from SurrealDB is cached in each agent's SQLite `lesson_cache` table and in-memory with a TTL (5 minutes default). On cache miss, the agent fetches from SurrealDB via HTTP using the `@http` package. On TTL expiry, the agent schedules a background refresh — the next user request reads the stale-but-fast cached data while the refresh completes asynchronously (stale-while-revalidate).

## Invariants

These rules must never be violated by any code change, refactor, or new feature.

1. **SvelteKit never accesses SurrealDB or any agent-local storage.** All data flows through Golem agents. The SvelteKit backend is a pure proxy and has no database credentials.

2. **No durable User Agent is created without an explicit admin activation.** The Ephemeral Gateway Agent must always check `AdminAgent.isUserActive(user_id)` before forwarding a request to a User Agent. Implicit agent creation via Golem's default behaviour is blocked by the gatekeeper.

3. **The Admin Agent is the single source of truth for user activation status and class-subject-teacher relationships.** No other agent may independently decide that a user is active or that a teacher owns a subject. All such state flows from the Admin Agent via RPC pushes.

4. **Every durable agent runs idempotent schema migrations on startup.** Before processing any invocation, the agent opens its SQLite database, reads `PRAGMA user_version`, compares it to the expected version constant, and applies only the necessary `ALTER TABLE` / `CREATE TABLE IF NOT EXISTS` statements within a transaction, updating the version after each step.

5. **Assignment deadlines are enforced authoritatively by the Teacher Agent.** The Student Agent performs a local check for immediate user feedback, but the Teacher Agent's timestamp comparison on receipt is the final word. The Teacher Agent's clock is the authority.

6. **Student-to-Teacher submission RPCs are sent directly, not routed through the Admin Agent or a central queue.** The Student Agent discovers the `teacher_id` via `AdminAgent.getTeacherFor(student_id, subject_id)` and caches it, then communicates directly with the Teacher Agent for all assignment operations.

7. **All agent-to-agent RPCs that modify state must be idempotent or use exactly-once semantics.** Golem's RPC provides exactly-once delivery, but method implementations should be safe to retry (e.g., `addOrUpdateAssignment` uses upsert semantics, not blind insert).

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
│  1. AdminAgent.isUserActive(user_id)? ──▶ Admin Agent (RPC)       │
│  2. If active: forward to User Agent (RPC)                        │
│  3. If not: 403                                                    │
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
| **Receptionist (Registry)** | Admin Agent holds all user activation records, teacher-class-subject assignments, and class rosters. Agents discover each other by querying the Admin Agent via RPC. |
| **Gatekeeper** | Ephemeral Gateway Agent prevents implicit user agent creation and blocks deactivated/suspended users before any request reaches a User Agent. |
| **Direct Actor Communication** | After discovery via the Admin Agent, Student Agents communicate directly with Teacher Agents for submissions and grading. |
| **Projection (CQRS-lite)** | The Teacher Agent maintains a local inbox of student submissions, populated by direct RPC pushes from Student Agents. The Student Agent remains the owner of the submission; the Teacher Agent holds a read-only projection for grading. |
| **Fire-and-Forget with Promises** | Long-running admin tasks (future) use fire-and-forget RPCs to ephemeral forked agents with a Promise handle for polling results. |
| **Stale-While-Revalidate Caching** | Agents cache lesson content in SQLite and in-memory with a TTL. On expiry, stale data is returned immediately while a background refresh fetches fresh data from SurrealDB. |
| **Manual Snapshot-Based Updates** | Golem agent updates for breaking state changes use `save-snapshot`/`load-snapshot` with idempotent SQLite migrations run on first load of the new version. |
