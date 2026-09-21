# Migrate Timetable UI from Next.js to SvelteKit

This plan outlines the migration of the Timetable Dashboard from the `micro1-hackathon` Next.js codebase to the new `school-management-system` SvelteKit frontend.

## User Review Required
The hackathon frontend was written in React (Next.js) using Tailwind CSS. We will port the core structure over to SvelteKit, mapping to the new Svelte `shadcn-svelte` components where applicable.

We need to decide where this lives in the navigation sidebar:
- I propose placing it under the **Admin** section as a new **Timetable** group in the sidebar (e.g., `/admin/timetable`).

## Proposed Changes

### 1. Route Generation
- `frontend/src/routes/admin/timetable/+page.svelte` (Main Dashboard with Timetable Grid and Stats)
- `frontend/src/routes/admin/timetable/+page.ts` (Data loaders pointing to `/api/admin/fetch-timetable`, etc.)

### 2. Component Migration
- `TimetableGrid.svelte`: The core interactive matrix mapping `(class_level) x (day, period)`.
- `RecommendationPanel.svelte`: Port of the constraint metrics and warnings panel.
- `TimetableConfigModal.svelte`: Dialog to configure `day_configs`, excluded periods, and `tier_overrides`.

### 3. API Integration
- Connect Svelte UI to our new MoonBit endpoint `POST /api/admin/generate-timetable`.
- Refactor the React `fetch` calls to use the SvelteKit `$lib/api.ts` Golem Bridge.

## Verification Plan
1. Start the Svelte dev server.
2. Navigate to the new `/admin/timetable` route.
3. Successfully render the blank Timetable grid.
4. Click "Generate Timetable" and verify the Svelte frontend successfully calls the MoonBit agent and refreshes the UI with the scheduled slots.
