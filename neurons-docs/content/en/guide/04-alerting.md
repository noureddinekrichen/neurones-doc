---
title: Alerting & Notifications
navTitle: Alerting
part: part3
weight: 4
labels:
  health-rules: Health rules
  notifications: Policies & notifications
  incidents: Incidents & War Rooms
---

The Alerting module brings together everything that lets the platform warn a team rather than just display numbers: threshold definitions, notification channels, and manual incident tracking. The "Alerting" screen is organized into six tabs: Overview, Rules, Alerts, Incidents, Policies, Destinations, Templates.

## Health Rules {#health-rules}

A health rule defines a threshold on an indicator (for example: error rate above 20%, or latency above 1500&nbsp;ms), evaluated over a given scope (application, environment, service). When a rule is violated, it generates an event, visible both in the Events screen and in the Troubleshoot "Health Rule Violations" tab.

{{< callout >}}
To avoid false alarms on anecdotal traffic, a minimum request-volume threshold is applied before a latency or error-rate rule is evaluated.
{{< /callout >}}

## Policies, destinations, and templates {#notifications}

Three building blocks work together to turn an event into an actual notification:

- **Destinations** — the channels a notification can be sent to: email, Slack webhook, Microsoft Teams webhook, generic webhook, or a REST API call. Each destination can be tested before being used in production.
- **Templates** — a notification's content and formatting, reusable across policies.
- **Policies** — the rule that links a trigger condition to one or more destinations and a template.

## Incidents and War Rooms {#incidents}

An incident can be opened manually as soon as a team starts investigating a problem, independently of automatic events. It groups the affected services, a status (open / resolved), and free-form notes. The Troubleshoot "War Rooms" tab is where these incidents are tracked, and it offers AI-generated postmortem report generation once the incident is resolved.
