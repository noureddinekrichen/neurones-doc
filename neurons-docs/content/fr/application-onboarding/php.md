---
title: Onboarding des applications PHP
linkTitle: PHP
lede: Instrumenter une application PHP avec OpenTelemetry pour que ses requêtes HTTP, ses appels à la base de données et ses traces distribuées apparaissent dans Neurons — puis, en option, ajouter la capture des données HTTP.
menus:
  onboarding:
    parent: opentelemetry
    weight: 10
labels:
  versions: Versions prises en charge
  connectivity: Connectivité au Collecteur
  configure: Configurer OpenTelemetry
  http-capture: Capture des données HTTP
  done: Definition of Done
---

Les applications PHP sont instrumentées avec l'extension PHP OpenTelemetry, associée aux paquets Composer d'auto-instrumentation. Aucune commande de démarrage encapsulée n'est nécessaire.

L'auto-instrumentation devient active lorsque :

- {{< mono "ext-opentelemetry" >}} est activée dans l'environnement d'exécution PHP ;
- les paquets Composer d'instrumentation requis sont installés et chargés ;
- `OTEL_PHP_AUTOLOAD_ENABLED=true` est visible par le processus PHP qui sert réellement l'application.

## Périmètre {#scope}

Ce guide couvre **uniquement le traçage backend** : spans serveur HTTP, spans de base de données PDO, propagation de trace distribuée, et l'identification de l'application et de l'environnement que Neurons utilise pour les regrouper.

Il ne configure **pas** :

- **Les logs** — l'export des logs PHP ne fait pas partie de cet onboarding ; la configuration ci-dessous définit `OTEL_LOGS_EXPORTER=none`.
- **Les métriques** — Neurons calcule les métriques de service (débit, erreurs, durée) à partir des traces elles-mêmes ; la configuration définit `OTEL_METRICS_EXPORTER=none`.
- **Le RUM navigateur** — instrumenter le backend PHP n'active aucune surveillance du navigateur. Le RUM navigateur s'intègre séparément : voir [Onboarding du RUM navigateur](../browser-rum/).

La capture des en-têtes/corps HTTP est un complément optionnel, décrit en fin de page.

## Architecture {#architecture}

{{< flow label="Comment la télémétrie PHP arrive dans Neurons" >}}
app | Votre application PHP | `ext-opentelemetry` + auto-instrumentation Composer (spans du framework et PDO)
→ OTLP sur HTTP (protobuf)
platform | Collecteur OpenTelemetry Neurons | Reçoit la télémétrie, la convertit en OTLP/JSON et ajoute le jeton d'ingestion
→ OTLP sur HTTP (JSON)
platform | apm-ingest | Service d'ingestion Neurons : valide et enregistre la télémétrie
→
platform | Neurons APM | Applications, services, traces et transactions métier
{{< /flow >}}

{{< callout >}}
La télémétrie PHP passe toujours par le Collecteur OpenTelemetry Neurons. L'exportateur PHP envoie de l'OTLP/protobuf ; le Collecteur le convertit et le transmet au service d'ingestion Neurons, qui n'accepte que l'OTLP/JSON. Ne jamais pointer l'exportateur PHP directement vers le service d'ingestion.
{{< /callout >}}

## Prérequis {#prerequisites}

Avant l'intégration, confirmer que :

- Une version de PHP prise en charge est installée sur le serveur applicatif cible (voir [Versions prises en charge](#versions)).
- Composer est installé.
- {{< mono "ext-opentelemetry" >}} peut être installée et activée.
- Le serveur applicatif peut joindre le Collecteur OpenTelemetry Neurons (voir [Connectivité au Collecteur](#connectivity)).
- Le nom `application` et un `OTEL_SERVICE_NAME` unique ont été convenus (voir [Application ou service](#naming)).
- L'environnement de déploiement cible est connu.
- L'équipe peut configurer les variables d'environnement du processus d'exécution PHP réel.

{{< callout >}}
L'équipe plateforme Neurons fournit ou confirme l'endpoint du Collecteur, s'il exige une authentification ou TLS, et la convention de nommage application/service avant l'intégration.
{{< /callout >}}

## Versions prises en charge {#versions}

Versions minimales requises par les paquets OpenTelemetry PHP actuels (vérifiées sur Packagist, octobre 2026) :

| Composant | Exigence |
|---|---|
| PHP | 8.1 ou plus — **8.2 ou plus** avec la version actuelle de {{< mono "opentelemetry-auto-pdo" >}} (0.5.x) |
| ext-opentelemetry | Requise par les paquets d'instrumentation du framework et de PDO |
| Laravel | 10, 11, 12 ou 13 ({{< mono "opentelemetry-auto-laravel" >}}) |
| Symfony | Toute version fournissant {{< mono "symfony/http-kernel" >}} ({{< mono "opentelemetry-auto-symfony" >}}) |
| Slim | 4 ({{< mono "opentelemetry-auto-slim" >}}) |
{firstcol="26"}

Configuration validée de bout en bout avec Neurons : **Laravel 11 sous Windows, IIS / FastCGI**.

{{< callout type="warn" >}}
Les autres combinaisons de version de PHP, de système d'exploitation, de serveur web (PHP-FPM, Apache, nginx, Docker) ou de version de framework devraient fonctionner si elles respectent les exigences ci-dessus, mais n'ont pas été validées par Neurons : exécuter la [vérification](#verify) complète avant de les considérer comme prises en charge. Les exigences des paquets évoluent d'une version à l'autre — vérifier celle que vous installez.
{{< /callout >}}

## Installer l'instrumentation Composer {#install}

Pour une application Laravel :

```bash
composer require \
  open-telemetry/opentelemetry-auto-laravel \
  open-telemetry/opentelemetry-auto-pdo \
  open-telemetry/sdk \
  open-telemetry/exporter-otlp \
  open-telemetry/sem-conv
```

- {{< mono "opentelemetry-auto-laravel" >}} — instrumentation des requêtes et du framework Laravel.
- {{< mono "opentelemetry-auto-pdo" >}} — spans PDO/base de données.
- {{< mono "sdk" >}} — le SDK OpenTelemetry.
- {{< mono "exporter-otlp" >}} — l'exportateur OTLP.
- {{< mono "sem-conv" >}} — les définitions des conventions sémantiques.

Pour Symfony ou Slim, remplacer le paquet Laravel par le paquet d'instrumentation correspondant :

| Framework | Paquet |
|---|---|
| Laravel | open-telemetry/opentelemetry-auto-laravel |
| Symfony | open-telemetry/opentelemetry-auto-symfony |
| Slim | open-telemetry/opentelemetry-auto-slim |
{mono="2"}

Les autres frameworks ne sont pas couverts par ce guide. S'il existe pour eux un paquet d'auto-instrumentation OpenTelemetry, il peut être utilisé de la même façon, mais le résultat doit être vérifié manuellement.

### Bases de données couvertes

Dans ce guide, le traçage de base de données désigne **PDO** ({{< mono "opentelemetry-auto-pdo" >}}) : MySQL, PostgreSQL, SQLite, SQL Server et les autres bases accédées via PDO. La couche base de données de Laravel utilise PDO, elle est donc couverte ; Doctrine DBAL l'est lorsqu'il est configuré avec un pilote `pdo_*`. Les applications qui utilisent un autre client — par exemple {{< mono "mysqli" >}} — n'obtiennent aucun span de base de données avec cette configuration.

## Activer ext-opentelemetry {#extension}

Les paquets Composer seuls ne suffisent pas : l'extension {{< mono "ext-opentelemetry" >}} doit aussi être activée dans la configuration PHP.

```ini
extension=opentelemetry
```

Vérification sous Linux :

```bash
php -m | grep -i opentelemetry
```

Vérification sous Windows :

```bat
php -m | findstr /I opentelemetry
```

Résultat attendu :

```text
opentelemetry
```

{{< callout type="warn" >}}
L'extension doit être activée dans l'environnement d'exécution PHP qui sert réellement l'application, pas seulement dans une installation PHP locale ou CLI.
{{< /callout >}}

Sous Windows, l'installation peut nécessiter la DLL d'extension PHP correspondant à la version et à la compilation de PHP, plutôt que `pecl install`.

## Vérifier la connectivité au Collecteur {#connectivity}

Avant de configurer l'application, vérifier depuis le **serveur applicatif** que le port OTLP/HTTP du Collecteur (4318 par défaut) est joignable.

Linux :

```bash
nc -vz <NEURONES_COLLECTOR_HOST> 4318
```

Windows (PowerShell) :

```powershell
Test-NetConnection <NEURONES_COLLECTOR_HOST> -Port 4318
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

## Configurer OpenTelemetry {#configure}

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

| Paramètre | Rôle |
|---|---|
| OTEL_PHP_AUTOLOAD_ENABLED | Active les hooks d'auto-instrumentation Composer. |
| OTEL_SERVICE_NAME | Le nom du **service** dans Neurons (voir ci-dessous). |
| OTEL_METRICS_EXPORTER / OTEL_LOGS_EXPORTER | `none` : seules les traces sont exportées (voir [Périmètre](#scope)). |
| OTEL_EXPORTER_OTLP_ENDPOINT | L'endpoint du Collecteur Neurons. |
| application | Le nom de l'**application** dans Neurons (voir ci-dessous). |
| deployment.environment | Identifie l'environnement déployé — par exemple `production`, `preprod`, `staging`, `qa`, `development`. |
{firstcol="30" mono="1"}

Note de compatibilité : pour le contrat d'ingestion actuel de Neurons, utiliser `deployment.environment`, et non le plus récent `deployment.environment.name`.

### Application ou service {#naming}

Neurons regroupe la télémétrie sur deux niveaux :

- **Application** — l'attribut de ressource `application`. C'est ce que liste l'écran Applications. Plusieurs services peuvent partager une même application.
- **Service** — `OTEL_SERVICE_NAME`. Chaque service est listé, avec ses propres métriques, sous son application.

Exemple — une boutique en ligne composée d'une vitrine Laravel et d'une API de paiement PHP séparée :

| Composant | application | OTEL_SERVICE_NAME |
|---|---|---|
| Vitrine Laravel | eshop | eshop-web |
| API de paiement | eshop | eshop-payment-api |
{mono="2,3"}

Les deux apparaissent sous l'application **eshop**, comme deux services.

{{< callout type="warn" >}}
L'attribut doit s'appeler exactement `application` — ni `application.name`, ni `service.namespace`. La télémétrie sans attribut `application` valide n'est pas rejetée : elle est regroupée sous **Unassigned**.
{{< /callout >}}

### Authentification {#auth}

Le service d'ingestion Neurons authentifie le **Collecteur**, pas l'application : c'est le Collecteur qui ajoute le jeton d'ingestion lorsqu'il transmet les données. Une application PHP n'envoie donc normalement aucun identifiant.

Si votre Collecteur est configuré pour exiger un en-tête de la part des applications (la [vérification de connectivité](#connectivity) renvoie 401/403), l'équipe plateforme fournit le nom et la valeur de l'en-tête. Le définir comme variable d'environnement du processus, jamais dans le code source :

```bash
OTEL_EXPORTER_OTLP_HEADERS=<HEADER_NAME>=<VALUE>
```

### TLS / HTTPS {#tls}

L'endpoint `http://` ci-dessus concerne un Collecteur joint via un réseau interne de confiance. Lorsque le trafic entre le serveur applicatif et le Collecteur traverse un réseau non maîtrisé, utiliser un endpoint `https://` — cela nécessite que l'équipe plateforme active TLS sur le Collecteur :

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=https://<NEURONES_COLLECTOR_HOST>:4318
```

Le certificat du Collecteur doit être reconnu par le serveur applicatif.

## Environnement d'exécution {#runtime}

{{< callout type="warn" >}}
Les variables `OTEL_*` doivent être visibles par le processus PHP qui sert réellement les requêtes web. Une valeur présente uniquement dans un fichier `.env` de l'application ou dans un shell de déploiement ne suffit pas, sauf si cet environnement d'exécution la reçoit effectivement.
{{< /callout >}}

Cela s'applique quel que soit l'environnement d'exécution — par exemple IIS / FastCGI, PHP-FPM, Docker, ou des processus PHP gérés par systemd.

### Redémarrer / recharger l'environnement d'exécution

Après la configuration, redémarrer ou recharger l'environnement d'exécution PHP pour que l'extension et les variables d'environnement soient appliquées — par exemple : recycler le pool d'applications, recharger PHP-FPM, redémarrer le conteneur, ou redémarrer le service géré.

## Générer du trafic de test {#test-traffic}

Déclencher au moins une vraie requête. Privilégier une route qui entre dans l'application PHP et exécute une requête en base de données : cela valide ensemble l'instrumentation HTTP et PDO.

## Vérification dans Neurons {#verify}

Confirmer que :

1. L'application apparaît dans la liste Applications sous son nom `application` (et non sous **Unassigned**).
2. Le service apparaît sous cette application avec son `OTEL_SERVICE_NAME`, avec un `last_seen` récent.
3. Une vraie requête HTTP apparaît dans Traces / Transactions métier.
4. La route HTTP, la méthode, le code de statut et la durée sont corrects.
5. Une requête qui touche la base de données produit des spans de base de données.
6. Le système et le nom de la base de données sont renseignés lorsque c'est pris en charge.
7. Les opérations de base de données sont correctement classées.
8. La propagation de trace fonctionne vers les services instrumentés en aval, le cas échéant.

{{< callout >}}
Une intégration n'est pas terminée tant qu'elle n'a pas été validée sur l'environnement déployé, et pas seulement en local.
{{< /callout >}}

## Optionnel — Capture des données HTTP {#http-capture}

La configuration OpenTelemetry PHP actuelle de Neurons ne fournit pas, via l'auto-instrumentation Laravel, le comportement de capture côté serveur des en-têtes/corps HTTP requis par Neurons. Lorsque c'est nécessaire, un middleware de framework Neurons approuvé enrichit le span de la requête active. Valeurs par défaut sûres :

```bash
NEURONES_APM_CAPTURE_HEADERS=true
NEURONES_APM_CAPTURE_REQUEST_BODY=false
NEURONES_APM_CAPTURE_RESPONSE_BODY=false
NEURONES_APM_CAPTURE_BODY_MAX_BYTES=4096
```

- Les en-têtes reposent sur une liste blanche.
- La capture du corps de la requête et celle du corps de la réponse sont indépendantes.
- La capture des corps est optionnelle (opt-in).
- Les champs sensibles doivent être masqués.
- Les routes sensibles doivent être exclues.
- Les contenus binaires, multipart et en streaming ne doivent pas être capturés.

Pour la politique de capture complète, voir les règles de capture des en-têtes et du corps dans [Instrumentation des applications (OpenTelemetry)](../../#otel).

## Sécurité et confidentialité {#security}

- Ne jamais commiter de jetons dans le contrôle de version.
- Ne pas capturer les valeurs `Authorization` ou `Cookie`.
- La capture des corps doit rester optionnelle (opt-in).
- Les champs sensibles doivent être masqués.
- Les routes sensibles doivent être exclues de la capture de contenu.

## Retour en arrière / désactivation {#rollback}

**Désactiver temporairement la télémétrie** — l'extension et les paquets restent installés, la réactivation est donc rapide :

1. Définir `OTEL_TRACES_EXPORTER=none` (arrête l'export), ou `OTEL_PHP_AUTOLOAD_ENABLED=false` (n'active plus du tout l'instrumentation).
2. Redémarrer ou recharger l'environnement d'exécution PHP.
3. Confirmer que `last_seen` dans Neurons n'avance plus après la fenêtre d'observation prévue.

Pour réactiver, restaurer la valeur précédente puis redémarrer ou recharger l'environnement d'exécution.

**Supprimer complètement l'instrumentation :**

1. Retirer les variables d'environnement `OTEL_*` de l'environnement d'exécution.
2. Supprimer les paquets d'instrumentation :

   ```bash
   composer remove \
     open-telemetry/opentelemetry-auto-laravel \
     open-telemetry/opentelemetry-auto-pdo \
     open-telemetry/sdk \
     open-telemetry/exporter-otlp \
     open-telemetry/sem-conv
   ```

3. Retirer `extension=opentelemetry` de la configuration PHP.
4. Redémarrer l'environnement d'exécution PHP, puis vérifier que l'application fonctionne toujours et que `php -m` ne liste plus `opentelemetry`.

## Dépannage {#troubleshooting}

| Symptôme | Cause probable | Action |
|---|---|---|
| Aucun span | {{< mono "ext-opentelemetry" >}} non chargée | Vérifier l'extension sur l'environnement d'exécution réel. |
| Extension chargée mais aucun span | `OTEL_PHP_AUTOLOAD_ENABLED` absent, ou instrumentation Composer non chargée | Vérifier l'environnement et les paquets Composer. |
| La configuration CLI semble correcte mais les requêtes web ne produisent aucune télémétrie | L'environnement d'exécution PHP web n'a pas le même environnement/configuration que PHP CLI | Vérifier l'environnement d'exécution réel (PHP-FPM / FastCGI / conteneur / service). |
| Erreurs d'export dans les logs de l'application | Collecteur injoignable, ou il exige une authentification ou TLS | Lancer la [vérification de connectivité](#connectivity) ; voir [Authentification](#auth) et [TLS](#tls). |
| Service visible mais listé sous **Unassigned** | Attribut `application` absent ou mal orthographié | Vérifier `OTEL_RESOURCE_ATTRIBUTES` (voir [Application ou service](#naming)). |
| L'application apparaît mais aucun span de base de données | Instrumentation PDO absente, ou l'application utilise un autre client de base de données | Vérifier {{< mono "opentelemetry-auto-pdo" >}} et la couche d'accès aux données (voir [Bases de données couvertes](#install)). |
| Champs présents dans les traces brutes mais absents ou erronés dans Neurons | Différence de compatibilité des conventions sémantiques | Comparer les attributs de span émis avec le contrat d'ingestion actuel de Neurons. |

## Definition of Done {#done}

L'intégration backend n'est terminée que lorsque :

- les versions de PHP, du framework et des paquets respectent les [versions prises en charge](#versions)
- {{< mono "ext-opentelemetry" >}} est activée sur le serveur/environnement d'exécution applicatif réel
- les paquets Composer requis sont installés
- le Collecteur est joignable depuis le serveur applicatif, avec authentification et TLS si nécessaire
- les variables `OTEL_*` sont disponibles pour l'environnement d'exécution PHP réel
- `application` et un `OTEL_SERVICE_NAME` unique sont configurés, et l'application n'est pas listée sous **Unassigned**
- `deployment.environment` est configuré
- une vraie requête HTTP apparaît dans Neurons
- le traçage de base de données est vérifié lorsque l'application utilise PDO
- la propagation de trace en aval est vérifiée le cas échéant
- la capture de contenu HTTP sensible est désactivée sauf approbation explicite
- les deux procédures de retour en arrière (désactivation temporaire, suppression complète) sont documentées et la désactivation temporaire a été testée
- la validation est effectuée sur l'environnement déployé
