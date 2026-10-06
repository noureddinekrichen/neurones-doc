---
title: Administration & Exploitation
navTitle: Administration
part: part4
weight: 5
labels:
  settings: Réglages
  otel: Instrumentation OpenTelemetry
  backup: Sauvegarde & restauration
tocLabels:
  otel: Instrumentation OTel
---

Cette partie s'adresse aux personnes responsables du bon fonctionnement de la plateforme elle-même : configuration, rétention des données, instrumentation des applications, intégrations externes, déploiement et sauvegarde.

## Réglages (Settings) {#settings}

La page « Settings » regroupe cinq zones de configuration, chacune sous forme d'une carte cliquable :

| Carte | Rôle |
|---|---|
| **OpenTelemetry Collector** | Gérer les configurations du Collecteur poussées vers les agents installés sur votre infrastructure. |
| **Database Configuration** | Basculer et gérer les sources de données Vertica / PostgreSQL / Oracle actives. |
| **Data Retention** | Configurer la durée de conservation de chaque catégorie de données (détail ci-dessous). |
| **External CMDB Integration** | Connecter et synchroniser les fiches d'actifs avec une CMDB externe. |
| **External Event Management** | Transférer les événements de la plateforme vers un outil externe de gestion d'incidents. |
{firstcol="30"}

## Rétention des données {#retention}

La rétention des données détermine combien de temps chaque catégorie de télémétrie est conservée avant suppression automatique — un arbitrage entre coût de stockage et profondeur d'investigation possible. Elle est configurée séparément pour chaque catégorie, car leur utilité dans le temps n'est pas la même :

| Catégorie | Par défaut | Plage | Pourquoi |
|---|---|---|---|
| Spans (traces brutes) | 30 j | 1–90 j | Volumineuses, surtout utiles les premiers jours/semaines pour investiguer un incident précis. |
| Logs | 30 j | 1–90 j | Même profil que les traces brutes. |
| Métriques — 1 minute | 15 j | 1–30 j | Analyses fines, utilisées au-delà d'une semaine lors d'une investigation approfondie. |
| Métriques — 1 heure | 90 j | 7–180 j | Comparaisons de tendance mois par mois. |
| Métriques — 1 jour | 400 j | 30–730 j | Comparaisons d'une année sur l'autre. |
| Événements résolus | 90 j | 1–730 j | Les événements ouverts ou acquittés ne sont jamais purgés, quel que soit leur âge. |
{mono="2,3"}

Pour chaque zone, la page présente une description pédagogique, un indicateur d'usage réel (lignes et taille estimée), le réglage du nombre de jours, un bouton de purge immédiate (avec confirmation), et un historique des purges passées.

{{< callout >}}
La taille sur le disque est une estimation ; si elle n'est pas disponible pour une table, le nombre de lignes reste affiché, avec une mention explicite que la taille est inconnue plutôt qu'une valeur fausse.
{{< /callout >}}

Une purge automatique passe une fois par jour et applique les réglages configurés pour chaque zone. Une purge peut aussi être déclenchée manuellement à tout moment ; dans les deux cas, l'action est journalisée avec la date, le nombre de lignes supprimées et la source du déclenchement.

## Instrumentation des applications (OpenTelemetry) {#otel}

Pour qu'une application apparaisse dans Neurons, elle doit être instrumentée avec OpenTelemetry et configurée pour exporter ses traces et logs vers le Collecteur. Ce paragraphe couvre un point d'attention fréquent une fois l'instrumentation de base en place : la capture des en-têtes HTTP et, plus rarement, du contenu des requêtes/réponses.

### Capture des en-têtes HTTP

Par sécurité, OpenTelemetry ne capture aucun en-tête HTTP par défaut — les en-têtes contiennent fréquemment des informations sensibles (jetons, cookies de session). La capture doit être explicitement activée, séparément pour les requêtes entrantes et sortantes, et séparément pour la requête et la réponse. Cela se fait par variables d'environnement pour la plupart des langages backend ; côté navigateur, la même liste explicite est déclarée dans la configuration JavaScript de l'instrumentation.

{{< callout type="warn" >}}
Quel que soit le langage, la même règle s'applique : ne jamais capturer « tous les en-têtes » — toujours une liste explicite, en excluant systématiquement les en-têtes d'authentification et les cookies.
{{< /callout >}}

### Capture du corps des requêtes et réponses

OpenTelemetry ne capture pas nativement le contenu (le corps) des requêtes ou réponses — uniquement leur taille en octets. Capturer le contenu réel nécessite une instrumentation personnalisée, activée uniquement pour les routes explicitement choisies, avec deux règles à respecter systématiquement : limiter la taille capturée, et masquer les champs sensibles avant tout envoi — il n'y a pas de retour en arrière possible une fois la donnée exportée.

## Intégrations externes {#integrations}

Deux intégrations permettent de relier Neurons au reste de l'écosystème d'exploitation :

- **CMDB externe** — synchronise la liste consolidée des applications, services et transactions métier avec une base de gestion de configuration externe.
- **Gestion externe des événements** — transfère les événements générés par Neurons vers un outil externe de gestion d'incidents.

## Déploiement Kubernetes {#k8s}

Neurons se déploie comme trois composants indépendants, chacun avec sa propre image, réunis dans le même espace de noms Kubernetes :

| Composant | Rôle | Mise à l'échelle |
|---|---|---|
| apm-ingest | Reçoit la télémétrie, exécute les workers de calcul et sert l'API de requêtage. | Le service d'ingestion/requêtage se scale horizontalement ; les 3 workers de fond restent à une seule instance. |
| neurones-backend | API de contrôle : authentification, CMDB, administration du Collecteur, événements temps réel. | Une seule instance. |
| neurones-frontend | Application web (dashboards, topologie, réglages), Next.js. | Se scale horizontalement. |
{mono="1"}

Les trois composants s'appuient sur une base Vertica externe et sur une petite base PostgreSQL de contrôle partagée. Les deux doivent exister et être accessibles avant de démarrer le déploiement.

### Points d'attention avant un premier déploiement

- Un StorageClass supportant l'accès **ReadWriteMany** est nécessaire pour le volume partagé de la base GeoIP — de nombreuses classes de stockage cloud par défaut (EBS, par exemple) ne le permettent pas.
- La base GeoIP (MaxMind GeoLite2) n'est pas fournie dans l'image publiée pour des raisons de licence : chaque client doit générer sa propre clé de licence.
- Le schéma PostgreSQL de {{< mono "neurones-backend" >}} n'est pas appliqué automatiquement en production — une migration {{< mono "alembic upgrade head" >}} doit être exécutée explicitement avant le premier démarrage.
- Le schéma Vertica n'est pas non plus appliqué automatiquement : toutes les migrations doivent être appliquées avant le premier démarrage d'apm-ingest.
- {{< mono "neurones-backend" >}} n'accepte que les origines explicitement listées dans sa configuration CORS ; l'oublier se traduit par un frontend qui s'affiche mais dont tous les appels API échouent silencieusement.
- Les URL publiques (API et WebSocket) de {{< mono "neurones-frontend" >}} sont figées au moment de la construction de son image, pas au démarrage du conteneur.
- Le tampon d'ingestion est uniquement en mémoire, sans file d'attente durable derrière lui : dimensionner la mémoire avec une marge, et laisser un délai d'arrêt suffisant lors des mises à jour.
- Le jeton d'ingestion est un secret partagé unique, sans portée par client : à traiter comme une information sensible et à faire tourner s'il est exposé.

Une fois configuré, un script unique ({{< mono "deploy-neurons-apm.sh" >}}) prend en charge l'ensemble du déploiement, puis attend que tout soit prêt. Il peut être relancé sans risque après une modification de configuration.

## Sauvegarde et restauration {#backup}

L'ensemble des données de Neurons réside dans une seule base Vertica, appelée « Data Lake ». Protéger cette base unique, c'est protéger l'ensemble du système — il n'existe aucune autre copie ailleurs.

### Ce qu'il faut savoir avant de faire confiance à une sauvegarde

- **Les données « en vol » ne sont pas couvertes.** La télémétrie reçue mais pas encore écrite en base est perdue si le service d'ingestion s'arrête brutalement.
- **Le point de restauration est celui de la dernière sauvegarde réussie.** Tout ce qui a été ingéré entre la dernière sauvegarde et l'incident est définitivement perdu.

Trois types de destination sont pris en charge : un stockage objet compatible S3 (recommandé en production), un partage réseau NFS, ou un disque local.

### Procédure de restauration, résumée

1. Évaluer l'ampleur des dégâts — en cas de doute, traiter comme une perte totale.
2. Arrêter le service d'ingestion et tous les workers de fond avant toute restauration.
3. Restaurer la dernière sauvegarde valide (ou une sauvegarde nommée spécifique).
4. Valider la base restaurée avant de rouvrir le trafic.
5. Redémarrer le service d'ingestion et les workers — chacun reprend automatiquement là où son point de reprise l'indique.
6. Reconstruire, si possible, ce qui peut l'être pour la période perdue (graphe de dépendance, registre des transactions métier).
7. Communiquer clairement la fenêtre de temps affectée.
{.steps}

{{< callout type="warn" >}}
Une sauvegarde qui n'a jamais été restaurée n'est pas une sauvegarde vérifiée. Une restauration de test mensuelle, et un exercice complet au moins une fois par an, sont recommandés.
{{< /callout >}}
