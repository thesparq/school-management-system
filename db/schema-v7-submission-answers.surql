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
-- `allocated_mark` is the mark awarded to that answer as far as the backend can tell at submit time:
-- an MCQ is scored there (`allocated_mark` = the question's `questions[*].marks` when the chosen letter
-- matches the question's stored `answer`, 0 otherwise), and any other answer keeps what the form sent
-- (the question's allocation). There is no separate per-answer scored field, and the question's own
-- allocation stays readable in `lesson_assessments.questions[*].marks`.
--
-- Additive only: `IF NOT EXISTS` on sub-fields that did not exist, no `REMOVE`, no rewrite. Applied
-- to prod on 2026-10-05 with the table at 0 rows; `roc-frontend/tests/e2e/fixtures/sandbox-schema.surql`
-- mirrors it.

DEFINE FIELD IF NOT EXISTS answers.*.question_index ON submissions TYPE int;
DEFINE FIELD IF NOT EXISTS answers.*.answer_type    ON submissions TYPE string;
DEFINE FIELD IF NOT EXISTS answers.*.answer_text    ON submissions TYPE string;
DEFINE FIELD IF NOT EXISTS answers.*.allocated_mark ON submissions TYPE int;
