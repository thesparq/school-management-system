-- Schema V9: the two-system write journal (pending_ops)
--
-- User management spans two systems with no shared transaction — Authentik (the login, its
-- password, whether it is enabled) and SurrealDB (the profile row). A crash between the steps of
-- a create or a delete would otherwise leave a half-state no compensation ran for. Every mutating
-- user operation therefore writes its intent here first and advances a `step` as each side
-- completes; `roc-backend/main.roc`'s reconciler sweeps rows that got stuck in `running` (at
-- startup and on demand via POST /api/users/reconcile) and finishes or rolls them back
-- idempotently, so an inconsistent state is either repaired or left visible in this table with a
-- message for an admin.
--
-- Additive only, like the rest of the lineage. **Applying this file to prod is part of deploying
-- the code that writes it** (create/delete answer 500 until the table exists), the same way v8's
-- id_sequences is.

DEFINE TABLE IF NOT EXISTS pending_ops SCHEMAFULL PERMISSIONS NONE;
-- What the operation was: `create_user` (login + optional password + profile) or `delete_user`
-- (profile soft-delete + login disable).
DEFINE FIELD IF NOT EXISTS kind ON pending_ops TYPE string ASSERT $value IN ["create_user", "delete_user"];
-- running | done | failed. failed rows stay visible with their message until an admin acts.
DEFINE FIELD IF NOT EXISTS state ON pending_ops TYPE string ASSERT $value IN ["running", "done", "failed"];
-- The last step that completed: login | password | profile (create), or profile_hidden | login_disabled (delete).
DEFINE FIELD IF NOT EXISTS step ON pending_ops TYPE option<string>;
-- The login's email (create) or the profile id being deleted (delete, in payload instead).
DEFINE FIELD IF NOT EXISTS email ON pending_ops TYPE option<string>;
-- The Authentik pk of the login once it exists.
DEFINE FIELD IF NOT EXISTS pk ON pending_ops TYPE option<string>;
-- The create payload (JSON text, password never included — only a wants_password flag), so the
-- reconciler can replay the profile write idempotently.
DEFINE FIELD IF NOT EXISTS payload ON pending_ops TYPE option<string>;
DEFINE FIELD IF NOT EXISTS message ON pending_ops TYPE option<string>;
DEFINE FIELD IF NOT EXISTS created_at ON pending_ops TYPE datetime DEFAULT time::now();
DEFINE FIELD IF NOT EXISTS updated_at ON pending_ops TYPE option<datetime>;
DEFINE INDEX IF NOT EXISTS idx_pending_state ON pending_ops COLUMNS state;
