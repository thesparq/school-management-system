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

Environment (see `.env.example`): `SURREAL_USER`/`SURREAL_PASS` (shared with the `surrealdb`
service), `AUTHENTIK_ISSUER_URL` for token validation, `AUTHENTIK_SERVICE_ACCOUNT_TOKEN` for creating
logins, `AUTHENTIK_HOST` for the fallback API URL. `DEV_MODE=false` is set in the compose file and
is what turns the local auth bypass off — never run the deployed app with it on.

**Authentik**: the frontend is a public PKCE client and sends `redirect_uri = <origin>/`, so the
deployed origin must be registered on its provider (Applications → the school app's provider →
Redirect URIs): `https://app.johnethel.school/`. Without it the login round trip fails with
`invalid_redirect_uri`.

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

