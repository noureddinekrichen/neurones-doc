---
title: ".NET Application Onboarding"
linkTitle: ".NET"
lede: Instrument a .NET or .NET Framework application with OpenTelemetry automatic instrumentation so its HTTP requests, database calls and distributed traces appear in Neurons — without code changes.
menus:
  onboarding:
    parent: opentelemetry
    weight: 30
labels:
  versions: Supported versions
  connectivity: Collector connectivity
  install: Install the instrumentation
  activate: Activate per runtime
  configure: Configure OpenTelemetry
  http-capture: HTTP header capture
  done: Definition of Done
---

.NET applications are instrumented with **OpenTelemetry .NET Automatic Instrumentation**, the official zero-code agent of the OpenTelemetry project. It attaches to the process at startup (CLR profiler and .NET startup hook) and instruments ASP.NET Core, ASP.NET, `HttpClient` and the common database clients without any change to the application code.

Instrumentation becomes active when the automatic instrumentation is installed on the server **and** the process that runs the application starts with its environment variables — which the provided scripts and PowerShell module set for you.

## Scope {#scope}

This guide covers **backend tracing only**: HTTP server and client spans, database spans, distributed trace propagation, and the application and environment identification Neurons uses to group them.

It does **not** configure:

- **Logs** — the configuration below sets `OTEL_LOGS_EXPORTER=none`.
- **Metrics** — Neurons computes service metrics (rate, errors, duration) from the traces themselves; the configuration sets `OTEL_METRICS_EXPORTER=none`.
- **Browser RUM** — instrumenting the .NET backend does not enable any browser monitoring. See [Browser RUM Onboarding](../browser-rum/).

HTTP header capture is an optional add-on, described at the end of this page.

## Architecture {#architecture}

{{< flow label="How .NET telemetry reaches Neurons" >}}
app | Your .NET application | OpenTelemetry .NET Automatic Instrumentation — CLR profiler, no code change
→ OTLP over HTTP (protobuf)
platform | Neurons OpenTelemetry Collector | Receives the telemetry, converts it to OTLP/JSON and adds the ingestion token
→ OTLP over HTTP (JSON)
platform | apm-ingest | Neurons ingestion service: validates and stores the telemetry
→
platform | Neurons APM | Applications, services, traces and business transactions
{{< /flow >}}

{{< callout >}}
.NET telemetry always goes through the Neurons OpenTelemetry Collector. The automatic instrumentation sends OTLP/protobuf; the Collector converts it and forwards it to the Neurons ingestion service, which only accepts OTLP/JSON. Never point the .NET exporter directly at the ingestion service.
{{< /callout >}}

## Prerequisites {#prerequisites}

Before onboarding, confirm that:

- The application runs on a supported runtime (see [Supported versions](#versions)).
- You have administrator / root access on the server, to install the instrumentation and change how the application is started.
- The application server can reach the Neurons OpenTelemetry Collector (see [Collector connectivity](#connectivity)).
- The `application` name and a unique `OTEL_SERVICE_NAME` have been agreed (see [Application vs service](#naming)).
- The target deployment environment is known.
- You know how the application is hosted: IIS, Windows Service, systemd, container, or started from a shell.

{{< callout >}}
The Neurons platform team provides or confirms the Collector endpoint, whether it requires authentication or TLS, and the application/service naming convention before onboarding.
{{< /callout >}}

## Supported versions {#versions}

Requirements of OpenTelemetry .NET Automatic Instrumentation **v1.17.0** (latest release, October 2026):

| Component | Requirement |
|---|---|
| .NET | All versions currently supported by Microsoft |
| .NET Framework | 4.6.2 or later (Windows only) |
| Architectures | x86, x64 — ARM64 is experimental |
| Operating systems | Windows Server, Linux (glibc and musl/Alpine), macOS |
| Windows PowerShell module | PowerShell 5.1 (the version shipped with Windows) |
{firstcol="26"}

Some instrumentations depend on the runtime — for example ASP.NET Core and Entity Framework Core are not instrumented on .NET Framework, and classic ASP.NET (MVC / Web API) is only instrumented on .NET Framework.

{{< callout type="warn" >}}
No .NET configuration has been validated end-to-end with Neurons yet. Run the full [verification](#verify) on the deployed environment before considering an application onboarded, and report the validated combination (runtime, OS, hosting) to the platform team.
{{< /callout >}}

## Check Collector connectivity {#connectivity}

Before installing anything, check from the **application server** that the Collector's OTLP/HTTP port (4318 by default) is reachable.

Windows (PowerShell):

```powershell
Test-NetConnection <NEURONES_COLLECTOR_HOST> -Port 4318
```

Linux:

```bash
nc -vz <NEURONES_COLLECTOR_HOST> 4318
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

## Install the instrumentation {#install}

Pin the version you install, and keep release verification enabled: the official installers verify the downloaded files with the [GitHub CLI](https://cli.github.com/) ({{< mono "gh" >}}), which must be installed on the server.

### Windows (PowerShell module)

Run in **Windows PowerShell 5.1, as administrator**:

```powershell
#Requires -PSEdition Desktop
$version = "v1.17.0"
$repository = "open-telemetry/opentelemetry-dotnet-instrumentation"
$release_workflow = "$repository/.github/workflows/release.yml"

$program_files = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::ProgramFiles)
$download_dir = Join-Path $program_files "OpenTelemetry .NET AutoInstrumentation Download $([System.Guid]::NewGuid().ToString("N"))"
$download_path = Join-Path $download_dir "OpenTelemetry.DotNet.Auto.psm1"
New-Item -ItemType Directory -Path $download_dir -ErrorAction Stop | Out-Null

try {
    Invoke-WebRequest -Uri "https://github.com/$repository/releases/download/$version/OpenTelemetry.DotNet.Auto.psm1" -OutFile $download_path -UseBasicParsing

    # Verify the module before importing it
    gh release verify-asset $version $download_path --repo $repository
    if ($LASTEXITCODE -ne 0) { throw "Release verification failed." }
    gh attestation verify $download_path --repo $repository --signer-workflow $release_workflow --source-ref "refs/tags/$version"
    if ($LASTEXITCODE -ne 0) { throw "Attestation verification failed." }

    Import-Module $download_path
    Install-OpenTelemetryCore -ErrorAction Stop

    # Keep the module for later updates and uninstallation
    Copy-Item -LiteralPath $download_path -Destination (Get-OpenTelemetryInstallDirectory) -Force
}
finally {
    Remove-Item -LiteralPath $download_dir -Force -Recurse -ErrorAction SilentlyContinue
}
```

The core files are installed under `C:\Program Files\OpenTelemetry .NET AutoInstrumentation`. Installing them does not instrument anything yet: see [Activate per runtime](#activate).

### Linux / macOS (shell scripts)

To instrument a service started by systemd, install into a system directory rather than the default `$HOME/.otel-dotnet-auto`:

```bash
version="v1.17.0"
repository="open-telemetry/opentelemetry-dotnet-instrumentation"
release_workflow="$repository/.github/workflows/release.yml"
download_dir="$(mktemp -d "${TMPDIR:-/tmp}/otel-dotnet-auto-installer.XXXXXX")"
installer="$download_dir/otel-dotnet-auto-install.sh"
trap 'rm -rf "$download_dir"' 0

curl -sSfL "https://github.com/$repository/releases/download/$version/otel-dotnet-auto-install.sh" -o "$installer"

# Verify the installer before executing it
gh release verify-asset "$version" "$installer" --repo "$repository"
gh attestation verify "$installer" --repo "$repository" \
  --signer-workflow "$release_workflow" --source-ref "refs/tags/$version"

# Install the core files
sudo OTEL_DOTNET_AUTO_HOME=/opt/otel-dotnet-auto VERSION="$version" sh "$installer"
sudo chmod +x /opt/otel-dotnet-auto/instrument.sh
```

On macOS, {{< mono "coreutils" >}} is also required.

### Containers and self-contained applications

For Docker images and for self-contained applications (published with a runtime identifier such as `-r linux-x64`), use the NuGet package instead — it is the upstream-recommended deployment method and ships the instrumentation with the application:

```bash
dotnet add package OpenTelemetry.AutoInstrumentation
```

The build output then contains `instrument.sh` / `instrument.cmd` launch scripts. Start the application through them, with the environment variables of [Configure OpenTelemetry](#configure).

## Configure OpenTelemetry {#configure}

```bash
OTEL_SERVICE_NAME=<SERVICE_NAME>

OTEL_TRACES_EXPORTER=otlp
OTEL_METRICS_EXPORTER=none
OTEL_LOGS_EXPORTER=none

OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_EXPORTER_OTLP_ENDPOINT=http://<NEURONES_COLLECTOR_HOST>:4318

OTEL_PROPAGATORS=tracecontext,baggage

OTEL_RESOURCE_ATTRIBUTES=application=<APPLICATION_NAME>,deployment.environment=<ENVIRONMENT>
```

| Setting | Role |
|---|---|
| OTEL_SERVICE_NAME | The **service** name in Neurons (see below). If omitted, a name is generated (on IIS / .NET Framework: `SiteName\VirtualPath`) — always set it explicitly. |
| OTEL_METRICS_EXPORTER / OTEL_LOGS_EXPORTER | `none`: only traces are exported (see [Scope](#scope)). |
| OTEL_EXPORTER_OTLP_PROTOCOL | `http/protobuf` is the automatic instrumentation's default; keep it (the `grpc` protocol is not supported on .NET Framework). |
| OTEL_EXPORTER_OTLP_ENDPOINT | The Neurons Collector endpoint. |
| application | The **application** name in Neurons (see below). |
| deployment.environment | Identifies the deployed environment — for example `production`, `preprod`, `staging`, `qa`, `development`. |
{firstcol="30" mono="1"}

{{< callout type="warn" >}}
The upstream OpenTelemetry examples use `deployment.environment.name`. Neurons currently reads **`deployment.environment`** — use that name, or the environment will not be shown.
{{< /callout >}}

Where to set these variables depends on the hosting model — see [Activate per runtime](#activate).

### Application vs service {#naming}

Neurons groups telemetry on two levels:

- **Application** — the `application` resource attribute. It is what the Applications screen lists. Several services can share one application.
- **Service** — `OTEL_SERVICE_NAME`. Each service is listed, with its own metrics, under its application.

Example — an ordering platform made of an ASP.NET Core web front end and a Windows Service that processes orders:

| Component | application | OTEL_SERVICE_NAME |
|---|---|---|
| ASP.NET Core front end | orders | orders-web |
| Order processing Windows Service | orders | orders-worker |
{mono="2,3"}

Both appear under the **orders** application, as two services.

{{< callout type="warn" >}}
The attribute must be named exactly `application` — not `application.name`, not `service.namespace`. Telemetry without a valid `application` attribute is not rejected: it is grouped under **Unassigned**.
{{< /callout >}}

### Authentication {#auth}

The Neurons ingestion service authenticates the **Collector**, not the application: the Collector adds the ingestion token when it forwards data, so a .NET application normally sends no credential.

If your Collector is configured to require a header from applications (the [connectivity check](#connectivity) returns 401/403), the platform team provides the header name and value. Set it as a process environment variable, never in source code or a committed configuration file:

```bash
OTEL_EXPORTER_OTLP_HEADERS=<HEADER_NAME>=<VALUE>
```

### TLS / HTTPS {#tls}

The `http://` endpoint above is for a Collector reached over a trusted internal network. When traffic between the application server and the Collector crosses an untrusted network, use an `https://` endpoint — this requires TLS to be enabled on the Collector by the platform team:

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=https://<NEURONES_COLLECTOR_HOST>:4318
```

The Collector's certificate must be trusted by the application server.

## Activate per runtime {#activate}

Installing the core files is not enough: the process that runs the application must start with the instrumentation's environment variables (CLR profiler, startup hook, `OTEL_DOTNET_AUTO_HOME`) **and** the `OTEL_*` settings above.

### IIS (ASP.NET and ASP.NET Core)

```powershell
Import-Module "C:\Program Files\OpenTelemetry .NET AutoInstrumentation\OpenTelemetry.DotNet.Auto.psm1"
Register-OpenTelemetryForIIS
```

{{< callout type="warn" >}}
`Register-OpenTelemetryForIIS` **restarts IIS** by default (use `-NoReset` to skip it and restart during a maintenance window).
{{< /callout >}}

- **ASP.NET Core on IIS:** the application pool must have **.NET CLR Version = No Managed Code**, otherwise no telemetry is produced. Set the `OTEL_*` variables with `<environmentVariable>` elements inside the `<aspNetCore>` block of the application's `web.config`.
- **ASP.NET (.NET Framework):** the `OTEL_*` settings can be set in `<appSettings>` of `web.config`, or as environment variables of the application pool in `applicationHost.config`.

{{< callout type="warn" >}}
.NET Framework applications that share one application pool run in a single `w3wp.exe` process: the **first** application to start sets the `OTEL_*` configuration — including the service name — for every application in that pool. Give each application to onboard its own application pool.
{{< /callout >}}

Run `iisreset` after any configuration change.

### Windows Service

```powershell
Import-Module "C:\Program Files\OpenTelemetry .NET AutoInstrumentation\OpenTelemetry.DotNet.Auto.psm1"
Register-OpenTelemetryForWindowsService -WindowsServiceName "<WINDOWS_SERVICE_NAME>" -OTelServiceName "<SERVICE_NAME>"
```

This **restarts the service** by default (`-NoReset` skips it). Set the other `OTEL_*` variables as environment variables of the service, then restart it with `Restart-Service -Name <WINDOWS_SERVICE_NAME> -Force`.

### Linux (systemd)

`instrument.sh` exports the instrumentation's variables. Start the application through a small launcher script:

```bash
#!/bin/sh
# /opt/myapp/start-with-otel.sh
export OTEL_DOTNET_AUTO_HOME=/opt/otel-dotnet-auto
. /opt/otel-dotnet-auto/instrument.sh
exec dotnet /opt/myapp/MyApp.dll
```

and put the `OTEL_*` settings in the unit file:

```ini
[Service]
ExecStart=/opt/myapp/start-with-otel.sh
Environment=OTEL_SERVICE_NAME=<SERVICE_NAME>
Environment=OTEL_TRACES_EXPORTER=otlp
Environment=OTEL_METRICS_EXPORTER=none
Environment=OTEL_LOGS_EXPORTER=none
Environment=OTEL_EXPORTER_OTLP_ENDPOINT=http://<NEURONES_COLLECTOR_HOST>:4318
Environment=OTEL_RESOURCE_ATTRIBUTES=application=<APPLICATION_NAME>,deployment.environment=<ENVIRONMENT>
```

Then `sudo systemctl daemon-reload && sudo systemctl restart <unit>`.

{{< callout type="warn" >}}
On .NET 8 and later, `DOTNET_EnableDiagnostics=0` disables the CLR profiler the instrumentation relies on. If your environment sets it, set `DOTNET_EnableDiagnostics=1` (or keep it at 0 and set `DOTNET_EnableDiagnostics_Profiler=1`).
{{< /callout >}}

## Generate test traffic {#test-traffic}

Trigger at least one real request. Prefer an endpoint that runs a database query: this validates HTTP and database instrumentation together.

## Verification in Neurons {#verify}

Confirm that:

1. The application appears in the Applications list under its `application` name (not under **Unassigned**).
2. The service appears under that application with its `OTEL_SERVICE_NAME`, with a recent `last_seen`.
3. A real HTTP request appears in Traces / Business Transactions.
4. The HTTP route, method, status code and duration are correct.
5. A request that touches the database produces database spans.
6. The database system and name are populated where supported.
7. Outgoing `HttpClient` calls to other instrumented services appear in the same distributed trace, where applicable.
8. The environment shown matches `deployment.environment`.

{{< callout >}}
An onboarding is not complete until it has been validated against the deployed environment, not only locally.
{{< /callout >}}

### Database coverage

The automatic instrumentation covers, among others:

| Instrumentation | Library | Runtime |
|---|---|---|
| SQLCLIENT | Microsoft.Data.SqlClient, System.Data.SqlClient | .NET and .NET Framework |
| ENTITYFRAMEWORKCORE | Microsoft.EntityFrameworkCore | .NET only |
| NPGSQL | Npgsql (PostgreSQL) | .NET and .NET Framework |
| MYSQLCONNECTOR | MySqlConnector | .NET and .NET Framework |
| MYSQLDATA | MySql.Data | .NET only |
| ORACLEMDA | Oracle.ManagedDataAccess(.Core) | .NET and .NET Framework |
| SQLITE | Microsoft.Data.Sqlite | .NET and .NET Framework |
{mono="1"}

For the complete, version-specific list, see the upstream [instrumented libraries](https://github.com/open-telemetry/opentelemetry-dotnet-instrumentation/blob/main/docs/config.md#instrumented-libraries-and-frameworks). A database client not covered there produces no database spans.

## Optional — HTTP header capture {#http-capture}

Header capture is built into the automatic instrumentation and is **off by default**. Enable it with an explicit allow-list:

```bash
# Incoming requests — ASP.NET Core
OTEL_DOTNET_AUTO_TRACES_ASPNETCORE_INSTRUMENTATION_CAPTURE_REQUEST_HEADERS=Content-Type,Accept,User-Agent,X-Correlation-Id
OTEL_DOTNET_AUTO_TRACES_ASPNETCORE_INSTRUMENTATION_CAPTURE_RESPONSE_HEADERS=Content-Type,X-Correlation-Id

# Incoming requests — ASP.NET (.NET Framework): same variables with ASPNET instead of ASPNETCORE

# Outgoing HttpClient calls
OTEL_DOTNET_AUTO_TRACES_HTTP_INSTRUMENTATION_CAPTURE_REQUEST_HEADERS=X-Correlation-Id
OTEL_DOTNET_AUTO_TRACES_HTTP_INSTRUMENTATION_CAPTURE_RESPONSE_HEADERS=Content-Type
```

{{< callout type="warn" >}}
Never add `Authorization`, `Cookie` or `Set-Cookie` to these lists: the value is recorded as-is, without masking.
{{< /callout >}}

Request and response **bodies** are not captured by the automatic instrumentation. Body capture would require custom code; it is not part of standard onboarding. For the general capture policy, see [Application Instrumentation (OpenTelemetry)](../../#otel).

## Security and privacy {#security}

- Never commit tokens or credentials to version control or to committed `web.config` / `appsettings` files.
- Keep release verification enabled when installing or updating the instrumentation.
- Do not capture `Authorization`, `Cookie` or `Set-Cookie` headers.
- Review whether SQL statement text recorded on database spans can contain personal or sensitive data.

## Rollback / disable {#rollback}

**Temporarily disable telemetry** — the instrumentation stays installed:

1. Set `OTEL_TRACES_EXPORTER=none` where the `OTEL_*` variables are configured (or `OTEL_DOTNET_AUTO_TRACES_INSTRUMENTATION_ENABLED=false` to stop instrumenting altogether).
2. Restart the application (`iisreset`, `Restart-Service`, `systemctl restart`, or redeploy the container).
3. Confirm that `last_seen` in Neurons no longer advances after the expected observation window.

To re-enable, restore the previous value and restart the application.

**Fully remove the instrumentation — Windows** (as administrator):

```powershell
Import-Module "C:\Program Files\OpenTelemetry .NET AutoInstrumentation\OpenTelemetry.DotNet.Auto.psm1"

# If IIS was registered
Unregister-OpenTelemetryForIIS

# For each registered Windows Service
Unregister-OpenTelemetryForWindowsService -WindowsServiceName <WINDOWS_SERVICE_NAME>

Uninstall-OpenTelemetryCore
```

Use the same module version for uninstallation as for installation.

**Fully remove the instrumentation — Linux:** start the application without the launcher script (restore the original `ExecStart`), remove the `OTEL_*` lines from the unit, run `systemctl daemon-reload` and restart, then delete `/opt/otel-dotnet-auto`.

**Containers / NuGet:** remove the `OpenTelemetry.AutoInstrumentation` package reference, rebuild and redeploy.

## Troubleshooting {#troubleshooting}

| Symptom | Likely cause | Action |
|---|---|---|
| No spans at all | The process was not started with the instrumentation's environment variables | Check how the real process starts (IIS registration, service registration, launcher script). |
| ASP.NET Core on IIS produces no telemetry | Application pool not set to **No Managed Code** | Change the pool's .NET CLR Version, then `iisreset`. |
| No spans on .NET 8+ | `DOTNET_EnableDiagnostics=0` disables the CLR profiler | Set `DOTNET_EnableDiagnostics=1` (see [Activate per runtime](#activate)). |
| Several IIS applications report the same service name | .NET Framework applications sharing an application pool | Give each application its own application pool. |
| Export errors in the application output | Collector unreachable, or it requires authentication or TLS | Run the [connectivity check](#connectivity); see [Authentication](#auth) and [TLS](#tls). |
| Service visible but listed under **Unassigned** | `application` attribute missing or misspelled | Check `OTEL_RESOURCE_ATTRIBUTES` (see [Application vs service](#naming)). |
| Environment not shown | `deployment.environment.name` used instead of `deployment.environment` | Use `deployment.environment`. |
| HTTP spans but no database spans | Database client not covered, or not supported on this runtime | Check [Database coverage](#verify). |
| Installer stops with a verification error | GitHub CLI missing, or a download that does not match the release | Install {{< mono "gh" >}} and retry; do not skip verification without a review. |

## Definition of Done {#done}

Backend onboarding is complete only when:

- the runtime meets the [supported versions](#versions)
- the instrumentation was installed with release verification, at a pinned version
- the Collector is reachable from the application server, with authentication and TLS as required
- the real process (IIS pool, Windows Service, systemd unit, container) starts with the instrumentation and the `OTEL_*` variables
- `application` and a unique `OTEL_SERVICE_NAME` are configured, and the application is not listed under **Unassigned**
- `deployment.environment` (not `.name`) is configured
- a real HTTP request appears in Neurons
- database tracing is verified where the application uses a covered database client
- downstream trace propagation is verified where applicable
- header capture is off, or limited to an approved allow-list
- both rollback paths (temporary disable, full removal) are documented and the temporary disable has been tested
- validation is performed on the deployed environment
