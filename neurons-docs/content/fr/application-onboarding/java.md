---
title: Onboarding des applications Java
linkTitle: Java
lede: Instrumenter une application Java / Spring Boot avec l'agent Java OpenTelemetry et envoyer ses traces et ses logs vers Neurons — sans modifier le code.
menus:
  onboarding:
    parent: opentelemetry
    weight: 20
labels:
  install: Installer l'agent Java
  configure: Configurer Neurons
  start: Démarrer ou redémarrer
  verify: Vérifier dans Neurons
  headers: Capture des en-têtes HTTP
  body-capture: Capture du corps HTTP
  logs: Logs et corrélation
  controls: Contrôles opérationnels
  rollback: Désactivation / retour arrière
  done: Definition of Done
---

## Présentation {#overview}

Ce guide explique comment instrumenter une application Java / Spring Boot avec l'**agent Java OpenTelemetry** et envoyer sa télémétrie vers Neurons. L'agent s'attache à la JVM au démarrage via `-javaagent` et instrumente automatiquement les serveurs et clients HTTP, l'accès aux bases de données, la messagerie et les logs : le code de l'application ne change pas.

L'onboarding de base exporte les **traces** et, en option, les **logs**. La capture des en-têtes et des corps HTTP sont des options avancées, décrites après les étapes de vérification.

{{< callout >}}
Le déploiement `springboot-ecommerce` — une application Spring Boot en microservices exécutée avec Docker Compose — sert d'**exemple de référence** lorsqu'une configuration concrète est utile. Ses chemins, noms de services et valeurs sont des exemples, pas des exigences.
{{< /callout >}}

La surveillance du navigateur s'intègre séparément : voir [Onboarding du RUM navigateur](../browser-rum/).

## Architecture {#architecture}

{{< flow label="Comment la télémétrie Java arrive dans Neurons" >}}
app | Votre application Java / Spring Boot | Agent Java OpenTelemetry chargé avec `-javaagent` — aucun code modifié
→ OTLP sur HTTP (protobuf) + `X-Neurones-Token`
platform | Collecteur OpenTelemetry Neurons | Reçoit les traces sur `/v1/traces` et les logs sur `/v1/logs`, et les transmet en OTLP/JSON
→ OTLP sur HTTP (JSON)
platform | apm-ingest | Service d'ingestion Neurons : valide et enregistre la télémétrie
→
platform | Neurons APM | Applications, services, traces, logs et transactions métier
{{< /flow >}}

- L'agent exporte en **OTLP/HTTP avec encodage protobuf**. Il doit envoyer vers le **Collecteur OpenTelemetry Neurons**, qui transmet les données au service d'ingestion Neurons — celui-ci n'accepte que l'OTLP/JSON, l'agent ne doit donc jamais pointer directement vers lui.
- Chaque export porte le jeton Neurons dans l'en-tête `X-Neurones-Token` (voir [Authentification](#auth)).
- **La propagation du contexte de trace est automatique.** L'agent propage l'en-tête W3C `traceparent` sur les appels sortants : une requête et tous les appels en aval qu'elle déclenche — à travers tous les services instrumentés — se retrouvent dans la même trace. Lorsque le frontend est instrumenté avec le RUM navigateur, les spans navigateur rejoignent la même trace.

## Prérequis {#prerequisites}

Avant l'onboarding, confirmer que :

- L'application s'exécute sur une JVM, et vous pouvez modifier son démarrage (options JVM ou variables d'environnement).
- Vous pouvez ajouter le jar de l'agent Java OpenTelemetry sur l'hôte ou dans l'image.
- L'hôte de l'application peut joindre le Collecteur OpenTelemetry Neurons (voir [Endpoint du Collecteur](#endpoint)).
- Vous disposez du jeton Neurons (`NEURONES_TOKEN`) de l'environnement cible.
- Le nom de l'**application** et les noms des **services** ont été convenus (voir [Identité de l'application et des services](#identity)).
- L'environnement de déploiement est connu (par exemple `production`, `staging`).

{{< callout type="warn" >}}
**Les versions prises en charge doivent être confirmées avec la matrice de compatibilité Neurons actuelle.** Neurons ne publie pas encore de politique de support Java / Spring Boot. À titre indicatif, l'agent Java OpenTelemetry en amont prend en charge Java 8 et plus, et instrumente Spring Web MVC 3.1+, Spring WebFlux 5.3+, Spring Cloud Gateway 2.0+ et Logback 1.0+ (voir les [bibliothèques prises en charge](https://github.com/open-telemetry/opentelemetry-java-instrumentation/blob/main/docs/supported-libraries.md) en amont). La seule configuration Java validée de bout en bout avec Neurons est le déploiement de référence `springboot-ecommerce`.
{{< /callout >}}

## Installer l'agent Java OpenTelemetry {#install}

L'agent est un jar unique, `opentelemetry-javaagent.jar`, publié avec chaque version du projet OpenTelemetry Java instrumentation. Ce n'est **pas** une dépendance Maven/Gradle de l'application.

1. Télécharger une version fixée de l'agent depuis les releases officielles :

   ```text
   https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v<VERSION>/opentelemetry-javaagent.jar
   ```

2. Vérifier l'intégrité du fichier (par exemple avec une somme SHA-256 enregistrée pour cette version) avant de l'utiliser.
3. Le placer là où la JVM peut le lire, par exemple `/opt/otel/opentelemetry-javaagent.jar`.
4. Le charger avec l'option JVM :

   ```text
   -javaagent:/opt/otel/opentelemetry-javaagent.jar
   ```

   soit sur la ligne de commande `java`, soit via la variable d'environnement `JAVA_TOOL_OPTIONS`, que toute JVM lit au démarrage (pratique pour les conteneurs, dont la commande de démarrage est fixée par l'image).

L'agent crée automatiquement des spans pour les serveurs et clients HTTP (Spring MVC, WebFlux/Netty, Feign, WebClient, RestTemplate), JDBC/R2DBC, Kafka, RabbitMQ, Redis et d'autres, et place `trace_id` / `span_id` dans le MDC de logging.

{{< callout >}}
**Version de l'agent.** Neurons n'impose pas de version obligatoire de l'agent Java. Fixer une version explicite par application et la mettre à jour de façon délibérée. Au moment de la rédaction, la dernière version en amont est la v2.32.0 ; le déploiement de référence utilise la v2.31.1.
{{< /callout >}}

### Exemple de référence — image Docker avec vérification de la somme de contrôle

*Exemple utilisé par `springboot-ecommerce`.* Le `Dockerfile` racine contient une étape dédiée qui télécharge l'agent et vérifie sa somme de contrôle ; le jar est ensuite copié dans `/app/otel-javaagent.jar` dans chaque image de service :

```dockerfile
FROM curlimages/curl:8.11.0 AS otel-agent
ARG OTEL_JAVAAGENT_VERSION=2.31.1
ARG OTEL_JAVAAGENT_SHA256=bbf83c151b6400709e2f225bdd07a04f839d9d13b8b93464241333fd25d3e3ba
RUN curl -fsSL -o /otel-javaagent.jar ".../v${OTEL_JAVAAGENT_VERSION}/opentelemetry-javaagent.jar" \
 && echo "${OTEL_JAVAAGENT_SHA256}  /otel-javaagent.jar" | sha256sum -c -
```

L'agent n'est activé **que** par `JAVA_TOOL_OPTIONS` dans `docker-compose.yml` : la même image fonctionne donc sans l'agent lorsque cette variable n'est pas définie — pratique pour déboguer.

### Exemple de référence — utiliser l'API OpenTelemetry dans le code

Nécessaire uniquement lorsque l'application ajoute ses propres attributs de span. Dans le projet de référence, le filtre de capture du corps de la gateway appelle `Span.current().setAttribute(...)` : `infrastructure/api-gateway/pom.xml` déclare donc `io.opentelemetry:opentelemetry-api` (version 1.65.0 dans ce projet) en scope **`provided`**. Le jar n'embarque ainsi pas sa propre copie de l'API ; à l'exécution, ce sont les classes injectées par l'agent qui sont utilisées, ce qui évite un conflit de classloader. Les applications qui s'appuient uniquement sur l'instrumentation automatique n'ont besoin d'aucune dépendance OpenTelemetry.

## Configurer Neurons {#configure}

Tous les paramètres sont des variables d'environnement OpenTelemetry standard, lues par l'agent au démarrage :

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

| Variable | Rôle |
|---|---|
| JAVA_TOOL_OPTIONS | Charge l'agent (peut aussi porter d'autres options JVM). |
| OTEL_SERVICE_NAME | Le nom du service. Optionnel pour Spring Boot (voir [Identité du service](#identity)). |
| OTEL_TRACES_EXPORTER | `otlp` : export des traces en OTLP. |
| OTEL_EXPORTER_OTLP_PROTOCOL | `http/protobuf` : OTLP sur HTTP, encodage protobuf. |
| OTEL_EXPORTER_OTLP_TRACES_ENDPOINT | Endpoint traces du Collecteur. |
| OTEL_EXPORTER_OTLP_TRACES_HEADERS | En-tête `X-Neurones-Token` sur chaque export de traces. |
| OTEL_LOGS_EXPORTER | `otlp` pour exporter les logs, `none` pour les garder en local (voir [Logs](#logs)). |
| OTEL_EXPORTER_OTLP_LOGS_ENDPOINT | Endpoint logs du Collecteur. |
| OTEL_EXPORTER_OTLP_LOGS_HEADERS | En-tête `X-Neurones-Token` sur chaque export de logs. |
| OTEL_METRICS_EXPORTER | `none` dans la configuration Neurons actuelle (voir [Métriques](#metrics)). |
| OTEL_RESOURCE_ATTRIBUTES | Identité de l'application et de l'environnement (voir ci-dessous). |
{firstcol="30" mono="1"}

### Endpoint du Collecteur {#endpoint}

Utiliser l'URL et le transport du Collecteur définis par l'équipe plateforme Neurons pour l'environnement cible. La forme `http://<NEURONES_COLLECTOR_HOST>:4318` ci-dessus est l'endpoint OTLP en HTTP simple utilisé par le déploiement de référence. L'obligation éventuelle de HTTPS/TLS dépend de l'environnement et n'est pas définie par ce guide : lorsque l'équipe plateforme fournit un endpoint `https://`, l'utiliser tel quel.

Vérifier depuis l'hôte de l'application que le port du Collecteur est joignable avant de démarrer l'application :

```bash
nc -vz <NEURONES_COLLECTOR_HOST> 4318
```

```powershell
Test-NetConnection <NEURONES_COLLECTOR_HOST> -Port 4318
```

### Authentification {#auth}

Le jeton Neurons est envoyé dans l'en-tête `X-Neurones-Token` sur chaque export de traces et de logs, via `OTEL_EXPORTER_OTLP_TRACES_HEADERS` et `OTEL_EXPORTER_OTLP_LOGS_HEADERS`.

- Fournir la valeur par un mécanisme de secret — un fichier `.env` du serveur exclu du contrôle de version, un secret du conteneur/de l'orchestrateur, ou une configuration de service protégée. **Ne jamais le commiter** et ne jamais l'inclure dans une image.
- Dans le déploiement de référence, `NEURONES_TOKEN` est défini dans le fichier `.env` du serveur et référencé comme `X-Neurones-Token=${NEURONES_TOKEN:-}` dans `docker-compose.yml`.
- Lorsque le Collecteur exige le jeton, une valeur absente ou invalide fait échouer chaque export en **HTTP 401** : aucune trace ni aucun log n'arrive dans Neurons, tandis que l'application continue de fonctionner.

### Identité de l'application et des services {#identity}

Neurons regroupe la télémétrie sur deux niveaux, qui doivent tous deux être correctement définis :

```text
Application : springboot-ecommerce         ← attribut de ressource "application"
  Services :
  - api-gateway                            ← service.name
  - order-service                          ← service.name
  - payment-service                        ← service.name
```

| Clé | Rôle dans Neurons |
|---|---|
| application | **La clé de regroupement des applications Neurons.** Tous les services d'un même produit partagent la même valeur. |
| service.name | Un service individuel. Le définir avec `OTEL_SERVICE_NAME` ; pour Spring Boot, l'agent peut aussi le reprendre de `spring.application.name`. |
| deployment.environment | L'environnement (`production`, `staging`, ...). |
| service.namespace | Aide au regroupement OpenTelemetry, optionnelle ; utile pour distinguer deux applications sur le même hôte. |
| tenant | Optionnel, spécifique à Neurons. |
{firstcol="26" mono="1"}

{{< callout type="warn" >}}
La clé doit s'appeler exactement `application` — ni `application.name`, ni `service.name`, ni `service.namespace`. Une clé erronée ou absente ne provoque aucune erreur : les services atterrissent silencieusement sous **Unassigned**.
{{< /callout >}}

**Exemple de référence.** Dans `springboot-ecommerce`, `OTEL_SERVICE_NAME` n'est pas défini : chaque service définit déjà `spring.application.name` (`api-gateway`, `order-service`, ...), qui devient son nom de service. Les attributs de ressource sont :

```text
service.namespace=ecommercespring
deployment.environment=production
tenant=default
application=springboot-ecommerce
```

Si le frontend est aussi instrumenté avec le RUM navigateur, utiliser les mêmes valeurs `application`, `deployment.environment`, `service.namespace` et `tenant` côté RUM.

### Environnement {#environment}

Définir `deployment.environment` dans `OTEL_RESOURCE_ATTRIBUTES`. Utiliser `deployment.environment`, et non le plus récent `deployment.environment.name` : Neurons lit actuellement `deployment.environment`.

### Métriques {#metrics}

La configuration Neurons actuelle définit `OTEL_METRICS_EXPORTER=none` : Neurons calcule les métriques de service (débit, erreurs, durée) à partir des traces, et le service d'ingestion ne stocke pas actuellement les métriques OTLP. Les métriques applicatives et JVM restent sur l'outillage propre de l'application — dans le déploiement de référence, Micrometer / Prometheus. Cela reflète la configuration Neurons actuelle, pas une limite de l'agent Java.

## Démarrer ou redémarrer l'application {#start}

L'agent et les variables ne prennent effet qu'au démarrage de la JVM. Redémarrer l'application après toute modification.

| Mode d'exécution | Où définir l'agent et les variables |
|---|---|
| Démarrage JVM direct | `java -javaagent:/opt/otel/opentelemetry-javaagent.jar -jar app.jar`, avec les variables `OTEL_*` dans l'environnement du processus. |
| Docker | `JAVA_TOOL_OPTIONS` et `OTEL_*` comme variables d'environnement du conteneur ; le jar dans l'image ou un volume monté. |
| Docker Compose | Le bloc `environment:` du service — ou une ancre YAML partagée, comme dans l'exemple de référence ci-dessous. |
| Kubernetes | Variables d'environnement du conteneur dans la spec du pod, avec le jeton issu d'un Secret. |
| systemd | Entrées `Environment=` / `EnvironmentFile=` de l'unité, puis redémarrage de l'unité. |
{firstcol="26"}

**Exemple de référence — Docker Compose.** Dans `springboot-ecommerce`, les variables sont définies une seule fois dans l'ancre `x-spring-app-defaults` → `environment` de `docker-compose.yml` et héritées par chaque service instrumenté :

| Variable | Valeur dans le déploiement de référence |
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
| OTEL_RESOURCE_ATTRIBUTES | voir [Identité de l'application et des services](#identity) |
{firstcol="30" mono="1"}

Les surcharges propres à un serveur vont dans `docker-compose.override.yml`. Un bloc de service y ne remplace rien de l'ancre : Compose fusionne les maps `environment`, donc les réglages d'export restent en place. Appliquer les changements avec `docker compose up -d <service>`.

## Vérifier dans Neurons {#verify}

1. **Confirmer que l'agent est chargé** — la sortie de la JVM contient une ligne du type `OpenTelemetry Javaagent ... started`.
2. **Générer du trafic réel** — appeler un endpoint qui accède aussi à une base de données et, si possible, à un autre service.
3. **L'application apparaît** dans la liste Applications sous son nom `application`.
4. **Les services apparaissent** sous cette application, chacun avec son nom de service et un `last_seen` récent.
5. **La trace atteint les services en aval** — une requête montre tous les services instrumentés traversés dans une seule trace.
6. **Les spans de base de données** apparaissent pour les requêtes qui interrogent une base, le cas échéant.
7. **Les logs** apparaissent dans l'écran Logs, corrélés aux traces, si l'export des logs est activé.
8. **Rien n'est regroupé sous Unassigned.**

{{< callout >}}
Un onboarding n'est pas terminé tant qu'il n'a pas été validé sur l'environnement déployé, et pas seulement en local.
{{< /callout >}}

**Exemple de référence — commandes `springboot-ecommerce` :**

```bash
# Agent chargé
docker compose logs api-gateway | grep -i "opentelemetry javaagent"
# attendu : "OpenTelemetry Javaagent ... started"

# Identifiants de trace présents dans les logs du service
docker compose logs api-gateway --tail=20 | grep trace_id
```

Pour voir exactement les attributs d'un span (en-têtes, corps) sans ouvrir Neurons, ajouter temporairement l'exportateur `logging` dans `docker-compose.override.yml`, envoyer une requête, puis lire la sortie du conteneur :

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

Retirer `logging` ensuite : il affiche chaque span.

## Avancé — Capture des en-têtes HTTP {#headers}

Non requise pour l'onboarding. La capture des en-têtes est **optionnelle (opt-in)** : rien n'est capturé tant que vous ne listez pas les en-têtes à enregistrer, avec les variables standard de l'agent. Aucun code n'est nécessaire ; définir la variable sur les services concernés et les redémarrer.

| Variable | Capture | Attribut de span obtenu |
|---|---|---|
| OTEL_INSTRUMENTATION_HTTP_SERVER_CAPTURE_REQUEST_HEADERS | En-têtes des requêtes entrantes | `http.request.header.<nom>` sur le span SERVER |
| OTEL_INSTRUMENTATION_HTTP_SERVER_CAPTURE_RESPONSE_HEADERS | En-têtes des réponses renvoyées par ce service | `http.response.header.<nom>` sur le span SERVER |
| OTEL_INSTRUMENTATION_HTTP_CLIENT_CAPTURE_REQUEST_HEADERS | En-têtes envoyés par ce service à d'autres services (Feign, WebClient, RestTemplate) | `http.request.header.<nom>` sur le span CLIENT |
| OTEL_INSTRUMENTATION_HTTP_CLIENT_CAPTURE_RESPONSE_HEADERS | En-têtes des réponses à ces appels | `http.response.header.<nom>` sur le span CLIENT |
{mono="1"}

Chaque valeur est une liste de noms d'en-têtes séparés par des virgules, insensible à la casse. Le nom de l'attribut utilise le nom de l'en-tête en minuscules ; la valeur est un tableau de chaînes.

{{< callout type="warn" >}}
**L'ordre des mots compte.** La forme correcte est `HTTP_<SERVER|CLIENT>_CAPTURE_<REQUEST|RESPONSE>_HEADERS`. Un nom dans un autre ordre, comme `HTTP_CAPTURE_HEADERS_SERVER_REQUEST`, est ignoré silencieusement : rien n'est capturé et aucune erreur n'apparaît. Référence : `opentelemetry.io/docs/zero-code/java/agent/instrumentation/http/`.
{{< /callout >}}

{{< callout type="warn" >}}
**Ne jamais capturer `Authorization`, `Cookie`, `Set-Cookie` ni aucun en-tête portant un secret de session ou d'authentification.** L'agent enregistre la valeur brute sans masquage : un jeton bearer serait stocké en clair dans Neurons.
{{< /callout >}}

**Exemple de référence — `springboot-ecommerce`** (dans `docker-compose.override.yml` sur le serveur ; la capture des en-têtes n'est pas dans le `docker-compose.yml` commité) :

```yaml
services:
  api-gateway:
    environment:
      OTEL_INSTRUMENTATION_HTTP_SERVER_CAPTURE_REQUEST_HEADERS: "Referer,X-Correlation-Id,Idempotency-Key,User-Agent"
      OTEL_INSTRUMENTATION_HTTP_SERVER_CAPTURE_RESPONSE_HEADERS: "X-Correlation-Id,Content-Type"
  order-service:
    environment:
      # appels vers les services cart/inventory/payment
      OTEL_INSTRUMENTATION_HTTP_CLIENT_CAPTURE_REQUEST_HEADERS: "X-User-Id,X-User-Role,X-Correlation-Id"
      OTEL_INSTRUMENTATION_HTTP_CLIENT_CAPTURE_RESPONSE_HEADERS: "Content-Type"
```

| En-tête | Où il apparaît | Pourquoi c'est utile |
|---|---|---|
| X-Correlation-Id | Requête/réponse de la gateway | Relie une trace à une recherche dans les logs |
| Idempotency-Key | `POST /api/orders` | Explique les commandes en double |
| X-User-Id, X-User-Role | Ajoutés par la gateway après validation du JWT, transmis en aval | Qui a fait l'appel, sur les spans en aval |
| Referer, User-Agent | Requête de la gateway | Quelle page ou quel client a déclenché l'appel |
{mono="1"}

## Avancé — Capture du corps HTTP {#body-capture}

**L'agent Java OpenTelemetry ne capture jamais les corps des requêtes ou des réponses.** La capture du corps ne fait pas partie de l'onboarding Java standard et n'est pas une fonctionnalité Java générique de Neurons : une application qui en a besoin nécessite son propre middleware ou sa propre instrumentation approuvés, qui ajoutent le corps au span actif.

{{< callout type="warn" >}}
Les corps des requêtes et des réponses peuvent contenir des identifiants, des jetons, des données personnelles et des données de paiement ou client. En production, la capture du corps doit être **optionnelle (opt-in)** : désactivée par défaut, limitée à des routes explicitement approuvées, de taille limitée, et revue sous l'angle de la confidentialité avant d'être activée.
{{< /callout >}}

### Implémentation de référence : API Gateway de springboot-ecommerce

Dans le projet de référence, la capture du corps est du code personnalisé implémenté **uniquement dans `api-gateway`**, car tout le trafic externe y passe :

- `infrastructure/api-gateway/src/main/java/com/backendguru/apigateway/telemetry/GatewayTelemetryProperties.java`
- `infrastructure/api-gateway/src/main/java/com/backendguru/apigateway/telemetry/BodyCaptureWebFilter.java`

Configuration, dans `infrastructure/config-server/src/main/resources/configs/api-gateway.yml` :

```yaml
gateway:
  telemetry:
    capture:
      request-body-enabled: ${GATEWAY_CAPTURE_REQUEST_BODY:true}
      response-body-enabled: ${GATEWAY_CAPTURE_RESPONSE_BODY:true}
      max-body-bytes: ${GATEWAY_CAPTURE_MAX_BODY_BYTES:4096}
      exclude-path-prefixes: ${GATEWAY_CAPTURE_EXCLUDE_PATHS:/api/auth,/sse}
```

| Variable | Défaut dans le projet de référence | Effet |
|---|---|---|
| GATEWAY_CAPTURE_REQUEST_BODY | `true` | Attache le corps de la requête en `http.request.body` |
| GATEWAY_CAPTURE_RESPONSE_BODY | `true` | Attache le corps de la réponse en `http.response.body` |
| GATEWAY_CAPTURE_MAX_BODY_BYTES | `4096` | Corps tronqué à ce nombre d'octets |
| GATEWAY_CAPTURE_EXCLUDE_PATHS | `/api/auth,/sse` | Préfixes de chemin jamais capturés |
{mono="1"}

{{< callout type="warn" >}}
**Les valeurs par défaut de référence ne sont pas une recommandation Neurons.** Le record Java `GatewayTelemetryProperties` déclare `@DefaultValue("false")`, mais cela ne s'applique que si la propriété est absente : le YAML servi par config-server définit `true`, la capture est donc effectivement **activée** dans le déploiement de référence. Pour une application de production, commencer avec les deux interrupteurs à `false` et ne les activer qu'après revue.
{{< /callout >}}

Comportement du filtre de référence :

- S'exécute à l'ordre `HIGHEST_PRECEDENCE + 5` : après le filtre de correlation-id et **avant l'authentification JWT** — les corps sont capturés même pour les requêtes qui finissent en 401.
- Ne capture que `application/json`, `text/plain` et `application/x-www-form-urlencoded` ; le contenu binaire n'est jamais capturé.
- `/api/auth/**` (login, inscription, refresh : mots de passe et jetons) et `/sse` (flux de longue durée) sont exclus par défaut.
- Côté requête : utilise `ServerWebExchangeUtils.cacheRequestBody` de Spring Cloud Gateway, pour ne pas consommer le corps deux fois.
- Côté réponse : un `ServerHttpResponseDecorator` lit chaque buffer avec `doOnNext` sans le modifier ; les octets envoyés au client sont identiques, capture activée ou non.
- Avec les deux interrupteurs à `false`, le filtre ne fait rien.

Pour le modifier : définir les variables sur `api-gateway` dans `docker-compose.override.yml` puis exécuter `docker compose up -d api-gateway` (surcharge temporaire). Pour changer le défaut commité dans `api-gateway.yml`, empaqueté dans le jar de `config-server`, exécuter `docker compose up -d --build config-server`, puis redémarrer `api-gateway`.

## Logs et corrélation avec les traces {#logs}

Deux mécanismes indépendants relient logs et traces.

**1. Corrélation trace ↔ log dans les logs propres de l'application.** L'instrumentation MDC Logback de l'agent place `trace_id` et `span_id` dans le MDC de chaque instruction de log exécutée dans une requête tracée. Pour les voir dans la sortie de logs de l'application, le format de log doit les inclure :

- un pattern texte comme `[%X{trace_id:-}]` ;
- pour un encodeur JSON qui liste explicitement les clés MDC, ajouter `trace_id` et `span_id` à la liste.

Utiliser les clés snake_case `trace_id` / `span_id` posées par l'agent, et non la clé camelCase `traceId`.

**2. Export des logs vers Neurons (OTLP).** L'instrumentation appender Logback de l'agent transforme chaque ligne de log en enregistrement de log OpenTelemetry. Avec `OTEL_LOGS_EXPORTER=otlp`, ces enregistrements sont envoyés à l'endpoint `/v1/logs` du Collecteur et apparaissent dans Neurons ; avec `none`, ils restent en local.

- C'est une sortie **supplémentaire** : les appenders console et fichier continuent de fonctionner comme avant.
- `trace_id` / `span_id` font partie de chaque enregistrement de log exporté, pris dans le span actif — ils ne dépendent pas de la configuration du MDC.
- Les clés MDC personnalisées (par exemple `userId`) ne sont **pas** exportées, sauf si elles sont listées dans `OTEL_INSTRUMENTATION_LOGBACK_APPENDER_EXPERIMENTAL_MDC_ATTRIBUTES_INCLUDED`.

**Exemple de référence — `springboot-ecommerce`.** Les services ayant un `logback-spring.xml` personnalisé (LogstashEncoder dans les profils `docker`/`prod`) n'écrivent que les clés MDC qu'ils listent ; ils incluent donc :

```xml
<includeMdcKeyName>trace_id</includeMdcKeyName>
<includeMdcKeyName>span_id</includeMdcKeyName>
<includeMdcKeyName>userId</includeMdcKeyName>
```

Le pattern texte du profil `dev` utilise `[%X{trace_id:-}]`. `userId` n'est pas exporté vers Neurons (la variable MDC expérimentale ci-dessus n'est pas activée).

## Contrôles opérationnels {#controls}

| Besoin | Comment |
|---|---|
| Désactiver l'agent sur un service sans rebuild | `OTEL_JAVAAGENT_ENABLED=false`, puis redémarrer |
| Désactiver une instrumentation (pour réduire la charge ou le bruit) | `OTEL_INSTRUMENTATION_<NAME>_ENABLED=false`, par ex. `OTEL_INSTRUMENTATION_JDBC_ENABLED=false` |
| Arrêter uniquement l'envoi des logs | `OTEL_LOGS_EXPORTER=none` |
| Afficher spans / logs dans la sortie de l'application pour déboguer | `OTEL_TRACES_EXPORTER=otlp,logging` / `OTEL_LOGS_EXPORTER=otlp,logging` — à retirer ensuite |
| Sortie de débogage de l'agent | `OTEL_JAVAAGENT_DEBUG=true` |
{firstcol="30"}

**Mémoire et CPU.** L'agent ajoute une charge mémoire et un temps de démarrage qui dépendent de la charge de travail et des instrumentations utilisées. La mesurer sur votre propre charge et dimensionner la mémoire de la JVM et du conteneur avec une marge suffisante.

*Observé dans le déploiement de référence :* environ 50–150 Mo de RSS supplémentaire par JVM, avec `mem_limit` réglé à environ 500 Mo par service (550 Mo pour `api-gateway`) dans `docker-compose.override.yml`. Ces chiffres ne valent qu'à titre indicatif pour ce déploiement.

## Dépannage {#troubleshooting}

| Symptôme | Cause probable | Action |
|---|---|---|
| Agent Java non chargé (pas de ligne « OpenTelemetry Javaagent ... started ») | `-javaagent` non appliqué au processus réel, ou chemin du jar erroné | Vérifier la commande de démarrage réelle / `JAVA_TOOL_OPTIONS` du processus en cours et le chemin du jar. |
| Aucun span | Agent non chargé, `OTEL_JAVAAGENT_ENABLED=false`, ou `OTEL_TRACES_EXPORTER` différent de `otlp` | Vérifier la ligne de démarrage de l'agent et les variables effectives ; redémarrer après modification. |
| Collecteur injoignable (délais ou connexions refusées dans les logs) | Pare-feu, hôte ou port erroné, ou Collecteur arrêté | Lancer la [vérification de connectivité](#endpoint) ; confirmer l'endpoint avec l'équipe plateforme. |
| Erreurs d'export 401 | `NEURONES_TOKEN` absent ou invalide | Vérifier que le jeton est défini et transmis dans `X-Neurones-Token` pour les traces et les logs (voir [Authentification](#auth)). |
| L'application n'apparaît pas dans Neurons | Aucune télémétrie exportée, ou pas de trafic récent | Parcourir les lignes ci-dessus, puis générer du trafic réel et élargir la fenêtre de temps. |
| Services listés sous **Unassigned** | Attribut `application` absent ou mal orthographié | Vérifier `OTEL_RESOURCE_ATTRIBUTES` (voir [Identité de l'application et des services](#identity)). |
| Logs absents | `OTEL_LOGS_EXPORTER` à `none`, endpoint/en-tête des logs absent, ou framework de logs non instrumenté | Vérifier les trois variables de logs ; pour un framework de logs autre que Logback, consulter les bibliothèques prises en charge en amont. |
| Spans de base de données absents | Accès à la base ne passant pas par un client instrumenté (JDBC/R2DBC), ou instrumentation désactivée | Vérifier le pilote et toute variable `OTEL_INSTRUMENTATION_*_ENABLED=false`. |
| Traces en aval déconnectées | Un service de la chaîne n'est pas instrumenté, ou un proxy / client personnalisé supprime l'en-tête `traceparent` | Instrumenter chaque service de la chaîne d'appels ; s'assurer que les intermédiaires transmettent `traceparent`. |
| Consommation mémoire ou CPU élevée | Charge de l'agent non prise en compte dans le dimensionnement | Augmenter la marge mémoire ; désactiver les instrumentations inutiles ; mesurer à nouveau. |
| La variable de capture des en-têtes n'a aucun effet | Mots du nom de variable dans le mauvais ordre | Utiliser `HTTP_<SERVER\|CLIENT>_CAPTURE_<REQUEST\|RESPONSE>_HEADERS`. |

## Désactivation / retour arrière {#rollback}

**Procédure générique :**

1. Choisir la portée :
   - **Tout arrêter :** définir `OTEL_JAVAAGENT_ENABLED=false`, ou retirer `-javaagent` de la commande de démarrage / de `JAVA_TOOL_OPTIONS`.
   - **Garder l'agent mais arrêter l'export :** définir `OTEL_TRACES_EXPORTER=none` et `OTEL_LOGS_EXPORTER=none`.
2. Redémarrer la JVM / le conteneur pour appliquer le changement.
3. Vérifier que la télémétrie s'est arrêtée : le `last_seen` des services dans Neurons n'avance plus après la fenêtre d'observation prévue, et l'application continue de fonctionner normalement.

Pour réactiver, restaurer les valeurs précédentes et redémarrer.

**Exemple de référence — `springboot-ecommerce` :** ajouter `OTEL_JAVAAGENT_ENABLED: "false"` au service dans `docker-compose.override.yml`, puis `docker compose up -d <service>`. Comme l'agent n'est activé que via `JAVA_TOOL_OPTIONS`, retirer cette variable fait aussi tourner la même image sans l'agent.

## Definition of Done {#done}

L'onboarding n'est terminé que lorsque :

- les versions Java / Spring Boot utilisées ont été confirmées avec la matrice de compatibilité Neurons
- l'agent est une version fixée, à l'intégrité vérifiée, et chargé par le processus réel (ligne de démarrage présente)
- l'endpoint et le transport du Collecteur ont été fournis par l'équipe plateforme et sont joignables
- `NEURONES_TOKEN` provient d'un mécanisme de secret et n'est commité nulle part
- `application`, les noms des services et `deployment.environment` sont définis comme convenu
- du trafic réel produit des traces dans Neurons, avec les services en aval dans la même trace
- les spans de base de données sont visibles le cas échéant
- les logs sont visibles et corrélés, si l'export des logs est activé
- rien n'est regroupé sous **Unassigned**
- la capture des en-têtes est désactivée ou limitée à une liste approuvée sans `Authorization` / `Cookie`
- la capture du corps est désactivée, ou explicitement approuvée et revue
- la procédure de retour arrière a été testée
- la validation est effectuée sur l'environnement déployé
