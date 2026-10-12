-- v11 — the school has one current session term, so the data enforces it.
--
-- New session terms are created inactive and the hub switches one on, which is the only thing that makes
-- a term usable. Nothing stopped a second row from being switched on with it: `active_session_term_id!`
-- reads one row with `LIMIT 1`, and a teacher's assignment write is scoped by that read — so two active
-- rows mean the save lands under whichever row the query happens to return first. The app's own hub had
-- this state on a sandbox and a pair was written against a term nobody was looking at.
--
-- A plain unique index on `active` would not do it (it would allow exactly one *inactive* row), so the
-- flag is mirrored into a field that is absent unless the row is active, and the unique index is over
-- that: SurrealDB's unique indexes ignore a value that is NONE, which is what makes this a partial one.
DEFINE FIELD IF NOT EXISTS only_active ON session_term TYPE option<string> VALUE IF active THEN 'active' ELSE NONE END;

-- Existing rows need a write before the computed value appears on them (a field's VALUE runs on write).
UPDATE session_term SET active = active;

DEFINE INDEX IF NOT EXISTS idx_st_only_active ON session_term COLUMNS only_active UNIQUE;

-- Applying this to a database that already holds two active rows is refused, naming one of them — that is
-- the rule doing its job, not a broken statement. Switch the extras off first:
--
--   SELECT id, session_name FROM session_term WHERE active = true;
--   UPDATE session_term SET active = false WHERE id != session_term:<the one to keep> AND active = true;
--
-- After this, switching a term on is a *move*: the row being switched on goes on after the others are
-- switched off (the index refuses the other order), which is what the hub's toggle endpoint does in one
-- call. A direct `UPDATE ... SET active = true` on a second row is refused, so no script or hand-run
-- statement can quietly reintroduce the state.
