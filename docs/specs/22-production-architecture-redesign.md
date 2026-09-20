# Spec 22: Production Architecture Redesign (CQRS, Caching & Security)

## 1. Executive Summary & Goals
This document outlines the architectural shift from a "Per-User Durable Agent" model to a strict **CQRS (Command Query Responsibility Segregation)** model. 
The goal is to eliminate database bottlenecking, remove the "fan-out cache invalidation" anti-pattern, and massively increase read performance, while reserving Golem's durable execution exclusively for active workflows and state mutations.

## 2. Mastra AI Integration Strategy
**Context:** We have an existing, fully functional lesson generation agent built with the Mastra (TypeScript/Node.js) framework.
**Decision:** We will **treat the Mastra agent as an External Microservice** rather than attempting to compile it into a Golem WebAssembly component immediately.
**Rationale:** While Golem v1.5+ does support Node.js and TypeScript, heavy AI frameworks often rely on native Node modules or advanced V8 networking APIs that can be brittle when componentized to WASM. By keeping Mastra in its native Node environment (e.g., hosted alongside your Telegram bot), we avoid compilation headaches.
**Integration Flow:** 
1. The SvelteKit frontend sends a `POST /generate-lesson` command.
2. A Golem Durable Agent (`AdminTaskDispatcher`) receives the command.
3. The Golem Agent makes a standard HTTP call to the external Mastra API. 
4. Because the Golem Agent is durable, if the Mastra API times out or rate-limits, Golem automatically pauses, sleeps, and retries the HTTP call without losing any context or double-billing for previous steps.

## 3. The New CQRS Architecture

### A. The Read Path (Queries) -> Stateless & Fast
*   **Edge Caching (SvelteKit):** Global, shared data (e.g., Curriculum structure, Subjects, Terms) will be aggressively cached at the SvelteKit layer using in-memory caches or standard `Cache-Control` headers.
*   **Request Coalescing:** To prevent "Cache Stampedes" on cold starts (e.g., 2,000 students logging in at 8:00 AM), SvelteKit will implement request coalescing, ensuring only *one* request hits the backend to warm the cache while the others wait a few milliseconds for the result.
*   **Ephemeral API Workers (Golem):** All read requests for dynamic, user-specific data (e.g., My Grades, Dashboard Stats) will route to a new, stateless Golem component (`core-api`). This component scales instantly, runs a fast SQL query against SurrealDB, returns the JSON, and terminates, leaving zero oplog bloat.

### B. The Write Path (Commands & State) -> Durable & Resilient
*   **Workflow-Scoped Agents:** We are deprecating the monolithic `StudentAgent` and `TeacherAgent`. Durable actors will map to *processes*, not users.
*   **Example (`AssessmentSession`):** When an exam starts, an `AssessmentSession` durable agent is spawned. It securely manages the timer, saves draft answers durably, grades the submission, writes the final grade to SurrealDB, and then gracefully deletes itself.

## 4. Security & Robustness (Stress-Test Mitigations)

1. **Authorization & IDOR Protection (Zero Trust):**
   * SvelteKit must inject the validated Authentik User UUID into a secure header (e.g., `X-Internal-User-ID`).
   * The Ephemeral API workers will *never* trust client-provided IDs (like `?student_id=123`).
   * Queries to SurrealDB will enforce ownership natively via ABAC (Attribute-Based Access Control): `SELECT * FROM grades WHERE student_id = $requested_id AND $requested_id IN (SELECT students FROM parent_profile WHERE id = $internal_user_id)`.
2. **Clock Skew & Cold Starts (Timestamp Injection):**
   * To prevent unfair deadline rejections due to Golem cold starts during high-traffic bursts, SvelteKit must inject a `received_at` timestamp into the command payload. The Durable Agent will use this timestamp to evaluate deadlines, ensuring perfect fairness regardless of queue processing time.
3. **Stale Cache Revalidation:**
   * SvelteKit will expose an internal webhook (e.g., `POST /api/internal/revalidate?tag=lesson-123`).
   * When an Admin edits a lesson in SurrealDB via a Golem worker, the worker will fire a fire-and-forget HTTP request to this webhook to instantly drop SvelteKit's edge cache, ensuring data consistency across the platform.
4. **Database Connection Exhaustion Protection:**
   * SvelteKit will implement Edge Rate Limiting (Token Bucket) to throttle massive bursts of individualized queries, preventing SurrealDB socket exhaustion.

## 5. Human-in-the-Loop (HITL) Interactive AI Workflows
Because the Mastra agent is interactive and requires clarifying questions during generation, Golem will act as a **Durable Chat Relay**.
1.  **Initiation:** The Golem Agent sends the initial prompt to Mastra.
2.  **Clarification Needed:** Mastra replies with `{"status": "clarification_needed", "question": "What grade level?"}`.
3.  **Durable Suspension:** The Golem Agent updates its state to `"Waiting for Admin"`, creates a Promise, and goes to sleep (consuming zero CPU).
4.  **UI Interaction:** SvelteKit polls the agent's status, displays the question to the Admin, and the Admin submits an answer via `POST /answer-question`.
5.  **Resumption:** The `POST` request resolves the Golem Promise. The agent wakes up, takes the answer, and sends the next HTTP request to Mastra to continue the generation, eventually saving the final output to SurrealDB.

## 6. Step-by-Step Implementation Plan

### Phase 1: Edge Caching & Cache Revalidation
1. Implement in-memory caching and Request Coalescing in SvelteKit for the `/lms/[subjectId]/[termId]/[lessonId]` routes.
2. Build the `POST /api/internal/revalidate` webhook in SvelteKit.
3. Update the existing Admin content editing logic to hit the revalidate webhook upon a successful SurrealDB update.

### Phase 2: Ephemeral Reads (`core-api`)
1. Create a new Golem component named `core-api` configured as an **Ephemeral Worker**.
2. Migrate the `student_fetch_my_grades` and `teacher_fetch_lessons` logic from the Durable Agents to this new stateless component.
3. Implement the SurrealDB Ownership Guards (ABAC) in the SQL queries.
4. Update SvelteKit API proxy routes to direct `GET` requests to the Ephemeral Worker.

### Phase 3: Workflow Agents & Roc Integration
1. Scaffold a new `AssessmentSession` durable agent (this is an ideal candidate for the newly improved `roc-golem` platform).
2. Migrate the exam submission and auto-grading logic into this workflow agent.
3. Implement the `received_at` timestamp deadline enforcement.
4. Update SvelteKit to route `POST /submit-assessment` commands to the `AssessmentSession` dispatcher.

### Phase 4: Mastra AI Integration & HITL
1. Ensure the Mastra agent exposes an HTTP API endpoint (e.g., `POST /generate` and `POST /continue`).
2. Create a Golem Durable Agent (`LessonGenerationSession`) that handles the HITL Promise workflow.
3. Implement the SvelteKit chat UI to poll the Golem agent's status and display clarification questions.
4. Connect the SvelteKit `POST /answer-question` route to resolve the Golem Agent's Promise.
5. The Golem Agent handles the final JSON response from Mastra and writes the output to SurrealDB. 

### Phase 5: Cleanup
1. Once all read operations and stateful workflows are migrated, safely deprecate and delete the monolithic `StudentAgent`, `TeacherAgent`, and `AdminAgent` durable components.
