#!/bin/bash
set -e
# Default configuration
GOLEM_URL="http://agents.localhost:9006"
AUTH_KEY="dev-auth-key-change-in-production"

echo "Running Robust Test Suite against Golem Server..."

# Test 1: Fetch Terms
echo "[1/4] Testing /admin/admin_1/terms endpoint"
RESPONSE=$(curl -s -H "X-Golem-Auth-Key: ${AUTH_KEY}" "${GOLEM_URL}/admin/admin_1/terms")
if echo "$RESPONSE" | grep -q "First Term"; then
    echo "  -> SUCCESS: Terms fetched and verified."
else
    echo "  -> FAILED: Expected 'First Term' in response."
    echo "     Response: $RESPONSE"
    exit 1
fi

# Test 2: Fetch Session Terms
echo "[2/4] Testing /admin/admin_1/session-terms endpoint"
RESPONSE=$(curl -s -H "X-Golem-Auth-Key: ${AUTH_KEY}" "${GOLEM_URL}/admin/admin_1/session-terms")
if echo "$RESPONSE" | grep -q "2026/2027"; then
    echo "  -> SUCCESS: Session Terms fetched and verified."
else
    echo "  -> FAILED: Expected '2026/2027' in response."
    echo "     Response: $RESPONSE"
    exit 1
fi

# Test 3: Fetch Subjects (Student Proxy)
echo "[3/4] Testing /student/student_1/subjects endpoint"
RESPONSE=$(curl -s -H "X-Golem-Auth-Key: ${AUTH_KEY}" "${GOLEM_URL}/student/student_1/subjects")
if echo "$RESPONSE" | grep -q "name"; then
    echo "  -> SUCCESS: Subjects fetched."
else
    echo "  -> FAILED: Failed to fetch subjects."
    echo "     Response: $RESPONSE"
    exit 1
fi

# Test 4: Fetch Classes (Teacher Proxy)
echo "[4/4] Testing /teacher/teacher_1/classes endpoint"
RESPONSE=$(curl -s -H "X-Golem-Auth-Key: ${AUTH_KEY}" "${GOLEM_URL}/teacher/teacher_1/classes")
if echo "$RESPONSE" | grep -q "class_level"; then
    echo "  -> SUCCESS: Classes fetched."
else
    echo "  -> FAILED: Failed to fetch classes."
    echo "     Response: $RESPONSE"
    exit 1
fi

echo "All tests passed successfully!"
