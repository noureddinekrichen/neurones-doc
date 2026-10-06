---
title: Python Application Onboarding
linkTitle: Python
lede: Instrument a Python application (Django, Flask, FastAPI) with OpenTelemetry auto-instrumentation so its HTTP requests, database calls and distributed traces appear in Neurons.
menus:
  onboarding:
    parent: opentelemetry
    weight: 50
labels:
  versions: Supported versions
  connectivity: Collector connectivity
  install: Install OpenTelemetry
  configure: Configure OpenTelemetry
  start: Start with OpenTelemetry
  http-capture: HTTP data capture
  done: Definition of Done
---

Python applications are instrumented with **`opentelemetry-distro`**, activated by placing the **`opentelemetry-instrument`** wrapper in front of the application's real start command. Unlike PHP, there is no extension to enable: the wrapper command is what turns instrumentation on.

## Scope {#scope}

This guide covers **backend tracing only**: HTTP server spans, database spans, distributed trace propagation, and the application and environment identification Neurons uses to group them.

It does **not** configure:

- **Logs** — the configuration below sets `OTEL_LOGS_EXPORTER=none`.
- **Metrics** — Neurons computes service metrics (rate, errors, duration) from the traces themselves; the configuration sets `OTEL_METRICS_EXPORTER=none`.
- **Browser RUM** — instrumenting the Python backend does not enable any browser monitoring. See [Browser RUM Onboarding](../browser-rum/).

HTTP header and body capture are optional add-ons, described at the end of this page.

## Architecture {#architecture}

{{< flow label="How Python telemetry reaches Neurons" >}}
app | Your Python application | Started through `opentelemetry-instrument`, with framework and database instrumentation
→ OTLP over HTTP (protobuf)
platform | Neurons OpenTelemetry Collector | Receives the telemetry, converts it to OTLP/JSON and adds the ingestion token
→ OTLP over HTTP (JSON)
platform | apm-ingest | Neurons ingestion service: validates and stores the telemetry
→
platform | Neurons APM | Applications, services, traces and business transactions
{{< /flow >}}

{{< callout >}}
Python telemetry always goes through the Neurons OpenTelemetry Collector. The exporter sends OTLP/protobuf; the Collector converts it and forwards it to the Neurons ingestion service, which only accepts OTLP/JSON. Never point the Python exporter directly at the ingestion service.
{{< /callout >}}

## Prerequisites {#prerequisites}

Before onboarding, confirm that:

- A supported Python version is installed on the target application server (see [Supported versions](#versions)), with pip available.
- The team can install Python dependencies in the application's environment (virtualenv, image, ...).
- The application server can reach the Neurons OpenTelemetry Collector (see [Collector connectivity](#connectivity)).
- The real application start command can be modified.
- Environment variables can be supplied to the real application process.
- The `application` name and a unique `OTEL_SERVICE_NAME` have been agreed (see [Application vs service](#naming)).
- The deployment environment, the application framework and — if database tracing is required — the database driver are known.

{{< callout >}}
The Neurons platform team provides or confirms the Collector endpoint, whether it requires authentication or TLS, and the application/service naming convention before onboarding.
{{< /callout >}}

## Supported versions {#versions}

Requirements of the current OpenTelemetry Python packages (`opentelemetry-distro` 0.66b0, exporter 1.45.0 — checked on PyPI, October 2026):

| Component | Requirement |
|---|---|
| Python | 3.10 or later |
| Django | 2.0 or later ({{< mono "opentelemetry-instrumentation-django" >}}) |
| Flask | 1.0 or later ({{< mono "opentelemetry-instrumentation-flask" >}}) |
| FastAPI | 0.92 or later, below 1.0 ({{< mono "opentelemetry-instrumentation-fastapi" >}}) |
{firstcol="26"}

{{< callout type="warn" >}}
Supported Python, framework and server versions must be confirmed against the current Neurons compatibility matrix. Combinations that meet the requirements above are expected to work but must pass the full [verification](#verify) before being considered supported. Package requirements change between releases — check the version you install.
{{< /callout >}}

## Check Collector connectivity {#connectivity}

Before configuring the application, check from the **application server** that the Collector's OTLP/HTTP port (4318 by default) is reachable.

Linux:

```bash
nc -vz <NEURONES_COLLECTOR_HOST> 4318
```

Windows (PowerShell):

```powershell
Test-NetConnection <NEURONES_COLLECTOR_HOST> -Port 4318
```

Then check that the OTLP receiver answers. This sends an empty export, so nothing is stored:

```bash
curl -i -X POST http://<NEURONES_COLLECTOR_HOST>:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d '{"resourceSpans":[]}'
```

| Result | Meaning |
|---|---|
| HTTP 2xx | The Collector is reachable and accepts OTLP/HTTP. |
| HTTP 401 / 403 | The Collector requires authentication — see [Authentication](#auth). |
| Connection refused / timeout | Firewall, wrong host or port, or the Collector is not running. Fix before going further. |
{firstcol="26"}

## Install OpenTelemetry {#install}

Install into the environment the application actually runs in (its virtualenv or image):

```bash
pip install \
  opentelemetry-distro \
  opentelemetry-exporter-otlp-proto-http
```

- {{< mono "opentelemetry-distro" >}} — the Python OpenTelemetry distribution and the auto-instrumentation tooling, including `opentelemetry-instrument`.
- {{< mono "opentelemetry-exporter-otlp-proto-http" >}} — trace export over OTLP HTTP/protobuf.

### Framework instrumentation

| Framework | Package |
|---|---|
| Django | opentelemetry-instrumentation-django |
| Flask | opentelemetry-instrumentation-flask |
| FastAPI | opentelemetry-instrumentation-fastapi |
{mono="2"}

Install only the package matching the application's framework, for example:

```bash
pip install opentelemetry-instrumentation-django
```

Other frameworks are not covered by this guide. If an OpenTelemetry instrumentation package exists for them, it can be used the same way, but the result requires manual verification.

### Database instrumentation

| Database / driver | Package |
|---|---|
| PostgreSQL / psycopg2 | opentelemetry-instrumentation-psycopg2 |
| PostgreSQL / psycopg (3) | opentelemetry-instrumentation-psycopg |
| MySQL / PyMySQL (below 2.0) | opentelemetry-instrumentation-pymysql |
| SQLite | opentelemetry-instrumentation-sqlite3 |
{mono="2"}

Install the instrumentation for the driver the application actually uses. **Framework instrumentation does not instrument database drivers**: queries are traced only when the matching driver instrumentation is installed. For a driver not listed here, use the corresponding OpenTelemetry instrumentation package and verify the result.

## Configure OpenTelemetry {#configure}

Currently validated Neurons Python configuration:

```bash
OTEL_SERVICE_NAME=<SERVICE_NAME>

OTEL_TRACES_EXPORTER=otlp_proto_http
OTEL_METRICS_EXPORTER=none
OTEL_LOGS_EXPORTER=none

OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://<NEURONES_COLLECTOR_HOST>:4318/v1/traces

OTEL_PROPAGATORS=tracecontext,baggage

OTEL_RESOURCE_ATTRIBUTES=application=<APPLICATION_NAME>,deployment.environment=<ENVIRONMENT>
```

| Setting | Role |
|---|---|
| OTEL_SERVICE_NAME | The **service** name in Neurons (see below). |
| OTEL_TRACES_EXPORTER | `otlp_proto_http`: the trace exporter of the validated setup. |
| OTEL_METRICS_EXPORTER / OTEL_LOGS_EXPORTER | `none`: only traces are exported (see [Scope](#scope)). |
| OTEL_EXPORTER_OTLP_TRACES_ENDPOINT | The Neurons Collector traces endpoint. |
| OTEL_PROPAGATORS | `tracecontext,baggage`: W3C trace propagation between instrumented services. |
| application | The **application** name in Neurons (see below). |
| deployment.environment | Identifies the deployed environment — for example `production`, `preprod`, `staging`, `qa`, `development`. |
{firstcol="30" mono="1"}

Compatibility note: for the current Neurons ingestion contract, use `deployment.environment`, not the newer `deployment.environment.name`.

### Application vs service {#naming}

Neurons groups telemetry on two levels:

- **Application** — the `application` resource attribute. It is what the Applications screen lists. Several services can share one application.
- **Service** — `OTEL_SERVICE_NAME`. Each service is listed, with its own metrics, under its application.

Example — a booking platform made of a Django back office and a FastAPI public API:

| Component | application | OTEL_SERVICE_NAME |
|---|---|---|
| Django back office | booking | booking-backoffice |
| FastAPI public API | booking | booking-api |
{mono="2,3"}

Both appear under the **booking** application, as two services.

{{< callout type="warn" >}}
The attribute must be named exactly `application` — not `application.name`, not `service.namespace`. Telemetry without a valid `application` attribute is not rejected: it is grouped under **Unassigned**.
{{< /callout >}}

### Authentication {#auth}

The Neurons ingestion service authenticates the **Collector**, not the application: the Collector adds the ingestion token when it forwards data, so a Python application normally sends no credential.

If your Collector is configured to require a header from applications (the [connectivity check](#connectivity) returns 401/403), the platform team provides the header name and value. Set it as a process environment variable, never in source code:

```bash
OTEL_EXPORTER_OTLP_HEADERS=<HEADER_NAME>=<VALUE>
```

### TLS / HTTPS {#tls}

The `http://` endpoint above is for a Collector reached over a trusted internal network. Use the Collector URL and transport defined by the Neurons platform team for the target environment: when it provides an `https://` endpoint, use it as given.

### Django-specific configuration

```bash
DJANGO_SETTINGS_MODULE=<DJANGO_PROJECT>.settings
```

The Django settings module must be available before instrumentation initializes the application. If Django cannot import the project when instrumentation is enabled, verify that the project root is on Python's import path.

### Make the configuration available to the real process

{{< callout type="warn" >}}
The `OTEL_*` variables must be visible to the process that actually runs the Python application. Values present only in an interactive shell, a developer terminal, a local `.env` file or a deployment script do not guarantee that the production service receives them.
{{< /callout >}}

This applies whatever manages the process — for example systemd, a Windows Service, Supervisor, Docker, Kubernetes, or a Gunicorn, Uvicorn or Waitress service.

## Start the application with OpenTelemetry {#start}

Auto-instrumentation is activated by placing `opentelemetry-instrument` before the application's real start command.

Gunicorn:

```bash
opentelemetry-instrument gunicorn app:app
```

Uvicorn / FastAPI:

```bash
opentelemetry-instrument uvicorn app:app
```

Waitress / Django:

```bash
opentelemetry-instrument waitress-serve --host=127.0.0.1 --port=8000 core.wsgi:application
```

{{< callout type="warn" >}}
If the production process starts the application directly, without `opentelemetry-instrument`, auto-instrumentation is not active. Validate the command used by the actual running service, not only the command documented in a deployment script.
{{< /callout >}}

## Generate test traffic {#test-traffic}

After the instrumented application starts:

1. Trigger a real HTTP request.
2. Prefer an endpoint that also executes a database query.
3. If distributed tracing is required, use a request that calls another instrumented service.
{.steps}

This single test validates HTTP tracing, database tracing and trace propagation where applicable. Telemetry can take several seconds to appear: an empty result immediately after the request does not necessarily mean the configuration is wrong.

## Verification in Neurons {#verify}

1. The application appears in the Applications list under its `application` name (not under **Unassigned**).
2. The service appears under that application with its `OTEL_SERVICE_NAME`, with a recent `last_seen`.
3. A real HTTP trace is visible, with the correct route, method and status code.
4. The trace duration is plausible.
5. Database spans appear for database-backed requests, with the database system and name populated where supported.
6. The database operation is classified correctly.
7. Downstream service calls share the same distributed trace, where applicable.
{.steps}

{{< callout >}}
An onboarding is not complete until it has been validated against the deployed environment. Local development validation alone is not sufficient.
{{< /callout >}}

If telemetry arrives but a field is blank or wrongly classified, compare the raw span attributes with the current Neurons ingestion contract: OpenTelemetry semantic conventions evolve, and different instrumentation versions may emit different attribute names.

## Optional — HTTP data capture {#http-capture}

Not part of the required onboarding. Enable it only when it is in scope.

### Headers

Header capture is provided natively by the Python OpenTelemetry server instrumentation:

```bash
OTEL_INSTRUMENTATION_HTTP_CAPTURE_HEADERS_SERVER_REQUEST=content-type,accept
OTEL_INSTRUMENTATION_HTTP_CAPTURE_HEADERS_SERVER_RESPONSE=content-type
OTEL_INSTRUMENTATION_HTTP_CAPTURE_HEADERS_SANITIZE_FIELDS=.*cookie.*,.*authorization.*,.*api.?key.*
```

- Header capture is opt-in: nothing is captured while the allow-lists are empty.
- Capture only explicitly approved headers.
- Sanitization patterns are a second safety layer; never rely on them as a substitute for a narrow allow-list.
- Never configure unrestricted production capture such as `.*` without a specific review.

### Request / response bodies — requires application middleware

The standard Python OpenTelemetry server instrumentation does not capture bodies. Body capture is performed by application middleware, controlled by two switches that must stay off by default:

```bash
OTEL_CAPTURE_HTTP_REQUEST_BODY=false
OTEL_CAPTURE_HTTP_RESPONSE_BODY=false
```

{{< callout type="warn" >}}
**Current implementation limitation.** The existing reference middleware is Django-only. It has independent request/response switches, off by default, and captures `application/json` bodies only, truncated to a fixed 4096 bytes. It does **not** provide field-level redaction or sensitive-route exclusions. Do not enable body capture on routes that carry credentials, tokens, personal data or payment data. Flask and FastAPI applications have no reference middleware yet.
{{< /callout >}}

Recommended production requirements for any body-capture implementation (not all are implemented by the current middleware):

- disabled by default, with independent request/response switches;
- a maximum byte limit and an approved content-type allow-list;
- field-level redaction and sensitive-route exclusions;
- no multipart/file upload, binary or streamed-response capture;
- no credentials, authentication tokens, passwords or payment card values.

For the general capture policy, see [Application Instrumentation (OpenTelemetry)](../../#otel).

## Security and privacy {#security}

- Never commit secrets.
- HTTP headers must use allow-lists; `Authorization` and `Cookie` must not be captured in clear text.
- Body capture must be opt-in, and kept off sensitive routes — the current reference middleware cannot redact fields.
- Do not capture SQL bind values containing personal or sensitive information unless explicitly approved.

## Rollback / disable {#rollback}

**Temporarily disable telemetry** — packages and wrapper stay in place:

```bash
OTEL_TRACES_EXPORTER=none
```

1. Restart or reload the Python application process.
2. Send test traffic.
3. Confirm that `last_seen` in Neurons no longer advances after the expected observation window.

To re-enable, restore the exporter value and restart the process.

**Fully remove the instrumentation:**

1. Remove `opentelemetry-instrument` from the process start command.
2. Remove the `OTEL_*` environment variables from the service.
3. Uninstall the packages from the application's environment, for example:

   ```bash
   pip uninstall opentelemetry-distro opentelemetry-exporter-otlp-proto-http \
     opentelemetry-instrumentation-django opentelemetry-instrumentation-psycopg2
   ```

4. Restart the process and check that the application works normally.

## Troubleshooting {#troubleshooting}

| Symptom | Likely cause | Action |
|---|---|---|
| No spans at all | Process not started through `opentelemetry-instrument` | Verify the actual running process command. |
| No spans even though the wrapper is present | `OTEL_*` environment missing from the actual service | Inspect the actual service/process environment. |
| Export errors in the application logs | Collector unreachable, or it requires authentication or TLS | Run the [connectivity check](#connectivity); see [Authentication](#auth) and [TLS](#tls). |
| Application fails during startup after enabling OpenTelemetry | Exporter package/configuration mismatch | Verify `opentelemetry-exporter-otlp-proto-http` is installed and `OTEL_TRACES_EXPORTER=otlp_proto_http` is set. |
| Django works normally but fails only when instrumented | Django project/settings import path unavailable during instrumentation startup | Verify `DJANGO_SETTINGS_MODULE` and the Python import path. |
| Service visible but listed under **Unassigned** | `application` attribute missing or misspelled | Check `OTEL_RESOURCE_ATTRIBUTES` (see [Application vs service](#naming)). |
| HTTP traces appear, database spans do not | Matching database instrumentation package missing | Verify the instrumentation for the actual database driver. |
| Application appears in Neurons but fields are blank | Semantic convention mismatch | Compare emitted span attributes with the current Neurons ingestion contract. |

## Definition of Done {#done}

Backend onboarding is complete only when:

- the Python and framework versions meet the [supported versions](#versions)
- the required OpenTelemetry, framework and database instrumentation packages are installed
- the Collector is reachable from the application server, with authentication and TLS as required
- `OTEL_*` variables reach the real production process
- the real process starts through `opentelemetry-instrument`
- `application` and a unique `OTEL_SERVICE_NAME` are configured, and the application is not listed under **Unassigned**
- `deployment.environment` is configured
- a real HTTP trace is visible in Neurons, with correct route, method and status
- database tracing is verified where applicable
- distributed propagation is verified where applicable
- sensitive HTTP body capture remains disabled unless approved
- both rollback paths (temporary disable, full removal) are documented and the temporary disable has been tested
- the deployed environment has been validated
