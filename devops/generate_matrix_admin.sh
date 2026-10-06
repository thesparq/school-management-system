#!/bin/bash

# Generates a Synapse admin user and grabs their access token
echo "Creating matrix system admin user..."
docker exec -it matrix-synapse-1 register_new_matrix_user -c /data/homeserver.yaml http://localhost:8008 -u system_admin -p "super_secure_admin_password_123" -a

echo "Generating access token..."
docker exec -it matrix-synapse-1 curl -X POST http://localhost:8008/_matrix/client/v3/login -H "Content-Type: application/json" -d '{"type":"m.login.password", "identifier":{"type":"m.id.user", "user":"system_admin"}, "password":"super_secure_admin_password_123"}'

echo ""
echo "Save the 'access_token' printed above. Inject it into Golem as MATRIX_ADMIN_TOKEN."
