---
title: PHP Application Onboarding
linkTitle: PHP
lede: Instrument a PHP application with OpenTelemetry so its HTTP requests, database calls and distributed traces appear in Neurons — then, optionally, add HTTP data capture.
menus:
  onboarding:
    parent: opentelemetry
    weight: 10
labels:
  versions: Supported versions
  connectivity: Collector connectivity
  configure: Configure OpenTelemetry
  http-capture: HTTP data capture
  done: Definition of Done
---

PHP applications are instrumented with the PHP OpenTelemetry extension together with Composer auto-instrumentation packages. No wrapped start command is required.

Auto-instrumentation becomes active when:

- {{< mono "ext-opentelemetry" >}} is enabled in the PHP runtime;
- the required Composer instrumentation packages are installed and loaded;
- `OTEL_PHP_AUTOLOAD_ENABLED=true` is visible to the PHP process that actually serves the application.

## Scope {#scope}

This guide covers **backend tracing only**: HTTP server spans, PDO database spans, distributed trace propagation, and the application and environment identification Neurons uses to group them.

It does **not** configure:

- **Logs** — PHP log export is not part of this onboarding; the configuration below sets `OTEL_LOGS_EXPORTER=none`.
- **Metrics** — Neurons computes service metrics (rate, errors, duration) from the traces themselves; the configuration sets `OTEL_METRICS_EXPORTER=none`.
- **Browser RUM** — instrumenting the PHP backend does not enable any browser monitoring. Browser RUM is onboarded separately: see [Browser RUM Onboarding](../browser-rum/).

HTTP header/body capture is an optional add-on, described at the end of this page.

## Architecture {#architecture}

{{< flow label="How PHP telemetry reaches Neurons" >}}
app | Your PHP application | `ext-opentelemetry` + Composer auto-instrumentation (framework and PDO spans)
→ OTLP over HTTP (protobuf)
platform | Neurons OpenTelemetry Collector | Receives the telemetry, converts it to OTLP/JSON and adds the ingestion token
→ OTLP over HTTP (JSON)
platform | apm-ingest | Neurons ingestion service: validates and stores the telemetry
→
platform | Neurons APM | Applications, services, traces and business transactions
{{< /flow >}}

{{< callout >}}
PHP telemetry always goes through the Neurons OpenTelemetry Collector. The PHP exporter sends OTLP/protobuf; the Collector converts it and forwards it to the Neurons ingestion service, which only accepts OTLP/JSON. Never point the PHP exporter directly at the ingestion service.
{{< /callout >}}

## Prerequisites {#prerequisites}

Before onboarding, confirm that:

- A supported PHP version is installed on the target application server (see [Supported versions](#versions)).
- Composer is installed.
- {{< mono "ext-opentelemetry" >}} can be installed and enabled.
- The application server can reach the Neurons OpenTelemetry Collector (see [Collector connectivity](#connectivity)).
- The `application` name and a unique `OTEL_SERVICE_NAME` have been agreed (see [Application vs service](#naming)).
- The target deployment environment is known.
- The team can configure environment variables for the real PHP runtime process.

{{< callout >}}
The Neurons platform team provides or confirms the Collector endpoint, whether it requires authentication or TLS, and the application/service naming convention before onboarding.
{{< /callout >}}

## Supported versions {#versions}

Minimum versions required by the current OpenTelemetry PHP packages (checked on Packagist, October 2026):

| Component | Requirement |
|---|---|
| PHP | 8.1 or later — **8.2 or later** if you use the current {{< mono "opentelemetry-auto-pdo" >}} release (0.5.x) |
| ext-opentelemetry | Required by the framework and PDO instrumentation packages |
| Laravel | 10, 11, 12 or 13 ({{< mono "opentelemetry-auto-laravel" >}}) |
| Symfony | Any version providing {{< mono "symfony/http-kernel" >}} ({{< mono "opentelemetry-auto-symfony" >}}) |
| Slim | 4 ({{< mono "opentelemetry-auto-slim" >}}) |
{firstcol="26"}

Configuration validated end-to-end with Neurons: **Laravel 11 on Windows, IIS / FastCGI**.

{{< callout type="warn" >}}
Other combinations of PHP version, operating system, web server (PHP-FPM, Apache, nginx, Docker) or framework version are expected to work when they meet the requirements above, but have not been validated by Neurons: run the full [verification](#verify) before considering them supported. Package requirements change between releases — check the version you install.
{{< /callout >}}

## Install Composer instrumentation {#install}

For a Laravel application:

```bash
composer require \
  open-telemetry/opentelemetry-auto-laravel \
  open-telemetry/opentelemetry-auto-pdo \
  open-telemetry/sdk \
  open-telemetry/exporter-otlp \
  open-telemetry/sem-conv
```

- {{< mono "opentelemetry-auto-laravel" >}} — Laravel request and framework instrumentation.
- {{< mono "opentelemetry-auto-pdo" >}} — PDO/database spans.
- {{< mono "sdk" >}} — the OpenTelemetry SDK.
- {{< mono "exporter-otlp" >}} — the OTLP exporter.
- {{< mono "sem-conv" >}} — the semantic convention definitions.

For Symfony or Slim, replace the Laravel package with the matching instrumentation package:

| Framework | Package |
|---|---|
| Laravel | open-telemetry/opentelemetry-auto-laravel |
| Symfony | open-telemetry/opentelemetry-auto-symfony |
| Slim | open-telemetry/opentelemetry-auto-slim |
{mono="2"}

Other frameworks are not covered by this guide. If an OpenTelemetry auto-instrumentation package exists for them, it can be used the same way, but the result requires manual verification.

### Database coverage

Database tracing in this guide means **PDO** ({{< mono "opentelemetry-auto-pdo" >}}): MySQL, PostgreSQL, SQLite, SQL Server and other databases accessed through PDO. Laravel's database layer uses PDO, so it is covered; Doctrine DBAL is covered when configured with a `pdo_*` driver. Applications that use another client — for example {{< mono "mysqli" >}} — get no database spans from this setup.

## Enable ext-opentelemetry {#extension}

Composer packages alone are not enough: the {{< mono "ext-opentelemetry" >}} extension must also be enabled in the PHP configuration.

```ini
extension=opentelemetry
```

Check on Linux:

```bash
php -m | grep -i opentelemetry
```

Check on Windows:

```bat
php -m | findstr /I opentelemetry
```

Expected output:

```text
opentelemetry
```

{{< callout type="warn" >}}
The extension must be enabled in the PHP runtime that actually serves the application, not only in a local or CLI PHP installation.
{{< /callout >}}

On Windows, installation may require the PHP extension DLL matching the PHP version and build, rather than `pecl install`.

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

## Configure OpenTelemetry {#configure}

```bash
OTEL_PHP_AUTOLOAD_ENABLED=true
OTEL_SERVICE_NAME=<SERVICE_NAME>

OTEL_TRACES_EXPORTER=otlp
OTEL_METRICS_EXPORTER=none
OTEL_LOGS_EXPORTER=none

OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_EXPORTER_OTLP_ENDPOINT=http://<NEURONES_COLLECTOR_HOST>:4318

OTEL_PROPAGATORS=baggage,tracecontext

OTEL_RESOURCE_ATTRIBUTES=application=<APPLICATION_NAME>,deployment.environment=<ENVIRONMENT>
```

| Setting | Role |
|---|---|
| OTEL_PHP_AUTOLOAD_ENABLED | Enables the Composer auto-instrumentation hooks. |
| OTEL_SERVICE_NAME | The **service** name in Neurons (see below). |
| OTEL_METRICS_EXPORTER / OTEL_LOGS_EXPORTER | `none`: only traces are exported (see [Scope](#scope)). |
| OTEL_EXPORTER_OTLP_ENDPOINT | The Neurons Collector endpoint. |
| application | The **application** name in Neurons (see below). |
| deployment.environment | Identifies the deployed environment — for example `production`, `preprod`, `staging`, `qa`, `development`. |
{firstcol="30" mono="1"}

Compatibility note: for the current Neurons ingestion contract, use `deployment.environment`, not the newer `deployment.environment.name`.

### Application vs service {#naming}

Neurons groups telemetry on two levels:

- **Application** — the `application` resource attribute. It is what the Applications screen lists. Several services can share one application.
- **Service** — `OTEL_SERVICE_NAME`. Each service is listed, with its own metrics, under its application.

Example — an online shop made of a Laravel storefront and a separate PHP payment API:

| Component | application | OTEL_SERVICE_NAME |
|---|---|---|
| Laravel storefront | eshop | eshop-web |
| Payment API | eshop | eshop-payment-api |
{mono="2,3"}

Both appear under the **eshop** application, as two services.

{{< callout type="warn" >}}
The attribute must be named exactly `application` — not `application.name`, not `service.namespace`. Telemetry without a valid `application` attribute is not rejected: it is grouped under **Unassigned**.
{{< /callout >}}

### Authentication {#auth}

The Neurons ingestion service authenticates the **Collector**, not the application: the Collector adds the ingestion token when it forwards data, so a PHP application normally sends no credential.

If your Collector is configured to require a header from applications (the [connectivity check](#connectivity) returns 401/403), the platform team provides the header name and value. Set it as a process environment variable, never in source code:

```bash
OTEL_EXPORTER_OTLP_HEADERS=<HEADER_NAME>=<VALUE>
```

### TLS / HTTPS {#tls}

The `http://` endpoint above is for a Collector reached over a trusted internal network. When traffic between the application server and the Collector crosses an untrusted network, use an `https://` endpoint — this requires TLS to be enabled on the Collector by the platform team:

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=https://<NEURONES_COLLECTOR_HOST>:4318
```

The Collector's certificate must be trusted by the application server.

## Runtime environment {#runtime}

{{< callout type="warn" >}}
The `OTEL_*` variables must be visible to the PHP process that actually serves web requests. A value present only in an application `.env` file or a deployment shell is not enough, unless that runtime actually receives it.
{{< /callout >}}

This applies whatever the runtime — for example IIS / FastCGI, PHP-FPM, Docker, or PHP processes managed by systemd.

### Restart / reload the runtime

After configuration, restart or reload the PHP runtime so the extension and environment variables are applied — for example: recycle the application pool, reload PHP-FPM, restart the container, or restart the managed service.

## Generate test traffic {#test-traffic}

Trigger at least one real request. Prefer a route that enters the PHP application and runs a database query: this validates HTTP and PDO instrumentation together.

## Verification in Neurons {#verify}

Confirm that:

1. The application appears in the Applications list under its `application` name (not under **Unassigned**).
2. The service appears under that application with its `OTEL_SERVICE_NAME`, with a recent `last_seen`.
3. A real HTTP request appears in Traces / Business Transactions.
4. The HTTP route, method, status code and duration are correct.
5. A request that touches the database produces database spans.
6. The database system and name are populated where supported.
7. Database operations are classified correctly.
8. Trace propagation works towards instrumented downstream services, where applicable.

{{< callout >}}
An onboarding is not complete until it has been validated against the deployed environment, not only locally.
{{< /callout >}}

## Optional — HTTP data capture {#http-capture}

The current Neurons PHP OpenTelemetry setup does not provide, through Laravel auto-instrumentation, the server-side HTTP header/body capture behavior Neurons requires. When needed, an approved Neurons framework middleware enriches the active request span. Safe defaults:

```bash
NEURONES_APM_CAPTURE_HEADERS=true
NEURONES_APM_CAPTURE_REQUEST_BODY=false
NEURONES_APM_CAPTURE_RESPONSE_BODY=false
NEURONES_APM_CAPTURE_BODY_MAX_BYTES=4096
```

- Headers use an allow-list.
- Request-body and response-body capture are independent.
- Body capture is opt-in.
- Sensitive fields must be redacted.
- Sensitive routes must be excluded.
- Binary, multipart and streaming content must not be captured.

For the full capture policy, see the header and body capture rules in [Application Instrumentation (OpenTelemetry)](../../#otel).

## Security and privacy {#security}

- Never commit tokens to version control.
- Do not capture `Authorization` or `Cookie` values.
- Body capture must remain opt-in.
- Sensitive fields must be redacted.
- Sensitive routes must be excluded from content capture.

## Rollback / disable {#rollback}

**Temporarily disable telemetry** — the extension and packages stay installed, so it can be switched back on quickly:

1. Set `OTEL_TRACES_EXPORTER=none` (stops exporting), or `OTEL_PHP_AUTOLOAD_ENABLED=false` (stops loading the instrumentation altogether).
2. Restart or reload the PHP runtime.
3. Confirm that `last_seen` in Neurons no longer advances after the expected observation window.

To re-enable, restore the previous value and restart or reload the runtime.

**Fully remove the instrumentation:**

1. Remove the `OTEL_*` environment variables from the runtime.
2. Remove the instrumentation packages:

   ```bash
   composer remove \
     open-telemetry/opentelemetry-auto-laravel \
     open-telemetry/opentelemetry-auto-pdo \
     open-telemetry/sdk \
     open-telemetry/exporter-otlp \
     open-telemetry/sem-conv
   ```

3. Remove `extension=opentelemetry` from the PHP configuration.
4. Restart the PHP runtime, then check that the application still works and that `php -m` no longer lists `opentelemetry`.

## Troubleshooting {#troubleshooting}

| Symptom | Likely cause | Action |
|---|---|---|
| No spans | {{< mono "ext-opentelemetry" >}} not loaded | Check the extension on the real runtime. |
| Extension loaded but no spans | `OTEL_PHP_AUTOLOAD_ENABLED` missing, or Composer instrumentation not loaded | Check the environment and the Composer packages. |
| CLI configuration looks correct but web requests produce no telemetry | The web PHP runtime does not have the same environment/configuration as PHP CLI | Check the real runtime (PHP-FPM / FastCGI / container / service). |
| Export errors in the application logs | Collector unreachable, or it requires authentication or TLS | Run the [connectivity check](#connectivity); see [Authentication](#auth) and [TLS](#tls). |
| Service visible but listed under **Unassigned** | `application` attribute missing or misspelled | Check `OTEL_RESOURCE_ATTRIBUTES` (see [Application vs service](#naming)). |
| Application appears but no database spans | PDO instrumentation missing, or the application uses another database client | Check {{< mono "opentelemetry-auto-pdo" >}} and the data-access layer (see [Database coverage](#install)). |
| Fields present in raw traces but missing or wrong in Neurons | Semantic convention compatibility difference | Compare the emitted span attributes with the current Neurons ingestion contract. |

## Definition of Done {#done}

Backend onboarding is complete only when:

- the PHP, framework and package versions meet the [supported versions](#versions)
- {{< mono "ext-opentelemetry" >}} is enabled on the real application server/runtime
- the required Composer packages are installed
- the Collector is reachable from the application server, with authentication and TLS as required
- the `OTEL_*` variables are available to the real PHP runtime
- `application` and a unique `OTEL_SERVICE_NAME` are configured, and the application is not listed under **Unassigned**
- `deployment.environment` is configured
- a real HTTP request appears in Neurons
- database tracing is verified when the application uses PDO
- downstream trace propagation is verified where applicable
- sensitive HTTP content capture is disabled unless explicitly approved
- both rollback paths (temporary disable, full removal) are documented and the temporary disable has been tested
- validation is performed on the deployed environment
