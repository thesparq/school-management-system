-- Seed for schema-v5.surql — NOT APPLIED TO PROD, and not safe to replay as it stands.
--
-- The table it seeds does not exist in prod, and `DELETE id_sequences;` below is a rewrite, against the
-- additive-only rule the lineage follows. Like the schema file, this one is not part of what prod runs: v5
-- declares `admission_number`/`staff_id` as required columns the backend never writes, so applying the pair to
-- a fresh database breaks `POST /api/users` for Student/Teacher/Admin.
--
-- Reconcile before replaying the lineage: the code writes the columns, or both v5 files are retired.
-- `docs/architecture.md` ("Storage model") carries the same note.

DELETE id_sequences;
UPSERT id_sequences:student CONTENT { type: "student", prefix: "JES", current_value: 0 };
UPSERT id_sequences:staff CONTENT { type: "staff", prefix: "EMP", current_value: 0 };
UPSERT id_sequences:admin CONTENT { type: "admin", prefix: "ADM", current_value: 0 };
