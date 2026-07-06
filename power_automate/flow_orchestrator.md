# Power Automate — Alert Orchestration Flow

## Purpose
Central routing logic that receives a data-driven alert from Power BI, evaluates its severity, and dispatches notifications to the appropriate channels (Teams, Email, Slack) with escalation support.

## Trigger
**"When a data-driven alert is triggered (Power BI)"**

Configured against the pinned card visual in the OTIF dashboard.

## Flow Design

```
Power BI Alert Trigger
        │
        ▼
  Parse Alert Payload
        │
        ▼
  Compute Severity (Critical / Breached / Warning)
        │
        ├── Critical ──► Teams + Email + Slack (parallel)
        │       │
        │       └──► Start 30-min escalation timer
        │
        ├── Breached ──► Teams + Email (parallel)
        │
        └── Warning ──► Email only
```

## Steps

### 1. Parse Alert Payload
```json
{
  "alertTitle": "OTIF SLA Breach - V006",
  "metricName": "Rolling 7D OTIF %",
  "metricValue": 68.5,
  "thresholdValue": 92.0,
  "severity": "Critical",
  "vendorCode": "V006",
  "vendorName": "Atlantic Wholesale Goods",
  "region": "SE",
  "timestamp": "2026-07-01T14:30:00Z",
  "powerBiReportUrl": "https://app.powerbi.com/...",
  "acknowledgmentUrl": "https://prod-xx.webtask.run/ack?id=..."
}
```

### 2. Compute Severity

Use a **Condition** action:

| Condition | Severity |
|-----------|----------|
| `metricValue < thresholdValue * 0.85` (preview mode) | **Critical** (store as `@triggerOutputs()?['body/severity']`) |
| `metricValue < thresholdValue` | **Breached** |
| Else | **Warning** |

For direct value comparison (no preview mode), use the `metricValue` and `thresholdValue` from the payload directly.

### 3. Severity Router

Use a **Switch** action on the `severity` variable:

#### Case: `Critical`
- **Teams** — Call `flow_teams.json` with severity `Critical`
- **Email** — Call `flow_email.html` with red badge, urgent subject
- **Slack** — Call Slack webhook with `danger` color
- **Escalation timer** — Set `delay` to 30 minutes, then check acknowledgment status

#### Case: `Breached`
- **Teams** — Call `flow_teams.json` with severity `Breached`
- **Email** — Call `flow_email.html` with orange badge
- *(Slack skipped for breached-level)*

#### Case: `Warning`
- **Email** — Call `flow_email.html` with yellow badge, informational subject
- *(Teams and Slack skipped)*

### 4. Escalation Logic (Critical only)

```
Apply to Each (severity == "Critical") ──► Delay 30 min
        │
        ▼
    Compose: acknowledgementStatus
        │
        ▼
    Condition: acknowledged == false
        ├── True  ──► Send manager notification via Teams
        └── False ──► End
```

### 5. Acknowledgment Tracking

Design a **Compose** or **Update row** action to record in `alert_history`:

```json
{
  "acknowledged": "@{body('Parse_Payload')?['acknowledged']}",
  "acknowledged_by": "@{body('Parse_Payload')?['acknowledgedBy']}",
  "acknowledged_at": "@{utcNow()}"
}
```

If using a database connector (PostgreSQL/SQL Server), update `alert_history` table directly.

## Parallel Branch Configuration

For the **Critical** severity branch, use **Parallel Branches**:

```
+---------------------------+
| Branch 1: Send Teams       |
|   - Compose Adaptive Card  |
|   - Post message (Teams)   |
+---------------------------+
| Branch 2: Send Email       |
|   - Compose HTML body      |
|   - Send email (Outlook)   |
+---------------------------+
| Branch 3: Send Slack       |
|   - Compose Block Kit JSON |
|   - HTTP POST to webhook   |
+---------------------------+
```

Each branch runs independently. The flow waits for all branches to complete before proceeding to the escalation step.

## Error Handling

For each notification action, configure a **Configure Run After** fallback:

- If Teams fails → log error, continue (don't block email/Slack)
- If Email fails → log error, continue
- If Slack fails → log error, continue
- If all fail → send alert to `ops@company.com` as last resort

## Sample Run After Configuration

```
Send_Teams_Message ──► is successful ──► (next step)
                    ──► has timed out  ──► Log_Error (parallel)
                    ──► has failed     ──► Log_Error (parallel)
```

## Testing

1. **Trigger test**: Manually trigger with a test payload using the Power Automate test pane
2. **Severity routing test**: Test with metric values in each severity band
3. **Escalation test**: Send a Critical alert, do not acknowledge, verify manager notification after 30 minutes
4. **Error handling test**: Disconnect Slack webhook, verify Teams and Email still fire

## Dependencies

| Connector | Purpose |
|-----------|---------|
| Power BI | Alert trigger (premium license required) |
| Microsoft Teams | Channel message posting |
| Office 365 Outlook | Email notification |
| Slack | Webhook HTTP call |
| PostgreSQL / SQL Server | Alert history persistence (optional) |
