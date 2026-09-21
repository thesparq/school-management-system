#!/bin/bash
set -e

# Load env
if [ -f .env ]; then
  source .env
else
  cp .env.example .env
  source .env
  echo "Created .env from .env.example. Please review and run again if needed."
fi

mkdir -p matrix caddy element authentik/media authentik/custom-templates authentik/certs

echo "Generating Synapse keys and baseline config..."
docker run -it --rm \
    -v $(pwd)/matrix:/data \
    -e SYNAPSE_SERVER_NAME=${MATRIX_DOMAIN} \
    -e SYNAPSE_REPORT_STATS=no \
    matrixdotorg/synapse:latest generate

echo "Keys generated in matrix/."

echo "Patching homeserver.yaml for PostgreSQL and OIDC (Authentik SSO)..."

# Use python to safely patch yaml or append to it
cat << 'PY' > patch_synapse.py
import yaml
import os

with open("matrix/homeserver.yaml", "r") as f:
    config = yaml.safe_load(f)

# Change DB from SQLite to PostgreSQL
config['database'] = {
    'name': 'psycopg2',
    'args': {
        'user': 'synapse',
        'password': os.environ.get('SYNAPSE_POSTGRES_PASSWORD', 'synapse_db_password'),
        'database': 'synapse',
        'host': 'synapse-postgresql',
        'cp_min': 5,
        'cp_max': 10
    }
}

# Disable local passwords (only SSO allowed)
config['password_config'] = {
    'enabled': False
}

config['enable_registration'] = False

# Macaroon & Registration secrets
config['macaroon_secret_key'] = os.environ.get('SYNAPSE_MACAROON_SECRET_KEY', 'default_secret')
config['registration_shared_secret'] = os.environ.get('SYNAPSE_REGISTRATION_SHARED_SECRET', 'default_secret')

# Configure OIDC for Authentik
config['oidc_providers'] = [
    {
        'idp_id': 'authentik',
        'idp_name': 'Johnethel School SSO',
        'issuer': f"https://{os.environ['AUTH_DOMAIN']}/application/o/matrix/",
        'client_id': 'matrix-synapse',
        'client_secret': 'client-secret-to-be-configured-in-authentik',
        'scopes': ['openid', 'profile', 'email'],
        'user_mapping_provider': {
            'config': {
                'localpart_template': "{{ user.preferred_username }}",
                'display_name_template': "{{ user.name }}"
            }
        }
    }
]

with open("matrix/homeserver.yaml", "w") as f:
    yaml.dump(config, f, default_flow_style=False)
PY

python3 patch_synapse.py
rm patch_synapse.py

echo "Setup complete. You can now run: docker compose up -d"

echo "Patching Element Web config.json..."
sed -i "s/matrix.localhost/${MATRIX_DOMAIN}/g" element/config.json
