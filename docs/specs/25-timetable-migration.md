# Timetable Engine (Phoenix Allocator) Migration Plan

We are porting the **Phoenix Allocator** (a Constraint Satisfaction Problem solver for school timetables) from the `micro1-hackathon` repository directly into our main `school-management-system` stack.

---

## 1. Schema Integration (SurrealDB)

We will introduce strictly-typed SurrealDB tables to store the timetable states, linking them directly to our existing graph.

### The Tiering Strategy (Global Defaults + Timetable Overrides)
To prevent blocking future sessions while avoiding repetitive data entry:
1. The `has_subject` edge gets a `default_tier` field (e.g., Mathematics is globally defaulted to 3).
2. The `timetables` record gets a `tier_overrides` object. When an admin tweaks a subject's importance for a specific timetable, it is saved here without affecting the global default or other timetables.
3. The MoonBit solver intelligently resolves the tier: `effective_tier = tier_overrides.get(subject) OR default_tier`.

### A. `timetables` (SCHEMAFULL)
Represents a specific schedule variation.
- `name`: string
- `description`: option<string>
- `is_active`: bool
- `session_term`: record<session_term>
- `day_configs`: array<object> (Embedded config: `day_of_week`, `periods_count`, `excluded_periods`)
- `tier_overrides`: object (Dynamic map of `has_subject` IDs to their specific integer tier for this timetable).

### B. `schedule_slots` (SCHEMAFULL)
The generated output matrix of the CSP solver.
- `timetable`: record<timetables>
- `class_level`: record<class_levels>
- `day_of_week`: string
- `period_number`: int
- `subject_edge`: option<record<has_subject>>
- `teacher`: option<record<teacher_profile>>
- `is_excluded`: bool

### C. `timetable_overrides` (SCHEMAFULL)
Tracks term-specific overrides to global availability (e.g., a teacher is unavailable on Fridays for this term only).
- `timetable`: record<timetables>
- `teacher`: record<teacher_profile>
- `is_participating`: bool
- `is_absent_override`: option<bool>
- `added_assignments`: array<record<has_subject>>
- `removed_assignments`: array<record<has_subject>>

---

## 2. Backend Logic (MoonBit CSP Solver)

The Rust solver (`generator.rs`) uses composite scoring (Daily Spreading Penalty, Arm Sync Bonus, Early Period Preference, Teacher Workload Balancing). We will write this natively in **MoonBit** as part of the `AdminAgent`.

**Flow:**
1. SvelteKit calls `AdminAgent.generate_timetable(timetable_id)`.
2. MoonBit fetches all relevant data into memory maps.
3. The MoonBit CSP loop runs, calculating the `effective_tier` for each subject and resolving the matrix.
4. MoonBit bulk-inserts the generated slots back into `schedule_slots`.
5. The AdminAgent pushes a cache invalidation RPC to all affected agents.

---

## 3. UI/UX Migration (React to Svelte 5)

We will port the React components into highly optimized **Svelte 5 runes** using our `shadcn-svelte` primitives.

### Routing & Roles
- **Admin (`/admin/timetable`)**: Full access to the Dashboard. Can tweak `tier_overrides` in the config modal and Auto-Generate.
- **Teacher (`/my-classes/timetable`)**: Read-only view of their personal schedule matrix across all classes.
- **Student/Parent (`/lms/timetable`)**: Read-only view of their specific class's schedule.

---

## 4. Execution Steps

**Phase 1: SurrealDB Schema Update**
- Write `schema-v4.surql` to define `timetables`, `schedule_slots`, and `timetable_overrides`.
- Add `default_tier` to the `has_subject` edge.

**Phase 2: MoonBit Backend Port**
- Add `timetable_types.mbt`.
- Port the Rust `generate_timetable()` algorithm into `admin_timetable.mbt`.
- Add HTTP endpoints to `AdminAgent`.

**Phase 3: Svelte 5 Frontend Port**
- Create the `/admin/timetable` route and translate the React UI to Svelte.
