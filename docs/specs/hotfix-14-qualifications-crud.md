# Hotfix-14: Qualifications Configuration CRUD

## Goal

Add a "Qualifications" tab under admin Configuration for managing teacher credentials (qualifications). This includes a dedicated page with table list, create dialog, and delete confirmation, backed by Admin Agent CRUD endpoints and SurrealDB `credentials` table.

## Design

### Backend — Admin Agent

**GET `/credentials`** — List all credentials (already existed from HF-10)

Returns JSON array of `{ id: string, name: string, active: bool }`.

**POST `/create-credential`** — Create a new credential

Request body: `{ name: string }`

Creates a record in the `credentials` table via SurrealDB INSERT.

**POST `/delete-credential`** — Delete a credential

Request body: `{ id: string }`

Hard-deletes from the `credentials` table via SurrealDB DELETE.

### Backend — Implementation

| Layer | Function | File |
|-------|----------|------|
| DB | `db_admin_create_credential(config, name)` | `db_admin.mbt:629` |
| DB | `db_admin_delete_credential(config, id)` | `db_admin.mbt:642` |
| Handler | `admin_create_credential(config, name)` | `admin_handler.mbt:446` |
| Handler | `admin_delete_credential(config, id)` | `admin_handler.mbt:473` |
| Agent | `POST /create-credential` | `admin_agent.mbt` |
| Agent | `POST /delete-credential` | `admin_agent.mbt` |

### Frontend — API Routes

**`GET /api/admin/credentials`** — Proxy to Admin Agent `/credentials`

Returns `{ data: CredentialInfo[] }`. Admin-only auth guard.

**`POST /api/admin/credentials`** — Proxy to Admin Agent `/create-credential`

Body: `{ name: string }`. Validates name is non-empty. Returns `{ data: { id, name } }` with 201 status.

**`DELETE /api/admin/credentials/[id]`** — Proxy to Admin Agent `/delete-credential`

Passes `{ id }` as extra params. Returns `{ success: true }`.

### Frontend — Page

**Route:** `/admin/configuration/qualifications`

**States:**
| State | Component | Content |
|-------|-----------|---------|
| Error | `StatusCard variant="error"` | Error message + Retry button |
| Empty | `StatusCard variant="info"` | "No qualifications created yet" |
| Data | `Card > Table` | Name column + Delete button per row |

**Create Dialog:**
- `Dialog` with form: name input + Cancel/Create buttons
- Submits POST to `/api/admin/credentials`
- On success: toast + reload list

**Delete Confirmation:**
- `AlertDialog` with qualification name
- Submits DELETE to `/api/admin/credentials/[id]`
- On success: toast + remove from local list (optimistic)

### Sidebar

Added "Qualifications" link under the Configuration group in the admin sidebar (`+layout.svelte`). Renders for admin users only.

## Data Flow

```
[SvelteKit Page] → fetch() → [API Route] → adminProxy() → [Admin Agent] → SurrealDB credentials table
```

## Files Changed

| File | Change |
|------|--------|
| `agents/app-agents/db_admin.mbt` | Added `db_admin_create_credential`, `db_admin_delete_credential` |
| `agents/app-agents/admin_handler.mbt` | Added `admin_create_credential`, `admin_delete_credential` handlers |
| `agents/app-agents/admin_agent.mbt` | Added `/create-credential`, `/delete-credential` endpoints |
| `frontend/src/routes/api/admin/credentials/+server.ts` | New — GET (list) + POST (create) |
| `frontend/src/routes/api/admin/credentials/[id]/+server.ts` | New — DELETE |
| `frontend/src/routes/admin/configuration/qualifications/+page.server.ts` | New — server load |
| `frontend/src/routes/admin/configuration/qualifications/+page.svelte` | New — page component |
| `frontend/src/routes/+layout.svelte` | Sidebar menu item |

## Build

- `pnpm check`: 0 errors
- `moon check --target wasm`: 0 errors
- 4 commits
