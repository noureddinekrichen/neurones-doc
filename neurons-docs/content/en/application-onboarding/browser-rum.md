---
title: Browser RUM Onboarding
linkTitle: Browser RUM
lede: Instrument a web frontend with OpenTelemetry browser instrumentation so Neurons shows what real users experience — page views, Web Vitals, frontend errors, sessions, frustration signals, and the backend traces behind each page.
menus:
  onboarding:
    parent: application-onboarding
    weight: 2
labels:
  add-sdk: Add browser instrumentation
  implement: Implement browser telemetry
  telemetry: Browser telemetry
  configure: Configure Neurons
  replay: Session replay
  identity: Application & frontend identity
  test-traffic: Generate test traffic
  verify: Verify in Neurons
  security: Security & privacy
  rollback: Disable / rollback
---

## Overview {#overview}

Browser Real User Monitoring (RUM) measures what users actually experience in their browser. Backend instrumentation answers *"what happened inside the application?"*; RUM answers *"what did the user see?"*. In Neurons, browser telemetry appears in the **Browser Performance** screen:

| Telemetry | What it tells you |
|---|---|
| Page views | Which pages are visited and how long they take to load — for full page loads and for single-page-app (SPA) route changes, with a breakdown of the load (network, server, rendering). |
| Web Vitals | The standard perceived-performance indicators — LCP, INP, CLS, FCP and TTFB — with percentiles, a good / needs improvement / poor rating, and an Apdex score. |
| Frontend errors | JavaScript errors raised in users' browsers, grouped by message. |
| Sessions | Each user's visit as a chronological journey across pages, and the most common page-to-page paths. |
| User actions and frustration signals | Rage clicks, dead clicks and error clicks — signs of a degraded experience even without a visible technical error. |
| Browser, device and location | Breakdowns by browser, operating system, device type and country. |
| Correlation with the backend | For each page, the backend business transactions it triggers, and for each trace, the browser and backend spans together. |
{firstcol="26"}

RUM is **independent of backend onboarding**: an application can have backend tracing without RUM, or both. Enabling or disabling RUM never changes the backend configuration. Correlation with backend traces requires the backend to be instrumented too — see the [PHP](../php/), [Java](../java/), [.NET](../dotnet/) and [Python](../python/) guides.

## Architecture {#architecture}

{{< flow label="How browser telemetry reaches Neurons" >}}
app | Browser | The user's browser loads your web application
→
app | OpenTelemetry browser instrumentation | Runs in the page: records page views, Web Vitals, errors, API calls and user actions
→ OTLP over HTTP (JSON), same origin
app | RUM ingestion endpoint | A route on your web server or reverse proxy that adds the Neurons token and the visitor's IP address
→ OTLP over HTTP (JSON) + `X-Neurones-Token`
platform | Neurons | The ingestion service recognizes browser telemetry, resolves geolocation and stores it
→
platform | Browser Performance / RUM | Page loads, Web Vitals, errors, sessions, frustration, frontend ↔ backend traces
{{< /flow >}}

- Browser instrumentation exports **OTLP/HTTP JSON**, which the Neurons ingestion service accepts directly: unlike backend agents, browser telemetry does not need to go through the OpenTelemetry Collector.
- The **RUM ingestion endpoint** is what the browser calls. It keeps the Neurons token out of the browser and passes on the visitor's IP address — see [Configure Neurons](#configure).
- **Trace correlation:** the browser instrumentation adds the W3C `traceparent` header to the application's API calls, so a user action and the backend work it triggers are recorded in the same distributed trace.

## Prerequisites {#prerequisites}

- A web frontend whose JavaScript entry point you can change, rebuild and redeploy.
- A web server or reverse proxy **on the same origin** as the frontend, able to forward requests and add a header (nginx, Apache, IIS, an API gateway, or a backend route).
- The Neurons ingestion token, provided by the Neurons platform team and held **server-side only** — plus the query token if session replay is in scope.
- The Neurons ingestion service URL for the target environment.
- The `application` name, the frontend `service.name` and the deployment environment, agreed with the backend services (see [Application and Frontend Identity](#identity)).
- An explicit decision on optional features: session replay, user identification, browser log export.

## Add Browser Instrumentation {#add-sdk}

### Install the packages

```bash
npm install \
  @opentelemetry/api \
  @opentelemetry/sdk-trace-web \
  @opentelemetry/sdk-trace-base \
  @opentelemetry/resources \
  @opentelemetry/semantic-conventions \
  @opentelemetry/context-zone \
  @opentelemetry/instrumentation \
  @opentelemetry/instrumentation-fetch \
  @opentelemetry/instrumentation-document-load \
  @opentelemetry/exporter-trace-otlp-http \
  web-vitals
```

| Package | Role |
|---|---|
| @opentelemetry/sdk-trace-web, sdk-trace-base | Tracer provider and batch span processor |
| @opentelemetry/resources, semantic-conventions | Resource attributes (`service.name`, `application`, ...) |
| @opentelemetry/context-zone | Keeps the active span across asynchronous callbacks |
| @opentelemetry/instrumentation-fetch | One span per `fetch` call, and `traceparent` injection |
| @opentelemetry/instrumentation-xml-http-request | The same for `XMLHttpRequest` — add it if the application uses XHR |
| @opentelemetry/instrumentation-document-load | Spans for the initial page load, with navigation timings |
| @opentelemetry/exporter-trace-otlp-http | Sends spans as OTLP/HTTP JSON |
| web-vitals | Measures LCP, INP, CLS, FCP and TTFB |
{firstcol="30" mono="1"}

### Initialize Browser Instrumentation

1. **Initialize first.** Import the RUM setup on the first line of the application entry point, so instrumentation is active before the first network call.
2. **Register the context manager.** Pass `ZoneContextManager` to `provider.register()` — installing `@opentelemetry/context-zone` alone does nothing.
3. **Exclude the telemetry endpoints** from the Fetch/XHR instrumentation, so telemetry uploads do not create spans of their own.
4. **Never break the page.** Wrap initialization — ideally each feature — in its own `try/catch`, and guard `crypto.randomUUID()`, which is unavailable in non-secure (HTTP) contexts. RUM that fails must leave the application working.
5. **One switch.** Make RUM depend on a single build setting, so it can be turned off by rebuilding.
6. **Propagate trace context.** Same-origin API calls get `traceparent` automatically. For an API on another origin, list it in the Fetch instrumentation's `propagateTraceHeaderCorsUrls` and allow the `traceparent` header in that API's CORS configuration.

Minimal initialization, to adapt to your build tool and framework:

```js
// rum.js — imported on the first line of the application entry point
import { WebTracerProvider } from '@opentelemetry/sdk-trace-web';
import { BatchSpanProcessor } from '@opentelemetry/sdk-trace-base';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { resourceFromAttributes } from '@opentelemetry/resources';
import { ZoneContextManager } from '@opentelemetry/context-zone';
import { registerInstrumentations } from '@opentelemetry/instrumentation';
import { FetchInstrumentation } from '@opentelemetry/instrumentation-fetch';
import { DocumentLoadInstrumentation } from '@opentelemetry/instrumentation-document-load';

const RUM_ENDPOINT = '/v1/traces'; // same-origin RUM ingestion endpoint; empty = RUM off

if (RUM_ENDPOINT) {
  try {
    const provider = new WebTracerProvider({
      resource: resourceFromAttributes({
        'service.name': '<FRONTEND_SERVICE_NAME>',
        'application': '<APPLICATION_NAME>',
        'deployment.environment': '<ENVIRONMENT>',
        'telemetry.sdk.language': 'webjs',
      }),
      spanProcessors: [new BatchSpanProcessor(new OTLPTraceExporter({ url: RUM_ENDPOINT }))],
    });
    provider.register({ contextManager: new ZoneContextManager() });

    registerInstrumentations({
      instrumentations: [
        new DocumentLoadInstrumentation(),
        new FetchInstrumentation({ ignoreUrls: [/\/v1\/traces/, /\/v1\/logs/, /\/rum\/replay/] }),
      ],
    });
  } catch (e) {
    // RUM must never break the application
  }
}
```

## Implement Neurons Browser Telemetry {#implement}

{{< callout type="warn" >}}
**The initialization above is not enough to populate Browser Performance.** The standard OpenTelemetry Web SDK creates generic spans (document load, `fetch` calls). It does not create the Neurons-specific browser telemetry described in the next section. Neurons does not currently ship an official browser library: these signals must currently be implemented by the integrating application, following the contract below.
{{< /callout >}}

The application must implement:

| Signal | What to implement |
|---|---|
| Hard page views | Turn the initial page load into a `page-view` span with `nav.type=hard` and the page-load timings. |
| SPA soft page views | Create a new `page-view` span with `nav.type=soft` on every client-side route change, and keep it active while the route's API calls start. |
| Web Vitals | Turn each `web-vitals` measurement into a `web-vital` span with its name, value and rating. |
| Sessions | Generate a `session.id` and set it on every span. |
| Browser errors | Catch JavaScript errors and unhandled promise rejections and record them as spans with `rum.kind=app-error` (or as log records). |
| API-call classification | Mark the application's API `fetch`/XHR spans with `api.kind`, and set a normalized `api.route`. |
| Frustration signals | Detect rage, dead and error clicks and record them as spans with `frustration.type`. |
{firstcol="26"}

## Browser Telemetry Expected by Neurons {#telemetry}

Neurons fills the Browser Performance screens from specific span names and attributes. A wrong name is not rejected — the data is simply missing from the screens.

### Page views

| Item | Contract |
|---|---|
| Span name | `page-view` (exact) |
| nav.type | `hard` for a full page load, `soft` for an SPA route change |
| Page | `page.path`, `page.url` |
| Timings | `pl.*` attributes — see [Page-load timings](#page-load-timings) |
{firstcol="26" mono="1"}

- For an SPA, a new `page-view` span must be created for **every route change**, with `nav.type=soft`, `pl.render_ms` (time to the next paint) and `pl.soft_ms`.
- **Route API total, Route backend total and Data wait** are computed by joining a soft `page-view` with the browser API calls **of the same trace**. The soft page-view span must therefore be active — or an ancestor — when the route's API calls start; API calls started outside it are not counted for that route.
- **Data wait** uses `pl.data_wait_ms` or `route.data_wait_ms` when present, and falls back to `pl.backend_ms` otherwise.
- When `pl.total_ms` is absent, the span duration is used.
- Business Journey steps of type `rum_page` are counted from `page-view` spans and their `page.path` — see [Business Journeys](../../#bj).

### Page-load timings {#page-load-timings}

All values are milliseconds.

| Attribute | Meaning |
|---|---|
| pl.total_ms | Total page-load time |
| pl.backend_ms, pl.frontend_ms | Server part and browser part of the load (`pl.frontend_ms` is derived as total − backend when absent) |
| pl.ttfb_ms, pl.first_byte_ms | Time to first byte (`pl.first_byte_ms` defaults to `pl.ttfb_ms`) |
| pl.dns_ms, pl.tcp_ms, pl.tls_ms | DNS lookup, TCP connection, TLS handshake |
| pl.request_ms, pl.response_download_ms | Request wait, response download |
| pl.dom_interactive_ms, pl.dom_content_loaded_ms, pl.dom_complete_ms | DOM milestones |
| pl.dom_processing_ms | DOM processing (`domComplete − responseEnd` when absent) |
| pl.load_event_ms | `load` event handler duration |
| pl.render_ms | Time to render (`view.render_ms` is also accepted) |
| pl.soft_ms | SPA route-change duration |
| pl.data_wait_ms, route.data_wait_ms | Optional: time an SPA route waits for data |
{firstcol="30" mono="1"}

Instead of computed `pl.*` values, a hard `page-view` span may carry the raw browser **Navigation Timing** fields; Neurons derives the timings from them when the corresponding `pl.*` attribute is absent:

| Raw fields (also accepted with a `navigation.` prefix) | Derived timing |
|---|---|
| loadEventEnd | pl.total_ms |
| domainLookupEnd − domainLookupStart | pl.dns_ms |
| connectEnd − connectStart | pl.tcp_ms |
| connectEnd − secureConnectionStart | pl.tls_ms |
| responseStart − requestStart | pl.request_ms |
| responseEnd − responseStart | pl.response_download_ms |
| responseStart | pl.ttfb_ms |
| domInteractive, domContentLoadedEventEnd, domComplete | pl.dom_interactive_ms, pl.dom_content_loaded_ms, pl.dom_complete_ms |
| domComplete − responseEnd | pl.dom_processing_ms |
| loadEventEnd − loadEventStart | pl.load_event_ms |
{mono="1,2"}

### Web Vitals and Apdex

| Item | Contract |
|---|---|
| Span name | `web-vital` (exact) |
| wv.name | `LCP`, `INP`, `CLS`, `FCP` or `TTFB` |
| wv.value | LCP, INP, FCP, TTFB in **milliseconds**; CLS as a **unitless score** |
| wv.rating | Exactly `good`, `needs-improvement` or `poor` — the values emitted by the `web-vitals` library |
{firstcol="26" mono="1"}

{{< callout type="warn" >}}
Without `wv.rating`, the Web Vital values are still shown, but the good / needs improvement / poor distributions stay empty and the Browser Performance **Apdex** is not calculated.
{{< /callout >}}

Browser Performance **Apdex** is calculated from the ratings of **LCP, INP and CLS** only:

```text
Apdex = (good + 0.5 × needs-improvement) / total
```

FCP and TTFB are displayed as Web Vitals but do not contribute to Apdex. Thresholds displayed by Neurons:

| Vital | Good | Needs improvement | Poor | In Apdex |
|---|---|---|---|---|
| LCP | ≤ 2500 ms | ≤ 4000 ms | > 4000 ms | Yes |
| INP | ≤ 200 ms | ≤ 500 ms | > 500 ms | Yes |
| CLS | ≤ 0.1 | ≤ 0.25 | > 0.25 | Yes |
| FCP | ≤ 1800 ms | ≤ 3000 ms | > 3000 ms | No |
| TTFB | ≤ 800 ms | ≤ 1800 ms | > 1800 ms | No |
{mono="1"}

### API calls

- Only **CLIENT** spans (the `fetch`/XHR spans) count as browser API calls.
- A CLIENT span is classified as an **API call** when it carries `api.kind` (or an explicit `rum.kind=api-call`).
- A CLIENT span with a URL or route but no API classification is treated as a **resource call**.
- The route shown is resolved from `api.route`, then `url.path`, then `http.route`, then `http.target`. Set a normalized `api.route` (identifiers replaced, e.g. `/api/orders/:id`) so calls group correctly.

### Browser errors

A browser span is counted as a JavaScript error **only when it carries `rum.kind=app-error`**:

- the span name `app.error` alone is **not** sufficient;
- an ERROR span status alone is **not** sufficient;
- `exception.*` attributes are **not** used for browser errors.

| Attribute | Content |
|---|---|
| rum.kind | `app-error` (required) |
| error.type | Error type, e.g. `TypeError` |
| error.message | Error message — if absent, the span name is used as the message |
| error.stack | Stack trace |
| page.path | Page where the error occurred |
{firstcol="26" mono="1"}

Errors can also be sent as **OTLP log records**: a log record is counted as a browser error when it carries `rum.kind=js-error` or `rum.kind=app-error`, with the same `error.*` attributes. This requires a `/v1/logs` forwarding route — see [Configure Neurons](#configure).

### Frustration signals

| Attribute | Content |
|---|---|
| frustration.type | `rage_click`, `dead_click` or `error_click` |
| target.selector, target.text | The clicked element |
| click.x, click.y | Click coordinates |
| page.url | Current page |
| session.id | Required — signals without it are not recorded |
{firstcol="26" mono="1"}

### Sessions and users

- `session.id` is **required** for sessions, journeys, replay and frustration signals. Neurons groups telemetry by the value it receives: the application decides the scope (for example one identifier per browser tab, kept in `sessionStorage`).
- The session timeline looks back up to 30 days.
- The **Users** metric counts distinct `user.id` values (or `user.name` when `user.id` is absent) on page views. Without user identification it stays empty. Sessions and Users are not available on long time ranges served from aggregated data.
- `user.id` and `user.name` are personal data — see [Security & privacy](#security).

## Configure Neurons {#configure}

### Configure the Browser RUM Ingestion Endpoint

Expose the ingestion paths on the frontend's own origin and forward them to the Neurons ingestion service. The forwarding route adds the token, so no credential is ever sent to the browser.

| Path called by the browser | Forward to | Headers the route must add |
|---|---|---|
| /v1/traces | `<NEURONES_INGEST_URL>/v1/traces` | `X-Neurones-Token: <ingestion token>`, `X-Forwarded-For`, `X-Real-IP` |
| /v1/logs — only if browser errors are sent as logs | `<NEURONES_INGEST_URL>/v1/logs` | `X-Neurones-Token: <ingestion token>`, `X-Forwarded-For`, `X-Real-IP` |
| /rum/replay — only if session replay is enabled | `<NEURONES_INGEST_URL>/rum/replay` | `X-Neurones-Token: <query token>`, `X-Forwarded-For`, `X-Real-IP` |
{firstcol="26" mono="1"}

Example with nginx (placeholders to replace; keep the token out of version control, for example by substituting it from the server environment at startup):

```nginx
location /v1/traces {
    proxy_pass         <NEURONES_INGEST_URL>/v1/traces;
    proxy_set_header   Host              $host;
    proxy_set_header   X-Real-IP         $remote_addr;
    proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header   X-Neurones-Token  <NEURONES_INGEST_TOKEN>;
}
```

A `/v1/logs` route, when used, is configured the same way with the ingestion token.

{{< callout type="warn" >}}
**Traces and session replay use different tokens.** In the current Neurons contract, `/v1/traces` and `/v1/logs` are authenticated with the **ingestion** token and `/rum/replay` with the **query** token. If the replay route is given the ingestion token, replay uploads are rejected with 401 unless the two tokens are equal in your environment. Confirm both values with the Neurons platform team.
{{< /callout >}}

If the Neurons platform team provides a RUM endpoint that the browser can call directly without a token, it can replace the forwarding route. In that case geolocation reflects whatever connects to the ingestion service, not necessarily the visitor.

### Geolocation

There is no client-side geolocation. Neurons resolves country, region, city and coordinates from the first **public** IP address in `X-Forwarded-For` (then `X-Real-IP`) of the ingestion request, and overwrites any `geo.*` attribute sent by the browser. Without these headers, every visitor is located at the address of the forwarding server.

## Optional — Session Replay {#replay}

{{< callout type="warn" >}}
**Session replay is not part of standard onboarding.** It records what users see and do. Applications handling credentials, financial or legal data, identity documents or other sensitive information require a dedicated privacy and masking review before it is enabled.
{{< /callout >}}

When approved, a recorder such as `@rrweb/record` uploads batches to `/rum/replay`:

| Field | Content |
|---|---|
| app | The **frontend `service.name`** (e.g. `shop-web`) — not the `application` value |
| session_id | Same value as the `session.id` span attribute |
| page_view_id | Page-view identifier |
| sequence_number | Batch counter, starting at 0 |
| compressed_events | Base64 of the gzip-compressed JSON (`{ events, metadata }`, or a plain array of rrweb events) |
| content_encoding | `gzip` or `identity` |
| reason, trigger_reason, trigger_timestamp | Optional: why the batch was sent; first notable event of the session |
{firstcol="26" mono="1"}

Replay sessions are associated with the browser telemetry through the frontend `service.name` and `session.id`: if `app` does not equal the frontend `service.name`, replays are not linked to the sessions and frustration signals of that frontend.

Unknown fields are rejected with **422**. Default size limits: 2 MiB compressed and 25 MiB decompressed per batch. Configure the recorder to mask every input value and to block elements that must never be recorded.

## Application and Frontend Identity {#identity}

Two attributes identify browser telemetry, at two levels:

- **`service.name` identifies the frontend.** Browser Performance lists and filters frontends by `service.name`, and replay is matched on it.
- **`application` groups services.** The same `application` value on the frontend and on its backend services groups them under one logical application; it is used for grouping and filtering, not to identify the frontend in Browser Performance.

Example:

```text
Frontend:  application = shop   service.name = shop-web   deployment.environment = production
Backend:   application = shop   service.name = shop-api   deployment.environment = production
```

The same `application` (`shop`) groups the frontend and the backend; the different `service.name` values (`shop-web`, `shop-api`) identify each service.

### Resource attributes

Set once, when the SDK is initialized:

| Attribute | Required | Notes |
|---|---|---|
| telemetry.sdk.language = webjs | **Yes** | Marks the data as browser RUM. Without it, the frontend is not shown in Browser Performance. |
| service.name | Yes | Identifies the frontend in Browser Performance, e.g. `shop-web`. Also the `app` value for session replay. |
| application | Yes | **The same value as the backend services**, so the frontend and its backend are grouped as one application. |
| deployment.environment | Yes | The same value as the backend, e.g. `production`. |
| app.type | No | `spa` or `mpa`. When absent, Neurons infers it from `nav.type`: any soft navigation means SPA, hard-only means MPA. |
{firstcol="30" mono="1"}

### Attributes on every span

Neurons reads these from each **span**, not from the resource — set them on every span the instrumentation creates or enriches:

| Attribute | Notes |
|---|---|
| session.id | **Required** for sessions, journeys, replay and frustration signals — see [Sessions and users](#telemetry). |
| page.path, page.url | The current page. |
| browser.name, os.name, device.type | Breakdown dimensions — `device.type`: `desktop`, `mobile` or `tablet`. |
| user.id, user.name | Optional, only after login and only if approved — personal data. `user.id` feeds the Users metric. |
{firstcol="30" mono="1"}

## Generate test traffic {#test-traffic}

After deploying the instrumented frontend:

1. Open the application from a real browser and do a full page reload.
2. Navigate between pages (route changes, for an SPA).
3. Perform an action that calls the backend.
4. Trigger a controlled JavaScript error.
5. Click the same spot three times quickly, to produce a rage click if frustration signals are implemented.
{.steps}

Telemetry is sent in batches: allow a few seconds before checking Neurons.

## Verify in Neurons {#verify}

1. In the browser's developer tools (Network), requests to the RUM ingestion endpoint return **2xx** — a 401 means the forwarding route does not add a valid token.
2. The frontend appears in **Browser Performance** under its `service.name`.
3. Page views arrive, for the full reload and for route changes.
4. Web Vitals arrive with their ratings, and the Apdex is calculated.
5. The controlled JavaScript error appears.
6. Sessions show the pages visited, in order.
7. Browser, OS and device are populated, and the location matches the visitor — not the server.
8. The backend call appears in the same trace as the browser action, and the page lists the business transactions it triggers.
9. For an SPA, route changes show Route API total, Route backend total and Data wait.
10. If enabled: frustration signals, the Users metric and session replay appear.
{.steps}

{{< callout >}}
An onboarding is not complete until it has been validated on the deployed environment, not only locally.
{{< /callout >}}

## Security & privacy {#security}

- **Never put a Neurons token in frontend code**, nor in a build variable that ends up in the JavaScript bundle. Tokens live only on the forwarding route.
- Never commit tokens to version control.
- Do not capture form values, passwords, authentication tokens, payment data or `Authorization` headers.
- `user.id` and `user.name` are personal data: send them only if approved.
- Review the collection of visitor IP addresses and locations against the application's privacy requirements.
- Session replay stays disabled unless approved after a privacy and masking review.

## Troubleshooting {#troubleshooting}

| Symptom | Likely cause | Action |
|---|---|---|
| `/v1/traces` returns 401 | The forwarding route does not add the ingestion token, or adds a wrong one | Check the route's header and the token value. |
| `/rum/replay` returns 401 while traces work | Replay is authenticated with the query token | Configure the query token on the replay route. |
| `/rum/replay` returns 422 | Unknown field, wrong `content_encoding`, or batch too large | Send only the documented fields; use `gzip` or `identity`; keep batches under the limits. |
| Replays not linked to sessions | Replay `app` differs from the frontend `service.name` | Send the frontend `service.name` as `app`. |
| Frontend missing from Browser Performance | `telemetry.sdk.language=webjs` missing, or no `page-view` spans | Check the resource attributes and implement page views (see [Implement Neurons Browser Telemetry](#implement)). |
| JavaScript errors missing | Error spans without `rum.kind=app-error` (an `app.error` name or ERROR status alone is not enough) | Set `rum.kind=app-error` and the `error.*` attributes. |
| Web Vitals shown but no ratings and no Apdex | `wv.rating` missing or not exactly `good` / `needs-improvement` / `poor` | Send the rating emitted by the `web-vitals` library. |
| API calls listed as resource calls | `api.kind` not set on the API spans | Set `api.kind` and a normalized `api.route`. |
| Route API total / backend total / Data wait empty | API calls not in the same trace as the soft `page-view` | Keep the soft page-view span active while the route's API calls start. |
| Every visitor located in the same place | The forwarding route does not pass the visitor IP | Add `X-Forwarded-For` / `X-Real-IP`. |
| Sessions, replay or frustration signals empty | `session.id` missing on spans | Set `session.id` on every span. |
| Users metric empty | No `user.id` on page views, or a long time range | Enable approved user identification; use a shorter range. |
| Browser and backend spans in separate traces | `traceparent` not sent, or backend not instrumented | Check the Fetch instrumentation; for a cross-origin API, `propagateTraceHeaderCorsUrls` and CORS. |
| Breakdowns show "unknown" | `browser.name` / `os.name` / `device.type` set only on the resource | Set them on each span. |
| Frontend grouped apart from its backend | Different `application` values | Use the same `application` value on both sides. |
| The page fails to load in production only | Unguarded RUM initialization, e.g. `crypto.randomUUID()` over HTTP | Guard ID generation; wrap each RUM feature in `try/catch`. |
| A package is installed but has no effect | Never imported or registered (e.g. `ZoneContextManager`) | Check the RUM source, not only `package.json`. |

## Disable / rollback {#rollback}

RUM can be disabled without touching backend tracing:

1. Turn the RUM switch off, or remove the RUM import from the application entry point.
2. Rebuild and redeploy the frontend — RUM is part of the JavaScript bundle, so a server-side change alone does not disable it.
3. Optionally remove the RUM ingestion routes from the web server.
4. Confirm that no new browser telemetry arrives in Neurons, and that backend traces continue normally.
