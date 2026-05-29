# HF-01 — SurrealDB Schema v2: Idiomatic Refactor

## Goal

Replace the relational-style normalization of `lesson_content` (FK columns, `class_subjects` junction table) with an idiomatic SurrealDB schema using `TYPE RELATION` graph edges and a properly `SCHEMAFULL`-typed `lessons` table. Keep `lesson_content` intact for legacy systems. Update all agent SQL queries, MoonBit types, and frontend types in lockstep.

## Design

### Schema Philosophy

- **Navigation fields** (`class_subject`, `term`, `week`, `topic_title`, `active`): strict typing with `ASSERT $value != NONE` — fail fast at the DB level if broken data enters.
- **Content payload** (`content_sections`, `objectives`, `mcq_questions`, etc.): typed as `array` but not deeply defined. MoonBit agent code is the real validation layer; AI output drifts over time and deep SurrealQL field definitions create unnecessary migration burden.
- **Graph edge** (`has_subject TYPE RELATION FROM class_levels TO subjects`) replaces the `class_subjects` junction table, enabling native graph traversal. Lessons hold a `record<has_subject>` FK guaranteeing every lesson has a registered class-subject pair.
- **`active` field removed** from `class_levels` and `subjects` (they are value objects — they exist or don't). Kept on `has_subject`, `lessons`, and `terms` for operational toggling (teacher can deactivate a subject for a class, a term, or individual lessons).
- **`age_range` moves** from lesson records to `class_levels` (it is a property of the class, not the lesson).
- **Terms are global** — `get_terms` returns all active terms regardless of class/subject. If a term has no lessons, the lesson list is simply empty.

### Deprecation Strategy

- `lesson_content` table is **untouched** — all records remain, no fields removed. New code queries `lessons`.
- Old string fields (`class_level`, `subject`, `term`, `week`) stay only in `lesson_content` for legacy readers.
- After all legacy consumers migrate, `lesson_content` can be dropped in a future cleanup.

## Implementation

### A. Database Schema — `db/schema-v2.surql`

Full migration script (idempotent, safe to re-run). See `db/schema-v2.surql` for the complete file.

Four logical steps:
1. Verify/create lookup tables (`class_levels`, `subjects`, `terms`) with updated fields
2. Create `has_subject TYPE RELATION` edge and migrate from `class_subjects`
3. Create `lessons` SCHEMAFULL table with typed navigation + loose content arrays
4. Migrate all `lesson_content` records to `lessons`

### B. MoonBit Agent Changes — `agents/app-agents/student_agent.mbt`

**`LessonInfo` struct (line 31):**
```moonbit
#derive.golem_schema
struct LessonInfo {
  id : String
  topic_title : String?
  week : Int?     -- was: week_number
}
```

**Subject queries (lines 167-171 and 238-240) — both replace:**
```surql
-- OLD:
-- SELECT subject_id.id AS id, subject_id.name AS name, subject_id.code AS code
-- FROM class_subjects WHERE class_level_id = $class_level_id AND active = true
-- ORDER BY subject_id.name ASC

-- NEW:
SELECT out.id AS id, out.name AS name, out.code AS code
FROM has_subject WHERE in = $class_level_id AND active = true
ORDER BY out.name ASC
```

**Terms query (lines 322-327):**
```surql
-- OLD: SELECT * FROM terms WHERE class_level_id = $class_level_id ORDER BY sort_order ASC
-- NEW:
SELECT * FROM terms WHERE active = true ORDER BY sort_order ASC
```

**Lessons query (lines 416-417):**
```surql
-- OLD: SELECT id, topic_title, week_number FROM lesson_content WHERE class_subject_id = $class_subject_id ORDER BY week_number ASC
-- NEW:
SELECT id, topic_title, week FROM lessons
WHERE class_subject = $class_subject_id AND active = true
ORDER BY week ASC
```

**JSON parse key (line 464):**
Change `obj.get("week_number")` → `obj.get("week")`.

**`agents/app-agents/admin_agent.mbt` line 125:**
```surql
-- OLD: SELECT id, name FROM class_levels WHERE active = true ORDER BY name ASC
-- NEW:
SELECT id, name FROM class_levels ORDER BY name ASC
```

### C. Frontend Changes — `frontend/src/lib/types.ts`

```typescript
export interface Lesson {
  id: string;
  topic_title: string | null;
  week: number | null;   // was: week_number
}
```

No other frontend changes. API routes are thin proxies — field names are not hardcoded in parameters.

### D. Documentation Changes

**`docs/architecture.md` — Storage Model section (lines 187-240):**
Rewrite to describe:
- `has_subject TYPE RELATION` graph edge replacing `class_subjects` junction table
- `lessons` SCHEMAFULL table with typed navigation fields
- No `active` on `class_levels`/`subjects`
- `age_range` migrated to `class_levels`
- Four indexes: `idx_hs_unique`, `idx_hs_in`, `idx_lessons_nav`, `idx_lessons_term`
- Deprecation note: `lesson_content` preserved, all new queries target `lessons`
- Remove old FK field table (`class_level_id`, `subject_id`, `term_id`, `week_number`)

**`docs/ai-workflow-rules.md` line ~72:**
Remove stale SQLite reference.

**`docs/progress-tracker.md`:**
Add Hotfix 01 entry.

**`docs/specs/00-build-plan.md`:**
Insert `## Hotfix` section at top of file with HF-01 entry.

## Dependencies

- SurrealDB staging instance with Unit 9 normalization already applied (has `lesson_content`, `class_subjects`, `class_levels`, `subjects`, `terms` tables).

## Verification Checklist

- [ ] `db/schema-v2.surql` runs without errors on staging DB
- [ ] `SELECT count() FROM lessons GROUP ALL` matches `SELECT count() FROM lesson_content GROUP ALL`
- [ ] `SELECT count() FROM has_subject GROUP ALL` matches `SELECT count() FROM class_subjects GROUP ALL`
- [ ] `moon check --target wasm` passes with zero errors
- [ ] `pnpm build && pnpm check` passes with zero errors
- [ ] `/gateway/db-test` returns OK
- [ ] `/api/student/subjects` returns subjects with valid IDs and names for an initialized student
- [ ] `/api/student/terms` returns First, Second, Third Term in correct sort_order
- [ ] `/api/student/lessons?class_subject_id={csid}` returns lessons with `week` field (not `week_number`)
- [ ] Old `lesson_content` table still contains all original records (deprecated, untouched)
- [ ] `golem build` succeeds (generated files auto-update on next build)
