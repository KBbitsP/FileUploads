#!/bin/bash

# ==========================================
# Configuration
# ==========================================
KB_URL="http://localhost:8080" 
KB_USER="admin"
KB_PASS="password"

API_KEY="24thApril2026T1key"
API_SECRET="24thApril2026T1secret"
ACCOUNT_ID="9b30d1e0-0e91-40b9-ab7d-587421eea918"
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
# Execution & Diagnostics
# ==========================================

echo "=== DIAGNOSTIC RUN START ==="
echo "1. Creating the initial subscription ($INITIAL_PLAN)..."

CREATE_RESPONSE=$(curl -s -i -u "$KB_USER:$KB_PASS" -X POST "$KB_URL/1.0/kb/subscriptions" \
  "${HEADERS[@]}" \
  -d '{
    "accountId": "'"$ACCOUNT_ID"'",
    "planName": "'"$INITIAL_PLAN"'"
  }')

SUBSCRIPTION_ID=$(echo "$CREATE_RESPONSE" | grep -i "^Location:" | grep -o -E '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')

if [ -z "$SUBSCRIPTION_ID" ]; then
  echo "Error: Failed to extract subscriptionId. Response was:"
  echo "$CREATE_RESPONSE"
  exit 1
fi
echo "   -> Subscription created. ID: $SUBSCRIPTION_ID"

# DIAGNOSTIC 1: Fetch state immediately after creation with FULL audit logs
echo "2. [DIAGNOSTIC] Fetching timeline BEFORE the plan change..."
INTERMEDIATE_RESPONSE=$(curl -s -u "$KB_USER:$KB_PASS" -X GET "$KB_URL/1.0/kb/subscriptions/$SUBSCRIPTION_ID?audit=FULL" "${HEADERS[@]}")

echo "3. Triggering plan change to $NEW_PLAN..."
curl -s -u "$KB_USER:$KB_PASS" -X PUT "$KB_URL/1.0/kb/subscriptions/$SUBSCRIPTION_ID" \
  "${HEADERS[@]}" \
  -d '{
    "planName": "'"$NEW_PLAN"'"
  }' > /dev/null
echo "   -> Plan change requested."

sleep 1

# DIAGNOSTIC 2: Fetch final state with FULL audit logs
echo "4. Fetching final timeline AFTER plan change..."
FINAL_RESPONSE=$(curl -s -u "$KB_USER:$KB_PASS" -X GET "$KB_URL/1.0/kb/subscriptions/$SUBSCRIPTION_ID?audit=FULL" "${HEADERS[@]}")

echo ""
echo "====================================================="
echo "               DIAGNOSTIC REPORT                     "
echo "====================================================="
echo ""
echo "--- RAW STATE BEFORE CHANGE ---"
echo "Look for 'START_ENTITLEMENT'. If plan/product are null here, the race condition happens on creation."
echo "$INTERMEDIATE_RESPONSE"
echo ""
echo "-----------------------------------------------------"
echo ""
echo "--- RAW FINAL STATE WITH AUDIT TIMESTAMPS ---"
echo "Look for 'START_ENTITLEMENT' and 'START_BILLING'."
echo "Inside their blocks, look for the 'auditLogs' array and check the 'insertDate'."
echo "$FINAL_RESPONSE"
echo "====================================================="
