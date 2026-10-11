-- v10 — the lesson indexes prod actually runs, so a fresh database matches it.
--
-- These two were applied to prod outside this lineage (there is no statement for either in v2-v9),
-- which made a first read of the schema misleading: `lessons` looked unindexed on `has_subject` and
-- `term` when prod in fact enforces one lesson per edge, term and week as a database rule. Recorded
-- here so the next reader — and every sandbox built from the fixture — sees prod's real shape.
--
-- Both are no-ops where they already exist (prod), and on a new database they install the rule that
-- keeps a re-run of the seeding from adding a second lesson to a week.
DEFINE INDEX IF NOT EXISTS idx_lessons_unique ON lessons COLUMNS has_subject, term, week UNIQUE;
DEFINE INDEX IF NOT EXISTS idx_lessons_slug ON lessons COLUMNS slug UNIQUE;

-- v2's `idx_lessons_topic` (on a `topic` column the lessons the app reads do not carry) is not in
-- prod — prod's lessons indexes are the two above and nothing else. A database carried over from the
-- v2 era might still hold it; this is how to tell, and how to drop it:
--
--   SELECT count() FROM lessons WHERE topic != NONE GROUP ALL;
--   -- 0 means it can go:
--   REMOVE INDEX idx_lessons_topic ON lessons;

-- Applying the UNIQUE statements above to a database that already holds duplicates is refused, with
-- the offending record named — nothing is deleted. Find them first with the HAVING-free form (this
-- SurrealDB build does not accept `HAVING`):
--
--   SELECT * FROM (SELECT count() AS n, has_subject, term, week FROM lessons
--     GROUP BY has_subject, term, week) WHERE n > 1;
--
-- db/apply-v10-and-verify.sh runs both of those for you, and reports what the indexes are afterwards.
