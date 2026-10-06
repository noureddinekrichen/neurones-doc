---
title: Onboarding du RUM navigateur
linkTitle: RUM navigateur
lede: Instrumenter un frontend web avec l'instrumentation navigateur OpenTelemetry pour que Neurons montre ce que vivent les utilisateurs réels — vues de page, Web Vitals, erreurs frontend, sessions, signaux de frustration, et les traces backend derrière chaque page.
menus:
  onboarding:
    parent: application-onboarding
    weight: 2
labels:
  add-sdk: Ajouter l'instrumentation navigateur
  implement: Implémenter la télémétrie navigateur
  telemetry: Télémétrie navigateur
  configure: Configurer Neurons
  replay: Session replay
  identity: Identité de l'application et du frontend
  test-traffic: Générer du trafic de test
  verify: Vérifier dans Neurons
  security: Sécurité et confidentialité
  rollback: Désactivation / retour arrière
---

## Présentation {#overview}

Le Real User Monitoring (RUM) navigateur mesure ce que les utilisateurs vivent réellement dans leur navigateur. L'instrumentation backend répond à *« que s'est-il passé dans l'application ? »* ; le RUM répond à *« qu'a vu l'utilisateur ? »*. Dans Neurons, la télémétrie navigateur apparaît dans l'écran **Browser Performance** :

| Télémétrie | Ce qu'elle indique |
|---|---|
| Vues de page | Quelles pages sont visitées et combien de temps elles mettent à se charger — pour les chargements complets et pour les changements de route des applications monopages (SPA), avec la décomposition du chargement (réseau, serveur, rendu). |
| Web Vitals | Les indicateurs standards de performance perçue — LCP, INP, CLS, FCP et TTFB — avec percentiles, évaluation bon / à améliorer / mauvais, et un score Apdex. |
| Erreurs frontend | Les erreurs JavaScript survenues dans le navigateur des utilisateurs, regroupées par message. |
| Sessions | La visite de chaque utilisateur sous forme de parcours chronologique entre les pages, et les enchaînements de pages les plus fréquents. |
| Actions utilisateur et signaux de frustration | Clics rageurs, clics morts et clics en erreur — signes d'une expérience dégradée même sans erreur technique visible. |
| Navigateur, appareil et localisation | Répartitions par navigateur, système d'exploitation, type d'appareil et pays. |
| Corrélation avec le backend | Pour chaque page, les transactions métier backend qu'elle déclenche, et pour chaque trace, les spans navigateur et backend ensemble. |
{firstcol="26"}

Le RUM est **indépendant de l'onboarding backend** : une application peut avoir le traçage backend sans RUM, ou les deux. Activer ou désactiver le RUM ne modifie jamais la configuration backend. La corrélation avec les traces backend nécessite que le backend soit aussi instrumenté — voir les guides [PHP](../php/), [Java](../java/), [.NET](../dotnet/) et [Python](../python/).

## Architecture {#architecture}

{{< flow label="Comment la télémétrie navigateur arrive dans Neurons" >}}
app | Navigateur | Le navigateur de l'utilisateur charge votre application web
→
app | Instrumentation navigateur OpenTelemetry | S'exécute dans la page : enregistre vues de page, Web Vitals, erreurs, appels API et actions utilisateur
→ OTLP sur HTTP (JSON), même origine
app | Endpoint d'ingestion RUM | Une route de votre serveur web ou reverse proxy qui ajoute le jeton Neurons et l'adresse IP du visiteur
→ OTLP sur HTTP (JSON) + `X-Neurones-Token`
platform | Neurons | Le service d'ingestion reconnaît la télémétrie navigateur, résout la géolocalisation et l'enregistre
→
platform | Browser Performance / RUM | Chargements de page, Web Vitals, erreurs, sessions, frustration, traces frontend ↔ backend
{{< /flow >}}

- L'instrumentation navigateur exporte en **OTLP/HTTP JSON**, que le service d'ingestion Neurons accepte directement : contrairement aux agents backend, la télémétrie navigateur n'a pas besoin de passer par le Collecteur OpenTelemetry.
- L'**endpoint d'ingestion RUM** est ce qu'appelle le navigateur. Il garde le jeton Neurons hors du navigateur et transmet l'adresse IP du visiteur — voir [Configurer Neurons](#configure).
- **Corrélation des traces :** l'instrumentation navigateur ajoute l'en-tête W3C `traceparent` aux appels API de l'application : une action utilisateur et le travail backend qu'elle déclenche sont enregistrés dans la même trace distribuée.

## Prérequis {#prerequisites}

- Un frontend web dont vous pouvez modifier, reconstruire et redéployer le point d'entrée JavaScript.
- Un serveur web ou reverse proxy **sur la même origine** que le frontend, capable de relayer des requêtes et d'ajouter un en-tête (nginx, Apache, IIS, une API gateway ou une route backend).
- Le jeton d'ingestion Neurons, fourni par l'équipe plateforme Neurons et détenu **uniquement côté serveur** — ainsi que le jeton de requêtage si le session replay est dans le périmètre.
- L'URL du service d'ingestion Neurons pour l'environnement cible.
- Le nom `application`, le `service.name` du frontend et l'environnement de déploiement, convenus avec les services backend (voir [Identité de l'application et du frontend](#identity)).
- Une décision explicite sur les fonctionnalités optionnelles : session replay, identification des utilisateurs, export des logs navigateur.

## Ajouter l'instrumentation navigateur {#add-sdk}

### Installer les paquets

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

| Paquet | Rôle |
|---|---|
| @opentelemetry/sdk-trace-web, sdk-trace-base | Fournisseur de traceurs et processeur de spans par lots |
| @opentelemetry/resources, semantic-conventions | Attributs de ressource (`service.name`, `application`, ...) |
| @opentelemetry/context-zone | Conserve le span actif à travers les callbacks asynchrones |
| @opentelemetry/instrumentation-fetch | Un span par appel `fetch`, et injection de `traceparent` |
| @opentelemetry/instrumentation-xml-http-request | La même chose pour `XMLHttpRequest` — à ajouter si l'application utilise XHR |
| @opentelemetry/instrumentation-document-load | Spans du chargement initial de la page, avec les timings de navigation |
| @opentelemetry/exporter-trace-otlp-http | Envoie les spans en OTLP/HTTP JSON |
| web-vitals | Mesure LCP, INP, CLS, FCP et TTFB |
{firstcol="30" mono="1"}

### Initialiser l'instrumentation navigateur

1. **Initialiser en premier.** Importer la configuration RUM dès la première ligne du point d'entrée de l'application, pour que l'instrumentation soit active avant le premier appel réseau.
2. **Enregistrer le gestionnaire de contexte.** Passer `ZoneContextManager` à `provider.register()` — installer `@opentelemetry/context-zone` seul ne fait rien.
3. **Exclure les endpoints de télémétrie** de l'instrumentation Fetch/XHR, pour que les envois de télémétrie ne créent pas leurs propres spans.
4. **Ne jamais casser la page.** Encapsuler l'initialisation — idéalement chaque fonctionnalité — dans son propre `try/catch`, et protéger `crypto.randomUUID()`, indisponible dans un contexte non sécurisé (HTTP). Un RUM en échec doit laisser l'application fonctionner.
5. **Un seul interrupteur.** Faire dépendre le RUM d'un seul réglage de build, pour pouvoir le désactiver par une reconstruction.
6. **Propager le contexte de trace.** Les appels API de même origine reçoivent `traceparent` automatiquement. Pour une API sur une autre origine, la lister dans l'option `propagateTraceHeaderCorsUrls` de l'instrumentation Fetch et autoriser l'en-tête `traceparent` dans la configuration CORS de cette API.

Initialisation minimale, à adapter à votre outil de build et à votre framework :

```js
// rum.js — importé dès la première ligne du point d'entrée de l'application
import { WebTracerProvider } from '@opentelemetry/sdk-trace-web';
import { BatchSpanProcessor } from '@opentelemetry/sdk-trace-base';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { resourceFromAttributes } from '@opentelemetry/resources';
import { ZoneContextManager } from '@opentelemetry/context-zone';
import { registerInstrumentations } from '@opentelemetry/instrumentation';
import { FetchInstrumentation } from '@opentelemetry/instrumentation-fetch';
import { DocumentLoadInstrumentation } from '@opentelemetry/instrumentation-document-load';

const RUM_ENDPOINT = '/v1/traces'; // endpoint d'ingestion RUM de même origine ; vide = RUM désactivé

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
    // le RUM ne doit jamais casser l'application
  }
}
```

## Implémenter la télémétrie navigateur Neurons {#implement}

{{< callout type="warn" >}}
**L'initialisation ci-dessus ne suffit pas à alimenter Browser Performance.** Le SDK Web OpenTelemetry standard crée des spans génériques (chargement du document, appels `fetch`). Il ne crée pas la télémétrie navigateur propre à Neurons décrite dans la section suivante. Neurons ne fournit pas actuellement de bibliothèque navigateur officielle : ces signaux doivent aujourd'hui être implémentés par l'application intégrée, en suivant le contrat ci-dessous.
{{< /callout >}}

L'application doit implémenter :

| Signal | À implémenter |
|---|---|
| Vues de page complètes | Transformer le chargement initial de la page en span `page-view` avec `nav.type=hard` et les timings de chargement. |
| Vues de page SPA | Créer un nouveau span `page-view` avec `nav.type=soft` à chaque changement de route côté client, et le garder actif pendant le démarrage des appels API de la route. |
| Web Vitals | Transformer chaque mesure `web-vitals` en span `web-vital` avec son nom, sa valeur et son évaluation. |
| Sessions | Générer un `session.id` et le poser sur chaque span. |
| Erreurs navigateur | Intercepter les erreurs JavaScript et les rejets de promesse non gérés, et les enregistrer en spans avec `rum.kind=app-error` (ou en enregistrements de log). |
| Classification des appels API | Marquer les spans `fetch`/XHR des API de l'application avec `api.kind`, et définir une `api.route` normalisée. |
| Signaux de frustration | Détecter les clics rageurs, morts et en erreur et les enregistrer en spans avec `frustration.type`. |
{firstcol="26"}

## Télémétrie navigateur attendue par Neurons {#telemetry}

Neurons alimente les écrans Browser Performance à partir de noms de spans et d'attributs précis. Un nom erroné n'est pas rejeté — les données manquent simplement dans les écrans.

### Vues de page

| Élément | Contrat |
|---|---|
| Nom du span | `page-view` (exact) |
| nav.type | `hard` pour un chargement complet, `soft` pour un changement de route SPA |
| Page | `page.path`, `page.url` |
| Timings | Attributs `pl.*` — voir [Timings de chargement](#page-load-timings) |
{firstcol="26" mono="1"}

- Pour une SPA, un nouveau span `page-view` doit être créé à **chaque changement de route**, avec `nav.type=soft`, `pl.render_ms` (temps jusqu'au rendu suivant) et `pl.soft_ms`.
- **Route API total, Route backend total et Data wait** sont calculés en joignant un `page-view` soft avec les appels API navigateur **de la même trace**. Le span page-view soft doit donc être actif — ou un ancêtre — lorsque les appels API de la route démarrent ; les appels API démarrés en dehors ne sont pas comptés pour cette route.
- **Data wait** utilise `pl.data_wait_ms` ou `route.data_wait_ms` s'ils sont présents, et à défaut `pl.backend_ms`.
- Lorsque `pl.total_ms` est absent, la durée du span est utilisée.
- Les étapes de Business Journey de type `rum_page` sont comptées à partir des spans `page-view` et de leur `page.path` — voir [Business Journeys](../../#bj).

### Timings de chargement {#page-load-timings}

Toutes les valeurs sont en millisecondes.

| Attribut | Signification |
|---|---|
| pl.total_ms | Temps total de chargement de la page |
| pl.backend_ms, pl.frontend_ms | Part serveur et part navigateur du chargement (`pl.frontend_ms` est déduit comme total − backend s'il est absent) |
| pl.ttfb_ms, pl.first_byte_ms | Temps jusqu'au premier octet (`pl.first_byte_ms` reprend `pl.ttfb_ms` par défaut) |
| pl.dns_ms, pl.tcp_ms, pl.tls_ms | Résolution DNS, connexion TCP, négociation TLS |
| pl.request_ms, pl.response_download_ms | Attente de la requête, téléchargement de la réponse |
| pl.dom_interactive_ms, pl.dom_content_loaded_ms, pl.dom_complete_ms | Étapes du DOM |
| pl.dom_processing_ms | Traitement du DOM (`domComplete − responseEnd` s'il est absent) |
| pl.load_event_ms | Durée du gestionnaire de l'événement `load` |
| pl.render_ms | Temps jusqu'au rendu (`view.render_ms` est aussi accepté) |
| pl.soft_ms | Durée d'un changement de route SPA |
| pl.data_wait_ms, route.data_wait_ms | Optionnels : temps d'attente des données d'une route SPA |
{firstcol="30" mono="1"}

Au lieu de valeurs `pl.*` calculées, un span `page-view` complet peut porter les champs bruts **Navigation Timing** du navigateur ; Neurons en déduit les timings lorsque l'attribut `pl.*` correspondant est absent :

| Champs bruts (aussi acceptés avec le préfixe `navigation.`) | Timing déduit |
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

### Web Vitals et Apdex

| Élément | Contrat |
|---|---|
| Nom du span | `web-vital` (exact) |
| wv.name | `LCP`, `INP`, `CLS`, `FCP` ou `TTFB` |
| wv.value | LCP, INP, FCP, TTFB en **millisecondes** ; CLS en **score sans unité** |
| wv.rating | Exactement `good`, `needs-improvement` ou `poor` — les valeurs émises par la bibliothèque `web-vitals` |
{firstcol="26" mono="1"}

{{< callout type="warn" >}}
Sans `wv.rating`, les valeurs des Web Vitals restent affichées, mais les répartitions bon / à améliorer / mauvais restent vides et l'**Apdex** de Browser Performance n'est pas calculé.
{{< /callout >}}

L'**Apdex** de Browser Performance est calculé à partir des évaluations de **LCP, INP et CLS** uniquement :

```text
Apdex = (good + 0,5 × needs-improvement) / total
```

FCP et TTFB sont affichés comme Web Vitals mais ne contribuent pas à l'Apdex. Seuils affichés par Neurons :

| Indicateur | Bon | À améliorer | Mauvais | Dans l'Apdex |
|---|---|---|---|---|
| LCP | ≤ 2500 ms | ≤ 4000 ms | > 4000 ms | Oui |
| INP | ≤ 200 ms | ≤ 500 ms | > 500 ms | Oui |
| CLS | ≤ 0,1 | ≤ 0,25 | > 0,25 | Oui |
| FCP | ≤ 1800 ms | ≤ 3000 ms | > 3000 ms | Non |
| TTFB | ≤ 800 ms | ≤ 1800 ms | > 1800 ms | Non |
{mono="1"}

### Appels API

- Seuls les spans **CLIENT** (les spans `fetch`/XHR) comptent comme appels API navigateur.
- Un span CLIENT est classé comme **appel API** lorsqu'il porte `api.kind` (ou un `rum.kind=api-call` explicite).
- Un span CLIENT avec une URL ou une route mais sans classification API est traité comme un **appel de ressource**.
- La route affichée est résolue à partir de `api.route`, puis `url.path`, puis `http.route`, puis `http.target`. Définir une `api.route` normalisée (identifiants remplacés, ex. `/api/orders/:id`) pour que les appels se regroupent correctement.

### Erreurs navigateur

Un span navigateur est compté comme erreur JavaScript **uniquement lorsqu'il porte `rum.kind=app-error`** :

- le nom de span `app.error` seul ne **suffit pas** ;
- un statut de span ERROR seul ne **suffit pas** ;
- les attributs `exception.*` ne sont **pas** utilisés pour les erreurs navigateur.

| Attribut | Contenu |
|---|---|
| rum.kind | `app-error` (requis) |
| error.type | Type d'erreur, ex. `TypeError` |
| error.message | Message d'erreur — s'il est absent, le nom du span sert de message |
| error.stack | Pile d'appels |
| page.path | Page où l'erreur s'est produite |
{firstcol="26" mono="1"}

Les erreurs peuvent aussi être envoyées en **enregistrements de log OTLP** : un enregistrement de log est compté comme erreur navigateur lorsqu'il porte `rum.kind=js-error` ou `rum.kind=app-error`, avec les mêmes attributs `error.*`. Cela nécessite une route de relais `/v1/logs` — voir [Configurer Neurons](#configure).

### Signaux de frustration

| Attribut | Contenu |
|---|---|
| frustration.type | `rage_click`, `dead_click` ou `error_click` |
| target.selector, target.text | L'élément cliqué |
| click.x, click.y | Coordonnées du clic |
| page.url | Page courante |
| session.id | Requis — les signaux sans cet attribut ne sont pas enregistrés |
{firstcol="26" mono="1"}

### Sessions et utilisateurs

- `session.id` est **requis** pour les sessions, les parcours, le replay et les signaux de frustration. Neurons regroupe la télémétrie selon la valeur reçue : l'application décide de la portée (par exemple un identifiant par onglet, conservé dans `sessionStorage`).
- La chronologie d'une session remonte jusqu'à 30 jours.
- La métrique **Users** compte les valeurs distinctes de `user.id` (ou de `user.name` si `user.id` est absent) sur les vues de page. Sans identification des utilisateurs, elle reste vide. Sessions et Users ne sont pas disponibles sur les longues périodes servies à partir de données agrégées.
- `user.id` et `user.name` sont des données personnelles — voir [Sécurité et confidentialité](#security).

## Configurer Neurons {#configure}

### Configurer l'endpoint d'ingestion RUM navigateur

Exposer les chemins d'ingestion sur l'origine du frontend et les relayer vers le service d'ingestion Neurons. La route de relais ajoute le jeton : aucun identifiant n'est jamais envoyé au navigateur.

| Chemin appelé par le navigateur | Relayer vers | En-têtes à ajouter par la route |
|---|---|---|
| /v1/traces | `<NEURONES_INGEST_URL>/v1/traces` | `X-Neurones-Token: <jeton d'ingestion>`, `X-Forwarded-For`, `X-Real-IP` |
| /v1/logs — uniquement si les erreurs navigateur sont envoyées en logs | `<NEURONES_INGEST_URL>/v1/logs` | `X-Neurones-Token: <jeton d'ingestion>`, `X-Forwarded-For`, `X-Real-IP` |
| /rum/replay — uniquement si le session replay est activé | `<NEURONES_INGEST_URL>/rum/replay` | `X-Neurones-Token: <jeton de requêtage>`, `X-Forwarded-For`, `X-Real-IP` |
{firstcol="26" mono="1"}

Exemple avec nginx (remplacer les valeurs entre chevrons ; garder le jeton hors du contrôle de version, par exemple en le substituant depuis l'environnement du serveur au démarrage) :

```nginx
location /v1/traces {
    proxy_pass         <NEURONES_INGEST_URL>/v1/traces;
    proxy_set_header   Host              $host;
    proxy_set_header   X-Real-IP         $remote_addr;
    proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header   X-Neurones-Token  <NEURONES_INGEST_TOKEN>;
}
```

Une route `/v1/logs`, si elle est utilisée, se configure de la même façon avec le jeton d'ingestion.

{{< callout type="warn" >}}
**Les traces et le session replay utilisent des jetons différents.** Dans le contrat Neurons actuel, `/v1/traces` et `/v1/logs` sont authentifiés par le jeton d'**ingestion** et `/rum/replay` par le jeton de **requêtage**. Si la route de replay reçoit le jeton d'ingestion, les envois de replay sont rejetés en 401, sauf si les deux jetons sont égaux dans votre environnement. Confirmer les deux valeurs avec l'équipe plateforme Neurons.
{{< /callout >}}

Si l'équipe plateforme Neurons fournit un endpoint RUM que le navigateur peut appeler directement sans jeton, il peut remplacer la route de relais. Dans ce cas, la géolocalisation reflète ce qui se connecte au service d'ingestion, pas forcément le visiteur.

### Géolocalisation

Il n'y a pas de géolocalisation côté client. Neurons résout pays, région, ville et coordonnées à partir de la première adresse IP **publique** de `X-Forwarded-For` (puis `X-Real-IP`) de la requête d'ingestion, et écrase tout attribut `geo.*` envoyé par le navigateur. Sans ces en-têtes, chaque visiteur est localisé à l'adresse du serveur de relais.

## Optionnel — Session replay {#replay}

{{< callout type="warn" >}}
**Le session replay ne fait pas partie de l'onboarding standard.** Il enregistre ce que les utilisateurs voient et font. Les applications traitant des identifiants, des données financières ou juridiques, des documents d'identité ou toute autre information sensible nécessitent une revue de confidentialité et de masquage dédiée avant son activation.
{{< /callout >}}

Une fois approuvé, un enregistreur comme `@rrweb/record` envoie des lots vers `/rum/replay` :

| Champ | Contenu |
|---|---|
| app | Le **`service.name` du frontend** (ex. `shop-web`) — pas la valeur `application` |
| session_id | Même valeur que l'attribut de span `session.id` |
| page_view_id | Identifiant de la vue de page |
| sequence_number | Compteur de lots, à partir de 0 |
| compressed_events | Base64 du JSON compressé en gzip (`{ events, metadata }`, ou tableau simple d'événements rrweb) |
| content_encoding | `gzip` ou `identity` |
| reason, trigger_reason, trigger_timestamp | Optionnels : motif d'envoi du lot ; premier événement notable de la session |
{firstcol="26" mono="1"}

Les sessions de replay sont associées à la télémétrie navigateur par le `service.name` du frontend et le `session.id` : si `app` ne correspond pas au `service.name` du frontend, les replays ne sont pas reliés aux sessions ni aux signaux de frustration de ce frontend.

Les champs inconnus sont rejetés en **422**. Limites de taille par défaut : 2 Mio compressés et 25 Mio décompressés par lot. Configurer l'enregistreur pour masquer la valeur de chaque champ de saisie et bloquer les éléments qui ne doivent jamais être enregistrés.

## Identité de l'application et du frontend {#identity}

Deux attributs identifient la télémétrie navigateur, à deux niveaux :

- **`service.name` identifie le frontend.** Browser Performance liste et filtre les frontends par `service.name`, et le replay y est rattaché.
- **`application` regroupe les services.** La même valeur `application` sur le frontend et sur ses services backend les regroupe sous une même application logique ; elle sert au regroupement et au filtrage, pas à identifier le frontend dans Browser Performance.

Exemple :

```text
Frontend : application = shop   service.name = shop-web   deployment.environment = production
Backend  : application = shop   service.name = shop-api   deployment.environment = production
```

La même `application` (`shop`) regroupe le frontend et le backend ; les valeurs `service.name` différentes (`shop-web`, `shop-api`) identifient chaque service.

### Attributs de ressource

Définis une seule fois, à l'initialisation du SDK :

| Attribut | Requis | Remarques |
|---|---|---|
| telemetry.sdk.language = webjs | **Oui** | Identifie les données comme du RUM navigateur. Sans lui, le frontend n'apparaît pas dans Browser Performance. |
| service.name | Oui | Identifie le frontend dans Browser Performance, ex. `shop-web`. C'est aussi la valeur `app` du session replay. |
| application | Oui | **La même valeur que les services backend**, pour que le frontend et son backend soient regroupés en une seule application. |
| deployment.environment | Oui | La même valeur que le backend, ex. `production`. |
| app.type | Non | `spa` ou `mpa`. S'il est absent, Neurons le déduit de `nav.type` : une navigation soft signifie SPA, des navigations hard uniquement signifient MPA. |
{firstcol="30" mono="1"}

### Attributs sur chaque span

Neurons les lit sur chaque **span**, pas sur la ressource — les poser sur chaque span créé ou enrichi par l'instrumentation :

| Attribut | Remarques |
|---|---|
| session.id | **Requis** pour les sessions, les parcours, le replay et les signaux de frustration — voir [Sessions et utilisateurs](#telemetry). |
| page.path, page.url | La page courante. |
| browser.name, os.name, device.type | Dimensions de répartition — `device.type` : `desktop`, `mobile` ou `tablet`. |
| user.id, user.name | Optionnels, uniquement après connexion et après approbation — données personnelles. `user.id` alimente la métrique Users. |
{firstcol="30" mono="1"}

## Générer du trafic de test {#test-traffic}

Après le déploiement du frontend instrumenté :

1. Ouvrir l'application depuis un vrai navigateur et recharger complètement la page.
2. Naviguer entre les pages (changements de route, pour une SPA).
3. Effectuer une action qui appelle le backend.
4. Déclencher une erreur JavaScript contrôlée.
5. Cliquer trois fois rapidement au même endroit, pour produire un clic rageur si les signaux de frustration sont implémentés.
{.steps}

La télémétrie est envoyée par lots : attendre quelques secondes avant de vérifier dans Neurons.

## Vérifier dans Neurons {#verify}

1. Dans les outils de développement du navigateur (Réseau), les requêtes vers l'endpoint d'ingestion RUM renvoient **2xx** — un 401 signifie que la route de relais n'ajoute pas de jeton valide.
2. Le frontend apparaît dans **Browser Performance** sous son `service.name`.
3. Les vues de page arrivent, pour le rechargement complet et pour les changements de route.
4. Les Web Vitals arrivent avec leurs évaluations, et l'Apdex est calculé.
5. L'erreur JavaScript contrôlée apparaît.
6. Les sessions montrent les pages visitées, dans l'ordre.
7. Navigateur, OS et appareil sont renseignés, et la localisation correspond au visiteur — pas au serveur.
8. L'appel backend apparaît dans la même trace que l'action navigateur, et la page liste les transactions métier qu'elle déclenche.
9. Pour une SPA, les changements de route affichent Route API total, Route backend total et Data wait.
10. Si activés : les signaux de frustration, la métrique Users et le session replay apparaissent.
{.steps}

{{< callout >}}
Un onboarding n'est pas terminé tant qu'il n'a pas été validé sur l'environnement déployé, et pas seulement en local.
{{< /callout >}}

## Sécurité et confidentialité {#security}

- **Ne jamais placer un jeton Neurons dans le code frontend**, ni dans une variable de build qui finit dans le bundle JavaScript. Les jetons ne vivent que sur la route de relais.
- Ne jamais commiter de jetons dans le contrôle de version.
- Ne pas capturer les valeurs de formulaire, mots de passe, jetons d'authentification, données de paiement ni en-têtes `Authorization`.
- `user.id` et `user.name` sont des données personnelles : ne les envoyer qu'après approbation.
- Revoir la collecte des adresses IP et des localisations des visiteurs selon les exigences de confidentialité de l'application.
- Le session replay reste désactivé sauf approbation après une revue de confidentialité et de masquage.

## Dépannage {#troubleshooting}

| Symptôme | Cause probable | Action |
|---|---|---|
| `/v1/traces` renvoie 401 | La route de relais n'ajoute pas le jeton d'ingestion, ou en ajoute un mauvais | Vérifier l'en-tête de la route et la valeur du jeton. |
| `/rum/replay` renvoie 401 alors que les traces fonctionnent | Le replay est authentifié par le jeton de requêtage | Configurer le jeton de requêtage sur la route de replay. |
| `/rum/replay` renvoie 422 | Champ inconnu, `content_encoding` incorrect, ou lot trop volumineux | N'envoyer que les champs documentés ; utiliser `gzip` ou `identity` ; respecter les limites. |
| Replays non reliés aux sessions | Le `app` du replay diffère du `service.name` du frontend | Envoyer le `service.name` du frontend comme `app`. |
| Frontend absent de Browser Performance | `telemetry.sdk.language=webjs` absent, ou aucun span `page-view` | Vérifier les attributs de ressource et implémenter les vues de page (voir [Implémenter la télémétrie navigateur Neurons](#implement)). |
| Erreurs JavaScript absentes | Spans d'erreur sans `rum.kind=app-error` (un nom `app.error` ou un statut ERROR seuls ne suffisent pas) | Définir `rum.kind=app-error` et les attributs `error.*`. |
| Web Vitals affichés mais sans évaluations ni Apdex | `wv.rating` absent ou différent de `good` / `needs-improvement` / `poor` | Envoyer l'évaluation émise par la bibliothèque `web-vitals`. |
| Appels API listés comme appels de ressource | `api.kind` absent des spans d'API | Définir `api.kind` et une `api.route` normalisée. |
| Route API total / backend total / Data wait vides | Appels API hors de la trace du `page-view` soft | Garder le span page-view soft actif pendant le démarrage des appels API de la route. |
| Tous les visiteurs localisés au même endroit | La route de relais ne transmet pas l'IP du visiteur | Ajouter `X-Forwarded-For` / `X-Real-IP`. |
| Sessions, replay ou signaux de frustration vides | `session.id` absent des spans | Poser `session.id` sur chaque span. |
| Métrique Users vide | Pas de `user.id` sur les vues de page, ou longue période | Activer l'identification des utilisateurs approuvée ; utiliser une période plus courte. |
| Spans navigateur et backend dans des traces séparées | `traceparent` non envoyé, ou backend non instrumenté | Vérifier l'instrumentation Fetch ; pour une API cross-origin, `propagateTraceHeaderCorsUrls` et CORS. |
| Répartitions à « unknown » | `browser.name` / `os.name` / `device.type` posés uniquement sur la ressource | Les poser sur chaque span. |
| Frontend regroupé à part de son backend | Valeurs `application` différentes | Utiliser la même valeur `application` des deux côtés. |
| La page ne se charge plus, en production uniquement | Initialisation RUM non protégée, ex. `crypto.randomUUID()` en HTTP | Protéger la génération d'identifiants ; encapsuler chaque fonctionnalité RUM dans un `try/catch`. |
| Un paquet est installé mais sans effet | Jamais importé ou enregistré (ex. `ZoneContextManager`) | Vérifier le code RUM, pas seulement `package.json`. |

## Désactivation / retour arrière {#rollback}

Le RUM peut être désactivé sans toucher au traçage backend :

1. Désactiver l'interrupteur RUM, ou retirer l'import RUM du point d'entrée de l'application.
2. Reconstruire et redéployer le frontend — le RUM fait partie du bundle JavaScript, une modification côté serveur seule ne le désactive pas.
3. Optionnellement, retirer les routes d'ingestion RUM du serveur web.
4. Confirmer qu'aucune nouvelle télémétrie navigateur n'arrive dans Neurons, et que les traces backend continuent normalement.
