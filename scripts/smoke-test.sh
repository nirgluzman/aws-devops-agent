#!/usr/bin/env bash
set -euo pipefail

API_URL="${1:-${API_URL:-}}"
if [[ -z "$API_URL" ]]; then
  echo "Usage: $0 <API_URL>"
  echo "  or set API_URL env var"
  exit 1
fi

# Strip trailing slash
API_URL="${API_URL%/}"
COUNT=5

echo "=== Smoke Test: $API_URL ==="
echo ""

# POST 5 messages
echo "--- POST $COUNT messages ---"
for i in $(seq 1 $COUNT); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API_URL/messages" \
    -H "Content-Type: application/json" \
    -d "{\"message\":\"smoke-test-$i\"}")
  if [[ "$STATUS" != "200" ]]; then
    echo "[FAIL] POST #$i returned HTTP $STATUS"
    exit 1
  fi
  echo "[PASS] POST #$i (HTTP 200)"
done

# GET and verify at least 5 messages exist
echo ""
echo "--- GET /messages ---"
RESPONSE=$(curl -s -w "\n%{http_code}" "$API_URL/messages")
STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$STATUS" != "200" ]]; then
  echo "[FAIL] GET /messages returned HTTP $STATUS"
  exit 1
fi
echo "[PASS] GET /messages (HTTP 200)"

GOT=$(echo "$BODY" | grep -o '"messages/' | wc -l | tr -d ' ')
if [[ "$GOT" -ge "$COUNT" ]]; then
  echo "[PASS] Found $GOT messages (expected >= $COUNT)"
else
  echo "[FAIL] Found $GOT messages (expected >= $COUNT)"
  exit 1
fi

echo ""
echo "=== All tests passed ==="
