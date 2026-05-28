# Unit 12 — User CRUD: Create and Delete Users

## Goal

Enable admins to create new Authentik users (with role/group assignment) and delete existing users directly from the admin user management pages, without leaving the application. Both operations call the Authentik Admin API exclusively — no Golem changes needed.

## Design

### Create User — Flow & UX

- A **"Create Student" / "Create Teacher" / "Create Admin"** button appears at the top of each role page (above the UserTable card), with label matching the current role.
- Clicking opens a shadcn-svelte `Dialog` with a form:

  | Field | Type | Required | Default | Notes |
  |---|---|---|---|---|
  | Username | `text` | Yes | — | `minlength=3`, validated client-side |
  | Full Name | `text` | Yes | — | |
  | Email | `email` | Yes | — | Validated client-side |
  | Password | `password` | Yes | — | `minlength=8`, with visibility toggle button |
  | Activate | `checkbox` | No | `true` | Sets `is_active = true` on creation |

- **On submit:** POST to `POST /api/admin/users` with `{ username, name, email, password, is_active }`.
- **Server-side:** creates user in Authentik → gets returned `AuthentikUser` object → auto-assigns user to the page's role group (group PK passed from frontend load data) → returns the full user object.
- **On success:** push returned user into `users` array, close dialog.
- **On error:** inline error message inside dialog, dialog stays open.

### Delete User — Flow & UX

- A **"Delete User"** button (destructive variant, red) is added at the bottom of the expanded Manage panel in UserTable.
- Clicking opens a shadcn-svelte `AlertDialog` with:
  - Title: `"Delete {username}?"`
  - Description: `"This permanently removes {username} from Authentik. The user will lose all access. This cannot be undone."`
  - Cancel button + **destructive Confirm** button labeled `"Delete"` (disabled while the request is in flight).
- **On confirm:** `DELETE /api/admin/users/[uuid]`.
- **On success:** remove the user from `users` array (optimistic). If the user was in `initMap`, remove them from `initMap` too (but not from Golem — Authentik-only deletion).
- **On error:** show error message inside the dialog.

### Route Structure

| Method | Path | File | Purpose |
|---|---|---|---|
| `POST` | `/api/admin/users` | `frontend/src/routes/api/admin/users/+server.ts` | Create user |
| `DELETE` | `/api/admin/users/[uuid]` | `frontend/src/routes/api/admin/users/[uuid]/+server.ts` | Delete user |

### Visual Layout

```
┌─────────────────────────────────────────────┐
│  Students                          ┌─────────┐ │
│                                     │Create   │ │
│                                     │Student  │ │
│                                     └─────────┘ │
│  ┌─────────────────────────────────────────────┐ │
│  │ Name    Email    Auth  Init  Activate Manage│ │
│  │ ...                                        │ │
│  │                                 ┌──────────┐│ │
│  │  Manage panel expanded:         │Delete    ││ │
│  │  Initialize, Reset Pwd, Groups  │User      ││ │
│  │                                 └──────────┘│ │
│  └─────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

## Implementation

### 1. `authentik.ts` — Add two functions

**`createUser`:**
```typescript
export interface CreateUserParams {
  username: string;
  name: string;
  email: string;
  password: string;
  is_active?: boolean;
  groups?: string[];
}

export async function createUser(params: CreateUserParams): Promise<AuthentikUser> {
  const response = await fetch(`${AUTHENTIK_HOST}/api/v3/core/users/`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${AUTHENTIK_SERVICE_ACCOUNT_TOKEN}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      username: params.username,
      name: params.name,
      email: params.email,
      password: params.password,
      is_active: params.is_active ?? true,
      groups: params.groups ?? [],
      path: 'users'
    })
  });
  if (!response.ok) {
    const body = await response.json().catch(() => null);
    throw new Error(body?.detail || `Authentik create failed: ${response.status}`);
  }
  return response.json();
}
```

**`deleteUser`:**
```typescript
export async function deleteUser(uuid: string): Promise<void> {
  const response = await fetch(`${AUTHENTIK_HOST}/api/v3/core/users/${uuid}/`, {
    method: 'DELETE',
    headers: { 'Authorization': `Bearer ${AUTHENTIK_SERVICE_ACCOUNT_TOKEN}` }
  });
  if (response.status !== 204 && response.status !== 200) {
    throw new Error(`Authentik delete failed: ${response.status}`);
  }
}
```

### 2. `POST /api/admin/users/+server.ts`

```
frontend/src/routes/api/admin/users/+server.ts  (new file)
```

```typescript
import { createUser } from '$lib/server/authentik';
import { error, json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

export const POST: RequestHandler = async (event) => {
  const user = event.locals.user;
  if (!user) error(401, 'Not authenticated');
  if (!user.roles.includes('admin')) error(403, 'Forbidden');

  const body = await event.request.json();
  const { username, name, email, password, is_active = true, group_pk } = body;

  if (!username || !name || !email || !password) {
    return json(
      { error: { code: 'VALIDATION_ERROR', message: 'Missing required fields' } },
      { status: 400 }
    );
  }

  try {
    const created = await createUser({
      username,
      name,
      email,
      password,
      is_active,
      groups: group_pk ? [group_pk] : []
    });

    const result = {
      pk: created.pk,
      uuid: created.uuid,
      username: created.username,
      name: created.name,
      email: created.email,
      groups: created.groups || [],
      is_active: created.is_active
    };

    return json({ data: result }, { status: 201 });
  } catch (err) {
    return json(
      {
        error: {
          code: 'AUTHENTIK_ERROR',
          message: err instanceof Error ? err.message : 'Failed to create user'
        }
      },
      { status: 502 }
    );
  }
};
```

The `group_pk` is passed from the frontend — each role page already knows its role group PK from load data.

### 3. `DELETE /api/admin/users/[uuid]/+server.ts`

```
frontend/src/routes/api/admin/users/[uuid]/+server.ts  (new file)
```

```typescript
import { deleteUser } from '$lib/server/authentik';
import { error, json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

export const DELETE: RequestHandler = async (event) => {
  const user = event.locals.user;
  if (!user) error(401, 'Not authenticated');
  if (!user.roles.includes('admin')) error(403, 'Forbidden');

  const targetUuid = event.params.uuid;
  if (!targetUuid) error(400, 'Missing uuid');

  try {
    await deleteUser(targetUuid);
    return json({ data: { deleted: true } }, { status: 200 });
  } catch (err) {
    return json(
      {
        error: {
          code: 'AUTHENTIK_ERROR',
          message: err instanceof Error ? err.message : 'Failed to delete user'
        }
      },
      { status: 502 }
    );
  }
};
```

### 4. `UserTable.svelte` — Add Create button

**New imports:**
- `Dialog`, `DialogContent`, `DialogHeader`, `DialogTitle`, `DialogDescription` from `$lib/components/ui/dialog`
- `Label` from `$lib/components/ui/label`

**New bindable prop:**
```typescript
groupPk?: string;
```

**New state:**
```typescript
let showCreateDialog = $state(false);
let createForm = $state({ username: '', name: '', email: '', password: '', isActive: true, showPassword: false });
let createLoading = $state(false);
let createError = $state('');
```

**Add Create button** between the `{/if}` closing the empty state and the main `{:else}` block — i.e., rendered only when there is data. Place it above the Card:

```svelte
{#if !isLoading && !hasError && hasUsers}
  <div class="flex justify-end mb-2">
    <Button
      onclick={() => showCreateDialog = true}
      variant="default"
      class="cursor-pointer"
    >
      Create {role === 'admin-role' ? 'Admin' : roleLabel}
    </Button>
  </div>
{/if}
```

**Create Dialog (inserted near bottom of file):**

```svelte
<Dialog open={showCreateDialog} onOpenChange={(o) => { showCreateDialog = o; if (!o) createError = ''; }}>
  <DialogContent>
    <DialogHeader>
      <DialogTitle>Create {role === 'admin-role' ? 'Admin' : roleLabel}</DialogTitle>
      <DialogDescription>
        Add a new user to Authentik and assign them to the {role} group.
      </DialogDescription>
    </DialogHeader>
    <form class="space-y-4" onsubmit={(e) => { e.preventDefault(); handleCreateUser(); }}>
      <div class="space-y-2">
        <Label for="create-username">Username</Label>
        <Input id="create-username" bind:value={createForm.username} required minlength={3} />
      </div>
      <div class="space-y-2">
        <Label for="create-name">Full Name</Label>
        <Input id="create-name" bind:value={createForm.name} required />
      </div>
      <div class="space-y-2">
        <Label for="create-email">Email</Label>
        <Input id="create-email" type="email" bind:value={createForm.email} required />
      </div>
      <div class="space-y-2">
        <Label for="create-password">Password</Label>
        <div class="relative">
          <Input
            id="create-password"
            type={createForm.showPassword ? 'text' : 'password'}
            bind:value={createForm.password}
            required
            minlength={8}
          />
          <button
            type="button"
            class="absolute right-2 top-1/2 -translate-y-1/2 text-surface-500 hover:text-surface-700 cursor-pointer"
            onclick={() => createForm.showPassword = !createForm.showPassword}
          >
            {createForm.showPassword ? 'Hide' : 'Show'}
          </button>
        </div>
      </div>
      <div class="flex items-center gap-2">
        <input
          id="create-active"
          type="checkbox"
          checked={createForm.isActive}
          onchange={(e) => createForm.isActive = e.currentTarget.checked}
          class="h-4 w-4 rounded border-surface-300 text-primary-600 focus:ring-primary-500 cursor-pointer"
        />
        <Label for="create-active">Activate user on creation</Label>
      </div>
      {#if createError}
        <p class="text-sm text-error-500">{createError}</p>
      {/if}
      <div class="flex justify-end gap-2">
        <Button
          type="button"
          variant="outline"
          onclick={() => { showCreateDialog = false; createError = ''; }}
          class="cursor-pointer"
        >
          Cancel
        </Button>
        <Button
          type="submit"
          variant="default"
          disabled={createLoading || !createForm.username || !createForm.name || !createForm.email || !createForm.password}
          class="cursor-pointer"
        >
          {createLoading ? 'Creating...' : 'Create'}
        </Button>
      </div>
    </form>
  </DialogContent>
</Dialog>
```

**`handleCreateUser` function:**

```typescript
async function handleCreateUser() {
  if (!createForm.username || !createForm.name || !createForm.email || !createForm.password) return;
  createLoading = true;
  createError = '';
  try {
    const res = await fetch('/api/admin/users', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        username: createForm.username,
        name: createForm.name,
        email: createForm.email,
        password: createForm.password,
        is_active: createForm.isActive,
        group_pk: groupPk
      })
    });
    const body = await res.json();
    if (!res.ok || body.error) {
      throw new Error(body.error?.message || 'Create failed');
    }
    users = [...users, body.data];
    showCreateDialog = false;
    createForm = { username: '', name: '', email: '', password: '', isActive: true, showPassword: false };
  } catch (err) {
    createError = err instanceof Error ? err.message : 'Create failed';
  } finally {
    createLoading = false;
  }
}
```

### 5. `UserTable.svelte` — Add Delete button in Manage panel

**New import:**
- `AlertDialog`, `AlertDialogTrigger`, `AlertDialogContent`, `AlertDialogHeader`, `AlertDialogTitle`, `AlertDialogDescription`, `AlertDialogFooter`, `AlertDialogCancel`, `AlertDialogAction` from `$lib/components/ui/alert-dialog`

**New state:**
```typescript
let deleteTarget = $state<number | null>(null);
let deleteLoading = $state(false);
let deleteError = $state('');
```

**Add Delete button at bottom of Manage panel** (after the groups section, before the action error display):

```svelte
<div class="border-t border-surface-200 pt-3 flex justify-end">
  <AlertDialog>
    <AlertDialogTrigger>
      {#snippet child({ props })}
      <Button
        {...props}
        variant="destructive"
        size="sm"
        class="cursor-pointer"
      >
        Delete User
      </Button>
      {/snippet}
    </AlertDialogTrigger>
    <AlertDialogContent>
      <AlertDialogHeader>
        <AlertDialogTitle>Delete {userObj.name || userObj.username}?</AlertDialogTitle>
        <AlertDialogDescription>
          This permanently removes {userObj.name || userObj.username} from Authentik.
          The user will lose all access. This cannot be undone.
        </AlertDialogDescription>
      </AlertDialogHeader>
      {#if deleteError}
        <p class="text-sm text-error-500">{deleteError}</p>
      {/if}
      <AlertDialogFooter>
        <AlertDialogCancel onclick={() => { deleteTarget = null; deleteError = ''; }}>
          Cancel
        </AlertDialogCancel>
        <AlertDialogAction
          disabled={deleteLoading}
          onclick={() => handleDeleteUser(userObj.pk)}
          class="bg-error-500 hover:bg-error-600 text-white"
        >
          {deleteLoading ? 'Deleting...' : 'Delete'}
        </AlertDialogAction>
      </AlertDialogFooter>
    </AlertDialogContent>
  </AlertDialog>
</div>
```

**`handleDeleteUser` function:**

```typescript
async function handleDeleteUser(pk: number) {
  const userObj = getUser(pk);
  if (!userObj) return;
  deleteLoading = true;
  deleteError = '';
  try {
    const res = await fetch(`/api/admin/users/${userObj.uuid}`, {
      method: 'DELETE'
    });
    const body = await res.json();
    if (!res.ok || body.error) {
      throw new Error(body.error?.message || 'Delete failed');
    }
    users = users.filter(u => u.pk !== pk);
    const { [userObj.uuid]: _, ...rest } = initMap;
    initMap = rest;
    deleteTarget = null;
  } catch (err) {
    deleteError = err instanceof Error ? err.message : 'Delete failed';
  } finally {
    deleteLoading = false;
  }
}
```

### 6. Role page updates — pass `groupPk` to UserTable

In each `+page.server.ts` (`students`, `teachers`, `admin-role`), add `groupPk` to the returned data:

```typescript
const roleGroupPk = await getGroupPkByName('students'); // or 'teachers', 'admin'
return {
  users: filteredUsers,
  initMap: Object.fromEntries(initMap),
  allGroups,
  role: 'students',
  groupPk: roleGroupPk   // NEW
};
```

In each `+page.svelte`, pass it to UserTable:

```svelte
<UserTable
  bind:users
  bind:initMap
  bind:allGroups
  role="students"
  {groupPk}
  isLoading
  hasError
  errorMessage={...}
/>
```

### 7. Install shadcn-svelte components

```bash
npx shadcn-svelte@latest add dialog
npx shadcn-svelte@latest add alert-dialog
npx shadcn-svelte@latest add label
```

## Dependencies

| Package | Action | Purpose |
|---------|--------|---------|
| `dialog` (shadcn-svelte) | `npx shadcn-svelte@latest add dialog` | Create User form dialog |
| `alert-dialog` (shadcn-svelte) | `npx shadcn-svelte@latest add alert-dialog` | Delete confirmation dialog |
| `label` (shadcn-svelte) | `npx shadcn-svelte@latest add label` | Form field labels |

No new MoonBit packages, npm packages (beyond shadcn-svelte), or Golem changes needed.

## Verification Checklist

### Authentik Helpers
- [ ] `createUser({ username, name, email, password, is_active: true })` creates user in Authentik and returns full `AuthentikUser` object
- [ ] `createUser` with `groups: [pk]` creates user and assigns to group
- [ ] `createUser` throws meaningful error on duplicate username
- [ ] `createUser` throws meaningful error on missing required fields
- [ ] `deleteUser(uuid)` removes user from Authentik (returns 204)
- [ ] `deleteUser(nonexistent_uuid)` throws meaningful error

### API Routes
- [ ] `POST /api/admin/users` returns 201 with `{ data: { pk, uuid, username, name, email, groups, is_active } }`
- [ ] `POST /api/admin/users` returns 400 on missing fields
- [ ] `POST /api/admin/users` returns 502 on Authentik error
- [ ] `POST /api/admin/users` returns 401/403 for unauthenticated/non-admin
- [ ] `DELETE /api/admin/users/[uuid]` returns 200 with `{ data: { deleted: true } }`
- [ ] `DELETE /api/admin/users/[uuid]` returns 502 on Authentik error
- [ ] `DELETE /api/admin/users/[uuid]` returns 401/403 for unauthenticated/non-admin

### UserTable — Create User
- [ ] "Create Student" button visible on Students page (top, before table)
- [ ] "Create Teacher" button visible on Teachers page
- [ ] "Create Admin" button visible on Admin-role page
- [ ] Button label matches the current role
- [ ] Button is hidden during loading/error states
- [ ] Click opens Dialog with all form fields
- [ ] Password field has visibility toggle
- [ ] Submit with empty required fields blocked by native HTML validation
- [ ] On success: dialog closes, new user appears in table
- [ ] New user has correct Auth Status (Active if auto-activate was checked)
- [ ] New user shows Init Status "Pending"
- [ ] New user belongs to the role group (visible in expanded Manage > Groups)
- [ ] On error: inline error message shown, dialog stays open
- [ ] No Golem initialization happens on create

### UserTable — Delete User
- [ ] "Delete User" button visible in expanded Manage panel per row
- [ ] Button uses destructive (red) styling
- [ ] Click opens AlertDialog with correct username and description
- [ ] Cancel closes dialog, no action taken
- [ ] Confirm calls DELETE endpoint
- [ ] On success: user removed from table immediately
- [ ] On success: if user was initialized, removed from initMap (Init Status column updates)
- [ ] On error: error message shown inside dialog
- [ ] Confirm button shows loading state during request, disabled while loading

### Role Pages
- [ ] Students page passes `groupPk` to UserTable for `students` group
- [ ] Teachers page passes `groupPk` for `teachers` group
- [ ] Admin-role page passes `groupPk` for `admin` group

### Build
- [ ] `pnpm build` succeeds (zero errors)
- [ ] `pnpm check` passes (zero errors)

### Regression
- [ ] Existing Initialize, Activate/Deactivate, Reset Password, and Group Management actions still work
- [ ] Existing role pages still load and filter correctly
- [ ] Existing expand/collapse behavior unchanged
- [ ] Existing sidebar navigation unchanged
- [ ] All existing `[uuid]/` sub-routes still work
