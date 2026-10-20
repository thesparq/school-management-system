-- v15 — a login whose password someone else chose has to change it before it can be used.
--
-- Passwords live in Authentik; this app never holds one. What it does know is *when* a password was set by
-- somebody other than its owner: an account created with a password (the school's own onboarding, where the
-- admin generates one and hands it over) and an admin's reset both leave the person holding a password
-- somebody else knows. That is the state this table records, and the backend refuses every other request from
-- such a login until the person sets a password of their own — see `password_change_required!` in main.roc.
--
-- One row per login, keyed by the Authentik pk the profile rows use (`password_state:<pk>`):
--
--   * `required_at` — when the requirement started (the create or the reset), so a later change can be told
--     apart from the one it is waiting for;
--   * `reason` — `created` or `reset`, which is what the person is told;
--   * `changed_at` — NONE while the requirement stands, the moment the person set their own password once it
--     is met. The row stays afterwards, so "this login was made with a password an admin knew, and the
--     person replaced it on <date>" is answerable — an absent row means it never applied.
--
-- A deployment with rows already in it needs nothing backfilled: no row means no requirement, which is the
-- state every existing login is in (their passwords were not set by this app).

DEFINE TABLE IF NOT EXISTS password_state SCHEMAFULL PERMISSIONS FULL;
DEFINE FIELD IF NOT EXISTS required_at ON password_state TYPE datetime DEFAULT time::now();
DEFINE FIELD IF NOT EXISTS reason ON password_state TYPE string DEFAULT 'created';
DEFINE FIELD IF NOT EXISTS changed_at ON password_state TYPE none | datetime;
