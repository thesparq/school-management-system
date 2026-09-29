#!/bin/bash
sed -i '/tls: false/a \  bind_addresses: ["0.0.0.0"]' matrix/homeserver.yaml
docker compose restart synapse
