#!/bin/bash
sed -i '/user: synapse/a \    allow_unsafe_locale: true' matrix/homeserver.yaml
docker compose restart synapse
