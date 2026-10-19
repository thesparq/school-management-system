-- v12 — validated bearer tokens are kept for a short while, so the userinfo endpoint is asked once per
-- token rather than once per request.
--
-- The backend validates every /api request's token by calling Authentik's userinfo endpoint, which is a
-- whole HTTPS round trip per request (`roc-backend/Authentik.roc`): a page boot fires about a dozen API
-- calls, so it pays for a dozen authoritative validations of the same token. A token that validated a
-- moment ago still validates, so the answer is kept here until a deadline.
--
-- **Strategy — push invalidation where this backend owns the change, TTL everywhere else.** A token's
-- entry is deleted the moment this backend changes what Authentik would answer about that login (disable,
-- delete, re-enable, a new email), because those writes happen in this same process: it is one more
-- statement in a handler that already talks to the database, not an extra request or a callback. A change
-- made directly in Authentik's own UI cannot be seen from here, so the backend's `token_cache_seconds`
-- bounds how long such a change takes to bite; that TTL is the backstop, not the mechanism.
--
-- An entry never outlives the token it stands for: `expires_at` is the earlier of now + the TTL and
-- the token's own JWT `exp` claim, which the backend reads out of the token when it can. A token that
-- is not a readable JWT is not cached at all (it has no exp to bound it by).
--
-- The record id is the SHA-256 of the bearer token, so this table holds no live credentials: a database
-- dump (or anyone reading the table) cannot lift a session out of it. The raw token is never stored.
--
-- Additive only, like the rest of the lineage. **Applying this file to prod is part of deploying the
-- code that writes it** — without it the cache silently does nothing (every request validates against
-- Authentik, exactly as before) and the startup log says so, rather than failing requests.

DEFINE TABLE IF NOT EXISTS token_cache SCHEMAFULL PERMISSIONS NONE;
-- The Authentik pk of the login the token belongs to: what an invalidation deletes by.
DEFINE FIELD IF NOT EXISTS subject ON token_cache TYPE string;
-- The userinfo body the token validated with, base64-encoded. Base64 keeps it a single quote-free,
-- backslash-free value: the response scanners read a string field between its quotes, so the JSON body
-- itself could not be read back intact, and it is the body — not a re-rendering of it — that a cache
-- hit hands to the route, so a hit and a fresh validation are indistinguishable downstream.
DEFINE FIELD IF NOT EXISTS identity ON token_cache TYPE string;
-- When the entry stops being served: now + the backend's `token_cache_seconds`, or the token's `exp` if
-- sooner.
DEFINE FIELD IF NOT EXISTS expires_at ON token_cache TYPE datetime;
DEFINE FIELD IF NOT EXISTS created_at ON token_cache TYPE datetime DEFAULT time::now();

-- The invalidation delete matches on `subject`.
DEFINE INDEX IF NOT EXISTS idx_token_cache_subject ON token_cache COLUMNS subject;
-- Entries that reached their deadline are pruned as the cache is written; this index is the range it
-- walks.
DEFINE INDEX IF NOT EXISTS idx_token_cache_expiry ON token_cache COLUMNS expires_at;
