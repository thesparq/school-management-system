-- v14 — an admin has a type and a set of permissions, so "admin" stops meaning "can do everything".
--
-- The role comes from Authentik's group (`Super Admins` → role admin) and says "this is a member of staff with
-- the admin shell". It never said which *part* of the school they run: a supervisor who oversees teaching and
-- learning needs the LMS, not the right to create accounts or rename subjects. This file adds the two facts
-- the backend now enforces:
--
--   * `admin_type` — a key from the backend's own catalog (`super_admin`, `supervisor` for now; more kinds
--     are added in code, not here). It is the label the school sees and the source of a new admin's default
--     ticks; a free-text label would not be filterable or checkable.
--   * `permissions` — the keys actually granted to this admin. This is the rule: a route that needs
--     `users.manage` is answered only for an admin whose row carries it (or whose type is `super_admin`).
--
-- Nothing here can lock the school out: every admin that exists is backfilled as `super_admin` with every
-- permission, and the backend refuses a write that would leave the school with no super admin at all (see
-- `guard_last_super_admin` in main.roc).

DEFINE FIELD IF NOT EXISTS admin_type ON admin_profile TYPE option<string>;
DEFINE FIELD IF NOT EXISTS permissions ON admin_profile TYPE array<string> DEFAULT [];

-- Existing admins keep every right they have today.
UPDATE admin_profile SET admin_type = 'super_admin',
  permissions = ['users.manage', 'setup.manage', 'lessons.manage', 'assessments.manage', 'assignments.manage', 'permissions.manage']
  WHERE admin_type IS NONE;
