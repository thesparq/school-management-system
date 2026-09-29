#!/bin/bash
sed -i "s/client-secret-to-be-configured-in-authentik/2YSBKRr4Uiae3458RGazOVp7w2MwzMGPM082Q93SnZy7ZDa0VvTcgn8MAQjdDZFgZNQS5BErco93jHy5koqhxnW1VzSGDZrlsA3NGYWrvZ4vFlLNWX51xCEvUvsRPY1v/g" matrix/homeserver.yaml
sed -i "s/matrix-synapse/6YMrolxcfMnREfemaQcaEogCXgM2r1T6NcRSkIJe/g" matrix/homeserver.yaml
docker compose restart synapse
