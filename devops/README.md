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

**The app no longer mirrors the Authentik admin role onto Synapse.** It used to, by calling
`PUT /_synapse/admin/v1/users/<id>/admin` on every token mint — which needed exactly the admin token this
flow removed. Server admin is still a Synapse-internal flag (stock Synapse has no group→admin mapping),
so it is now a deliberate act: make the person a server admin once with
`register_new_matrix_user -a` or the admin API. Nobody needs it to chat — it is for moderation.

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

## In-app chat (the page logs into Matrix itself)

The app's Messaging page talks to Synapse directly from the browser, and it logs in **as the person
using it**: the page opens the homeserver's own SSO entry point
(`/_matrix/client/v3/login/sso/redirect/authentik?redirectUrl=…`), Synapse hands the browser to
Authentik — the provider in `devops/matrix-config/homeserver.yaml` — and comes back to the page with a
one-time `loginToken`, which the page exchanges for an access token it keeps for the tab session.

So the deployment holds **no chat credential at all**. There is no admin token for the backend to keep
valid, no account for it to create, and nothing that can silently stop working when a shared secret goes
stale — the failure mode that a minting proxy has and this flow does not. The account is the same one
Element uses, because both are created by Synapse from the same Authentik identity
(`localpart_template: {{ user.preferred_username }}` → `@thesparq:matrix.johnethel.school`).

What is left to configure:

1. `PUBLIC_MATRIX_URL` in the environment (the compose passes it to the `app` service). `/api/matrix/config`
   hands it to the page; unset, that route answers 503 naming it, same convention as R2.
2. The app's URL in the homeserver's `sso.client_whitelist` (`devops/matrix-config/homeserver.yaml`), so
   Synapse accepts it as a return address instead of showing a confirmation page.
3. Nothing else. `MATRIX_ADMIN_TOKEN` (and `MATRIX_SERVER_NAME`) are no longer read by anything: delete
   them from the environment where they were set.

Notes on how the session behaves:

- The token lives in the tab's **session storage**: reloading keeps it (no second login), closing the tab
  ends it, and signing out clears it.
- A connect attempt that fails leaves a note in that storage, and the Messaging panel shows the reason
  with a **Try again** button — instead of bouncing the browser through Authentik again in a loop.
- A 401 on a client call (a token revoked server-side) drops the stored token and runs the login once more.
- **The app no longer syncs a Synapse server-admin flag.** It used to mirror the Authentik admin role onto
  the chat account; nothing does that now, because nothing holds a credential to do it with. If someone
  needs server-admin powers for moderation, make them one deliberately: `docker compose -f
  devops/docker-compose.yml exec synapse register_new_matrix_user -c /data/homeserver.yaml -a -u <name> -p
  <password> http://localhost:8008` (or the admin API), once.

Verified by `node roc-frontend/tests/e2e/e2e_matrix_sso.cjs` in Chromium against `fixtures/mock_synapse.py`:
the redirect and the exchange, the token kept across a reload (and no second login), a replayed
`loginToken` refused without a loop, **Try again** working, and — the point of the whole change — the
mock never receiving a single `/_synapse/admin/` call.

