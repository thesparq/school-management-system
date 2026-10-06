# Spec 24: Identity, PBAC, and External System Architecture

## 1. Overview
Transition the Johnethel School Management System from email-based logins to an ID-based system (Admission Numbers and Staff IDs). Implement Permission-Based Access Control (PBAC) for granular admin roles, and lay the groundwork for SSO integration with external self-hosted services (Matrix/Element and OpenCloud).

## 2. Core Identity Changes
- **Auto-Generated IDs:** The system will manage an ID sequence in SurrealDB. Manual entry of IDs is disabled to prevent typos and gaps.
- **Immutability:** Once an ID is assigned to a `student_profile`, `teacher_profile`, or `admin_profile`, it is permanently immutable.
- **Authentik Integration:** When the Golem `admin_agent` creates an internal user, it will pass the auto-generated ID as the `username` to Authentik. Parents will continue to use their email address as their username.

## 3. Permission-Based Access Control (PBAC)
- Role-checking (e.g., `role == 'Finance_Admin'`) is deprecated.
- The system will rely on atomic permissions (e.g., `manage:fees`, `manage:timetables`, `reset:passwords`).
- Authentik will bundle these permissions into Groups.
- The SvelteKit UI and Golem endpoints will verify the presence of specific permissions in the JWT claims before authorizing actions.

## 4. Deletion Workflow
- **Soft Deletes:** Deleting a user applies a `deleted_at` timestamp. The Authentik user is deactivated/deleted, but the SurrealDB record remains to preserve audit logs. The ID remains occupied.
- **Hard Deletes:** Admins can permanently delete soft-deleted rows via a "Trash Can" UI. Sequence IDs are never recycled, even upon hard deletion.

## 5. Password Resets
- Matrix/OpenCloud cannot be used for password resets due to the SSO dependency chain.
- Password resets for ID-based accounts must be performed out-of-band by an admin possessing the `reset:passwords` permission via the SvelteKit portal.

## 6. Implementation Phases
1. **Schema & Backend:** Implement `sequence` table and update `create_user_saga` in MoonBit to auto-generate and use IDs for Authentik.
2. **Frontend UI:** Update creation forms (remove manual ID entry), update User Tables to display generated IDs, update Login screen labels.
3. **PBAC Wiring:** Refactor SvelteKit and MoonBit to check for granular permissions in JWTs instead of roles.
