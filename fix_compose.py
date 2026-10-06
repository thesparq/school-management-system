import yaml
import sys

with open('devops/docker-compose.yml.original', 'r') as f:
    data = yaml.safe_load(f)

# Remove frontend
if 'frontend' in data['services']:
    del data['services']['frontend']

# Add Authentik services
authentik_yaml = """
postgresql-authentik:
  image: docker.io/library/postgres:16-alpine
  restart: unless-stopped
  healthcheck:
    test: ["CMD-SHELL", "pg_isready -d $${POSTGRES_DB} -U $${POSTGRES_USER}"]
    start_period: 20s
    interval: 30s
    retries: 5
    timeout: 5s
  volumes:
    - authentik_database:/var/lib/postgresql/data
  environment:
    POSTGRES_PASSWORD: ${PG_PASS:?database password required}
    POSTGRES_USER: ${PG_USER:-authentik}
    POSTGRES_DB: ${PG_DB:-authentik}
  networks:
    - default

redis-authentik:
  image: docker.io/library/redis:alpine
  restart: unless-stopped
  healthcheck:
    test: ["CMD-SHELL", "redis-cli ping | grep PONG"]
    start_period: 20s
    interval: 30s
    retries: 5
    timeout: 3s
  volumes:
    - authentik_redis:/data
  networks:
    - default

authentik-server:
  image: ${AUTHENTIK_IMAGE:-ghcr.io/goauthentik/server}:${AUTHENTIK_TAG:-2024.8.2}
  restart: unless-stopped
  command: server
  environment:
    AUTHENTIK_REDIS__HOST: redis-authentik
    AUTHENTIK_POSTGRESQL__HOST: postgresql-authentik
    AUTHENTIK_POSTGRESQL__USER: ${PG_USER:-authentik}
    AUTHENTIK_POSTGRESQL__NAME: ${PG_DB:-authentik}
    AUTHENTIK_POSTGRESQL__PASSWORD: ${PG_PASS}
    AUTHENTIK_SECRET_KEY: ${AUTHENTIK_SECRET_KEY}
  volumes:
    - ./authentik/media:/media
    - ./authentik/custom-templates:/templates
  depends_on:
    postgresql-authentik:
      condition: service_healthy
    redis-authentik:
      condition: service_healthy
  networks:
    - default
    - dokploy-network
  labels:
    - traefik.enable=true
    - traefik.docker.network=dokploy-network
    - traefik.http.routers.authentik.rule=Host(`${AUTHENTIK_SERVER_NAME}`)
    - traefik.http.routers.authentik.entrypoints=websecure
    - traefik.http.routers.authentik.tls=true
    - traefik.http.routers.authentik.tls.certresolver=letsencrypt
    - traefik.http.services.authentik.loadbalancer.server.port=9000

authentik-worker:
  image: ${AUTHENTIK_IMAGE:-ghcr.io/goauthentik/server}:${AUTHENTIK_TAG:-2024.8.2}
  restart: unless-stopped
  command: worker
  environment:
    AUTHENTIK_REDIS__HOST: redis-authentik
    AUTHENTIK_POSTGRESQL__HOST: postgresql-authentik
    AUTHENTIK_POSTGRESQL__USER: ${PG_USER:-authentik}
    AUTHENTIK_POSTGRESQL__NAME: ${PG_DB:-authentik}
    AUTHENTIK_POSTGRESQL__PASSWORD: ${PG_PASS}
    AUTHENTIK_SECRET_KEY: ${AUTHENTIK_SECRET_KEY}
  user: root
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock
    - ./authentik/media:/media
    - ./authentik/certs:/certs
    - ./authentik/custom-templates:/templates
  depends_on:
    postgresql-authentik:
      condition: service_healthy
    redis-authentik:
      condition: service_healthy
  networks:
    - default
"""

auth_services = yaml.safe_load(authentik_yaml)
data['services'].update(auth_services)

if 'volumes' not in data:
    data['volumes'] = {}
data['volumes']['authentik_database'] = None
data['volumes']['authentik_redis'] = None

class CustomDumper(yaml.Dumper):
    def ignore_aliases(self, data):
        return True

with open('devops/docker-compose.yml', 'w') as f:
    yaml.dump(data, f, Dumper=CustomDumper, default_flow_style=False, sort_keys=False)

