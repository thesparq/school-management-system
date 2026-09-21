#!/bin/bash
export SURREAL_DB_URL="http://localhost:8001"
export SURREAL_USER="root"
export SURREAL_PASS="root"
export SURREAL_NS="main"
export SURREAL_DB="johnethel-school-generated-lessons"

curl -s -X POST -u "$SURREAL_USER:$SURREAL_PASS" -H "surreal-ns: $SURREAL_NS" -H "surreal-db: $SURREAL_DB" -H "Accept: application/json" --data-binary @../ai-lesson-generator/db/test-setup.surql $SURREAL_DB_URL/sql > /dev/null

curl -s -X POST -u "$SURREAL_USER:$SURREAL_PASS" -H "surreal-ns: $SURREAL_NS" -H "surreal-db: $SURREAL_DB" -H "Accept: application/json" --data-binary @db/schema-v2.surql $SURREAL_DB_URL/sql | jq -c '.[] | select(.status != "OK")'

cat << 'INNER_EOF' > /tmp/terms.surql
CREATE session_term CONTENT { session_name: '2026/2027', term: type::record('terms', 'noel_term'), active: true };
INNER_EOF

curl -s -X POST -u "$SURREAL_USER:$SURREAL_PASS" -H "surreal-ns: $SURREAL_NS" -H "surreal-db: $SURREAL_DB" -H "Accept: application/json" --data-binary @/tmp/terms.surql $SURREAL_DB_URL/sql > /dev/null

echo "Setup done."
