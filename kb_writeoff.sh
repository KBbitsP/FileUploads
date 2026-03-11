#!/bin/bash

# --- Kill Bill Configuration ---
KB_URL="http://localhost:8080"
API_KEY="5thmarch2026tct7key"
API_SECRET="5thmarch2026tct7secret"
USERNAME="admin"
PASSWORD="password"
CREATED_BY="KB_Automated_Script"

# The UUID for the WRITTEN_OFF tag in Kill Bill
WRITTEN_OFF_TAG_ID="00000000-0000-0000-0000-000000000004"

# Get the invoice ID from the command line argument
INVOICE_ID=$1
if [ -z "$INVOICE_ID" ]; then
    INVOICE_ID="eaa0c0eb-8466-4615-820b-09a7c5cd6007"
    echo "No Invoice ID provided as argument. Using default: $INVOICE_ID"
fi

echo "--- Starting Refund and Write-Off Process for Invoice: $INVOICE_ID ---"

# ==========================================
# STEP 1: Get Payment ID and Amount
# ==========================================
echo -e "\nStep 1: Fetching associated payments..."

PAYMENTS_JSON=$(curl -s -X GET "$KB_URL/1.0/kb/invoices/$INVOICE_ID/payments?withPluginInfo=false&withAttempts=false&audit=NONE" \
    -u "$USERNAME:$PASSWORD" \
    -H "Accept: application/json" \
    -H "X-Killbill-ApiKey: $API_KEY" \
    -H "X-Killbill-ApiSecret: $API_SECRET")

# Use grep -o to extract ONLY the targeted key-value pairs from the minified JSON string
PAYMENT_ID=$(echo "$PAYMENTS_JSON" | grep -o '"paymentId":"[^"]*"' | head -n 1 | awk -F'"' '{print $4}')

if [ -z "$PAYMENT_ID" ]; then
    echo "No payments found for this invoice. Proceeding directly to Write-Off (Step 3)."
    AMOUNT_TO_REFUND=0
else
    # Extract purchased and refunded amounts (handling potential spaces safely)
    PURCHASED=$(echo "$PAYMENTS_JSON" | grep -o '"purchasedAmount"[[:space:]]*:[[:space:]]*[0-9.]*' | head -n 1 | awk -F':' '{print $2}' | tr -d ' ')
    REFUNDED=$(echo "$PAYMENTS_JSON" | grep -o '"refundedAmount"[[:space:]]*:[[:space:]]*[0-9.]*' | head -n 1 | awk -F':' '{print $2}' | tr -d ' ')
    
    # Default to 0 if empty
    PURCHASED=${PURCHASED:-0}
    REFUNDED=${REFUNDED:-0}
    
    # Calculate target refund amount using awk
    AMOUNT_TO_REFUND=$(awk "BEGIN {print $PURCHASED - $REFUNDED}")
    
    echo "Found Payment ID: $PAYMENT_ID"
    echo "Purchased: $PURCHASED | Refunded: $REFUNDED"
    echo "Target Refund Amount: $AMOUNT_TO_REFUND"
fi

# ==========================================
# STEP 2: Issue Refund
# ==========================================
# Use awk to check if AMOUNT_TO_REFUND > 0
SHOULD_REFUND=$(awk "BEGIN { if ($AMOUNT_TO_REFUND > 0) print 1; else print 0 }")

if [ "$SHOULD_REFUND" -eq 1 ]; then
    echo -e "\nStep 2: Issuing refund for $AMOUNT_TO_REFUND..."
    
    REFUND_PAYLOAD="{\"amount\": $AMOUNT_TO_REFUND}"
    
    REFUND_HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$KB_URL/1.0/kb/payments/$PAYMENT_ID/refunds" \
        -u "$USERNAME:$PASSWORD" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -H "X-Killbill-ApiKey: $API_KEY" \
        -H "X-Killbill-ApiSecret: $API_SECRET" \
        -H "X-Killbill-CreatedBy: $CREATED_BY" \
        -d "$REFUND_PAYLOAD")

    if [[ "$REFUND_HTTP_STATUS" == 200 || "$REFUND_HTTP_STATUS" == 201 ]]; then
        echo "SUCCESS: Refund processed successfully."
    else
        echo "FAILED (Step 2): Could not process refund. HTTP Status: $REFUND_HTTP_STATUS"
        exit 1
    fi
elif [ -n "$PAYMENT_ID" ]; then
    echo -e "\nStep 2: Skipping refund (Amount available to refund is $AMOUNT_TO_REFUND)."
fi

# ==========================================
# STEP 3: Invoice Write-Off
# ==========================================
echo -e "\nStep 3: Tagging invoice as WRITTEN_OFF..."

TAGS_PAYLOAD="[\"$WRITTEN_OFF_TAG_ID\"]"

TAG_HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$KB_URL/1.0/kb/invoices/$INVOICE_ID/tags" \
    -u "$USERNAME:$PASSWORD" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -H "X-Killbill-ApiKey: $API_KEY" \
    -H "X-Killbill-ApiSecret: $API_SECRET" \
    -H "X-Killbill-CreatedBy: $CREATED_BY" \
    -d "$TAGS_PAYLOAD")

if [[ "$TAG_HTTP_STATUS" == 200 || "$TAG_HTTP_STATUS" == 201 ]]; then
    echo "SUCCESS: Invoice $INVOICE_ID has been successfully written off."
else
    echo "FAILED (Step 3): Could not write off invoice. HTTP Status: $TAG_HTTP_STATUS"
    exit 1
fi

echo -e "\n--- Process Completed Successfully ---"