# Johnethel School SSO & Matrix Stack

This directory contains the production-grade, local-first Docker Compose setup for Authentik (SSO) and Matrix/Element (Chat).

## Quick Start (Local Setup)

1. **Review Environment Variables:**
   ```bash
   cp .env.example .env
   # Leave DOMAIN=localhost for local testing
   ```
2. **Run the setup script (generates Synapse configs & patches Element):**
   ```bash
   ./setup.sh
   ```
3. **Start the containers:**
   ```bash
   docker compose up -d
   ```

## Services & URLs (Local)
* **Authentik:** `https://auth.localhost`
* **Element Web (Chat):** `https://chat.localhost`
* **Matrix Synapse:** `https://matrix.localhost`

> **Note:** Caddy automatically generates and trusts SSL certificates for `*.localhost` domains. Your browser may show a "Not Secure" warning on the first visit—just click "Proceed to localhost".

## Production Deployment (VPS)

When you are ready to deploy this to a VPS:
1. Update `.env`:
   ```env
   DOMAIN=johnethel.com
   ACME_EMAIL=your-email@johnethel.com
   ```
2. Set strong secrets for `AUTHENTIK_SECRET_KEY`, database passwords, etc.
3. Configure your DNS provider to point `auth.johnethel.com`, `matrix.johnethel.com`, and `chat.johnethel.com` to your VPS's IP address.
4. Run `./setup.sh` and `docker compose up -d`. Caddy will automatically fetch Let's Encrypt certificates.

## Matrix OIDC Configuration

After spinning up the containers, you must configure Authentik to act as the Identity Provider for Matrix:
1. Go to `https://auth.localhost/if/admin/` and login with the default credentials (`akadmin`).
2. Navigate to **Applications -> Providers** and create an **OAuth2/OpenID Provider**:
   * Name: `Matrix Synapse`
   * Authorization Flow: `implicit-consent`
   * Client Type: `Confidential`
   * Redirect URIs: `https://matrix.localhost/_synapse/client/oidc/callback`
   * Scopes: Select `email`, `openid`, and `profile`
3. Copy the **Client ID** and **Client Secret**.
4. Update `devops/matrix/homeserver.yaml` -> `oidc_providers` section with the generated `client_id` and `client_secret`.
5. Restart Synapse: `docker compose restart synapse`.
