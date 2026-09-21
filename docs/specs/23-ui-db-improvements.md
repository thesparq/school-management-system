# 23. UI & Database Improvements

## 1. UI/UX Analysis & Redesign (The Johnethel Aesthetic)

### Current State
*   **Color Palette:** The current application uses default Tailwind grey/blue (`oklch` scale) and Shadcn defaults.
*   **Border Radius & Typography:** Mostly standard rounded corners (`0.625rem`) and standard fonts (Inter).
*   **Overall Vibe:** Professional, but somewhat sterile and disconnected from the school's actual brand identity.

### Proposed Johnethel Theme Redesign
Based on the `johnethel.school` website, the aesthetic is "bold and playful" using the FrankenUI/Tailwind system.

*   **Color Palette Update:**
    *   **Primary (Navy Blue):** `hsl(220 85% 25%)` — Used for main navigation, active states, and primary actions.
    *   **Secondary (Vibrant Yellow):** `hsl(45 100% 55%)` — Used for highlights, playful accents, and interactive elements.
    *   **Background (Warm Cream):** `hsl(40 40% 97%)` — A softer, less sterile background than pure white.
    *   **Accent/Cyan:** `hsl(200 90% 50%)` — Great for active states or links.
*   **Border Radius:** Increase default border-radius to `.75rem` (12px) to match the school's softer, friendlier UI.
*   **Playful Interactions:**
    *   Add hover transitions (`translate-y-[-2px]` and shadow expansion) on cards to make them feel tactile.
    *   Use the vibrant yellow for interactive elements like focus rings.

---

## 2. Database Structure Analysis & Improvements

### Current State
The database successfully migrated from a flat structure to a relational structure in `schema-v2.surql`, but it still leans heavily on traditional relational patterns (linking tables) rather than fully embracing SurrealDB's graph database superpowers.

### Proposed Graph & Schema Improvements

**A. Fully Embrace Graph Edges (Instead of Join Tables)**
*   **Current:** `teacher_assignment` is a junction table connecting `teacher_profile`, `has_subject` (itself an edge!), and `session_term`.
*   **Problem:** Querying requires multiple nested joins and `SELECT * FROM teacher_assignment WHERE teacher_id = ...`.
*   **Graph Proposal:** Use SurrealDB's `RELATE` statement to draw direct edges. 
    *   `RELATE teacher:teacher_1 -> teaches -> has_subject:hs_1 SET session = session_term:2026_noel`
    *   *Why?* Traversing is significantly faster and queries become much more readable: `SELECT ->teaches->has_subject->out.name AS subjects FROM teacher:teacher_1`.

**B. Optimize the `has_subject` Edge**
*   **Current:** `topics` table stores a pointer to `has_subject`.
*   **Proposal:** Since a topic is essentially part of a syllabus for a class+subject combo, the topic should ideally belong to the `has_subject` edge itself, or be an edge from `has_subject` to a `term`.
    *   `RELATE has_subject:hs_1 -> covers -> term:noel_term SET topics = [topic_1, topic_2]`

**C. Eliminate Enum-Like Tables if Unnecessary**
*   **Current:** `credentials` is a table just to hold string names.
*   **Proposal:** If credentials are just a static list of strings (e.g., "B.Sc", "PGDE"), they could simply be an `array<string>` on `teacher_profile` with an `ASSERT $value INSIDE ['B.Sc', 'M.Sc', 'PGDE', ...]`. This reduces table bloat.

**D. AI Assessment JSON Storage**
*   **Current:** `lesson_assessments.questions` is an `array<object>`.
*   **Proposal:** Add STRICT typing to the objects in SurrealDB. SurrealDB allows you to define exactly what the objects inside the array must look like:
    ```surql
    DEFINE FIELD questions.*.type ON lesson_assessments TYPE string ASSERT $value INSIDE ['mcq', 'boolean'];
    DEFINE FIELD questions.*.question ON lesson_assessments TYPE string;
    DEFINE FIELD questions.*.options ON lesson_assessments TYPE option<array<string>>;
    DEFINE FIELD questions.*.answer ON lesson_assessments TYPE string;
    ```
    This prevents the AI agents from accidentally writing malformed JSON into the database.

---

## 3. Implementation Steps

1.  **Phase 1: UI / Theme Injection**
    *   Update `frontend/src/app.css` with the new theme variables.
    *   Apply Tailwind base layers to use the variables.
    *   Test the UI across Admin, Teacher, and Student dashboard components to verify readability.
2.  **Phase 2: Add Playful UI Interactions**
    *   Add hover classes on generic cards/buttons to introduce subtle lift (`-translate-y-1`) and shadow.
3.  **Phase 3: Database Graph Refactor (schema-v3.surql)**
    *   Create `schema-v3.surql` incorporating Graph edges for assignments (`->teaches->`).
    *   Add strict typing to assessment objects.
    *   Run schema migrations to move existing data over without loss.
4.  **Phase 4: Agent & API Adjustments**
    *   Update Moonbit agents (`db_teacher.mbt`, `db_admin.mbt`) to query the graph (`->teaches->`) instead of the `teacher_assignment` table.
