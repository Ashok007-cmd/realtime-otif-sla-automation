# Power BI Data-Driven Alert Configuration

## Prerequisites

- **Power BI Pro or Premium Per User** license (alerts only work in Power BI Service, not Desktop)
- Report published to a shared workspace
- Dashboard created with pinned visuals from the report

---

## Alert 1: OTIF SLA Breach (7-Day Rolling OTIF < 92%)

### Step 1: Pin the Visual
1. Open the published report in Power BI Service
2. Navigate to the OTIF Overview page
3. Hover over the **"7D Rolling OTIF %" card visual** → Pin icon
4. Pin to a dashboard named **"OTIF SLA Monitoring"**

### Step 2: Create the Alert
1. On the dashboard, hover over the pinned card → click the bell icon 🔔
2. Configure:
   - **Alert title**: `OTIF SLA Breach`
   - **Condition**: `If value is less than 0.92` (92%)
   - **Frequency**: `At least once every 6 hours` (default)
   - **Send me an email**: Checked (Power BI native)
   - **Power Automate flow**: Also selected (see Phase 3)

### Step 3: Test the Alert
1. Temporarily adjust the condition to `less than 1.00` to trigger immediately
2. Verify the alert fires and the Power Automate flow triggers
3. Reset to `less than 0.92`

---

## Alert 2: Backorder Cost Threshold Exceeded

### Step 1: Pin the Visual
1. Pin the **"Total Open Backorder Cost" card visual** to the dashboard

### Step 2: Create the Alert
1. Click the bell icon on the pinned backorder card
2. Configure:
   - **Alert title**: `Backorder Cost Threshold`
   - **Condition**: `If value is greater than 10000` ($10K single vendor)
   - Also create for `greater than 50000` ($50K aggregate)

---

## Alert 3: Consecutive Delivery Failures

### Step 1: Pin a Table Visual Showing Alerts
1. Create a **table visual** bound to `v_alert_dashboard_summary`
2. Filter to `alert_type = "CONSECUTIVE_FAILURES"`
3. Show columns: `entity (vendor)`, `alert_severity`, `metric_value`, `event_date`
4. Pin to dashboard

### Step 2: Create the Alert
1. Set alert condition: `If value is greater than 2` (when consecutive failures ≥ 3)
2. Frequency: every 1 hour

---

## Alert 4: Carrier Performance Breach

### Step 1: Pin the Visual
1. Pin the **Carrier On Time % table** (or a card showing worst-performing carrier) to the dashboard

### Step 2: Create the Alert
1. Set alert condition: `If value is less than 0.85` (85% on-time threshold)

---

## Alert Payload JSON Schema (for Power Automate)

When triggered, Power BI sends this JSON body to the Power Automate flow:

```json
{
  "type": "alert",
  "alertTitle": "OTIF SLA Breach",
  "dashboardName": "OTIF SLA Monitoring",
  "cardName": "7D Rolling OTIF %",
  "metricName": "7D Rolling OTIF %",
  "metricValue": 0.873,
  "threshold": 0.92,
  "direction": "Less than",
  "url": "https://app.powerbi.com/groups/xxx/reports/yyy/",
  "dashboardId": "xxx",
  "occurred": "2025-01-15T14:30:00Z"
}
```

This schema is parsed in the Power Automate flow for dynamic notification content.

---

## Alert Management Best Practices

| Practice | Detail |
|----------|--------|
| **Throttling** | Set minimum frequency to 6 hours to avoid notification spam |
| **Severity tiers** | Use OTIF % ranges to classify: **Critical** < 85%, **Breached** 85-92%, **Warning** 92-95% |
| **Escalation** | Critical alerts route to Teams + Email + Slack; Warning alerts route to email only |
| **Quiet hours** | Configure weekend/holiday suppression if needed |
| **Validation** | Review alert history weekly; tune thresholds quarterly based on actual performance |
| **Cooldown** | Alert fatigue is real — ensure the flow doesn't re-trigger within the cooldown period |
