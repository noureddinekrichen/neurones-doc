---
title: Java Application Onboarding
linkTitle: Java
lede: Instrument a Java / Spring Boot application with the OpenTelemetry Java agent and send its traces and logs to Neurons — no code change required.
menus:
  onboarding:
    parent: opentelemetry
    weight: 20
labels:
  install: Install the Java agent
  configure: Configure Neurons
  start: Start or restart
  verify: Verify in Neurons
  headers: HTTP header capture
  body-capture: HTTP body capture
  logs: Logs and trace correlation
  controls: Operational controls
  rollback: Disable / rollback
  done: Definition of Done
---

## Overview {#overview}

This guide explains how to instrument a Java / Spring Boot application with the **OpenTelemetry Java agent** and send its telemetry to Neurons. The agent attaches to the JVM at startup with `-javaagent` and instruments HTTP servers and clients, database access, messaging and logging automatically: the application code does not change.

The basic onboarding exports **traces** and, optionally, **logs**. HTTP header and body capture are advanced options, described after the verification steps.

{{< callout >}}
The `springboot-ecommerce` deployment — a Spring Boot microservice application run with Docker Compose — is used as the **reference example** wherever concrete configuration helps. Its file paths, service names and values are examples, not requirements.
{{< /callout >}}

Browser monitoring is onboarded separately: see [Browser RUM Onboarding](../browser-rum/).

## Architecture {#architecture}

{{< flow label="How Java telemetry reaches Neurons" >}}
app | Your Java / Spring Boot application | OpenTelemetry Java agent loaded with `-javaagent` — no code change
→ OTLP over HTTP (protobuf) + `X-Neurones-Token`
platform | Neurons OpenTelemetry Collector | Receives traces on `/v1/traces` and logs on `/v1/logs`, and forwards them as OTLP/JSON
→ OTLP over HTTP (JSON)
platform | apm-ingest | Neurons ingestion service: validates and stores the telemetry
→
platform | Neurons APM | Applications, services, traces, logs and business transactions
{{< /flow >}}

- The agent exports over **OTLP/HTTP with protobuf encoding**. It must send to the **Neurons OpenTelemetry Collector**, which forwards the data to the Neurons ingestion service — the ingestion service only accepts OTLP/JSON, so the agent must never point at it directly.
- Each export carries the Neurons token in the `X-Neurones-Token` header (see [Authentication](#auth)).
- **Trace context propagation is automatic.** The agent propagates the W3C `traceparent` header on outgoing calls, so a request and every downstream call it triggers — across all instrumented services — end up in the same trace. When the frontend is instrumented with Browser RUM, browser spans join the same trace.

## Prerequisites {#prerequisites}

Before onboarding, confirm that:

- The application runs on a JVM, and you can change how it is started (JVM options or environment variables).
- You can add the OpenTelemetry Java agent jar to the host or image.
- The application host can reach the Neurons OpenTelemetry Collector (see [Collector endpoint](#endpoint)).
- You have the Neurons token (`NEURONES_TOKEN`) for the target environment.
- The **application** name and the **service** names have been agreed (see [Application and service identity](#identity)).
- The deployment environment is known (for example `production`, `staging`).

{{< callout type="warn" >}}
**Supported versions must be confirmed against the current Neurons compatibility matrix.** Neurons does not yet publish a Java / Spring Boot support policy. For reference, the upstream OpenTelemetry Java agent supports Java 8 and later, and instruments Spring Web MVC 3.1+, Spring WebFlux 5.3+, Spring Cloud Gateway 2.0+ and Logback 1.0+ (see the upstream [supported libraries](https://github.com/open-telemetry/opentelemetry-java-instrumentation/blob/main/docs/supported-libraries.md)). The only Java setup validated end-to-end with Neurons is the `springboot-ecommerce` reference deployment.
{{< /callout >}}

## Install the OpenTelemetry Java agent {#install}

The agent is a single jar, `opentelemetry-javaagent.jar`, published with each release of the OpenTelemetry Java instrumentation project. It is **not** a Maven/Gradle dependency of the application.

1. Download a pinned version of the agent from the official releases:

   ```text
   https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v<VERSION>/opentelemetry-javaagent.jar
   ```

2. Verify the file's integrity (for example with a SHA-256 checksum recorded for that version) before using it.
3. Place it where the JVM can read it, for example `/opt/otel/opentelemetry-javaagent.jar`.
4. Load it with the JVM option:

   ```text
   -javaagent:/opt/otel/opentelemetry-javaagent.jar
   ```

   either on the `java` command line, or through the `JAVA_TOOL_OPTIONS` environment variable, which every JVM reads at startup (convenient for containers, where the start command is fixed by the image).

The agent automatically creates spans for HTTP servers and clients (Spring MVC, WebFlux/Netty, Feign, WebClient, RestTemplate), JDBC/R2DBC, Kafka, RabbitMQ, Redis and more, and puts `trace_id` / `span_id` into the logging MDC.

{{< callout >}}
**Agent version.** Neurons does not define a mandatory Java agent version. Pin an explicit version per application and upgrade deliberately. At the time of writing, the latest upstream release is v2.32.0; the reference deployment uses v2.31.1.
{{< /callout >}}

### Reference example — Docker image with checksum verification

*Example used by `springboot-ecommerce`.* The root `Dockerfile` has a dedicated stage that downloads the agent and checks its checksum; the jar is then copied to `/app/otel-javaagent.jar` in every service image:

```dockerfile
FROM curlimages/curl:8.11.0 AS otel-agent
ARG OTEL_JAVAAGENT_VERSION=2.31.1
ARG OTEL_JAVAAGENT_SHA256=bbf83c151b6400709e2f225bdd07a04f839d9d13b8b93464241333fd25d3e3ba
RUN curl -fsSL -o /otel-javaagent.jar ".../v${OTEL_JAVAAGENT_VERSION}/opentelemetry-javaagent.jar" \
 && echo "${OTEL_JAVAAGENT_SHA256}  /otel-javaagent.jar" | sha256sum -c -
```

The agent is activated **only** through `JAVA_TOOL_OPTIONS` in `docker-compose.yml`, so the same image still runs without the agent when that variable is not set — useful for debugging.

### Reference example — using the OpenTelemetry API from application code

Only needed when the application adds its own span attributes. In the reference project, the API gateway's body-capture filter calls `Span.current().setAttribute(...)`, so `infrastructure/api-gateway/pom.xml` declares `io.opentelemetry:opentelemetry-api` (version 1.65.0 in that project) with scope **`provided`**. The jar then does not ship its own copy of the API; at runtime the classes injected by the agent are used, which avoids a classloader conflict. Applications that rely only on automatic instrumentation need no OpenTelemetry dependency at all.

## Configure Neurons {#configure}

All settings are standard OpenTelemetry environment variables, read by the agent at startup:

```bash
JAVA_TOOL_OPTIONS=-javaagent:/opt/otel/opentelemetry-javaagent.jar

OTEL_SERVICE_NAME=<SERVICE_NAME>

OTEL_TRACES_EXPORTER=otlp
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://<NEURONES_COLLECTOR_HOST>:4318/v1/traces
OTEL_EXPORTER_OTLP_TRACES_HEADERS=X-Neurones-Token=<NEURONES_TOKEN>

OTEL_LOGS_EXPORTER=otlp
OTEL_EXPORTER_OTLP_LOGS_ENDPOINT=http://<NEURONES_COLLECTOR_HOST>:4318/v1/logs
OTEL_EXPORTER_OTLP_LOGS_HEADERS=X-Neurones-Token=<NEURONES_TOKEN>

OTEL_METRICS_EXPORTER=none

OTEL_RESOURCE_ATTRIBUTES=application=<APPLICATION_NAME>,deployment.environment=<ENVIRONMENT>
```

| Variable | Purpose |
|---|---|
| JAVA_TOOL_OPTIONS | Loads the agent (can also carry other JVM options). |
| OTEL_SERVICE_NAME | The service name. Optional for Spring Boot (see [Service identity](#identity)). |
| OTEL_TRACES_EXPORTER | `otlp`: export traces over OTLP. |
| OTEL_EXPORTER_OTLP_PROTOCOL | `http/protobuf`: OTLP over HTTP, protobuf encoding. |
| OTEL_EXPORTER_OTLP_TRACES_ENDPOINT | Collector traces endpoint. |
| OTEL_EXPORTER_OTLP_TRACES_HEADERS | `X-Neurones-Token` header on every trace export. |
| OTEL_LOGS_EXPORTER | `otlp` to export logs, `none` to keep logs local (see [Logs](#logs)). |
| OTEL_EXPORTER_OTLP_LOGS_ENDPOINT | Collector logs endpoint. |
| OTEL_EXPORTER_OTLP_LOGS_HEADERS | `X-Neurones-Token` header on every log export. |
| OTEL_METRICS_EXPORTER | `none` in the current Neurons configuration (see [Metrics](#metrics)). |
| OTEL_RESOURCE_ATTRIBUTES | Application and environment identity (see below). |
{firstcol="30" mono="1"}

### Collector endpoint {#endpoint}

Use the Collector URL and transport defined by the Neurons platform team for the target environment. The `http://<NEURONES_COLLECTOR_HOST>:4318` form above is the plain-HTTP OTLP endpoint used by the reference deployment. Whether HTTPS/TLS is required depends on the environment and is not defined by this guide: when the platform team provides an `https://` endpoint, use it as given.

Check from the application host that the Collector port is reachable before starting the application:

```bash
nc -vz <NEURONES_COLLECTOR_HOST> 4318
```

```powershell
Test-NetConnection <NEURONES_COLLECTOR_HOST> -Port 4318
```

### Authentication {#auth}

The Neurons token is sent in the `X-Neurones-Token` header on every trace and log export, through `OTEL_EXPORTER_OTLP_TRACES_HEADERS` and `OTEL_EXPORTER_OTLP_LOGS_HEADERS`.

- Provide the value through a secret mechanism — a server `.env` file excluded from version control, a container/orchestrator secret, or a protected service configuration. **Never commit it** and never put it in an image.
- In the reference deployment, `NEURONES_TOKEN` is defined in the server's `.env` file and referenced as `X-Neurones-Token=${NEURONES_TOKEN:-}` in `docker-compose.yml`.
- When the Collector requires the token, a missing or invalid value makes every export fail with **HTTP 401**: no traces and no logs reach Neurons, while the application itself keeps working.

### Application and service identity {#identity}

Neurons groups telemetry on two levels, and both must be set correctly:

```text
Application: springboot-ecommerce          ← resource attribute "application"
  Services:
  - api-gateway                            ← service.name
  - order-service                          ← service.name
  - payment-service                        ← service.name
```

| Key | Role in Neurons |
|---|---|
| application | **The Neurons application grouping key.** All services of one product share the same value. |
| service.name | One individual service. Set it with `OTEL_SERVICE_NAME`; for Spring Boot, the agent can also take it from `spring.application.name`. |
| deployment.environment | The environment (`production`, `staging`, ...). |
| service.namespace | Optional OpenTelemetry grouping helper; useful to tell apart two applications on the same host. |
| tenant | Optional, Neurons-specific. |
{firstcol="26" mono="1"}

{{< callout type="warn" >}}
The key must be exactly `application` — not `application.name`, not `service.name`, not `service.namespace`. A wrong or missing key raises no error: the services silently land under **Unassigned**.
{{< /callout >}}

**Reference example.** In `springboot-ecommerce`, `OTEL_SERVICE_NAME` is not set: each service already defines `spring.application.name` (`api-gateway`, `order-service`, ...), which becomes its service name. The resource attributes are:

```text
service.namespace=ecommercespring
deployment.environment=production
tenant=default
application=springboot-ecommerce
```

If the frontend is also instrumented with Browser RUM, use the same `application`, `deployment.environment`, `service.namespace` and `tenant` values on the RUM side.

### Environment {#environment}

Set `deployment.environment` in `OTEL_RESOURCE_ATTRIBUTES`. Use `deployment.environment`, not the newer `deployment.environment.name`: Neurons currently reads `deployment.environment`.

### Metrics {#metrics}

The current Neurons configuration sets `OTEL_METRICS_EXPORTER=none`: Neurons computes service metrics (rate, errors, duration) from the traces, and the ingestion service does not currently store OTLP metrics. Application and JVM metrics stay on the application's own tooling — in the reference deployment, Micrometer / Prometheus. This reflects the current Neurons configuration, not a limitation of the Java agent.

## Start or restart the application {#start}

The agent and the variables take effect only when the JVM starts. Restart the application after any change.

| How the application runs | Where to set the agent and the variables |
|---|---|
| Direct JVM start | `java -javaagent:/opt/otel/opentelemetry-javaagent.jar -jar app.jar`, with the `OTEL_*` variables in the process environment. |
| Docker | `JAVA_TOOL_OPTIONS` and `OTEL_*` as container environment variables; the jar in the image or a mounted volume. |
| Docker Compose | The service's `environment:` block — or a shared YAML anchor, as in the reference example below. |
| Kubernetes | Container environment variables in the pod spec, with the token from a Secret. |
| systemd | `Environment=` / `EnvironmentFile=` entries of the unit, then restart the unit. |
{firstcol="26"}

**Reference example — Docker Compose.** In `springboot-ecommerce`, the variables are defined once in the `x-spring-app-defaults` → `environment` anchor of `docker-compose.yml` and inherited by every instrumented service:

| Variable | Value in the reference deployment |
|---|---|
| JAVA_TOOL_OPTIONS | `-XX:MaxRAMPercentage=75 -XX:+UseG1GC -javaagent:/app/otel-javaagent.jar` |
| OTEL_TRACES_EXPORTER | `otlp` |
| OTEL_EXPORTER_OTLP_PROTOCOL | `http/protobuf` |
| OTEL_EXPORTER_OTLP_TRACES_ENDPOINT | `http://<NEURONES_COLLECTOR_HOST>:4318/v1/traces` |
| OTEL_EXPORTER_OTLP_TRACES_HEADERS | `X-Neurones-Token=${NEURONES_TOKEN:-}` |
| OTEL_LOGS_EXPORTER | `otlp` |
| OTEL_EXPORTER_OTLP_LOGS_ENDPOINT | `http://<NEURONES_COLLECTOR_HOST>:4318/v1/logs` |
| OTEL_EXPORTER_OTLP_LOGS_HEADERS | `X-Neurones-Token=${NEURONES_TOKEN:-}` |
| OTEL_METRICS_EXPORTER | `none` |
| OTEL_RESOURCE_ATTRIBUTES | see [Application and service identity](#identity) |
{firstcol="30" mono="1"}

Per-server overrides go in `docker-compose.override.yml`. A service block there replaces nothing from the anchor: Compose merges the `environment` maps, so the exporter settings stay in place. Apply changes with `docker compose up -d <service>`.

## Verify in Neurons {#verify}

1. **Confirm the agent is loaded** — the JVM output contains a line such as `OpenTelemetry Javaagent ... started`.
2. **Generate real traffic** — call an endpoint that also reaches a database and, if possible, another service.
3. **The application appears** in the Applications list under its `application` name.
4. **The services appear** under that application, each with its service name and a recent `last_seen`.
5. **The trace reaches downstream services** — one request shows every instrumented service it went through in a single trace.
6. **Database spans** appear for requests that query a database, where applicable.
7. **Logs** appear in the Logs screen, correlated to traces, if log export is enabled.
8. **Nothing is grouped under Unassigned.**

{{< callout >}}
An onboarding is not complete until it has been validated against the deployed environment, not only locally.
{{< /callout >}}

**Reference example — `springboot-ecommerce` commands:**

```bash
# Agent loaded
docker compose logs api-gateway | grep -i "opentelemetry javaagent"
# expected: "OpenTelemetry Javaagent ... started"

# Trace ids present in the service logs
docker compose logs api-gateway --tail=20 | grep trace_id
```

To see exactly which attributes a span carries (headers, bodies) without opening Neurons, temporarily add the `logging` exporter in `docker-compose.override.yml`, send a request, and read the container output:

```yaml
api-gateway:
  environment:
    OTEL_TRACES_EXPORTER: otlp,logging
```

```bash
docker compose up -d api-gateway
curl -s -X POST http://localhost:8085/api/cart/items -H 'Content-Type: application/json' -d '{"productId":1,"quantity":1}'
docker compose logs api-gateway --tail=50 | grep -E "http.request.header|http.response.header|http.request.body|http.response.body"
```

Remove `logging` afterwards: it prints every span.

## Advanced — HTTP header capture {#headers}

Not required for onboarding. Header capture is **opt-in**: nothing is captured until you list the headers to record, using the agent's standard variables. No code is involved; set the variable on the services concerned and restart them.

| Variable | Captures | Resulting span attribute |
|---|---|---|
| OTEL_INSTRUMENTATION_HTTP_SERVER_CAPTURE_REQUEST_HEADERS | Headers of incoming requests | `http.request.header.<name>` on the SERVER span |
| OTEL_INSTRUMENTATION_HTTP_SERVER_CAPTURE_RESPONSE_HEADERS | Headers of responses this service returns | `http.response.header.<name>` on the SERVER span |
| OTEL_INSTRUMENTATION_HTTP_CLIENT_CAPTURE_REQUEST_HEADERS | Headers this service sends to other services (Feign, WebClient, RestTemplate) | `http.request.header.<name>` on the CLIENT span |
| OTEL_INSTRUMENTATION_HTTP_CLIENT_CAPTURE_RESPONSE_HEADERS | Headers of the responses to those calls | `http.response.header.<name>` on the CLIENT span |
{mono="1"}

Each value is a comma-separated, case-insensitive list of header names. The attribute name uses the lowercase header name; the value is an array of strings.

{{< callout type="warn" >}}
**The word order matters.** The correct form is `HTTP_<SERVER|CLIENT>_CAPTURE_<REQUEST|RESPONSE>_HEADERS`. A name in a different order, such as `HTTP_CAPTURE_HEADERS_SERVER_REQUEST`, is silently ignored: nothing is captured and no error is shown. Reference: `opentelemetry.io/docs/zero-code/java/agent/instrumentation/http/`.
{{< /callout >}}

{{< callout type="warn" >}}
**Never capture `Authorization`, `Cookie`, `Set-Cookie` or any header carrying a session or authentication secret.** The agent records the raw value with no masking: a bearer token would be stored in plain text in Neurons.
{{< /callout >}}

**Reference example — `springboot-ecommerce`** (in `docker-compose.override.yml` on the server; header capture is not in the committed `docker-compose.yml`):

```yaml
services:
  api-gateway:
    environment:
      OTEL_INSTRUMENTATION_HTTP_SERVER_CAPTURE_REQUEST_HEADERS: "Referer,X-Correlation-Id,Idempotency-Key,User-Agent"
      OTEL_INSTRUMENTATION_HTTP_SERVER_CAPTURE_RESPONSE_HEADERS: "X-Correlation-Id,Content-Type"
  order-service:
    environment:
      # calls to cart/inventory/payment services
      OTEL_INSTRUMENTATION_HTTP_CLIENT_CAPTURE_REQUEST_HEADERS: "X-User-Id,X-User-Role,X-Correlation-Id"
      OTEL_INSTRUMENTATION_HTTP_CLIENT_CAPTURE_RESPONSE_HEADERS: "Content-Type"
```

| Header | Where it appears | Why it helps |
|---|---|---|
| X-Correlation-Id | Gateway request/response | Links a trace to a log search |
| Idempotency-Key | `POST /api/orders` | Explains duplicate order requests |
| X-User-Id, X-User-Role | Added by the gateway after JWT validation, forwarded downstream | Who made the call, on downstream spans |
| Referer, User-Agent | Gateway request | Which page or client triggered the call |
{mono="1"}

## Advanced — HTTP body capture {#body-capture}

**The OpenTelemetry Java agent never captures request or response bodies.** Body capture is not part of standard Java onboarding and is not a generic Neurons Java feature: an application that needs it requires its own approved middleware or instrumentation that adds the body to the active span.

{{< callout type="warn" >}}
Request and response bodies can contain credentials, tokens, personal data and payment or customer data. Production body capture should be **opt-in**: off by default, limited to explicitly approved routes, size-limited, and reviewed for privacy before it is enabled.
{{< /callout >}}

### Reference implementation: springboot-ecommerce API Gateway

In the reference project, body capture is custom code implemented **only in `api-gateway`**, because all external traffic passes through it:

- `infrastructure/api-gateway/src/main/java/com/backendguru/apigateway/telemetry/GatewayTelemetryProperties.java`
- `infrastructure/api-gateway/src/main/java/com/backendguru/apigateway/telemetry/BodyCaptureWebFilter.java`

Configuration, in `infrastructure/config-server/src/main/resources/configs/api-gateway.yml`:

```yaml
gateway:
  telemetry:
    capture:
      request-body-enabled: ${GATEWAY_CAPTURE_REQUEST_BODY:true}
      response-body-enabled: ${GATEWAY_CAPTURE_RESPONSE_BODY:true}
      max-body-bytes: ${GATEWAY_CAPTURE_MAX_BODY_BYTES:4096}
      exclude-path-prefixes: ${GATEWAY_CAPTURE_EXCLUDE_PATHS:/api/auth,/sse}
```

| Variable | Default in the reference project | Effect |
|---|---|---|
| GATEWAY_CAPTURE_REQUEST_BODY | `true` | Attaches the request body as `http.request.body` |
| GATEWAY_CAPTURE_RESPONSE_BODY | `true` | Attaches the response body as `http.response.body` |
| GATEWAY_CAPTURE_MAX_BODY_BYTES | `4096` | Body truncated to this many bytes |
| GATEWAY_CAPTURE_EXCLUDE_PATHS | `/api/auth,/sse` | Path prefixes never captured |
{mono="1"}

{{< callout type="warn" >}}
**The reference defaults are not a Neurons recommendation.** The Java record `GatewayTelemetryProperties` declares `@DefaultValue("false")`, but that only applies when the property is missing: the YAML served by config-server sets `true`, so capture is effectively **on** in the reference deployment. For a production application, start with both switches set to `false` and enable them only after review.
{{< /callout >}}

Behavior of the reference filter:

- Runs at order `HIGHEST_PRECEDENCE + 5`: after the correlation-id filter and **before JWT authentication** — bodies are captured even for requests that end in 401.
- Captures only `application/json`, `text/plain` and `application/x-www-form-urlencoded`; binary content is never captured.
- `/api/auth/**` (login, register, refresh: passwords and tokens) and `/sse` (long-lived stream) are excluded by default.
- Request side: uses Spring Cloud Gateway's `ServerWebExchangeUtils.cacheRequestBody`, so the body is not consumed twice.
- Response side: a `ServerHttpResponseDecorator` reads each buffer with `doOnNext` without modifying it; the bytes sent to the client are identical whether capture is on or off.
- With both switches `false`, the filter does nothing.

To change it: set the variables on `api-gateway` in `docker-compose.override.yml` and run `docker compose up -d api-gateway` (temporary override). To change the committed default in `api-gateway.yml`, which is packaged inside the `config-server` jar, run `docker compose up -d --build config-server`, then restart `api-gateway`.

## Logs and trace correlation {#logs}

Two independent mechanisms connect logs and traces.

**1. Trace ↔ log correlation in the application's own logs.** The agent's Logback MDC instrumentation puts `trace_id` and `span_id` into the MDC of every log statement made inside a traced request. To see them in the application's log output, the log format must include them:

- a text pattern such as `[%X{trace_id:-}]`;
- for a JSON encoder that lists MDC keys explicitly, add `trace_id` and `span_id` to the list.

Use the snake_case keys `trace_id` / `span_id` set by the agent, not the camelCase `traceId`.

**2. Log export to Neurons (OTLP).** The agent's Logback appender instrumentation turns each log line into an OpenTelemetry log record. With `OTEL_LOGS_EXPORTER=otlp` those records are sent to the Collector's `/v1/logs` endpoint and appear in Neurons; with `none` they stay local.

- This is an **additional** output: console and file appenders keep working as before.
- `trace_id` / `span_id` are part of each exported log record, taken from the active span — they do not depend on the MDC configuration.
- Custom MDC keys (for example `userId`) are **not** exported unless listed in `OTEL_INSTRUMENTATION_LOGBACK_APPENDER_EXPERIMENTAL_MDC_ATTRIBUTES_INCLUDED`.

**Reference example — `springboot-ecommerce`.** Services with a custom `logback-spring.xml` (LogstashEncoder in the `docker`/`prod` profiles) only output the MDC keys they list, so they include:

```xml
<includeMdcKeyName>trace_id</includeMdcKeyName>
<includeMdcKeyName>span_id</includeMdcKeyName>
<includeMdcKeyName>userId</includeMdcKeyName>
```

The `dev` profile's text pattern uses `[%X{trace_id:-}]`. `userId` is not exported to Neurons (the experimental MDC variable above is not enabled).

## Operational controls {#controls}

| Need | How |
|---|---|
| Turn the agent off on one service without rebuilding | `OTEL_JAVAAGENT_ENABLED=false`, then restart |
| Turn off one instrumentation (to reduce overhead or noise) | `OTEL_INSTRUMENTATION_<NAME>_ENABLED=false`, e.g. `OTEL_INSTRUMENTATION_JDBC_ENABLED=false` |
| Stop sending logs only | `OTEL_LOGS_EXPORTER=none` |
| Print spans / logs in the application output for debugging | `OTEL_TRACES_EXPORTER=otlp,logging` / `OTEL_LOGS_EXPORTER=otlp,logging` — remove afterwards |
| Agent debug output | `OTEL_JAVAAGENT_DEBUG=true` |
{firstcol="30"}

**Memory and CPU.** The agent adds memory and startup overhead that depends on the workload and on the instrumentations in use. Measure it in your own workload and size JVM and container memory with sufficient headroom.

*Observed in the reference deployment:* about 50–150 MB of additional RSS per JVM, with `mem_limit` set to about 500 MB per service (550 MB for `api-gateway`) in `docker-compose.override.yml`. Treat these figures as an indication for that deployment only.

## Troubleshooting {#troubleshooting}

| Symptom | Likely cause | Action |
|---|---|---|
| Java agent not loaded (no "OpenTelemetry Javaagent ... started" line) | `-javaagent` not applied to the real process, or wrong jar path | Check the actual start command / `JAVA_TOOL_OPTIONS` of the running process and the jar path. |
| No spans | Agent not loaded, `OTEL_JAVAAGENT_ENABLED=false`, or `OTEL_TRACES_EXPORTER` not `otlp` | Check the agent startup line and the effective variables; restart after changes. |
| Collector unreachable (export timeouts / connection refused in the logs) | Firewall, wrong host or port, or Collector down | Run the [connectivity check](#endpoint); confirm the endpoint with the platform team. |
| 401 export errors | Missing or invalid `NEURONES_TOKEN` | Check that the token is set and passed in `X-Neurones-Token` for both traces and logs (see [Authentication](#auth)). |
| Application not appearing in Neurons | No telemetry exported, or no recent traffic | Work through the rows above, then generate real traffic and widen the time window. |
| Services listed under **Unassigned** | `application` attribute missing or misspelled | Check `OTEL_RESOURCE_ATTRIBUTES` (see [Application and service identity](#identity)). |
| Logs missing | `OTEL_LOGS_EXPORTER` is `none`, logs endpoint/header missing, or logging framework not instrumented | Check the three log variables; for a logging framework other than Logback, check the upstream supported libraries. |
| Database spans missing | Database access not done through an instrumented client (JDBC/R2DBC), or that instrumentation disabled | Check the driver and any `OTEL_INSTRUMENTATION_*_ENABLED=false`. |
| Downstream traces disconnected | A service in the chain is not instrumented, or a proxy / custom client drops the `traceparent` header | Instrument every service in the call chain; make sure intermediaries forward `traceparent`. |
| High memory or CPU usage | Agent overhead not accounted for in sizing | Increase memory headroom; disable unused instrumentations; measure again. |
| Header capture variable has no effect | Variable name words in the wrong order | Use `HTTP_<SERVER\|CLIENT>_CAPTURE_<REQUEST\|RESPONSE>_HEADERS`. |

## Disable / rollback {#rollback}

**Generic procedure:**

1. Choose the scope:
   - **Stop everything:** set `OTEL_JAVAAGENT_ENABLED=false`, or remove `-javaagent` from the start command / `JAVA_TOOL_OPTIONS`.
   - **Keep the agent but stop exporting:** set `OTEL_TRACES_EXPORTER=none` and `OTEL_LOGS_EXPORTER=none`.
2. Restart the JVM / container so the change applies.
3. Validate that telemetry has stopped: the services' `last_seen` in Neurons no longer advances after the expected observation window, and the application keeps working normally.

To re-enable, restore the previous values and restart.

**Reference example — `springboot-ecommerce`:** add `OTEL_JAVAAGENT_ENABLED: "false"` to the service in `docker-compose.override.yml`, then `docker compose up -d <service>`. Because the agent is only activated through `JAVA_TOOL_OPTIONS`, removing that variable also runs the same image without the agent.

## Definition of Done {#done}

Onboarding is complete only when:

- the Java / Spring Boot versions in use have been confirmed against the Neurons compatibility matrix
- the agent is a pinned version, integrity-checked, and loaded by the real process (startup line present)
- the Collector endpoint and transport were provided by the platform team and are reachable
- `NEURONES_TOKEN` comes from a secret mechanism and is not committed anywhere
- `application`, the service names and `deployment.environment` are set as agreed
- real traffic produces traces in Neurons, with downstream services in the same trace
- database spans are visible where applicable
- logs are visible and correlated, if log export is enabled
- nothing is grouped under **Unassigned**
- header capture is off or limited to an approved list without `Authorization` / `Cookie`
- body capture is off, or explicitly approved and reviewed
- the rollback procedure has been tested
- validation is performed on the deployed environment
