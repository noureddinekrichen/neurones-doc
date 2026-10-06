---
title: Onboarding des applications .NET
linkTitle: ".NET"
lede: Instrumenter une application .NET ou .NET Framework avec l'instrumentation automatique OpenTelemetry pour que ses requêtes HTTP, ses appels à la base de données et ses traces distribuées apparaissent dans Neurons — sans modifier le code.
menus:
  onboarding:
    parent: opentelemetry
    weight: 30
labels:
  versions: Versions prises en charge
  connectivity: Connectivité au Collecteur
  install: Installer l'instrumentation
  activate: Activer selon l'hébergement
  configure: Configurer OpenTelemetry
  http-capture: Capture des en-têtes HTTP
  done: Definition of Done
---

Les applications .NET sont instrumentées avec **OpenTelemetry .NET Automatic Instrumentation**, l'agent officiel sans code du projet OpenTelemetry. Il s'attache au processus au démarrage (profileur CLR et startup hook .NET) et instrumente ASP.NET Core, ASP.NET, `HttpClient` et les clients de base de données courants, sans aucune modification du code de l'application.

L'instrumentation devient active lorsque l'instrumentation automatique est installée sur le serveur **et** que le processus qui exécute l'application démarre avec ses variables d'environnement — ce que les scripts et le module PowerShell fournis configurent pour vous.

## Périmètre {#scope}

Ce guide couvre **uniquement le traçage backend** : spans HTTP serveur et client, spans de base de données, propagation de trace distribuée, et l'identification de l'application et de l'environnement que Neurons utilise pour les regrouper.

Il ne configure **pas** :

- **Les logs** — la configuration ci-dessous définit `OTEL_LOGS_EXPORTER=none`.
- **Les métriques** — Neurons calcule les métriques de service (débit, erreurs, durée) à partir des traces elles-mêmes ; la configuration définit `OTEL_METRICS_EXPORTER=none`.
- **Le RUM navigateur** — instrumenter le backend .NET n'active aucune surveillance du navigateur. Voir [Onboarding du RUM navigateur](../browser-rum/).

La capture des en-têtes HTTP est un complément optionnel, décrit en fin de page.

## Architecture {#architecture}

{{< flow label="Comment la télémétrie .NET arrive dans Neurons" >}}
app | Votre application .NET | OpenTelemetry .NET Automatic Instrumentation — profileur CLR, aucun code modifié
→ OTLP sur HTTP (protobuf)
platform | Collecteur OpenTelemetry Neurons | Reçoit la télémétrie, la convertit en OTLP/JSON et ajoute le jeton d'ingestion
→ OTLP sur HTTP (JSON)
platform | apm-ingest | Service d'ingestion Neurons : valide et enregistre la télémétrie
→
platform | Neurons APM | Applications, services, traces et transactions métier
{{< /flow >}}

{{< callout >}}
La télémétrie .NET passe toujours par le Collecteur OpenTelemetry Neurons. L'instrumentation automatique envoie de l'OTLP/protobuf ; le Collecteur le convertit et le transmet au service d'ingestion Neurons, qui n'accepte que l'OTLP/JSON. Ne jamais pointer l'exportateur .NET directement vers le service d'ingestion.
{{< /callout >}}

## Prérequis {#prerequisites}

Avant l'intégration, confirmer que :

- L'application tourne sur un environnement d'exécution pris en charge (voir [Versions prises en charge](#versions)).
- Vous disposez d'un accès administrateur / root sur le serveur, pour installer l'instrumentation et modifier le démarrage de l'application.
- Le serveur applicatif peut joindre le Collecteur OpenTelemetry Neurons (voir [Connectivité au Collecteur](#connectivity)).
- Le nom `application` et un `OTEL_SERVICE_NAME` unique ont été convenus (voir [Application ou service](#naming)).
- L'environnement de déploiement cible est connu.
- Le mode d'hébergement de l'application est connu : IIS, service Windows, systemd, conteneur, ou lancement depuis un shell.

{{< callout >}}
L'équipe plateforme Neurons fournit ou confirme l'endpoint du Collecteur, s'il exige une authentification ou TLS, et la convention de nommage application/service avant l'intégration.
{{< /callout >}}

## Versions prises en charge {#versions}

Exigences d'OpenTelemetry .NET Automatic Instrumentation **v1.17.0** (dernière version, octobre 2026) :

| Composant | Exigence |
|---|---|
| .NET | Toutes les versions actuellement prises en charge par Microsoft |
| .NET Framework | 4.6.2 ou plus (Windows uniquement) |
| Architectures | x86, x64 — ARM64 est expérimental |
| Systèmes d'exploitation | Windows Server, Linux (glibc et musl/Alpine), macOS |
| Module PowerShell Windows | PowerShell 5.1 (la version fournie avec Windows) |
{firstcol="26"}

Certaines instrumentations dépendent de l'environnement d'exécution — par exemple ASP.NET Core et Entity Framework Core ne sont pas instrumentés sur .NET Framework, et ASP.NET classique (MVC / Web API) ne l'est que sur .NET Framework.

{{< callout type="warn" >}}
Aucune configuration .NET n'a encore été validée de bout en bout avec Neurons. Exécuter la [vérification](#verify) complète sur l'environnement déployé avant de considérer une application comme intégrée, et communiquer la combinaison validée (runtime, OS, hébergement) à l'équipe plateforme.
{{< /callout >}}

## Vérifier la connectivité au Collecteur {#connectivity}

Avant toute installation, vérifier depuis le **serveur applicatif** que le port OTLP/HTTP du Collecteur (4318 par défaut) est joignable.

Windows (PowerShell) :

```powershell
Test-NetConnection <NEURONES_COLLECTOR_HOST> -Port 4318
```

Linux :

```bash
nc -vz <NEURONES_COLLECTOR_HOST> 4318
```

Vérifier ensuite que le récepteur OTLP répond. Cette commande envoie un export vide : rien n'est enregistré.

```bash
curl -i -X POST http://<NEURONES_COLLECTOR_HOST>:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d '{"resourceSpans":[]}'
```

| Résultat | Signification |
|---|---|
| HTTP 2xx | Le Collecteur est joignable et accepte l'OTLP/HTTP. |
| HTTP 401 / 403 | Le Collecteur exige une authentification — voir [Authentification](#auth). |
| Connexion refusée / délai dépassé | Pare-feu, hôte ou port erroné, ou Collecteur arrêté. À corriger avant d'aller plus loin. |
{firstcol="26"}

## Installer l'instrumentation {#install}

Fixer la version installée et conserver la vérification de la release : les installateurs officiels vérifient les fichiers téléchargés avec la [GitHub CLI](https://cli.github.com/) ({{< mono "gh" >}}), qui doit être installée sur le serveur.

### Windows (module PowerShell)

À exécuter dans **Windows PowerShell 5.1, en administrateur** :

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

    # Vérifier le module avant de l'importer
    gh release verify-asset $version $download_path --repo $repository
    if ($LASTEXITCODE -ne 0) { throw "Release verification failed." }
    gh attestation verify $download_path --repo $repository --signer-workflow $release_workflow --source-ref "refs/tags/$version"
    if ($LASTEXITCODE -ne 0) { throw "Attestation verification failed." }

    Import-Module $download_path
    Install-OpenTelemetryCore -ErrorAction Stop

    # Conserver le module pour les mises à jour et la désinstallation
    Copy-Item -LiteralPath $download_path -Destination (Get-OpenTelemetryInstallDirectory) -Force
}
finally {
    Remove-Item -LiteralPath $download_dir -Force -Recurse -ErrorAction SilentlyContinue
}
```

Les fichiers sont installés sous `C:\Program Files\OpenTelemetry .NET AutoInstrumentation`. Cette installation n'instrumente encore rien : voir [Activer selon l'hébergement](#activate).

### Linux / macOS (scripts shell)

Pour instrumenter un service démarré par systemd, installer dans un répertoire système plutôt que dans `$HOME/.otel-dotnet-auto` (défaut) :

```bash
version="v1.17.0"
repository="open-telemetry/opentelemetry-dotnet-instrumentation"
release_workflow="$repository/.github/workflows/release.yml"
download_dir="$(mktemp -d "${TMPDIR:-/tmp}/otel-dotnet-auto-installer.XXXXXX")"
installer="$download_dir/otel-dotnet-auto-install.sh"
trap 'rm -rf "$download_dir"' 0

curl -sSfL "https://github.com/$repository/releases/download/$version/otel-dotnet-auto-install.sh" -o "$installer"

# Vérifier l'installateur avant de l'exécuter
gh release verify-asset "$version" "$installer" --repo "$repository"
gh attestation verify "$installer" --repo "$repository" \
  --signer-workflow "$release_workflow" --source-ref "refs/tags/$version"

# Installer les fichiers
sudo OTEL_DOTNET_AUTO_HOME=/opt/otel-dotnet-auto VERSION="$version" sh "$installer"
sudo chmod +x /opt/otel-dotnet-auto/instrument.sh
```

Sous macOS, {{< mono "coreutils" >}} est également requis.

### Conteneurs et applications self-contained

Pour les images Docker et les applications self-contained (publiées avec un identifiant de runtime, par exemple `-r linux-x64`), utiliser plutôt le paquet NuGet — c'est la méthode de déploiement recommandée en amont, qui embarque l'instrumentation avec l'application :

```bash
dotnet add package OpenTelemetry.AutoInstrumentation
```

La sortie de build contient alors les scripts de lancement `instrument.sh` / `instrument.cmd`. Démarrer l'application à travers eux, avec les variables d'environnement de [Configurer OpenTelemetry](#configure).

## Configurer OpenTelemetry {#configure}

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

| Paramètre | Rôle |
|---|---|
| OTEL_SERVICE_NAME | Le nom du **service** dans Neurons (voir ci-dessous). S'il est omis, un nom est généré (sur IIS / .NET Framework : `SiteName\VirtualPath`) — toujours le définir explicitement. |
| OTEL_METRICS_EXPORTER / OTEL_LOGS_EXPORTER | `none` : seules les traces sont exportées (voir [Périmètre](#scope)). |
| OTEL_EXPORTER_OTLP_PROTOCOL | `http/protobuf` est la valeur par défaut de l'instrumentation automatique ; la conserver (le protocole `grpc` n'est pas pris en charge sur .NET Framework). |
| OTEL_EXPORTER_OTLP_ENDPOINT | L'endpoint du Collecteur Neurons. |
| application | Le nom de l'**application** dans Neurons (voir ci-dessous). |
| deployment.environment | Identifie l'environnement déployé — par exemple `production`, `preprod`, `staging`, `qa`, `development`. |
{firstcol="30" mono="1"}

{{< callout type="warn" >}}
Les exemples OpenTelemetry en amont utilisent `deployment.environment.name`. Neurons lit actuellement **`deployment.environment`** — utiliser ce nom, sinon l'environnement ne sera pas affiché.
{{< /callout >}}

L'endroit où définir ces variables dépend du mode d'hébergement — voir [Activer selon l'hébergement](#activate).

### Application ou service {#naming}

Neurons regroupe la télémétrie sur deux niveaux :

- **Application** — l'attribut de ressource `application`. C'est ce que liste l'écran Applications. Plusieurs services peuvent partager une même application.
- **Service** — `OTEL_SERVICE_NAME`. Chaque service est listé, avec ses propres métriques, sous son application.

Exemple — une plateforme de commandes composée d'un front web ASP.NET Core et d'un service Windows qui traite les commandes :

| Composant | application | OTEL_SERVICE_NAME |
|---|---|---|
| Front web ASP.NET Core | orders | orders-web |
| Service Windows de traitement | orders | orders-worker |
{mono="2,3"}

Les deux apparaissent sous l'application **orders**, comme deux services.

{{< callout type="warn" >}}
L'attribut doit s'appeler exactement `application` — ni `application.name`, ni `service.namespace`. La télémétrie sans attribut `application` valide n'est pas rejetée : elle est regroupée sous **Unassigned**.
{{< /callout >}}

### Authentification {#auth}

Le service d'ingestion Neurons authentifie le **Collecteur**, pas l'application : c'est le Collecteur qui ajoute le jeton d'ingestion lorsqu'il transmet les données. Une application .NET n'envoie donc normalement aucun identifiant.

Si votre Collecteur est configuré pour exiger un en-tête de la part des applications (la [vérification de connectivité](#connectivity) renvoie 401/403), l'équipe plateforme fournit le nom et la valeur de l'en-tête. Le définir comme variable d'environnement du processus, jamais dans le code source ni dans un fichier de configuration commité :

```bash
OTEL_EXPORTER_OTLP_HEADERS=<HEADER_NAME>=<VALUE>
```

### TLS / HTTPS {#tls}

L'endpoint `http://` ci-dessus concerne un Collecteur joint via un réseau interne de confiance. Lorsque le trafic entre le serveur applicatif et le Collecteur traverse un réseau non maîtrisé, utiliser un endpoint `https://` — cela nécessite que l'équipe plateforme active TLS sur le Collecteur :

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=https://<NEURONES_COLLECTOR_HOST>:4318
```

Le certificat du Collecteur doit être reconnu par le serveur applicatif.

## Activer selon l'hébergement {#activate}

Installer les fichiers ne suffit pas : le processus qui exécute l'application doit démarrer avec les variables d'environnement de l'instrumentation (profileur CLR, startup hook, `OTEL_DOTNET_AUTO_HOME`) **et** les paramètres `OTEL_*` ci-dessus.

### IIS (ASP.NET et ASP.NET Core)

```powershell
Import-Module "C:\Program Files\OpenTelemetry .NET AutoInstrumentation\OpenTelemetry.DotNet.Auto.psm1"
Register-OpenTelemetryForIIS
```

{{< callout type="warn" >}}
`Register-OpenTelemetryForIIS` **redémarre IIS** par défaut (utiliser `-NoReset` pour l'éviter et redémarrer pendant une fenêtre de maintenance).
{{< /callout >}}

- **ASP.NET Core sous IIS :** le pool d'applications doit avoir **Version CLR .NET = Aucun code managé** (No Managed Code), sinon aucune télémétrie n'est produite. Définir les variables `OTEL_*` avec des éléments `<environmentVariable>` dans le bloc `<aspNetCore>` du `web.config` de l'application.
- **ASP.NET (.NET Framework) :** les paramètres `OTEL_*` peuvent être définis dans `<appSettings>` du `web.config`, ou comme variables d'environnement du pool d'applications dans `applicationHost.config`.

{{< callout type="warn" >}}
Les applications .NET Framework qui partagent un pool d'applications s'exécutent dans un seul processus `w3wp.exe` : la **première** application démarrée fixe la configuration `OTEL_*` — y compris le nom de service — pour toutes les applications du pool. Donner à chaque application intégrée son propre pool d'applications.
{{< /callout >}}

Exécuter `iisreset` après toute modification de configuration.

### Service Windows

```powershell
Import-Module "C:\Program Files\OpenTelemetry .NET AutoInstrumentation\OpenTelemetry.DotNet.Auto.psm1"
Register-OpenTelemetryForWindowsService -WindowsServiceName "<WINDOWS_SERVICE_NAME>" -OTelServiceName "<SERVICE_NAME>"
```

Cette commande **redémarre le service** par défaut (`-NoReset` l'évite). Définir les autres variables `OTEL_*` comme variables d'environnement du service, puis le redémarrer avec `Restart-Service -Name <WINDOWS_SERVICE_NAME> -Force`.

### Linux (systemd)

`instrument.sh` exporte les variables de l'instrumentation. Démarrer l'application via un petit script de lancement :

```bash
#!/bin/sh
# /opt/myapp/start-with-otel.sh
export OTEL_DOTNET_AUTO_HOME=/opt/otel-dotnet-auto
. /opt/otel-dotnet-auto/instrument.sh
exec dotnet /opt/myapp/MyApp.dll
```

et placer les paramètres `OTEL_*` dans le fichier d'unité :

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

Puis `sudo systemctl daemon-reload && sudo systemctl restart <unit>`.

{{< callout type="warn" >}}
À partir de .NET 8, `DOTNET_EnableDiagnostics=0` désactive le profileur CLR dont dépend l'instrumentation. Si votre environnement le définit, passer `DOTNET_EnableDiagnostics=1` (ou le laisser à 0 et définir `DOTNET_EnableDiagnostics_Profiler=1`).
{{< /callout >}}

## Générer du trafic de test {#test-traffic}

Déclencher au moins une vraie requête. Privilégier un endpoint qui exécute une requête en base de données : cela valide ensemble l'instrumentation HTTP et base de données.

## Vérification dans Neurons {#verify}

Confirmer que :

1. L'application apparaît dans la liste Applications sous son nom `application` (et non sous **Unassigned**).
2. Le service apparaît sous cette application avec son `OTEL_SERVICE_NAME`, avec un `last_seen` récent.
3. Une vraie requête HTTP apparaît dans Traces / Transactions métier.
4. La route HTTP, la méthode, le code de statut et la durée sont corrects.
5. Une requête qui touche la base de données produit des spans de base de données.
6. Le système et le nom de la base de données sont renseignés lorsque c'est pris en charge.
7. Les appels `HttpClient` sortants vers d'autres services instrumentés apparaissent dans la même trace distribuée, le cas échéant.
8. L'environnement affiché correspond à `deployment.environment`.

{{< callout >}}
Une intégration n'est pas terminée tant qu'elle n'a pas été validée sur l'environnement déployé, et pas seulement en local.
{{< /callout >}}

### Bases de données couvertes

L'instrumentation automatique couvre notamment :

| Instrumentation | Bibliothèque | Environnement d'exécution |
|---|---|---|
| SQLCLIENT | Microsoft.Data.SqlClient, System.Data.SqlClient | .NET et .NET Framework |
| ENTITYFRAMEWORKCORE | Microsoft.EntityFrameworkCore | .NET uniquement |
| NPGSQL | Npgsql (PostgreSQL) | .NET et .NET Framework |
| MYSQLCONNECTOR | MySqlConnector | .NET et .NET Framework |
| MYSQLDATA | MySql.Data | .NET uniquement |
| ORACLEMDA | Oracle.ManagedDataAccess(.Core) | .NET et .NET Framework |
| SQLITE | Microsoft.Data.Sqlite | .NET et .NET Framework |
{mono="1"}

Pour la liste complète et propre à chaque version, voir les [bibliothèques instrumentées](https://github.com/open-telemetry/opentelemetry-dotnet-instrumentation/blob/main/docs/config.md#instrumented-libraries-and-frameworks) en amont. Un client de base de données absent de cette liste ne produit aucun span de base de données.

## Optionnel — Capture des en-têtes HTTP {#http-capture}

La capture des en-têtes est intégrée à l'instrumentation automatique et **désactivée par défaut**. L'activer avec une liste blanche explicite :

```bash
# Requêtes entrantes — ASP.NET Core
OTEL_DOTNET_AUTO_TRACES_ASPNETCORE_INSTRUMENTATION_CAPTURE_REQUEST_HEADERS=Content-Type,Accept,User-Agent,X-Correlation-Id
OTEL_DOTNET_AUTO_TRACES_ASPNETCORE_INSTRUMENTATION_CAPTURE_RESPONSE_HEADERS=Content-Type,X-Correlation-Id

# Requêtes entrantes — ASP.NET (.NET Framework) : mêmes variables avec ASPNET au lieu de ASPNETCORE

# Appels HttpClient sortants
OTEL_DOTNET_AUTO_TRACES_HTTP_INSTRUMENTATION_CAPTURE_REQUEST_HEADERS=X-Correlation-Id
OTEL_DOTNET_AUTO_TRACES_HTTP_INSTRUMENTATION_CAPTURE_RESPONSE_HEADERS=Content-Type
```

{{< callout type="warn" >}}
Ne jamais ajouter `Authorization`, `Cookie` ou `Set-Cookie` à ces listes : la valeur est enregistrée telle quelle, sans masquage.
{{< /callout >}}

Les **corps** des requêtes et réponses ne sont pas capturés par l'instrumentation automatique. Leur capture nécessiterait du code spécifique ; elle ne fait pas partie de l'intégration standard. Pour la politique de capture générale, voir [Instrumentation des applications (OpenTelemetry)](../../#otel).

## Sécurité et confidentialité {#security}

- Ne jamais commiter de jetons ou d'identifiants dans le contrôle de version, ni dans des fichiers `web.config` / `appsettings` commités.
- Conserver la vérification de la release lors de l'installation ou de la mise à jour de l'instrumentation.
- Ne pas capturer les en-têtes `Authorization`, `Cookie` ou `Set-Cookie`.
- Vérifier si le texte SQL enregistré sur les spans de base de données peut contenir des données personnelles ou sensibles.

## Retour en arrière / désactivation {#rollback}

**Désactiver temporairement la télémétrie** — l'instrumentation reste installée :

1. Définir `OTEL_TRACES_EXPORTER=none` là où les variables `OTEL_*` sont configurées (ou `OTEL_DOTNET_AUTO_TRACES_INSTRUMENTATION_ENABLED=false` pour ne plus instrumenter du tout).
2. Redémarrer l'application (`iisreset`, `Restart-Service`, `systemctl restart`, ou redéploiement du conteneur).
3. Confirmer que `last_seen` dans Neurons n'avance plus après la fenêtre d'observation prévue.

Pour réactiver, restaurer la valeur précédente puis redémarrer l'application.

**Supprimer complètement l'instrumentation — Windows** (en administrateur) :

```powershell
Import-Module "C:\Program Files\OpenTelemetry .NET AutoInstrumentation\OpenTelemetry.DotNet.Auto.psm1"

# Si IIS a été enregistré
Unregister-OpenTelemetryForIIS

# Pour chaque service Windows enregistré
Unregister-OpenTelemetryForWindowsService -WindowsServiceName <WINDOWS_SERVICE_NAME>

Uninstall-OpenTelemetryCore
```

Utiliser pour la désinstallation la même version du module que pour l'installation.

**Supprimer complètement l'instrumentation — Linux :** démarrer l'application sans le script de lancement (restaurer l'`ExecStart` d'origine), retirer les lignes `OTEL_*` de l'unité, exécuter `systemctl daemon-reload` et redémarrer, puis supprimer `/opt/otel-dotnet-auto`.

**Conteneurs / NuGet :** retirer la référence au paquet `OpenTelemetry.AutoInstrumentation`, reconstruire et redéployer.

## Dépannage {#troubleshooting}

| Symptôme | Cause probable | Action |
|---|---|---|
| Aucun span | Le processus n'a pas démarré avec les variables d'environnement de l'instrumentation | Vérifier comment le processus réel démarre (enregistrement IIS, enregistrement du service, script de lancement). |
| ASP.NET Core sous IIS ne produit aucune télémétrie | Pool d'applications non réglé sur **Aucun code managé** | Changer la version CLR .NET du pool, puis `iisreset`. |
| Aucun span sur .NET 8+ | `DOTNET_EnableDiagnostics=0` désactive le profileur CLR | Définir `DOTNET_EnableDiagnostics=1` (voir [Activer selon l'hébergement](#activate)). |
| Plusieurs applications IIS remontent le même nom de service | Applications .NET Framework partageant un pool d'applications | Donner à chaque application son propre pool. |
| Erreurs d'export dans la sortie de l'application | Collecteur injoignable, ou il exige une authentification ou TLS | Lancer la [vérification de connectivité](#connectivity) ; voir [Authentification](#auth) et [TLS](#tls). |
| Service visible mais listé sous **Unassigned** | Attribut `application` absent ou mal orthographié | Vérifier `OTEL_RESOURCE_ATTRIBUTES` (voir [Application ou service](#naming)). |
| Environnement non affiché | `deployment.environment.name` utilisé au lieu de `deployment.environment` | Utiliser `deployment.environment`. |
| Spans HTTP mais aucun span de base de données | Client de base de données non couvert, ou non pris en charge sur cet environnement d'exécution | Vérifier les [bases de données couvertes](#verify). |
| L'installateur s'arrête sur une erreur de vérification | GitHub CLI absente, ou téléchargement ne correspondant pas à la release | Installer {{< mono "gh" >}} et réessayer ; ne pas désactiver la vérification sans revue. |

## Definition of Done {#done}

L'intégration backend n'est terminée que lorsque :

- l'environnement d'exécution respecte les [versions prises en charge](#versions)
- l'instrumentation a été installée avec vérification de la release, à une version fixée
- le Collecteur est joignable depuis le serveur applicatif, avec authentification et TLS si nécessaire
- le processus réel (pool IIS, service Windows, unité systemd, conteneur) démarre avec l'instrumentation et les variables `OTEL_*`
- `application` et un `OTEL_SERVICE_NAME` unique sont configurés, et l'application n'est pas listée sous **Unassigned**
- `deployment.environment` (et non `.name`) est configuré
- une vraie requête HTTP apparaît dans Neurons
- le traçage de base de données est vérifié lorsque l'application utilise un client couvert
- la propagation de trace en aval est vérifiée le cas échéant
- la capture des en-têtes est désactivée, ou limitée à une liste blanche approuvée
- les deux procédures de retour en arrière (désactivation temporaire, suppression complète) sont documentées et la désactivation temporaire a été testée
- la validation est effectuée sur l'environnement déployé
