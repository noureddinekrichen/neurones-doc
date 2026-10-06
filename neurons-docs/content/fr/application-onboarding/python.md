---
title: Onboarding des applications Python
linkTitle: Python
lede: Instrumenter une application Python (Django, Flask, FastAPI) avec l'auto-instrumentation OpenTelemetry pour que ses requêtes HTTP, ses appels à la base de données et ses traces distribuées apparaissent dans Neurons.
menus:
  onboarding:
    parent: opentelemetry
    weight: 50
labels:
  versions: Versions prises en charge
  connectivity: Connectivité au Collecteur
  install: Installer OpenTelemetry
  configure: Configurer OpenTelemetry
  start: Démarrer avec OpenTelemetry
  http-capture: Capture des données HTTP
  done: Definition of Done
---

Les applications Python sont instrumentées avec **`opentelemetry-distro`**, activé en plaçant l'enveloppe **`opentelemetry-instrument`** devant la commande de démarrage réelle de l'application. Contrairement à PHP, il n'y a pas d'extension à activer : c'est la commande d'enveloppe qui active l'instrumentation.

## Périmètre {#scope}

Ce guide couvre **uniquement le traçage backend** : spans serveur HTTP, spans de base de données, propagation de trace distribuée, et l'identification de l'application et de l'environnement que Neurons utilise pour les regrouper.

Il ne configure **pas** :

- **Les logs** — la configuration ci-dessous définit `OTEL_LOGS_EXPORTER=none`.
- **Les métriques** — Neurons calcule les métriques de service (débit, erreurs, durée) à partir des traces elles-mêmes ; la configuration définit `OTEL_METRICS_EXPORTER=none`.
- **Le RUM navigateur** — instrumenter le backend Python n'active aucune surveillance du navigateur. Voir [Onboarding du RUM navigateur](../browser-rum/).

La capture des en-têtes et des corps HTTP sont des compléments optionnels, décrits en fin de page.

## Architecture {#architecture}

{{< flow label="Comment la télémétrie Python arrive dans Neurons" >}}
app | Votre application Python | Démarrée via `opentelemetry-instrument`, avec l'instrumentation du framework et de la base de données
→ OTLP sur HTTP (protobuf)
platform | Collecteur OpenTelemetry Neurons | Reçoit la télémétrie, la convertit en OTLP/JSON et ajoute le jeton d'ingestion
→ OTLP sur HTTP (JSON)
platform | apm-ingest | Service d'ingestion Neurons : valide et enregistre la télémétrie
→
platform | Neurons APM | Applications, services, traces et transactions métier
{{< /flow >}}

{{< callout >}}
La télémétrie Python passe toujours par le Collecteur OpenTelemetry Neurons. L'exportateur envoie de l'OTLP/protobuf ; le Collecteur le convertit et le transmet au service d'ingestion Neurons, qui n'accepte que l'OTLP/JSON. Ne jamais pointer l'exportateur Python directement vers le service d'ingestion.
{{< /callout >}}

## Prérequis {#prerequisites}

Avant l'intégration, confirmer que :

- Une version de Python prise en charge est installée sur le serveur applicatif cible (voir [Versions prises en charge](#versions)), avec pip disponible.
- L'équipe peut installer des dépendances Python dans l'environnement de l'application (virtualenv, image, ...).
- Le serveur applicatif peut joindre le Collecteur OpenTelemetry Neurons (voir [Connectivité au Collecteur](#connectivity)).
- La commande de démarrage réelle de l'application peut être modifiée.
- Des variables d'environnement peuvent être fournies au processus applicatif réel.
- Le nom `application` et un `OTEL_SERVICE_NAME` unique ont été convenus (voir [Application ou service](#naming)).
- L'environnement de déploiement, le framework de l'application et — si le traçage de base de données est requis — le pilote de base de données sont connus.

{{< callout >}}
L'équipe plateforme Neurons fournit ou confirme l'endpoint du Collecteur, s'il exige une authentification ou TLS, et la convention de nommage application/service avant l'intégration.
{{< /callout >}}

## Versions prises en charge {#versions}

Exigences des paquets OpenTelemetry Python actuels (`opentelemetry-distro` 0.66b0, exportateur 1.45.0 — vérifiées sur PyPI, octobre 2026) :

| Composant | Exigence |
|---|---|
| Python | 3.10 ou plus |
| Django | 2.0 ou plus ({{< mono "opentelemetry-instrumentation-django" >}}) |
| Flask | 1.0 ou plus ({{< mono "opentelemetry-instrumentation-flask" >}}) |
| FastAPI | 0.92 ou plus, inférieure à 1.0 ({{< mono "opentelemetry-instrumentation-fastapi" >}}) |
{firstcol="26"}

{{< callout type="warn" >}}
Les versions de Python, de framework et de serveur prises en charge doivent être confirmées avec la matrice de compatibilité Neurons actuelle. Les combinaisons qui respectent les exigences ci-dessus devraient fonctionner, mais doivent passer la [vérification](#verify) complète avant d'être considérées comme prises en charge. Les exigences des paquets évoluent d'une version à l'autre — vérifier celle que vous installez.
{{< /callout >}}

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

## Installer OpenTelemetry {#install}

Installer dans l'environnement où l'application s'exécute réellement (son virtualenv ou son image) :

```bash
pip install \
  opentelemetry-distro \
  opentelemetry-exporter-otlp-proto-http
```

- {{< mono "opentelemetry-distro" >}} — la distribution OpenTelemetry Python et l'outillage d'auto-instrumentation, dont `opentelemetry-instrument`.
- {{< mono "opentelemetry-exporter-otlp-proto-http" >}} — l'export des traces en OTLP HTTP/protobuf.

### Instrumentation du framework

| Framework | Paquet |
|---|---|
| Django | opentelemetry-instrumentation-django |
| Flask | opentelemetry-instrumentation-flask |
| FastAPI | opentelemetry-instrumentation-fastapi |
{mono="2"}

N'installer que le paquet correspondant au framework de l'application, par exemple :

```bash
pip install opentelemetry-instrumentation-django
```

Les autres frameworks ne sont pas couverts par ce guide. S'il existe pour eux un paquet d'instrumentation OpenTelemetry, il peut être utilisé de la même façon, mais le résultat doit être vérifié manuellement.

### Instrumentation de la base de données

| Base de données / pilote | Paquet |
|---|---|
| PostgreSQL / psycopg2 | opentelemetry-instrumentation-psycopg2 |
| PostgreSQL / psycopg (3) | opentelemetry-instrumentation-psycopg |
| MySQL / PyMySQL (inférieur à 2.0) | opentelemetry-instrumentation-pymysql |
| SQLite | opentelemetry-instrumentation-sqlite3 |
{mono="2"}

Installer l'instrumentation du pilote réellement utilisé par l'application. **L'instrumentation du framework n'instrumente pas les pilotes de base de données** : les requêtes ne sont tracées que si l'instrumentation du pilote correspondant est installée. Pour un pilote absent de cette liste, utiliser le paquet d'instrumentation OpenTelemetry correspondant et vérifier le résultat.

## Configurer OpenTelemetry {#configure}

Configuration Python Neurons actuellement validée :

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

| Paramètre | Rôle |
|---|---|
| OTEL_SERVICE_NAME | Le nom du **service** dans Neurons (voir ci-dessous). |
| OTEL_TRACES_EXPORTER | `otlp_proto_http` : l'exportateur de traces de la configuration validée. |
| OTEL_METRICS_EXPORTER / OTEL_LOGS_EXPORTER | `none` : seules les traces sont exportées (voir [Périmètre](#scope)). |
| OTEL_EXPORTER_OTLP_TRACES_ENDPOINT | L'endpoint traces du Collecteur Neurons. |
| OTEL_PROPAGATORS | `tracecontext,baggage` : propagation de trace W3C entre services instrumentés. |
| application | Le nom de l'**application** dans Neurons (voir ci-dessous). |
| deployment.environment | Identifie l'environnement déployé — par exemple `production`, `preprod`, `staging`, `qa`, `development`. |
{firstcol="30" mono="1"}

Note de compatibilité : pour le contrat d'ingestion actuel de Neurons, utiliser `deployment.environment`, et non le plus récent `deployment.environment.name`.

### Application ou service {#naming}

Neurons regroupe la télémétrie sur deux niveaux :

- **Application** — l'attribut de ressource `application`. C'est ce que liste l'écran Applications. Plusieurs services peuvent partager une même application.
- **Service** — `OTEL_SERVICE_NAME`. Chaque service est listé, avec ses propres métriques, sous son application.

Exemple — une plateforme de réservation composée d'un back-office Django et d'une API publique FastAPI :

| Composant | application | OTEL_SERVICE_NAME |
|---|---|---|
| Back-office Django | booking | booking-backoffice |
| API publique FastAPI | booking | booking-api |
{mono="2,3"}

Les deux apparaissent sous l'application **booking**, comme deux services.

{{< callout type="warn" >}}
L'attribut doit s'appeler exactement `application` — ni `application.name`, ni `service.namespace`. La télémétrie sans attribut `application` valide n'est pas rejetée : elle est regroupée sous **Unassigned**.
{{< /callout >}}

### Authentification {#auth}

Le service d'ingestion Neurons authentifie le **Collecteur**, pas l'application : c'est le Collecteur qui ajoute le jeton d'ingestion lorsqu'il transmet les données. Une application Python n'envoie donc normalement aucun identifiant.

Si votre Collecteur est configuré pour exiger un en-tête de la part des applications (la [vérification de connectivité](#connectivity) renvoie 401/403), l'équipe plateforme fournit le nom et la valeur de l'en-tête. Le définir comme variable d'environnement du processus, jamais dans le code source :

```bash
OTEL_EXPORTER_OTLP_HEADERS=<HEADER_NAME>=<VALUE>
```

### TLS / HTTPS {#tls}

L'endpoint `http://` ci-dessus concerne un Collecteur joint via un réseau interne de confiance. Utiliser l'URL et le transport du Collecteur définis par l'équipe plateforme Neurons pour l'environnement cible : lorsqu'elle fournit un endpoint `https://`, l'utiliser tel quel.

### Configuration spécifique à Django

```bash
DJANGO_SETTINGS_MODULE=<DJANGO_PROJECT>.settings
```

Le module de paramètres Django doit être disponible avant que l'instrumentation n'initialise l'application. Si Django ne parvient pas à importer le projet lorsque l'instrumentation est activée, vérifier que la racine du projet figure dans le chemin d'import de Python.

### Rendre la configuration disponible au processus réel

{{< callout type="warn" >}}
Les variables `OTEL_*` doivent être visibles par le processus qui exécute réellement l'application Python. Des valeurs présentes uniquement dans un shell interactif, un terminal de développement, un fichier `.env` local ou un script de déploiement ne garantissent pas que le service de production les reçoive.
{{< /callout >}}

Cela s'applique quel que soit le gestionnaire du processus — par exemple systemd, un service Windows, Supervisor, Docker, Kubernetes, ou un service Gunicorn, Uvicorn ou Waitress.

## Démarrer l'application avec OpenTelemetry {#start}

L'auto-instrumentation s'active en plaçant `opentelemetry-instrument` devant la commande de démarrage réelle de l'application.

Gunicorn :

```bash
opentelemetry-instrument gunicorn app:app
```

Uvicorn / FastAPI :

```bash
opentelemetry-instrument uvicorn app:app
```

Waitress / Django :

```bash
opentelemetry-instrument waitress-serve --host=127.0.0.1 --port=8000 core.wsgi:application
```

{{< callout type="warn" >}}
Si le processus de production démarre l'application directement, sans `opentelemetry-instrument`, l'auto-instrumentation n'est pas active. Valider la commande utilisée par le service réellement en cours d'exécution, pas seulement celle documentée dans un script de déploiement.
{{< /callout >}}

## Générer du trafic de test {#test-traffic}

Après le démarrage de l'application instrumentée :

1. Déclencher une vraie requête HTTP.
2. Privilégier un endpoint qui exécute aussi une requête en base de données.
3. Si le traçage distribué est requis, utiliser une requête qui appelle un autre service instrumenté.
{.steps}

Ce seul test valide le traçage HTTP, le traçage de base de données et la propagation de trace le cas échéant. La télémétrie peut mettre plusieurs secondes à apparaître : un résultat vide juste après la requête ne signifie pas forcément que la configuration est erronée.

## Vérification dans Neurons {#verify}

1. L'application apparaît dans la liste Applications sous son nom `application` (et non sous **Unassigned**).
2. Le service apparaît sous cette application avec son `OTEL_SERVICE_NAME`, avec un `last_seen` récent.
3. Une vraie trace HTTP est visible, avec la route, la méthode et le code de statut corrects.
4. La durée de la trace est plausible.
5. Des spans de base de données apparaissent pour les requêtes qui accèdent à la base, avec le système et le nom de la base renseignés lorsque c'est pris en charge.
6. L'opération de base de données est correctement classée.
7. Les appels vers les services en aval partagent la même trace distribuée, le cas échéant.
{.steps}

{{< callout >}}
Une intégration n'est pas terminée tant qu'elle n'a pas été validée sur l'environnement déployé. Une validation en développement local ne suffit pas.
{{< /callout >}}

Si la télémétrie arrive mais qu'un champ est vide ou mal classé, comparer les attributs bruts des spans avec le contrat d'ingestion actuel de Neurons : les conventions sémantiques OpenTelemetry évoluent, et différentes versions d'instrumentation peuvent émettre des noms d'attributs différents.

## Optionnel — Capture des données HTTP {#http-capture}

Ne fait pas partie de l'intégration requise. À n'activer que lorsque c'est dans le périmètre.

### En-têtes

La capture des en-têtes est fournie nativement par l'instrumentation serveur OpenTelemetry Python :

```bash
OTEL_INSTRUMENTATION_HTTP_CAPTURE_HEADERS_SERVER_REQUEST=content-type,accept
OTEL_INSTRUMENTATION_HTTP_CAPTURE_HEADERS_SERVER_RESPONSE=content-type
OTEL_INSTRUMENTATION_HTTP_CAPTURE_HEADERS_SANITIZE_FIELDS=.*cookie.*,.*authorization.*,.*api.?key.*
```

- La capture des en-têtes est optionnelle (opt-in) : rien n'est capturé tant que les listes blanches sont vides.
- Ne capturer que des en-têtes explicitement approuvés.
- Les motifs de nettoyage sont une seconde sécurité ; ne jamais les utiliser en remplacement d'une liste blanche restreinte.
- Ne jamais configurer de capture illimitée en production, comme `.*`, sans revue spécifique.

### Corps des requêtes / réponses — nécessite un middleware applicatif

L'instrumentation serveur OpenTelemetry Python standard ne capture pas les corps. La capture des corps est réalisée par un middleware applicatif, contrôlé par deux interrupteurs qui doivent rester désactivés par défaut :

```bash
OTEL_CAPTURE_HTTP_REQUEST_BODY=false
OTEL_CAPTURE_HTTP_RESPONSE_BODY=false
```

{{< callout type="warn" >}}
**Limite de l'implémentation actuelle.** Le middleware de référence existant ne fonctionne qu'avec Django. Il dispose d'interrupteurs requête/réponse indépendants, désactivés par défaut, et ne capture que les corps `application/json`, tronqués à 4096 octets fixes. Il ne fournit **pas** de masquage par champ ni d'exclusion des routes sensibles. Ne pas activer la capture des corps sur des routes qui transportent des identifiants, des jetons, des données personnelles ou des données de paiement. Les applications Flask et FastAPI n'ont pas encore de middleware de référence.
{{< /callout >}}

Exigences de production recommandées pour toute implémentation de capture des corps (toutes ne sont pas implémentées par le middleware actuel) :

- désactivée par défaut, avec des interrupteurs requête/réponse indépendants ;
- une limite d'octets maximale et une liste blanche de types de contenu approuvés ;
- un masquage par champ et l'exclusion des routes sensibles ;
- aucune capture multipart/envoi de fichiers, binaire ou de réponse en streaming ;
- aucun identifiant, jeton d'authentification, mot de passe ni numéro de carte de paiement.

Pour la politique de capture générale, voir [Instrumentation des applications (OpenTelemetry)](../../#otel).

## Sécurité et confidentialité {#security}

- Ne jamais commiter de secrets.
- Les en-têtes HTTP doivent reposer sur des listes blanches ; `Authorization` et `Cookie` ne doivent pas être capturés en clair.
- La capture des corps doit être optionnelle (opt-in), et tenue à l'écart des routes sensibles — le middleware de référence actuel ne sait pas masquer les champs.
- Ne pas capturer les valeurs de paramètres SQL contenant des informations personnelles ou sensibles, sauf approbation explicite.

## Retour en arrière / désactivation {#rollback}

**Désactiver temporairement la télémétrie** — les paquets et l'enveloppe restent en place :

```bash
OTEL_TRACES_EXPORTER=none
```

1. Redémarrer ou recharger le processus de l'application Python.
2. Envoyer du trafic de test.
3. Confirmer que `last_seen` dans Neurons n'avance plus après la fenêtre d'observation prévue.

Pour réactiver, restaurer la valeur de l'exportateur et redémarrer le processus.

**Supprimer complètement l'instrumentation :**

1. Retirer `opentelemetry-instrument` de la commande de démarrage du processus.
2. Retirer les variables d'environnement `OTEL_*` du service.
3. Désinstaller les paquets de l'environnement de l'application, par exemple :

   ```bash
   pip uninstall opentelemetry-distro opentelemetry-exporter-otlp-proto-http \
     opentelemetry-instrumentation-django opentelemetry-instrumentation-psycopg2
   ```

4. Redémarrer le processus et vérifier que l'application fonctionne normalement.

## Dépannage {#troubleshooting}

| Symptôme | Cause probable | Action |
|---|---|---|
| Aucun span | Processus non démarré via `opentelemetry-instrument` | Vérifier la commande réelle du processus en cours. |
| Aucun span alors que l'enveloppe est présente | Environnement `OTEL_*` absent du service réel | Inspecter l'environnement réel du service/processus. |
| Erreurs d'export dans les logs de l'application | Collecteur injoignable, ou il exige une authentification ou TLS | Lancer la [vérification de connectivité](#connectivity) ; voir [Authentification](#auth) et [TLS](#tls). |
| L'application échoue au démarrage après activation d'OpenTelemetry | Incohérence de paquet/configuration de l'exportateur | Vérifier que `opentelemetry-exporter-otlp-proto-http` est installé et que `OTEL_TRACES_EXPORTER=otlp_proto_http` est défini. |
| Django fonctionne normalement mais échoue uniquement une fois instrumenté | Chemin d'import du projet/des paramètres Django indisponible au démarrage de l'instrumentation | Vérifier `DJANGO_SETTINGS_MODULE` et le chemin d'import Python. |
| Service visible mais listé sous **Unassigned** | Attribut `application` absent ou mal orthographié | Vérifier `OTEL_RESOURCE_ATTRIBUTES` (voir [Application ou service](#naming)). |
| Des traces HTTP apparaissent, mais aucun span de base de données | Paquet d'instrumentation de base de données correspondant absent | Vérifier l'instrumentation du pilote réellement utilisé. |
| L'application apparaît dans Neurons mais des champs sont vides | Différence de conventions sémantiques | Comparer les attributs de span émis avec le contrat d'ingestion actuel de Neurons. |

## Definition of Done {#done}

L'intégration backend n'est terminée que lorsque :

- les versions de Python et du framework respectent les [versions prises en charge](#versions)
- les paquets OpenTelemetry, d'instrumentation du framework et de la base de données requis sont installés
- le Collecteur est joignable depuis le serveur applicatif, avec authentification et TLS si nécessaire
- les variables `OTEL_*` atteignent le processus de production réel
- le processus réel démarre via `opentelemetry-instrument`
- `application` et un `OTEL_SERVICE_NAME` unique sont configurés, et l'application n'est pas listée sous **Unassigned**
- `deployment.environment` est configuré
- une vraie trace HTTP est visible dans Neurons, avec route, méthode et statut corrects
- le traçage de base de données est vérifié le cas échéant
- la propagation distribuée est vérifiée le cas échéant
- la capture des corps HTTP sensibles reste désactivée sauf approbation
- les deux procédures de retour en arrière (désactivation temporaire, suppression complète) sont documentées et la désactivation temporaire a été testée
- l'environnement déployé a été validé
