-- v16 — the school's own directory of chat channels, and the codes that open them.
--
-- The channels themselves live on the Matrix homeserver; this table is what the *app* knows about them: the
-- name to list, whether the channel is offered to everyone or only to those given its code, and who added
-- it. The page reads this instead of the homeserver's room directory, which is not usable here: since
-- Synapse 1.126 only server admins may publish a room to that directory (`room_list_publication_rules`), so
-- a room made from the app would be created unlisted and the app's own "join" list would come up empty.
-- Reading the app's list also puts the school's rule where it belongs — the backend refuses an addition
-- from anyone but an administrator (see `required_role` in main.roc), rather than merely not drawing the
-- button for them.
--
-- One row per channel, with the id the database assigns:
--
--   * `room_id` — the Matrix room it points at (`!abc:matrix.johnethel.school`), unique;
--   * `name` — what the page lists it as;
--   * `visibility` — `public` (anyone in the school finds and joins it) or `private` (listed to
--     administrators only, and entered with the code below);
--   * `code` — the short code that opens it. The page generates it (this backend has no random source) and
--     the unique index below makes a collision impossible rather than unlikely: the insert fails, the page
--     draws another. Every channel has one — a public channel's is redundant with the listing, a private
--     channel's is the only way in;
--   * `created_by` — the school-side pk of the administrator who added it; `created_at`, `updated_at`;
--     `deleted_at` — NONE while it is offered.
--
-- A code is a pointer, not a permission: the room behind a private channel is created unlisted but
-- joinable (`preset: public_chat` with `visibility: private`), so whoever holds the code can enter it and
-- nobody who does not can find it. A room that has to be tighter than that is invited to, not coded.
--
-- Nothing needs backfilling. A room that already exists on the homeserver but has no row here is simply not
-- listed by the app; an administrator listing it again (the page's own create, or a re-registration of the
-- same room) writes the row.

DEFINE TABLE IF NOT EXISTS chat_channel SCHEMAFULL PERMISSIONS FULL;
DEFINE FIELD IF NOT EXISTS room_id ON chat_channel TYPE string;
DEFINE FIELD IF NOT EXISTS name ON chat_channel TYPE string;
DEFINE FIELD IF NOT EXISTS visibility ON chat_channel TYPE string DEFAULT 'private';
DEFINE FIELD IF NOT EXISTS code ON chat_channel TYPE string;
DEFINE FIELD IF NOT EXISTS created_by ON chat_channel TYPE string DEFAULT '';
DEFINE FIELD IF NOT EXISTS created_at ON chat_channel TYPE datetime DEFAULT time::now();
DEFINE FIELD IF NOT EXISTS updated_at ON chat_channel TYPE datetime DEFAULT time::now();
DEFINE FIELD IF NOT EXISTS deleted_at ON chat_channel TYPE none | datetime;
DEFINE INDEX IF NOT EXISTS idx_chat_channel_code ON chat_channel COLUMNS code UNIQUE;
DEFINE INDEX IF NOT EXISTS idx_chat_channel_room ON chat_channel COLUMNS room_id UNIQUE;
