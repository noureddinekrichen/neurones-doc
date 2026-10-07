---
title: Déployer Neurons sur votre cluster Kubernetes
linkTitle: Kubernetes
lede: Déployer Neurons sur votre propre cluster à partir des images officielles fournies par Confoline, étape par étape, jusqu'à la première connexion.
menus:
  onboarding:
    parent: deployment
    weight: 10
labels:
  prerequis: Prérequis
  fichiers: Fichiers de déploiement
  namespace: Namespace
  registre: Accès aux images
  vertica: Base Vertica
  secrets: Secrets
  postgres: PostgreSQL
  migrations: Structure de la base
  admin: Administrateur
  applications: Applications
  verifier: Vérifications
  collecteurs: Collecteurs
---

Ce guide permet de déployer **Neurons** sur votre propre serveur et votre propre cluster Kubernetes, à partir des **images officielles fournies par Confoline**. À la fin, Neurons est accessible en HTTPS sur votre domaine, relié à votre base Vertica et prêt à recevoir les traces de vos applications.

{{< callout type="warn" >}}Lancez **toutes les commandes dans le même terminal**, sans le fermer : les valeurs saisies à une étape sont réutilisées aux suivantes. Une commande par bloc : copiez et lancez les blocs un par un.{{< /callout >}}

{{< callout >}}Plus rapide : Confoline peut aussi vous fournir un installateur automatique, `installer-neurones.sh`, qui réalise toutes ces étapes en posant quelques questions.{{< /callout >}}

## Avant de commencer : ce qu'il vous faut {#prerequis}

**Fourni par Confoline :** l'adresse du registre d'images et son identifiant (lecture seule), et la **liste des images** de votre version (backend, frontend, apm-ingest).

**De votre côté :**

- une machine avec **`kubectl`** (administrateur du cluster), **`vsql`** (le client Vertica), **`openssl`** et **`curl`** ;
- un cluster Kubernetes **1.27 ou plus récent**, avec **ingress-nginx** et une **StorageClass** par défaut ;
- au moins **1,5 cœur** et **3,5 Go** de mémoire libres ;
- un compte **administrateur Vertica** (`dbadmin`), et le port de Vertica joignable depuis le cluster ;
- le **domaine** de Neurons, et son **certificat HTTPS** avec sa clé privée (fichiers PEM).

Les valeurs à remplacer sont marquées **`<À REMPLIR>`**.

## Étape 1 — On télécharge les fichiers de déploiement {#fichiers}

| Fichier | Contenu | Étape |
|---|---|---|
| [`apm-tables.sql`](../../../files/deployment/apm-tables.sql) | le schéma `apm` et ses 89 tables | 4 |
| [`vertica-comptes.sql`](../../../files/deployment/vertica-comptes.sql) | les deux comptes Vertica de Neurons et leurs droits | 4 |
| [`postgres.yaml`](../../../files/deployment/postgres.yaml) | PostgreSQL | 6 |
| [`migrations.yaml`](../../../files/deployment/migrations.yaml) | la création des tables de PostgreSQL | 7 |
| [`applications.yaml`](../../../files/deployment/applications.yaml) | les 6 applications et leurs routes web | 9 |
{mono="1"}

Ils ne contiennent aucun mot de passe : seulement des repères (`__DOMAINE__`…) remplacés automatiquement par vos valeurs au moment du déploiement. Cliquez sur un nom de fichier pour le consulter ; la commande ci-dessous les télécharge tous sur le serveur.

On crée un dossier de travail :

```bash
mkdir neurons-deploiement && cd neurons-deploiement
```

On télécharge les 5 fichiers :

```bash
for f in apm-tables.sql vertica-comptes.sql postgres.yaml migrations.yaml applications.yaml; do curl -fsSLO "https://docs.confoline.com/neurons/files/deployment/$f"; done
```

On vérifie qu'ils sont là :

```bash
ls
```

Attendu : `apm-tables.sql  applications.yaml  migrations.yaml  postgres.yaml  vertica-comptes.sql`

## Étape 2 — On crée le namespace de Neurons {#namespace}

Tout Neurons vivra dans ce namespace.

```bash
kubectl create namespace neurons
```

## Étape 3 — On donne au cluster l'accès aux images {#registre}

Ce secret sert à télécharger les images, à l'installation comme à chaque redémarrage : il **reste** dans le cluster. Remplacez les trois valeurs par celles fournies par Confoline :

```bash
kubectl -n neurons create secret docker-registry neurones-registry --docker-server='<À REMPLIR : registre>' --docker-username='<À REMPLIR : identifiant>' --docker-password='<À REMPLIR : mot de passe>'
```

## Étape 4 — On prépare la base Vertica {#vertica}

### Les valeurs de votre Vertica

```bash
export VERTICA_HOST='<À REMPLIR : serveur Vertica>'
```

```bash
export VERTICA_DB='<À REMPLIR : nom de la base Vertica>'
```

Les mots de passe des deux comptes que Neurons va utiliser (rien ne s'affiche pendant la saisie) :

```bash
read -rs -p "Mot de passe a creer pour neurones_reader : " LECTEUR_MDP; echo
```

```bash
read -rs -p "Mot de passe a creer pour neurones_writer : " ECRIVAIN_MDP; echo
```

### On crée le schéma apm et ses 89 tables

Le mot de passe de `dbadmin` est demandé.

```bash
vsql -h "$VERTICA_HOST" -d "$VERTICA_DB" -U dbadmin -f apm-tables.sql
```

### On crée les deux comptes de Neurons

Un compte **lecteur** et un compte **écrivain** : Neurons n'utilise jamais `dbadmin`.

```bash
vsql -h "$VERTICA_HOST" -d "$VERTICA_DB" -U dbadmin -v lecteur_mdp="'$LECTEUR_MDP'" -v ecrivain_mdp="'$ECRIVAIN_MDP'" -f vertica-comptes.sql
```

### On vérifie

```bash
vsql -h "$VERTICA_HOST" -d "$VERTICA_DB" -U dbadmin -c "SELECT COUNT(*) FROM v_catalog.tables WHERE table_schema = 'apm';"
```

Attendu : **89**.

## Étape 5 — On crée les secrets des applications {#secrets}

### Les valeurs générées automatiquement

Le mot de passe de PostgreSQL :

```bash
export POSTGRES_MDP=$(openssl rand -hex 16)
```

Le jeton d'ingestion, qui protège la réception des traces :

```bash
export JETON=$(openssl rand -hex 32)
```

### Le certificat HTTPS de votre domaine

```bash
export CERTIFICAT='<À REMPLIR : chemin du certificat, ex. /root/neurons.crt>'
```

```bash
export CLE='<À REMPLIR : chemin de la cle privee, ex. /root/neurons.key>'
```

### On crée les 5 secrets

```bash
kubectl -n neurons create secret generic postgres-secret --from-literal=POSTGRES_DB=neurones --from-literal=POSTGRES_USER=postgres --from-literal=POSTGRES_PASSWORD="$POSTGRES_MDP"
```

```bash
kubectl -n neurons create secret generic apm-secret --from-literal=VERTICA_PASSWORD="$ECRIVAIN_MDP" --from-literal=NEURONES_INGEST_TOKEN="$JETON" --from-literal=APM_ALERT_EMAIL_PASSWORD=''
```

```bash
kubectl -n neurons create secret generic neurones-backend-secret --from-literal=SECRET_KEY="$(openssl rand -hex 32)" --from-literal=CMDB_SECRET_KEYS="$(openssl rand -base64 32 | tr '+/' '-_')" --from-literal=VERTICA_PASSWORD="$LECTEUR_MDP"
```

```bash
kubectl -n neurons create secret generic neurones-frontend-secret --from-literal=APM_TOKEN="$JETON" --from-literal=GEMINI_API_KEY=''
```

```bash
kubectl -n neurons create secret tls neurones-tls --cert="$CERTIFICAT" --key="$CLE"
```

## Étape 6 — On déploie PostgreSQL {#postgres}

```bash
kubectl -n neurons apply -f postgres.yaml
```

On attend qu'il soit prêt :

```bash
kubectl -n neurons rollout status statefulset/postgres --timeout=300s
```

## Étape 7 — On crée la structure de la base PostgreSQL {#migrations}

### L'image du backend

```bash
export IMAGE_BACKEND='<À REMPLIR : image backend de la liste Confoline>'
```

### On lance les migrations

```bash
sed -e "s|__IMAGE_BACKEND__|$IMAGE_BACKEND|" -e "s|__VERTICA_HOST__|$VERTICA_HOST|" -e "s|__VERTICA_DB__|$VERTICA_DB|" migrations.yaml | kubectl -n neurons apply -f -
```

On attend la fin :

```bash
kubectl -n neurons wait --for=condition=complete job/neurones-migrations --timeout=600s
```

On vérifie :

```bash
kubectl -n neurons logs job/neurones-migrations | tail -2
```

Attendu : la dernière ligne indique la dernière migration (`... -> 9a4f6b2e7c15`).

## Étape 8 — On crée l'administrateur et la connexion à Vertica {#admin}

{{< callout type="warn" >}}À faire **avant** l'étape 9 : sinon, l'application crée elle-même une connexion Vertica incomplète, et la réception des traces ne pourra pas écrire.{{< /callout >}}

### Le premier administrateur de Neurons

```bash
export ADMIN_EMAIL='<À REMPLIR : email de l administrateur>'
```

```bash
read -rs -p "Mot de passe de l'administrateur Neurons : " ADMIN_MDP; echo
```

### On les enregistre dans PostgreSQL

Ce bloc se copie **en entier** : c'est un seul envoi à PostgreSQL.

```bash
kubectl -n neurons exec -i postgres-0 -- psql -U postgres -d neurones -v ON_ERROR_STOP=1 <<EOF
CREATE EXTENSION IF NOT EXISTS pgcrypto;
INSERT INTO users (id, email, hashed_password, is_active, is_admin) VALUES (gen_random_uuid(), '$ADMIN_EMAIL', crypt('$ADMIN_MDP', gen_salt('bf', 12)), true, true);
INSERT INTO databases_config (name, db_type, host, port, username, password, database, is_active) VALUES ('neurones', 'postgresql', 'postgres', 5432, 'postgres', '$POSTGRES_MDP', 'neurones', true);
INSERT INTO databases_config (name, db_type, host, port, username, password, database, reader_username, reader_password, writer_username, writer_password, is_active) VALUES ('$VERTICA_DB', 'vertica', '$VERTICA_HOST', 5433, 'neurones_reader', '$LECTEUR_MDP', '$VERTICA_DB', 'neurones_reader', '$LECTEUR_MDP', 'neurones_writer', '$ECRIVAIN_MDP', true);
EOF
```

Attendu : `CREATE EXTENSION`, puis trois fois `INSERT 0 1`.

## Étape 9 — On déploie les applications de Neurons {#applications}

### Votre domaine et les deux autres images

```bash
export DOMAINE='<À REMPLIR : domaine, ex. neurons.votre-domaine.com>'
```

```bash
export IMAGE_FRONTEND='<À REMPLIR : image frontend de la liste Confoline>'
```

```bash
export IMAGE_APM='<À REMPLIR : image apm-ingest de la liste Confoline>'
```

### On déploie

```bash
sed -e "s|__DOMAINE__|$DOMAINE|g" -e "s|__VERTICA_HOST__|$VERTICA_HOST|g" -e "s|__VERTICA_DB__|$VERTICA_DB|g" -e "s|__IMAGE_BACKEND__|$IMAGE_BACKEND|g" -e "s|__IMAGE_FRONTEND__|$IMAGE_FRONTEND|g" -e "s|__IMAGE_APM__|$IMAGE_APM|g" applications.yaml | kubectl -n neurons apply -f -
```

On attend que les 6 applications soient prêtes :

```bash
kubectl -n neurons wait --for=condition=available deployment --all --timeout=300s
```

## Étape 10 — On vérifie que Neurons tourne {#verifier}

Les pods :

```bash
kubectl -n neurons get pods
```

Attendu : les 6 applications et `postgres-0` en `Running`.

Les routes web :

```bash
kubectl -n neurons get ingress
```

Attendu : une adresse dans la colonne `ADDRESS`.

Si la colonne `ADDRESS` est encore vide, ou si une des vérifications suivantes répond `503`, les routes ne sont pas encore prises en compte : attendez une minute, puis relancez.

La page d'accueil :

```bash
curl -k -s -o /dev/null -w '%{http_code}\n' "https://$DOMAINE/"
```

Attendu : `200`.

L'API d'administration, sans connexion :

```bash
curl -k -s -o /dev/null -w '%{http_code}\n' "https://$DOMAINE/api/admin/databases/connected"
```

Attendu : `401` (fermée).

La réception des traces, sans jeton :

```bash
curl -k -s -o /dev/null -w '%{http_code}\n' -X POST "https://$DOMAINE/v1/traces"
```

Attendu : `401` (fermée).

Ouvrez enfin `https://<votre domaine>` et connectez-vous avec l'administrateur de l'étape 8.

## Étape 11 — On relie les collecteurs OpenTelemetry {#collecteurs}

Le jeton d'ingestion (à garder secret) :

```bash
echo "$JETON"
```

Ajoutez cet exportateur à la configuration de vos collecteurs, puis redémarrez-les :

```yaml
exporters:
  otlphttp/neurones:
    endpoint: https://<votre domaine>
    encoding: json                 # obligatoire : Neurons ne lit que le JSON
    headers:
      X-Neurones-Token: <jeton d'ingestion>
```

Pour retrouver le jeton plus tard, dans un autre terminal :

```bash
kubectl -n neurons get secret apm-secret -o jsonpath='{.data.NEURONES_INGEST_TOKEN}' | base64 -d; echo
```
