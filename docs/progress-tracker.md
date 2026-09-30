# Progress Tracker

## Current Phase: Phase 11 - Unified Notifications & In-App Matrix Messaging
**Status: COMPLETED**

### Completed Work
- Phase 1-9: Golem Architecture, Agent Data Models, CI/CD, Frontend Admin Dashboards, and UI Porting (including Timetable).
- Phase 10: Matrix Server & Single-Sign-On Infrastructure Polish (Traefik, Synapse rate limits, 50MB media limits, telemetry disabled).
- Phase 11:
  - Generated Matrix Admin tokens securely.
  - Built `matrix_client.mbt` MoonBit client for Synapse admin API.
  - Exposed `/matrix/sync-user`, `/matrix/create-room`, `/matrix/token`, and `/matrix/notify` on the Golem AdminAgent.
  - Injected Matrix user sync into `create_user_saga` so all newly created users automatically get a Matrix identity.
  - Created `matrixStore.svelte.ts` polling logic in the SvelteKit frontend to act as a lightweight Matrix client using Golem tokens.
  - Built `NotificationBell.svelte` and `MiniChatWidget.svelte` UI components in SvelteKit and integrated them into the layout.

### Open Questions
- None.

### Next Steps
- Begin Phase 12 or proceed with further platform polish depending on user requirements (e.g. `roc-graph-agent` Framework, Stalwart/Traefik IP Ban fix, or `roc-golem` upgrade).

### Completed
- **Performance Optimization**: Created `get_curriculum_planner_data` BFF aggregation endpoint in MoonBit `AdminAgent` to eliminate network waterfall and Golem actor locking overhead.
- **SvelteKit SSR**: Migrated CurriculumManager and Class Arms pages to use Server-Side Rendering (SSR) via SvelteKit `+page.server.ts` to instantly inject data on initial load.
- **Environment Variables**: Fixed `golem.yaml` and deployment script to properly source `.env` secrets during `golem deploy`.
- **Database Resilience**: Fixed "Database query failed" UI error by intercepting SurrealDB's "Table does not exist" error in MoonBit's `db_client.mbt` and returning empty arrays `Ok([])`.
- **UI/UX Cleanup**: Stripped multi-colored gradients (purple/violet) from CurriculumManager and unified them with shadcn standard themes (`bg-card`).
- **User Role Hubs**: Implemented dedicated dashboard Hubs for Teachers (`/teacher`), Students (`/student`), and Parents (`/parent`), integrated into the main sidebar.

- **Database Migration**: Successfully exported the full 118MB database from `db.johnethel.school` and cleanly imported all 3,413 lessons into the new `db2.johnethel.school` SurrealDB instance on Dokploy.
