#!/bin/bash

KB_URL="http://localhost:8080"
B64_AUTH=$(echo -n "admin:password" | base64)
CREATED_BY="FixRebilling"

show_invoices() {
    local acct="$1"
    local label="$2"
    echo ""
    echo "========================================="
    echo " $label"
    echo "========================================="

    local tmpfile="/tmp/invoices_$$.json"
    > "$tmpfile"

    local ids=$(curl -s "$KB_URL/1.0/kb/accounts/$acct/invoices" \
      -H "Accept: application/json" \
      -H "Authorization: Basic $B64_AUTH" \
      -H "X-Killbill-ApiKey: $API_KEY" \
      -H "X-Killbill-ApiSecret: $API_SECRET" \
      | grep -o '"invoiceId":"[^"]*"' | cut -d'"' -f4)

    for id in $ids; do
        local inv=$(curl -s "$KB_URL/1.0/kb/invoices/$id?withItems=true" \
          -H "Accept: application/json" \
          -H "Authorization: Basic $B64_AUTH" \
          -H "X-Killbill-ApiKey: $API_KEY" \
          -H "X-Killbill-ApiSecret: $API_SECRET")

        echo "$inv" >> "$tmpfile"

        local num=$(echo "$inv" | grep -o '"invoiceNumber":"[^"]*"' | head -1 | cut -d'"' -f4)
        local dt=$(echo "$inv" | grep -o '"invoiceDate":"[^"]*"' | head -1 | cut -d'"' -f4)
        local amt=$(echo "$inv" | grep -o '"amount":[0-9.]*' | head -1 | cut -d: -f2)
        local bal=$(echo "$inv" | grep -o '"balance":[0-9.]*' | head -1 | cut -d: -f2)
        local item_types=$(echo "$inv" | grep -o '"itemType":"[^"]*"' | cut -d'"' -f4 | tr '\n' ', ' | sed 's/,$//')

        echo "  Invoice #$num | Date: $dt | Amount: $amt | Balance: $bal"
        echo "    Items: [$item_types]"
    done

    echo ""
    local fc=$(grep -o '"itemType":"FIXED"' "$tmpfile" | wc -l | tr -d ' ')
    local rc=$(grep -o '"itemType":"RECURRING"' "$tmpfile" | wc -l | tr -d ' ')
    local rp=$(grep -o '"itemType":"REPAIR_ADJ"' "$tmpfile" | wc -l | tr -d ' ')
    local cb=$(grep -o '"itemType":"CBA_ADJ"' "$tmpfile" | wc -l | tr -d ' ')
    echo "  Total FIXED items:      $fc"
    echo "  Total RECURRING items:  $rc"
    echo "  Total REPAIR_ADJ items: $rp"
    echo "  Total CBA_ADJ items:    $cb"

    if [ "$fc" -gt 1 ]; then
        echo ""
        echo "  *** DUPLICATE FIXED CHARGE DETECTED! ***"
    else
        echo ""
        echo "  *** No duplicate FIXED charge. ***"
    fi

    rm -f "$tmpfile"
}

echo "============================================================"
echo " FIX ATTEMPT: Move FIXED to DISCOUNT phase"
echo " Client's exact catalog but FIXED $723 moved from"
echo " EVERGREEN finalPhase -> 1-day DISCOUNT initialPhase"
echo "============================================================"

# --- Step 1: Create tenant ---
API_KEY="fix-$(date +%s)"
API_SECRET="secret"
echo -e "\n--- Step 1: Create tenant ---"
curl -s -X POST "$KB_URL/1.0/kb/tenants" \
  -H "Content-Type: application/json" \
  -H "Authorization: Basic $B64_AUTH" \
  -H "X-Killbill-CreatedBy: $CREATED_BY" \
  -d "{\"apiKey\":\"$API_KEY\",\"apiSecret\":\"$API_SECRET\"}" > /dev/null
sleep 2
echo " Done. apiKey=$API_KEY"

# --- Step 2: Set clock ---
echo -e "\n--- Step 2: Set clock to Jan 3 2030 ---"
curl -s -X POST "$KB_URL/1.0/kb/test/clock?requestedDate=2030-01-03T10:00:00.000Z" \
  -H "Authorization: Basic $B64_AUTH" \
  -H "X-Killbill-ApiKey: $API_KEY" \
  -H "X-Killbill-ApiSecret: $API_SECRET" > /dev/null
sleep 3
echo " Done."

# --- Step 3: Upload V1 — FIXED moved to DISCOUNT phase ---
echo -e "\n--- Step 3: Upload Catalog V1 (FIXED in DISCOUNT phase, NO addon) ---"
curl -s -X POST "$KB_URL/1.0/kb/catalog/xml?callCompletion=true&callTimeoutSec=15" \
  -H "Content-Type: text/xml" \
  -H "Authorization: Basic $B64_AUTH" \
  -H "X-Killbill-ApiKey: $API_KEY" \
  -H "X-Killbill-ApiSecret: $API_SECRET" \
  -H "X-Killbill-CreatedBy: $CREATED_BY" \
  -d '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<catalog>
    <effectiveDate>2030-01-01T00:00:00Z</effectiveDate>
    <catalogName>DEFAULT</catalogName>
    <recurringBillingMode>IN_ADVANCE</recurringBillingMode>
    <currencies>
        <currency>USD</currency>
    </currencies>
    <units>
        <unit name="cell-phone-message-one"/>
        <unit name="cell-phone-message-two"/>
        <unit name="cell-phone-message-three"/>
        <unit name="cell-phone-message-four"/>
        <unit name="cell-phone-message-five"/>
    </units>
    <products>
        <product name="Standard">
            <category>BASE</category>
        </product>
        <product name="RemoteControl">
            <category>ADD_ON</category>
        </product>
        <product name="OilSlick">
            <category>ADD_ON</category>
        </product>
    </products>
    <rules>
        <changePolicy>
            <changePolicyCase>
                <policy>IMMEDIATE</policy>
            </changePolicyCase>
        </changePolicy>
        <changeAlignment>
            <changeAlignmentCase>
                <alignment>START_OF_BUNDLE</alignment>
            </changeAlignmentCase>
        </changeAlignment>
        <cancelPolicy>
            <cancelPolicyCase>
                <productCategory>BASE</productCategory>
                <policy>IMMEDIATE</policy>
            </cancelPolicyCase>
            <cancelPolicyCase>
                <policy>IMMEDIATE</policy>
            </cancelPolicyCase>
        </cancelPolicy>
        <createAlignment>
            <createAlignmentCase>
                <alignment>START_OF_BUNDLE</alignment>
            </createAlignmentCase>
        </createAlignment>
        <billingAlignment>
            <billingAlignmentCase>
                <alignment>ACCOUNT</alignment>
            </billingAlignmentCase>
        </billingAlignment>
        <priceList>
            <priceListCase>
                <toPriceList>DEFAULT</toPriceList>
            </priceListCase>
        </priceList>
    </rules>
    <plans>
        <plan name="standard-daily" prettyName="standard-daily-prepaid-prettyname">
            <product>Standard</product>
            <recurringBillingMode>IN_ADVANCE</recurringBillingMode>
            <initialPhases>
                <phase type="DISCOUNT">
                    <duration>
                        <unit>DAYS</unit>
                        <number>1</number>
                    </duration>
                    <fixed type="ONE_TIME">
                        <fixedPrice>
                            <price>
                                <currency>USD</currency>
                                <value>723</value>
                            </price>
                        </fixedPrice>
                    </fixed>
                    <recurring>
                        <billingPeriod>DAILY</billingPeriod>
                        <recurringPrice>
                            <price>
                                <currency>USD</currency>
                                <value>234</value>
                            </price>
                        </recurringPrice>
                    </recurring>
                </phase>
            </initialPhases>
            <finalPhase type="EVERGREEN">
                <duration>
                    <unit>UNLIMITED</unit>
                </duration>
                <recurring>
                    <billingPeriod>DAILY</billingPeriod>
                    <recurringPrice>
                        <price>
                            <currency>USD</currency>
                            <value>234</value>
                        </price>
                    </recurringPrice>
                </recurring>
            </finalPhase>
        </plan>
        <plan name="remotecontrol-daily" prettyName="remotecontrol-daily-prettyname">
            <product>RemoteControl</product>
            <recurringBillingMode>IN_ADVANCE</recurringBillingMode>
            <initialPhases/>
            <finalPhase type="EVERGREEN">
                <duration>
                    <unit>UNLIMITED</unit>
                </duration>
                <recurring>
                    <billingPeriod>DAILY</billingPeriod>
                    <recurringPrice>
                        <price>
                            <currency>USD</currency>
                            <value>0</value>
                        </price>
                    </recurringPrice>
                </recurring>
                <usages/>
            </finalPhase>
        </plan>
        <plan name="oilslick-daily" prettyName="oilslick-daily-prettyname">
            <product>OilSlick</product>
            <recurringBillingMode>IN_ADVANCE</recurringBillingMode>
            <initialPhases/>
            <finalPhase type="EVERGREEN">
                <duration>
                    <unit>UNLIMITED</unit>
                </duration>
                <recurring>
                    <billingPeriod>DAILY</billingPeriod>
                    <recurringPrice>
                        <price>
                            <currency>USD</currency>
                            <value>0</value>
                        </price>
                    </recurringPrice>
                </recurring>
                <usages/>
            </finalPhase>
        </plan>
    </plans>
    <priceLists>
        <defaultPriceList name="DEFAULT">
            <plans>
                <plan>standard-daily</plan>
                <plan>remotecontrol-daily</plan>
                <plan>oilslick-daily</plan>
            </plans>
        </defaultPriceList>
    </priceLists>
</catalog>' > /dev/null
sleep 3
echo " Done."

# --- Step 4: Create account + payment ---
echo -e "\n--- Step 4: Create account + payment method ---"
ACC_RES=$(curl -s -D - -X POST "$KB_URL/1.0/kb/accounts?callCompletion=true&callTimeoutSec=15" \
  -H "Content-Type: application/json" \
  -H "Authorization: Basic $B64_AUTH" \
  -H "X-Killbill-ApiKey: $API_KEY" \
  -H "X-Killbill-ApiSecret: $API_SECRET" \
  -H "X-Killbill-CreatedBy: $CREATED_BY" \
  -d '{"name":"Fix Rebilling Test","currency":"USD"}')
ACCOUNT_ID=$(echo "$ACC_RES" | grep -i "^Location:" | awk '{print $2}' | tr -d '\r' | awk -F'/' '{print $NF}')
echo " Account: $ACCOUNT_ID"
sleep 2

curl -s -X POST "$KB_URL/1.0/kb/accounts/$ACCOUNT_ID/paymentMethods?isDefault=true&callCompletion=true&callTimeoutSec=15" \
  -H "Content-Type: application/json" \
  -H "Authorization: Basic $B64_AUTH" \
  -H "X-Killbill-ApiKey: $API_KEY" \
  -H "X-Killbill-ApiSecret: $API_SECRET" \
  -H "X-Killbill-CreatedBy: $CREATED_BY" \
  -d '{"pluginName":"__EXTERNAL_PAYMENT__","pluginInfo":{}}' > /dev/null
sleep 2
echo " Payment method added."

# --- Step 5: Create subscription under V1 ---
echo -e "\n--- Step 5: Create subscription (V1 only exists) ---"
SUB_RES=$(curl -s -D - -X POST "$KB_URL/1.0/kb/subscriptions?callCompletion=true&callTimeoutSec=15" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "Authorization: Basic $B64_AUTH" \
  -H "X-Killbill-ApiKey: $API_KEY" \
  -H "X-Killbill-ApiSecret: $API_SECRET" \
  -H "X-Killbill-CreatedBy: $CREATED_BY" \
  -d '{"accountId":"'"$ACCOUNT_ID"'","planName":"standard-daily"}')
SUB_ID=$(echo "$SUB_RES" | grep -i "^Location:" | awk '{print $2}' | tr -d '\r' | awk -F'/' '{print $NF}')
echo " Subscription: $SUB_ID"
sleep 5

show_invoices "$ACCOUNT_ID" "INVOICES AFTER CREATION (Jan 3)"

# --- Step 6: Upload V2 with addon availability (same DISCOUNT structure) ---
echo -e "\n--- Step 6: Upload Catalog V2 (effective Jan 8, WITH addon, same DISCOUNT structure) ---"
curl -s -X POST "$KB_URL/1.0/kb/catalog/xml?callCompletion=true&callTimeoutSec=15" \
  -H "Content-Type: text/xml" \
  -H "Authorization: Basic $B64_AUTH" \
  -H "X-Killbill-ApiKey: $API_KEY" \
  -H "X-Killbill-ApiSecret: $API_SECRET" \
  -H "X-Killbill-CreatedBy: $CREATED_BY" \
  -d '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<catalog>
    <effectiveDate>2030-01-08T00:00:00Z</effectiveDate>
    <catalogName>DEFAULT</catalogName>
    <recurringBillingMode>IN_ADVANCE</recurringBillingMode>
    <currencies>
        <currency>USD</currency>
    </currencies>
    <units>
        <unit name="cell-phone-message-one"/>
        <unit name="cell-phone-message-two"/>
        <unit name="cell-phone-message-three"/>
        <unit name="cell-phone-message-four"/>
        <unit name="cell-phone-message-five"/>
    </units>
    <products>
        <product name="Standard">
            <category>BASE</category>
            <available>
                <addonProduct>RemoteControl</addonProduct>
            </available>
        </product>
        <product name="RemoteControl">
            <category>ADD_ON</category>
        </product>
        <product name="OilSlick">
            <category>ADD_ON</category>
        </product>
    </products>
    <rules>
        <changePolicy>
            <changePolicyCase>
                <policy>IMMEDIATE</policy>
            </changePolicyCase>
        </changePolicy>
        <changeAlignment>
            <changeAlignmentCase>
                <alignment>START_OF_BUNDLE</alignment>
            </changeAlignmentCase>
        </changeAlignment>
        <cancelPolicy>
            <cancelPolicyCase>
                <productCategory>BASE</productCategory>
                <policy>IMMEDIATE</policy>
            </cancelPolicyCase>
            <cancelPolicyCase>
                <policy>IMMEDIATE</policy>
            </cancelPolicyCase>
        </cancelPolicy>
        <createAlignment>
            <createAlignmentCase>
                <alignment>START_OF_BUNDLE</alignment>
            </createAlignmentCase>
        </createAlignment>
        <billingAlignment>
            <billingAlignmentCase>
                <alignment>ACCOUNT</alignment>
            </billingAlignmentCase>
        </billingAlignment>
        <priceList>
            <priceListCase>
                <toPriceList>DEFAULT</toPriceList>
            </priceListCase>
        </priceList>
    </rules>
    <plans>
        <plan name="standard-daily" prettyName="standard-daily-prepaid-prettyname">
            <product>Standard</product>
            <recurringBillingMode>IN_ADVANCE</recurringBillingMode>
            <initialPhases>
                <phase type="DISCOUNT">
                    <duration>
                        <unit>DAYS</unit>
                        <number>1</number>
                    </duration>
                    <fixed type="ONE_TIME">
                        <fixedPrice>
                            <price>
                                <currency>USD</currency>
                                <value>723</value>
                            </price>
                        </fixedPrice>
                    </fixed>
                    <recurring>
                        <billingPeriod>DAILY</billingPeriod>
                        <recurringPrice>
                            <price>
                                <currency>USD</currency>
                                <value>234</value>
                            </price>
                        </recurringPrice>
                    </recurring>
                </phase>
            </initialPhases>
            <finalPhase type="EVERGREEN">
                <duration>
                    <unit>UNLIMITED</unit>
                </duration>
                <recurring>
                    <billingPeriod>DAILY</billingPeriod>
                    <recurringPrice>
                        <price>
                            <currency>USD</currency>
                            <value>234</value>
                        </price>
                    </recurringPrice>
                </recurring>
            </finalPhase>
        </plan>
        <plan name="remotecontrol-daily" prettyName="remotecontrol-daily-prettyname">
            <product>RemoteControl</product>
            <recurringBillingMode>IN_ADVANCE</recurringBillingMode>
            <initialPhases/>
            <finalPhase type="EVERGREEN">
                <duration>
                    <unit>UNLIMITED</unit>
                </duration>
                <recurring>
                    <billingPeriod>DAILY</billingPeriod>
                    <recurringPrice>
                        <price>
                            <currency>USD</currency>
                            <value>0</value>
                        </price>
                    </recurringPrice>
                </recurring>
                <usages/>
            </finalPhase>
        </plan>
        <plan name="oilslick-daily" prettyName="oilslick-daily-prettyname">
            <product>OilSlick</product>
            <recurringBillingMode>IN_ADVANCE</recurringBillingMode>
            <initialPhases/>
            <finalPhase type="EVERGREEN">
                <duration>
                    <unit>UNLIMITED</unit>
                </duration>
                <recurring>
                    <billingPeriod>DAILY</billingPeriod>
                    <recurringPrice>
                        <price>
                            <currency>USD</currency>
                            <value>0</value>
                        </price>
                    </recurringPrice>
                </recurring>
                <usages/>
            </finalPhase>
        </plan>
    </plans>
    <priceLists>
        <defaultPriceList name="DEFAULT">
            <plans>
                <plan>standard-daily</plan>
                <plan>remotecontrol-daily</plan>
                <plan>oilslick-daily</plan>
            </plans>
        </defaultPriceList>
    </priceLists>
</catalog>' > /dev/null
sleep 3
echo " Done."

# --- Step 7: Warp clock past V2 ---
echo -e "\n--- Step 7: Warp clock to Jan 10 2030 ---"
curl -s -X POST "$KB_URL/1.0/kb/test/clock?requestedDate=2030-01-10T10:00:00.000Z" \
  -H "Authorization: Basic $B64_AUTH" \
  -H "X-Killbill-ApiKey: $API_KEY" \
  -H "X-Killbill-ApiSecret: $API_SECRET" > /dev/null
sleep 5
echo " Done."

show_invoices "$ACCOUNT_ID" "INVOICES BEFORE PLAN CHANGE (Jan 10)"

# --- Step 8: Plan change to same plan ---
echo -e "\n--- Step 8: Plan change to SAME plan ---"
curl -s -X PUT "$KB_URL/1.0/kb/subscriptions/$SUB_ID?callCompletion=true&callTimeoutSec=15" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "Authorization: Basic $B64_AUTH" \
  -H "X-Killbill-ApiKey: $API_KEY" \
  -H "X-Killbill-ApiSecret: $API_SECRET" \
  -H "X-Killbill-CreatedBy: $CREATED_BY" \
  -d '{"planName":"standard-daily"}' > /dev/null
sleep 5
echo " Done."

show_invoices "$ACCOUNT_ID" "INVOICES AFTER PLAN CHANGE (Jan 10)"

echo ""
echo "============================================================"
echo " RESULT: Compare FIXED count before vs after plan change."
echo " If still 1 -> DISCOUNT phase fix works!"
echo " If 2 -> DISCOUNT phase fix did NOT help."
echo "============================================================"