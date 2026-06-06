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
│   │   ├── main.mbt              # Entry point
│   │   ├── errors.mbt            # AppError, ErrorCode, structured error handling
│   │   ├── config.mbt            # SharedConfig, SurrealCfg, AuthentikCfg (resolved)
│   │   ├── http_client.mbt       # Shared WASI HTTP request/response helper
│   │   ├── auth.mbt              # require_auth() helper (replaces check_auth_key boilerplate)
│   │   ├── validation.mbt        # Input validation (email, password, username, role, class_level)
│   │   ├── surreal_client.mbt    # SurrealDB HTTP client (surreal_query, save_profile, soft_delete)
│   │   ├── authentik_client.mbt  # Authentik REST API client (user CRUD, groups, group PK resolution)
│   │   ├── cache_types.mbt       # CacheData enum, CacheItem struct, CACHE_TTL constant
  │   │   ├── admin_agent.mbt       # Durable Admin Agent (per-admin, HTTP)
  │   │   ├── student_agent.mbt    # Durable Student Agent (per-student, HTTP)
  │   │   ├── teacher_agent.mbt   # Durable Teacher Agent (per-teacher, HTTP)
  │   │   ├── parent_agent.mbt    # Durable Parent Agent (per-parent, HTTP, mirrors student)
  │   │   ├── admin_handler.mbt    # Admin business logic (16 role-specific CRUD)
  │   │   ├── student_handler.mbt  # Student business logic
  │   │   ├── teacher_handler.mbt  # Teacher business logic
  │   │   ├── parent_handler.mbt   # Parent business logic
  │   │   ├── db_admin.mbt         # Admin DB queries (22 role-specific functions)
  │   │   ├── db_student.mbt       # Student DB queries
  │   │   ├── db_teacher.mbt       # Teacher DB queries
  │   │   ├── db_parent.mbt        # Parent DB queries
  │   │   ├── types_admin.mbt      # Admin types (Student/Teacher/Admin/ParentProfileInfo)
  │   │   ├── types_student.mbt    # Student types (StudentProfile with current_class)
  │   │   ├── types_teacher.mbt    # Teacher types
  │   │   └── types_parent.mbt     # Parent types (ParentStudentInfo)
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
    │   │   ├── +page.svelte     # Root page (LMS subjects for students, My Classes for teachers, dashboard for admins)
    │   │   ├── lms/             # Student LMS routes (subjects → terms → lessons)
    │   │   │   └── [subjectId]/
    │   │   │       ├── +page.svelte
    │   │   │       └── [termId]/
    │   │   │           ├── +page.svelte
    │   │   │           └── [lessonId]/
    │   │   │               └── +page.svelte   # Student 2-tab lesson (wrapper → LessonPage)
    │   │   ├── my-classes/      # Teacher class browsing
    │   │   │   └── [classId]/
    │   │   │       ├── +page.svelte
    │   │   │       └── [subjectId]/
    │   │   │           ├── +page.svelte
    │   │   │           └── [termId]/
    │   │   │               ├── +page.svelte
    │   │   │               └── [lessonId]/
    │   │   │                   └── +page.svelte   # Teacher 3-tab lesson (wrapper → LessonPage)
  │   │   ├── admin/           # Admin routes (user management, configuration)
  │   │   │   ├── users/
  │   │   │   │   ├── users-shared/    # Shared: PassportUpload, NameFields, CredentialsSelect
  │   │   │   │   ├── students/        # StudentUserTable + page
  │   │   │   │   ├── teachers/        # TeacherUserTable + page
  │   │   │   │   ├── admin-role/      # AdminUserTable + page
  │   │   │   │   └── parents/         # ParentUserTable + page
  │   │   │   └── configuration/
  │   │   │       └── session-terms/
  │   │   ├── parent/          # Parent LMS routes (student mirror)
  │   │   └── api/             # Proxy routes to Golem agent endpoints
    │   └── lib/
    │       ├── components/      # shadcn-svelte components + LessonPage.svelte + accordion/checkbox
    │       │       ├── SidebarLogo.svelte  # Logo with collapsed-state header integration + mobile sidebar auto-close
    │       │       ├── PageHeader.svelte    # Consistent page heading + action layout
    │       │       └── ui/skeleton/
    │       │           └── PageSkeleton.svelte  # Reusable loading skeleton (list/grid/card layouts)
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

The scaffold produces a `app-agents/` directory. All three agent types (Admin, Student, Teacher) live in this single component, sharing one WASM binary and one set of generated typed RPC clients. This enables type-safe agent-to-agent calls using `<AgentName>Client::scoped(...)` without cross-component bridging.

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

- **Rendering**: Svelte 5 components with runes (`$state`, `$derived`, `$effect`); shadcn-svelte primitives; Tailwind CSS v4 utilities configured via `@theme` in `app.css`. All UI uses shadcn semantic CSS tokens (`text-foreground`, `text-muted-foreground`, `bg-background`, `bg-muted`, `bg-accent`, `border-border`, `border-input`, `text-destructive`, `bg-destructive`, `text-card-foreground`, `text-sidebar-foreground`) — raw Tailwind color classes (e.g. `text-surface-*`, `bg-white`, `border-surface-*`) are never used for UI surfaces; they are replaced by their semantic equivalents.
- **Server-side hooks** (`src/hooks.server.ts`): Validates the Authentik JWT on every request using Authentik's JWKS endpoint, extracts the internal `user_id` and roles, and stores them in `locals` for downstream load functions and actions.
- **API routes** (`src/routes/api/`): Thin proxy handlers. They read `user_id` from `locals`, construct a request to the target Golem agent's HTTP endpoint, and return the response. They never query a database.
- **MoonBit modules**: Imported via `mbt:shared/…` prefix. Used for shared validation, data transformations, and type definitions that must be identical on both frontend and backend. The `vite-plugin-moonbit` plugin resolves these imports from the workspace `_build/` directory.
- **No database credentials, no Golem internal addresses, and no internal agent IDs are ever exposed to the browser.**

### Backend Proxy (SvelteKit server — same process, logical boundary)

- **Authentik token validation**: Uses Authentik's JWKS endpoint (RS256-signed JWTs) with cached public keys.
- **User ID extraction**: Reads the `sub` claim and maps it to the internal stable user identifier.
- **Golem API Gateway calls**: All calls are server-to-server over HTTPS. The gateway URL and any service-level credentials are stored in environment variables on the SvelteKit host.
- **Network firewall**: Only the SvelteKit server's static IP is whitelisted to reach the Golem API Gateway. Golem's built-in OIDC support is **not** used; all auth is handled by the SvelteKit proxy.

### Golem Cloud Backend (agents — `agents/`)

All agents are defined in the single `app:agents` component (`app-agents/`). They share one WASM binary, and the `golem-sdk-tools agents` step generates typed RPC clients for every agent type so intra-component calls use `<AgentName>Client::scoped(...)` with full type safety. No Gateway Agent exists — each agent exposes its own HTTP endpoints via `#derive.endpoint` annotations. SvelteKit proxies directly to the target agent.

| Agent Type | Mode | Instances | Responsibility |
| :--- | :--- | :--- | :--- |
| **Admin Agent** (`AdminAgent`) | Durable | One (singleton) | Central registry, user initialization (4 role-specific CRUD), teacher-subject-class assignments, session term management, credentials management, and long-running task dispatcher. Tracks profiles via SurrealDB `student_profile`/`teacher_profile`/`admin_profile`/`parent_profile` tables. HTTP-accessible via 16 role-specific endpoints + `/credentials` + `/students/list`. |
| **Student Agent** (`StudentAgent`) | Durable | One per student | Owns all student state: profile (`student_profile` table with surname, first_name, display_name, date_of_birth, passport, class_enrolled, current_class), subjects, cached lesson metadata, assignment configurations, submissions, and grades. HTTP-accessible via `#derive.endpoint`. |
| **Teacher Agent** (`TeacherAgent`) | Durable | One per teacher | Owns teacher state: assigned classes/subjects, class rosters, assignment definitions, submission inbox, and grading records. HTTP-accessible via `#derive.endpoint`. |
| **Parent Agent** (`ParentAgent`) | Durable | One per parent | Read-only mirror of student agent with multi-student access. Returns linked student list on login (`parent_profile.students` array). SurrealDB for reads, typed RPC to StudentAgent for writes (assignment submission). Verifies student is in parent's `students` array before any operation. HTTP-accessible via 7 endpoints. |

### SurrealDB

- **Accessed only by Golem agents** via HTTP using the `golemcloud/golem_sdk/http` package with HTTP Basic Auth.
- Stores canonical entity data: user profiles (`user_profile`), teacher assignments (`teacher_assignment`), session terms (`session_term`), curriculum structure (`has_subject`), lesson content (`lessons`), and future assignment/submission/grade records.
- Golem automatically persists all outgoing HTTP requests and responses in the agent's operation log. On replay, the response is read from the log rather than re-executing the network call, ensuring deterministic behaviour.

## Storage Model

### SurrealDB — Schema v2 (Idiomatic Graph/Document)

The database uses SurrealDB's idiomatic multi-model approach. Navigation fields are strictly typed (`SCHEMAFULL` with `ASSERT $value != NONE`), while content payloads are loosely typed as `array` to accommodate AI output drift. A `TYPE RELATION` graph edge replaces the relational junction table.

**Lookup tables (meaningful record IDs, no `active` field):**

| Table | Key Fields | Purpose |
|---|---|---|
| `subjects` | `name` (unique), `code?` | All curriculum subjects (e.g., "Basic Science", "Mathematics") |
| `class_levels` | `name` (unique), `code`, `active` | All class/year levels (e.g., "Primary 1", "JSS 1") |
| `terms` | `name` (unique), `sort_order`, `active` | Academic terms: "Noel Term" (1), "Calvary Term" (2), "Summer Term" (3) |

**Graph edge — `has_subject` (`TYPE RELATION`):**

Defines which subjects belong to which class as a native SurrealDB edge. Enables graph traversal without JOINs.

| Field | Type | Notes |
|---|---|---|
| `in` | `record<class_levels>` | Auto-generated by `TYPE RELATION FROM class_levels` |
| `out` | `record<subjects>` | Auto-generated by `TYPE RELATION TO subjects` |
| `active` | `bool` | Default `true`. Toggle to hide a subject for a class. |

Unique index on `COLUMNS in, out` prevents duplicate edges. Index on `in` accelerates dashboard query.

**`student_profile` table (SCHEMAFULL, HF-10):**

Replaces `user_profile` for students. Record ID = `student_profile:{auth_uuid}` (Authentik UUID as record ID).

| Field | Type | Notes |
|---|---|---|
| `surname` | `string` | Required |
| `first_name` | `string` | Required |
| `middle_name` | `option<string>` | Optional |
| `display_name` | `string` | Computed: `"surname firstname middlename"` |
| `date_of_birth` | `datetime` | Required |
| `class_enrolled` | `record<class_levels>` | Set on create, immutable |
| `current_class` | `record<class_levels>` | Create: = class_enrolled. Edit: updatable |
| `passport` | `string` | Required. R2 public URL |
| `created_at` | `datetime` | |
| `updated_at` | `option<datetime>` | |
| `deleted_at` | `option<datetime>` | Soft delete |

**`teacher_profile` table (SCHEMAFULL, HF-10):**

Record ID = `teacher_profile:{auth_uuid}`.

| Field | Type | Notes |
|---|---|---|
| `surname` | `string` | Required |
| `first_name` | `string` | Required |
| `middle_name` | `option<string>` | |
| `display_name` | `string` | Computed |
| `qualifications` | `option<array<record<credentials>>>` | Array of credentials record IDs |
| `date_employed` | `option<datetime>` | |
| `passport` | `string` | Required. R2 URL |
| `created_at` | `datetime` | |
| `updated_at` | `option<datetime>` | |
| `deleted_at` | `option<datetime>` | |

**`admin_profile` table (SCHEMAFULL, HF-10):**

Record ID = `admin_profile:{auth_uuid}`.

| Field | Type | Notes |
|---|---|---|
| `surname` | `string` | Required |
| `first_name` | `string` | Required |
| `middle_name` | `option<string>` | |
| `display_name` | `string` | Computed |
| `role_title` | `option<string>` | e.g., "Bursar", "Receptionist" |
| `passport` | `string` | Required. R2 URL |
| `created_at` | `datetime` | |
| `updated_at` | `option<datetime>` | |
| `deleted_at` | `option<datetime>` | |

**`parent_profile` table (SCHEMAFULL, HF-10):**

Record ID = `parent_profile:{auth_uuid}`.

| Field | Type | Notes |
|---|---|---|
| `name` | `string` | Required. Single name field (no split) |
| `display_name` | `string` | Required. Same as name |
| `students` | `array<record<student_profile>>` | Required (≥1). Typed references |
| `passport` | `string` | Required. R2 URL |
| `created_at` | `datetime` | |
| `updated_at` | `option<datetime>` | |
| `deleted_at` | `option<datetime>` | |

**`credentials` table (SCHEMAFULL, HF-10):**

Record ID = `credentials:{slug}`. Teacher qualification lookup table.

| Field | Type | Notes |
|---|---|---|
| `name` | `string` | Required. Unique. |
| `active` | `bool` | Default true |

Unique index on `name`.

**Deprecated:** `user_profile` table removed — replaced by 4 role-specialized tables.

**`teacher_assignment` table (SCHEMAFULL, new):**

Replaces `AdminAgent.teacher_assignments`. Maps teacher → has_subject edge. Supports multiple teachers per class-subject pair via separate rows.

| Field | Type | Notes |
|---|---|---|
| `teacher_id` | `string` | Teacher's auth_id |
| `has_subject` | `record<has_subject>` | FK to the graph edge — guarantees registered class-subject pair |
| `session_term` | `record<session_term>` | FK to the active session term — scopes assignments to a school period |
| `assigned_at` | `datetime` | When this assignment was created |
| `deleted_at` | `option<datetime>` | Soft-delete timestamp |

Unique index on `(teacher_id, has_subject, session_term)` prevents duplicate assignments for the same teacher in the same session term.

**`lessons` table (SCHEMAFULL, renamed from `lesson_content`):**

| Navigation Field | Type | Notes |
|---|---|---|
| `topic` | `record<topics>` | FK to the topics table (which links to has_subject + term) |
| `topic_title` | `string` | Lesson title |
| `week` | `int` | Week number within the term (1-based) |
| `active` | `bool` | Default `true`. Toggle to hide a lesson. |
| `duration_mins` | `int` | Lesson duration in minutes |

The `topic` FK resolves through `topics.has_subject` (→ `has_subject` edge → `class_level` + `subject`) and `topics.term` (→ `terms` table). Lesson queries use dot-traversal: `topic.has_subject.in`, `topic.has_subject.out`, `topic.term`.

Content fields (`objectives`, `content_sections`, `key_points`, `lesson_steps`, `mcq_questions`, `theoretical_questions`, `materials`, `prior_knowledge`, `success_criteria`, `extension_activities`, `textbook_references`) and string fields (`introduction`, `conclusion`, `formative_assessment`, `summative_assessment`, `remediation`, `teacher_tips`) are typed as `FLEXIBLE TYPE array<object>` / `string` — the MoonBit agent code is the real validation layer. `FLEXIBLE` prevents SCHEMAFULL from silently stripping nested object properties when no explicit `field.*.property` definitions exist.

**Indexes:**

| Index | Fields | Purpose |
|---|---|---|
| `idx_cl_name` | `name` (unique) | Class-level lookup by name (drives dot-traversal queries) |
| `idx_hs_unique` | `in, out` (unique) | Prevent duplicate class-subject edges |
| `idx_hs_in` | `in` | Lookup: find all has_subject edges for a class |
| `idx_topics_unique` | `has_subject, term, week` (unique) | Prevent duplicate topics for same subject+term+week |
| `idx_lessons_topic` | `topic` (unique) | One lesson per topic |
| `idx_lessons_term` | `class_subject, term` | Which terms have lessons for a subject |

**Deprecation note:** The original `lesson_content` table remains intact for legacy systems. All new queries target `lessons`. After all legacy consumers are migrated, `lesson_content` can be dropped.

Agents query via HTTP using the `surreal_client` module (`agents/app-agents/surreal_client.mbt`), which wraps WASI HTTP POST requests to `https://{host}/sql` with HTTP Basic Auth (`username:password` base64-encoded). Namespace and database are sent as `surreal-ns` / `surreal-db` headers.

A shared `SharedConfig` struct defines all connection parameters as Golem secrets with prefixed field names:

```moonbit
#derive.config
pub(all) struct SharedConfig {
  surreal_host      : @config.Secret[String]
  surreal_ns        : @config.Secret[String]
  surreal_database  : @config.Secret[String]
  surreal_username  : @config.Secret[String]
  surreal_password  : @config.Secret[String]
  authentik_host    : @config.Secret[String]
  authentik_api_token : @config.Secret[String]
  auth_key          : @config.Secret[String]
}
```

Companion `SurrealCfg` and `AuthentikCfg` structs (plain, non-config) provide resolved string values to client modules via `resolve_surreal_cfg(config)` and `resolve_authentik_cfg(config)` helpers defined in `config.mbt`.

**Admin Agent**, **Student Agent**, and **Teacher Agent** each hold credentials via a single `@config.Config[SharedConfig]`.

### Agent Durable State

Every durable agent stores its state in MoonBit struct fields. Golem's durable
execution op‑log persists these fields across restarts and replays — no external
database, no migration scripts. New fields are added with safe defaults.

Following the **Two Layers, Clear Separation** principle (see Architecture Principles below), agent durable state is reserved for in-progress work and active session context. Completed facts and canonical entity data live in SurrealDB.

**Admin Agent struct fields:**

| Field | MoonBit Type | Purpose | Storage |
| :--- | :--- | :--- | :--- |
| `admin_id` | `String` | Authentik UUID — agent identity | Constructor |
| `config` | `@config.Config[SharedConfig]` | Injected credentials (SurrealDB + Authentik + auth key) | Secret |
| `caches` | `Map[String, CacheItem]` | Generic in-memory cache map | Durable |
| *(removed)* | — | `initialized_users` → `user_profile` table | DB |
| *(removed)* | — | `teacher_assignments` → `teacher_assignment` table | DB |

**Student Agent struct fields:**

| Field | MoonBit Type | Purpose | Strategy |
| :--- | :--- | :--- | :--- |
| `student_id` | `String` | Authentik UUID — agent identity | Constructor |
| `config` | `@config.Config[SharedConfig]` | Injected credentials | Secret |
| `caches` | `Map[String, CacheItem]` | Unified cache map for profile + all data | Reactive TTL cache (Rule 4B) |

Cache keys: `"profile"` (backbone — invalidates all), `"subjects"`, `"terms:{class_level}"`, `"lessons:{subject_id}|{term_id}"`, `"lesson:{lesson_id}"`.

The `get_class_level()` method is the reactive gatekeeper — it checks the profile cache first; on miss or expired TTL, queries the DB. If the profile has no `class_level`, it returns `None` and the caller returns `NOT_INITIALIZED`. No negative caching — empty results never cached.

**Teacher Agent struct fields:**

| Field | MoonBit Type | Purpose | Strategy |
| :--- | :--- | :--- | :--- |
| `teacher_id` | `String` | Authentik UUID — agent identity | Constructor |
| `config` | `@config.Config[SharedConfig]` | Injected credentials | Secret |
| `caches` | `Map[String, CacheItem]` | Unified cache map | Reactive TTL cache (Rule 4B) |

Cache keys: `"class_groups"` (backbone — invalidates all) and `"active_session_term"` (cross-agent, TTL 600s). Terms and lessons are queried directly from SurrealDB on each request without TTL caching. Teacher agent's `get_terms` and `get_lessons` do not filter by `active` — inactive items are returned and rendered with lock icon styling on the frontend.

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
| `student` | `/lms/*` (2-tab lesson page: Lesson + Assessments), `/assignments/*`, `/grades/*` |
| `teacher` | `/my-classes/*` (3-tab lesson page: Lesson + Assessments + Grading), `/lms/*` (student-preview, 2-tab), `/assignments/*` (grading), `/students/*` |
| `admin` | `/admin/*` (user management, content management, configuration) |
| `parent` | `/parent/*` (full student LMS mirror, read + write), `/lms/*` (read-only student preview) |

### Init Check (Reactive Pattern)

No Gateway Agent exists. The Student Agent uses a **reactive gatekeeper** pattern — `get_class_level()` is the single method that checks initialization:

1. Checks the profile cache (`caches.get("profile")`) with TTL guard and non-empty class_level guard
2. If cache hit with valid non-empty class_level → returns `Some(class_level)` immediately
3. If cache miss, stale, or empty class_level → queries `user_profile` table from SurrealDB
4. If a record exists with a valid class_level → caches the typed `Profile(StudentProfile)`, returns `Some(class_level)`
5. If no record exists → returns `None`; the caller returns a structured `NOT_INITIALIZED` error (translates to HTTP 403)
6. **No negative caching** — failed lookups never write a sentinel to the cache map

When an admin creates or edits a user profile (writes `user_profile` to SurrealDB), they call the agent's `invalidate_cache("profile")` RPC. This clears ALL caches (profile + subjects + terms + lessons) because `"profile"` is the backbone key. The next request re-fetches everything from SurrealDB.

Activation/deactivation (login permission) is handled by SvelteKit API routes directly against Authentik, not by Golem agents.

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

Subject lists, term lists, and lesson content are cached in each agent's unified `caches` map with TTL (default: 600 seconds). On cache miss or TTL expiry, the next request fetches fresh data from SurrealDB. No background refresh — the cache is reactive and self-warming. Empty results are never cached; they return structured errors instead.

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
- **Strategy A: Push Invalidation (Strong Consistency)** — Writer sends targeted RPC to affected agents after the DB write. Use when staleness is unacceptable. Proxy backbone keys cascade invalidation to all dependent caches (e.g., `"profile"` → clears all).
- **Strategy B: TTL (Eventual Consistency)** — Agent re-queries after a time interval (600s). Use when data changes rarely. Empty results are never cached.
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

2. **No durable User Agent can serve data requests without an existing `user_profile` record in SurrealDB.** The Student Agent's `get_class_level()` method serves as the reactive gatekeeper — if no profile row exists, it returns `None` and the caller returns a structured `NOT_INITIALIZED` error (HTTP 403). A user agent cannot be implicitly created — the Admin Agent is the sole writer of `user_profile` records.

3. **SurrealDB is the single source of truth for entity data.** User profiles, teacher assignments, and class rosters are stored in `user_profile` and `teacher_assignment` tables. Agent durable memory holds only ephemeral cache and in-progress work.

4. **The Admin Agent is the sole writer of `user_profile` records.** Agents read their profile from SurrealDB on first request via the cache-first pattern. Agents never write their own profile.

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
│  │  (pages)  │  │ (JWT check)  │  │  → Agent HTTP Endpoints      │ │
│  └──────────┘  └──────────────┘  └─────────────────────────────┘ │
└──────────────────────┬───────────────────────────────────────────┘
                       │ HTTPS (IP-whitelisted)
         ┌─────────────┼─────────────┐
         ▼             ▼             ▼
   ┌──────────┐ ┌──────────┐ ┌──────────┐
   │  Admin    │ │ Student  │ │ Teacher  │
   │  Agent    │ │  Agent   │ │  Agent   │
   │(durable,  │ │(durable, │ │(durable, │
   │ HTTP)     │ │ HTTP)    │ │ HTTP)    │
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
   │        (All Entity Data)            │
   └─────────────────────────────────────┘
```

No Gateway Agent sits between SvelteKit and the agents. Each agent exposes its own HTTP endpoints via `#derive.endpoint`. Agent init check is handled internally via the cache-first pattern — no external gatekeeper required.

## Key Design Patterns

| Pattern | Implementation |
| :--- | :--- |
| **DB-Backed Facts** | User profiles, teacher assignments, and class rosters live in SurrealDB tables (`user_profile`, `teacher_assignment`). Agents read from DB directly; writes go through the orchestrating agent. |
| **Cache with Explicit Strategy** | Every cached field uses one of three strategies: Push Invalidation (Rule 4A), TTL (Rule 4B), or No Cache (Rule 4C). Strategy is declared per data type. Empty results are never cached. |
| **Deterministic Worker IDs** | Worker IDs are computed from entity IDs (`"teacher-{auth_id}"`, `"student-{auth_id}"`). No agent holds a registry of other agents. |
| **Reactive Cache Pattern** | Profile cache serves as the backbone — `get_class_level()` checks cache first; on miss or empty class_level, queries SurrealDB. No negative caching, no `ensure_initialized` pre-flight check. Cache hits with non-empty data skip the DB; all other paths fall through to a DB query. |
| **Direct Actor Communication** | After discovery via the Admin Agent, Student Agents communicate directly with Teacher Agents for submissions and grading. |
| **Fire-and-Forget with Promises** | Long-running admin tasks (future) use fire-and-forget RPCs to ephemeral forked agents with a Promise handle for polling results. |
| **Simple TTL Caching** | Subject lists, term lists, lesson metadata are cached in-memory with a configurable TTL (default: 600s). On cache miss or TTL expiry, the next request fetches fresh data from SurrealDB — no background refresh. |
| **Dot-Traversal Queries** | SurrealQL uses dot-traversal (`topic.has_subject.in = $class_level`) instead of nested `IN (SELECT ...)` subqueries. Record ID comparisons on embedded fields use direct value interpolation (not `$var` bindings which don't auto-cast in SurrealDB 3.x). |
| **Soft Deletes** | Every entity table has a `deleted_at` field. All queries filter `WHERE deleted_at IS NONE`. Hard deletes are never used. |

## Sidebar Structure

The root layout (`+layout.svelte`) renders three sidebar groups:

```
Navigation              ← visible to all roles
  └── LMS
  └── My Classes        ← teachers only
  └── My Children       ← parents only
Configuration           ← admin only (above Users)
  └── Session Terms
  └── Terms
Users                   ← admin only
  ├── Students
  ├── Teachers
  ├── Parents
  └── Admin
```

## Sidebar Collapsed UX

The sidebar uses shadcn-svelte's `SidebarProvider` with `collapsible="offcanvas"` (default). When collapsed:

- **Sidebar slides off-screen** (both desktop offcanvas and mobile sheet).
- **Full logo transitions to top bar** — `SidebarLogo.svelte` (rendered inside `<Sidebar>`) watches `sb.state` (from `useSidebar()` context). When `collapsed`, it renders nothing in the sidebar; the `+layout.svelte` header shows the full logo (`logo.jpg`) between the `SidebarTrigger` and the breadcrumb via `{#if !sidebarOpen}` with `transition:fade`.
- **Visual separator** — a `<Separator orientation="vertical" />` sits between the logo and the breadcrumb when the logo is visible.
- **Mobile auto-close** — `SidebarLogo.svelte` has an `$effect` watching `$page.url.pathname` that calls `sb.setOpenMobile(false)`, closing the mobile sidebar sheet after any navigation.
- **State persistence** — sidebar open/close state is saved to and restored from `localStorage('sidebar_state')`.

## Session Term Management (HF-04)

Admin users can manage session terms via **Configuration > Session Terms**. A session term links a school session (e.g., "2024") to an academic term (e.g., "Noel Term"). Only one session term can be active at a time.

**Backend**: 4 AdminAgent HTTP endpoints: `GET /terms`, `GET /session-terms`, `POST /create-session-term`, `POST /activate-session-term`. Also `GET /active-session-term` (from HF-03). Cache key `"session_terms"` (TTL 600s) is invalidated on create/activate via `self.caches.remove("session_terms")`. Cache key `"active_session_term"` (TTL 600s) is invalidated on create/activate via `self.caches.remove("active_session_term")` — Admin only; Teacher agent queries `active_session_term` directly (Strategy C: Always Fresh) to avoid stale cache on session-term change. Known limitation: teacher's `class_groups` cache does not auto-invalidate on session-term change — to be addressed in a follow-up hotfix.

**Frontend**: Table with session/term/active badge/created date/activate button. Create dialog with session input, term dropdown (from terms table), and active checkbox (default checked). Activate deactivates all other terms. Non-blocking terms fetch with degraded text-input fallback.

## UI Components

### StatusCard

`StatusCard.svelte` — three variants (info, warning, error) with optional Retry button. Used uniformly across all page-level states: loading skeletons, empty data, error alerts, `NOT_INITIALIZED` info cards.

### Toast Notifications

Global toast notification system (`lib/stores/toast.ts`, `lib/components/ui/toast/`). Four variants: success (green), info (blue), warning (amber), error (red). Features: progress bar timer with pause-on-hover, fade-in/fade-out animations (200ms), auto-dismiss after 5 seconds, manual dismiss via close button. Rendered via `<ToastContainer />` in `+layout.svelte`. Instances clean up on route navigation (`onDestroy`).

**Usage**: `addToast('success', 'Title', 'Description')` — used in UserTable (all 6 CRUD operations), session terms page (create/activate), dashboard ($effect guards prevent re-fire on navigation). Toast is for transient operation feedback; `StatusCard` is for persistent page-level state.

### AppButton

`AppButton.svelte` (`$lib/components/ui/app-button.svelte`) — wraps the shadcn-svelte `Button` with a unified `loading` prop. When true, shows an animated SVG spinner icon next to the button text and auto-disables the button. All other props (`variant`, `size`, `onclick`, `disabled`, `class`, etc.) pass through to the underlying Button. Used across all 10 app-level Button consumers — eliminates manual `disabled={loading}` + ad-hoc spinner patterns. Text swap (`{loading ? 'Saving...' : 'Save'}`) is still controlled by the caller.

### PageSkeleton

`PageSkeleton.svelte` (`$lib/components/ui/skeleton/PageSkeleton.svelte`) — reusable loading skeleton with three layout variants:
- **`list`**: Alternating row skeletons mimicking table rows with avatar/square/circle shapes.
- **`grid`**: 4-column responsive card skeleton grid matching the subject/class card layout.
- **`card`**: Single card skeleton for detail pages.

Used as primary per-page loading state across all routes (dashboard, LMS pages, my-classes pages, user tables). The top loading bar (`h-0.5 bg-secondary-400/500` in `+layout.svelte`) serves as a secondary global navigation indicator.

### Edit Dialog Lazy-Load

All 4 `UserTable` components (Student, Teacher, Admin, Parent) use an optimistic opening pattern:
1. Dialog opens immediately on "Edit" click.
2. Shows `<p class="text-sm text-muted-foreground"><span class="animate-spin">...</span> Loading profile data...</p>`.
3. Save button is disabled until the profile fetch completes.
4. Once data arrives, the form is populated, the spinner text is replaced, and Save becomes enabled.
5. If fetch fails, the error is shown inline and the user can still fill fields manually.

### AlertDialog

shadcn-svelte `AlertDialog` used for destructive/irreversible confirmations: session-term activation (replaced `window.confirm()`), user delete confirmation (replaced custom `div` overlay in `UserTable`). Provides accessible focus trapping, escape-to-close, consistent overlay styling (`bg-black/10`), and ARIA patterns via the `bits-ui` `AlertDialog` primitive.
