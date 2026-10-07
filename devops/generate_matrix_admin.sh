#!/bin/bash
#
# Obtains the Synapse admin access token the app's chat proxy needs (MATRIX_ADMIN_TOKEN).
#
# Run from the repository on the Dokploy box. The homeserver disables password login
# (matrix-config/homeserver.yaml, `password_config.enabled: false`), so getting the token needs a
# one-line temporary flip — a few minutes and one homeserver restart; do it in a quiet moment.
# (If a MATRIX_ADMIN_TOKEN was already injected for the retired Golem stack, reuse it and skip
# all of this.)
set -e

COMPOSE=(docker compose -f devops/docker-compose.yml)
ADMIN_USER=${MATRIX_ADMIN_USER:-system_admin}

# 1. Create the admin account. Uses the registration shared secret from the container's own
#    rendered config, so it works even with password login disabled; `-a` makes it a server
#    admin. "Already exists" is a success here.
ADMIN_PASS=${MATRIX_ADMIN_PASS:?set a strong password}

echo "registering ${ADMIN_USER} as a server admin..."
"${COMPOSE[@]}" exec -T synapse register_new_matrix_user \
  -c /data/homeserver.yaml http://localhost:8008 -u "$ADMIN_USER" -p "$ADMIN_PASS" -a \
  || true

echo
echo "2. Get the token (password login is disabled, so temporarily enable it):"
echo "   a. In matrix-config/homeserver.yaml change \`password_config.enabled\` to \`true\`, then:"
echo "      docker compose -f devops/docker-compose.yml up -d synapse"
echo "   b. Log in and copy the access_token from the answer:"
echo "      ${COMPOSE[@]} exec -T synapse curl -s -X POST http://localhost:8008/_matrix/client/v3/login"
echo "        -H 'Content-Type: application/json'"
echo "        -d '{\"type\":\"m.login.password\",\"identifier\":{\"type\":\"m.id.user\",\"user\":\"${ADMIN_USER}\"},\"password\":\"<the password>\"}'"
echo "   c. Restore \`enabled: false\`, then:"
echo "      docker compose -f devops/docker-compose.yml up -d synapse"
echo
echo "3. Inject the token as MATRIX_ADMIN_TOKEN in Dokploy (Infisical) and redeploy the app."
echo "   Verify with a real login: curl -s -H 'Authorization: Bearer <app token>' <app>/api/matrix/token"
echo "   should answer with a homeserver and a token (not null)."


