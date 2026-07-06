# Slack Webhook Integration — OTIF SLA Alerts

## Overview

Sends formatted Slack messages to the `#logistics-alerts` channel when a Power BI data-driven alert fires. Uses Slack's Block Kit for rich message formatting.

---

## Prerequisites

1. A Slack workspace with permissions to create Incoming Webhooks
2. Create a Slack App → "Incoming Webhooks" → Activate → Add New Webhook → Post to `#logistics-alerts`
3. Copy the webhook URL (format: `https://hooks.slack.com/services/T00/B00/xxxxxxxx`)

---

## Power Automate Flow Design

### Flow Name
`OTIF SLA Breach — Slack Notification`

### Trigger
| Setting | Value |
|---------|-------|
| Connector | Power BI |
| Trigger | When a data-driven alert is triggered |
| Dashboard | OTIF SLA Monitoring |

### Steps

#### Step 1: Parse Alert Payload
| Setting | Value |
|---------|-------|
| Action | Initialize variable — `Severity` |
| Type | String |
| Expression | `if(less(triggerOutputs()?['body/metricValue'], 0.85), 'Critical', if(less(triggerOutputs()?['body/metricValue'], 0.92), 'Breached', 'Warning'))` |

#### Step 2: Compose Slack Message (Block Kit JSON)

```json
{
  "channel": "#logistics-alerts",
  "username": "OTIF SLA Bot",
  "icon_emoji": ":warning:",
  "blocks": [
    {
      "type": "header",
      "text": {
        "type": "plain_text",
        "text": "⚠️ OTIF SLA Breach"
      }
    },
    {
      "type": "section",
      "fields": [
        {
          "type": "mrkdwn",
          "text": "*Alert:*\n@{triggerOutputs()?['body/alertTitle']}"
        },
        {
          "type": "mrkdwn",
          "text": "*Metric:*\n@{formatNumber(triggerOutputs()?['body/metricValue'], 'P2')}"
        }
      ]
    },
    {
      "type": "section",
      "fields": [
        {
          "type": "mrkdwn",
          "text": "*Threshold:*\n@{formatNumber(triggerOutputs()?['body/threshold'], 'P2')}"
        },
        {
          "type": "mrkdwn",
          "text": "*Direction:*\n@{triggerOutputs()?['body/direction']}"
        }
      ]
    },
    {
      "type": "section",
      "fields": [
        {
          "type": "mrkdwn",
          "text": "*Dashboard:*\n@{triggerOutputs()?['body/dashboardName']}"
        },
        {
          "type": "mrkdwn",
          "text": "*Severity:*\n@{variables('Severity')}"
        }
      ]
    },
    {
      "type": "context",
      "elements": [
        {
          "type": "mrkdwn",
          "text": "Triggered at: @{triggerOutputs()?['body/occurred']}"
        }
      ]
    },
    {
      "type": "actions",
      "elements": [
        {
          "type": "button",
          "text": {
            "type": "plain_text",
            "text": "Open Report"
          },
          "url": "@{triggerOutputs()?['body/url']}",
          "style": "primary"
        }
      ]
    },
    {
      "type": "divider"
    }
  ]
}
```

#### Step 3: HTTP POST to Slack Webhook
| Setting | Value |
|---------|-------|
| Connector | HTTP |
| Method | POST |
| URI | `https://hooks.slack.com/services/YOUR/TEAM/WEBHOOK` |
| Headers | `Content-Type: application/json` |
| Body | `@outputs('Compose_Slack_Message')` |

---

## Slack Message Preview

```
╔══════════════════════════════════════════════════╗
║  ⚠️ OTIF SLA Breach                              ║
║                                                  ║
║  Alert:   OTIF SLA Breach    Metric:   87.30%    ║
║  Threshold:  92.00%          Direction: Less than║
║  Dashboard:  OTIF SLA Mon.   Severity: Breached  ║
║                                                  ║
║  Triggered at: 2025-01-15T14:30:00Z              ║
║                                                  ║
║  [ Open Report ]                                 ║
╚══════════════════════════════════════════════════╝
```

---

## Orchestration — Multi-Channel Routing

In the main Power Automate flow, use a **Condition** block to route by severity:

```
IF severity == "Critical"
  → Teams (Adaptive Card) + Email (HTML) + Slack (Block Kit)  [PARALLEL]
  → Start escalation timer (30 min)
ELSE IF severity == "Breached"
  → Teams (Adaptive Card) + Email (HTML)  [PARALLEL]
ELSE
  → Email only
```

### Escalation Logic

| Step | Action |
|------|--------|
| 1 | Send initial notification (channels per severity) |
| 2 | Wait 30 minutes (using "Delay" action) |
| 3 | Check if alert was acknowledged (via Teams Action.Submit or a separate acknowledgment flow) |
| 4 | If NOT acknowledged → Send escalation notification to manager channel + SMS via Teams |
| 5 | If acknowledged → Log to audit and stop |
