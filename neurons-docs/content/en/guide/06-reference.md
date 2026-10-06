---
title: Reference
part: ref
weight: 6
---

## Query API {#api}

Neurons exposes an HTTP API that powers every screen described in this document. Every call must present a token in the `X-Neurones-Token` header, except for a handful of technical endpoints.

| Category | Endpoints | Contents |
|---|---|---|
| Catalog | 4 | Applications, environments, per-application aggregates. |
| Services | 3 | Service list, metrics, service map. |
| Traces | 8 | Search, filters, trace-based service map, trace detail. |
| Logs | 2 | Log list and volume. |
| RUM | 42 | Overview, Web Vitals, sessions, replay, journeys, frontend errors, geography. |
| Business transactions | 20 | Catalog, configuration, groups, notifications, flow map. |
| BT detection rules | 5 | Create, list, update, delete, prioritize. |
| Business Journeys | 6 | Create, list, detail, update, delete, funnel. |
| Events | 15 | List, create, count, monthly summary, retention, purge, lifecycle. |
| External event management | 3 | Configuration of forwarding to an external tool. |
| Health rules | 7 | Create, list, detail, evaluation, investigation context. |
| Incidents | 3 | Create, list, update. |
| Alerting | 18 | Overview, destinations, templates, policies. |
| Webhooks | 1 | Receiving transaction alerts, authenticated by signature. |
| OpenTelemetry Collector | 4 | Registration, retrieval, and configuration reporting for a remote agent. |
| Troubleshoot | 8 | Contributors, error signatures, window comparison. |
| Database | 2 | Statistics and metrics for outbound database calls. |
| Data source | 2 | Active Vertica cluster and immediate failover. |
| Ingestion (OTLP) | 3 | Receiving traces, logs, and metrics in OpenTelemetry format. |
| Operations | 2 | Health check and Prometheus export, unauthenticated. |
{mono="2"}

This summary is meant to give a sense of the platform's capabilities. The [Query API reference](reference/query-api/) lists every endpoint with its path and purpose; for the technical detail of each parameter, see the interactive Swagger documentation published by the service (path `/docs`).
{.ref-note}

## Glossary {#glossary}

| Term | Definition |
|---|---|
| **APM** | Application Performance Monitoring — monitoring application performance. |
| **Span** | A single step inside a trace. |
| **Trace** | The set of a request's spans, linked together. |
| **RED** | Rate, Errors, Duration — a service's three baseline indicators. |
| **Rollup** | A periodic aggregation computation that summarizes raw data for fast display. |
| **Business transaction** | A named, tracked application entry point, detected automatically. |
| **Business Journey** | A conversion funnel linking several pages and business transactions. |
| **Health Rule** | A rule defining a threshold on an indicator, whose violation generates an event. |
| **Incident / War Room** | A manual, team-opened tracking of an ongoing investigation. |
| **RUM** | Real User Monitoring — measuring end users' real experience. |
| **Web Vitals** | Standard browser-side perceived-performance indicators: LCP, INP, CLS, FCP, TTFB. |
| **GeoIP** | A database mapping IP addresses to geographic locations. |
| **Vertica** | The analytical database that serves as the single data warehouse for the entire platform. |
| **OTel Collector** | The component that receives telemetry from instrumented applications and forwards it to Neurons. |
| **Retention** | The length of time a data category is kept before automatic deletion. |
| **vbr** | Vertica Backup and Restore — the utility bundled with Vertica to back up and restore the database. |
{firstcol="26"}
