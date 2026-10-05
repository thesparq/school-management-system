-- Schema V7: Submission answers

-- `submissions` is SCHEMAFULL and `answers` was declared as `array<object>` with no sub-field
-- definitions (that declaration auto-creates `answers.*` as a bare `object`). Every answer object was
-- therefore rejected:
--   Found field 'answers[0].allocated_mark', but no such field exists for table 'submissions'
-- so a student could not store a single answer, and grading had nothing to read.
--
-- These four fields are exactly what the student answer form sends, and what the MoonBit agents'
-- `SubmissionAnswer` carried: one entry per question, in question order.
--
-- Additive only: `IF NOT EXISTS` on sub-fields that did not exist, no `REMOVE`, no rewrite. Applied
-- to prod on 2026-10-05 with the table at 0 rows; `roc-frontend/tests/e2e/fixtures/sandbox-schema.surql`
-- mirrors it.

DEFINE FIELD IF NOT EXISTS answers.*.question_index ON submissions TYPE int;
DEFINE FIELD IF NOT EXISTS answers.*.answer_type    ON submissions TYPE string;
DEFINE FIELD IF NOT EXISTS answers.*.answer_text    ON submissions TYPE string;
DEFINE FIELD IF NOT EXISTS answers.*.allocated_mark ON submissions TYPE int;
