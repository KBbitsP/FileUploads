#!/bin/bash

# ==========================================
# Configuration
# ==========================================
KB_URL="http://localhost:8080" 

# Basic HTTP Auth credentials (default for local KB)
KB_USER="admin"
KB_PASS="password"

API_KEY="24thApril2026T1key"
API_SECRET="24thApril2026T1secret"
ACCOUNT_ID="edcbdb23-052a-44d6-a66f-1031cc20d3c0"
INITIAL_PLAN="Plan_A"
NEW_PLAN="Plan_B"
CREATED_BY="ReplicationScript"

HEADERS=(
  -H "X-Killbill-ApiKey: $API_KEY"
  -H "X-Killbill-ApiSecret: $API_SECRET"
  -H "X-Killbill-CreatedBy: $CREATED_BY"
  -H "Content-Type: application/json"
  -H "Accept: application/json"
)

# ==========================================
# Execution
# ==========================================

echo "1. Creating the initial subscription ($INITIAL_PLAN) for Account $ACCOUNT_ID..."

# Added -u flag for basic authentication
CREATE_RESPONSE=$(curl -s -i -u "$KB_USER:$KB_PASS" -X POST "$KB_URL/1.0/kb/subscriptions" \
  "${HEADERS[@]}" \
  -d '{
    "accountId": "'"$ACCOUNT_ID"'",
    "planName": "'"$INITIAL_PLAN"'"
  }')

# Find the "Location:" header and extract the UUID from the end of it
SUBSCRIPTION_ID=$(echo "$CREATE_RESPONSE" | grep -i "^Location:" | grep -o -E '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')

if [ -z "$SUBSCRIPTION_ID" ]; then
  echo "Error: Failed to extract subscriptionId. Response was:"
  echo "$CREATE_RESPONSE"
  exit 1
fi

echo "   -> Success! Subscription ID: $SUBSCRIPTION_ID"
echo "2. IMMEDIATELY triggering plan change to $NEW_PLAN..."

# Added -u flag here as well
curl -s -u "$KB_USER:$KB_PASS" -X PUT "$KB_URL/1.0/kb/subscriptions/$SUBSCRIPTION_ID" \
  "${HEADERS[@]}" \
  -d '{
    "planName": "'"$NEW_PLAN"'"
  }' > /dev/null

echo "   -> Plan change request sent."
echo "3. Fetching the final subscription events timeline..."
sleep 1

# Fetch the timeline
TIMELINE_RESPONSE=$(curl -s -u "$KB_USER:$KB_PASS" -X GET "$KB_URL/1.0/kb/subscriptions/$SUBSCRIPTION_ID" "${HEADERS[@]}")

echo ""
echo "================ RAW TIMELINE DATA =================="
echo "$TIMELINE_RESPONSE"
echo "====================================================="