# Johnethel School stack

What `docker-compose.yml` deploys, and what each piece needs.

| Service | Purpose | URL |
|---|---|---|
| `app` | The Roc stack: the Joy/WASM frontend and the backend that serves it (`../Dockerfile.app`) | `https://app.johnethel.school` |
| `surrealdb` | The database every part of the app reads and writes | `https://db2.johnethel.school` (external), `surrealdb:8000` (in-network) |
| `synapse` + `synapse-postgresql` | Matrix homeserver behind the in-app chat | `https://matrix.johnethel.school` |
| `element-web` | Chat client | `https://chat.johnethel.school` |
| `coturn` | TURN server for calls (host networking) | — |
| `opencloud` | File cloud (separate product, not used by the app) | `${OC_DOMAIN}` |

Production runs this on a Dokploy server: services join the external `dokploy-network` and Traefik
publishes them by label (`Host(...)`, `certresolver=letsencrypt`). Authentik (`auth.johnethel.school`)
is managed by Dokploy itself, not by this file.

## The app service

One container: `roc build main.roc` produces a static binary that serves both the API and the
frontend bundle, so there is no separate web server. `Dockerfile.app` builds it from the repository
root (frontend bundle first, then the binary) and pins the Roc compiler to the nightly this project
builds with.

```sh
docker build -f Dockerfile.app -t school-app .
docker run --rm -p 8000:8000 --env-file devops/.env school-app
```

Environment: `devops/.env.example` lists every name this file interpolates, grouped by service; the
`app` service takes `SURREAL_USER`/`SURREAL_PASS` (shared with the `surrealdb` service),
`AUTHENTIK_ISSUER_URL` and `AUTHENTIK_USERINFO_URL` for token validation,
`AUTHENTIK_SERVICE_ACCOUNT_TOKEN` for the login writes, `AUTHENTIK_HOST` for the fallback API URL,
and the five `R2_*` values for passport-photo uploads. Without all five `R2_*` values
`/api/upload-url` answers 503 naming the ones that are missing — that is how a misconfigured deploy
reports itself, so it is worth checking after a first deploy. `roc-backend/.env.example` is the same
names for running the backend on its own. `DEV_MODE=false` is set in the compose file and
is what turns the local auth bypass off — never run the deployed app with it on.

**Authentik**: the frontend is a public PKCE client and sends `redirect_uri = <origin>/auth/callback`, so
the deployed origin must have that exact URI registered on its provider (Applications → the school
app's provider → Redirect URIs): `https://app.johnethel.school/auth/callback`. Without it the login
round trip fails with `invalid_redirect_uri`. (The older SvelteKit app used
`<origin>/api/auth/callback`; that is a separate registration and stays as it is.)

## Legacy

- `legacy/docker-compose.golem.yml` — the retired Golem agent runtime (8 services + 4 volumes), kept
  for reference and rollback, not deployed. The Roc stack replaced the MoonBit agents it ran.
- `setup.sh`, `caddy/`, `matrix/`, `matrix-config/`, `golem/`, `golem-router/`, `scripts/` and the
  `patch_*` helpers come from the earlier Caddy-based local setup (and its Authentik/Matrix
  generation scripts). The deployed stack uses Traefik instead; these still work for a local
  `*.localhost` run.

## Matrix OIDC

Synapse authenticates through Authentik:

1. In Authentik, **Applications → Providers →** the Matrix provider: OAuth2/OpenID, confidential
   client, redirect URI `https://matrix.johnethel.school/_synapse/client/oidc/callback`, scopes
   `email`, `openid`, `profile`.
2. Put its client id and secret in `matrix-config/homeserver.yaml` (`oidc_providers`) and in the
   `SYNAPSE_CLIENT_ID`/`SYNAPSE_CLIENT_SECRET` environment.
3. Restart Synapse.

## coturn (voice/video calls)

`coturn` runs with `network_mode: host` because the TURN invitation Synapse hands out points
clients straight at `turn:matrix.johnethel.school` — Traefik is not in the path. It takes
`COTURN_SHARED_SECRET` (shared with Synapse) and `COTURN_LISTEN_IP` (the server's own address,
`hostname -I`); see `.env.example`.

Two host requirements that have been the source of the container refusing to start:

- **The host must not run another TURN server.** A leftover `eturnal` (or second coturn) holding
  port 3478 makes this container fail to bind. With no explicit `listening-ip`, coturn binds a
  listener on *every* discovered address including loopback, and a single bind failure makes it
  retry for 60 seconds and then exit — which `restart: unless-stopped` loops forever. That is the
  signature: repeated `Cannot bind ... 127.0.0.1:3478` lines ending in `Fatal final failure`.
  `ss -tulpn | grep 3478` names the holder (`eturnal` answers with a `SOFTWARE=eturnal` STUN
  attribute; our own container would say `Coturn-…`); `systemctl disable --now eturnal` removes it.
  The compose now pins `--listening-ip`, so loopback is never bound, but a second TURN on the same
  IP still has to go.
- **The firewall must allow the ports it serves**: `3478/tcp+udp`, `5349/tcp` (unused without
  TLS certs but harmless to open), and the relay range `49152-49252/udp`.

After either change: `docker compose -f devops/docker-compose.yml up -d coturn`, then
`python3 devops/stun_probe.py` should report the advertised server as `Coturn-…` on both tcp and
udp (before the fix it reports the leftover `eturnal`).

## In-app chat (Matrix token proxy)

The app's Messaging page talks to Synapse directly from the browser, with an access token the
backend mints per request: `GET /api/matrix/token` (any authenticated role) calls Synapse's admin
API as **the homeserver's admin account** — `PUT /_synapse/admin/v2/users/<id>` so the account
exists, then `POST /_synapse/admin/v1/users/<id>/login` — and returns
`{"homeserver","token"}` for `@<the user's own id>:matrix.johnethel.school`. No Matrix
credentials live in the browser or the app; only the backend holds the admin token.

To set it up once:

1. Put the homeserver URL and the admin token in the environment (`devops/.env.example`):
   `PUBLIC_MATRIX_URL` and `MATRIX_ADMIN_TOKEN`. The compose passes both to the `app` service;
   without the token, `/api/matrix/token` answers 503 naming it (same convention as R2).
2. Get the admin token with `devops/generate_matrix_admin.sh` (register a server admin, grab its
   access token during a one-line temporary enable of password login, restore). If the retired
   Golem stack already injected a `MATRIX_ADMIN_TOKEN`, reuse that.
3. Deploy, then a user opening **Messaging** gets their account (created on first use) and can
   create a channel (public, appears in the room directory), browse and join channels, invite
   people by name or user id, and accept invites — see `roc-frontend/www/index.html`
   (`renderMatrixChannelControls` and friends).

Two notes on how tokens and devices work:

- The proxy **reuses** a token the page already holds: the page caches it for the tab session and
  sends it back as `X-Matrix-Token`; the proxy validates it via the homeserver's `whoami` and
  only mints a fresh token — and with it a fresh Synapse device — when the old one is gone or
  invalid. So repeated visits do not pile up devices (the minted token is the *admin*'s, acting
  as the user, so each mint is a new device of the admin account).
- A 401 on any client call (a token revoked server-side) makes the page drop the cache and mint
  exactly once more.

Verified by `sh roc-frontend/tests/e2e/matrix_token.sh` against a mock Synapse (21 checks:
auth gate, all roles allowed, caller's encoded user id on both admin calls, the display name,
token reuse vs. re-mint, the 503 for a missing admin token).

