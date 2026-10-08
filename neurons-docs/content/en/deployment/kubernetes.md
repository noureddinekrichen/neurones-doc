---
title: Deploy Neurons on Your Kubernetes Cluster
linkTitle: Kubernetes
lede: Deploy Neurons on your own cluster from the official images provided by Confoline, step by step, up to the first login.
menus:
  onboarding:
    parent: deployment
    weight: 10
labels:
  prerequis: Prerequisites
  fichiers: Deployment files
  namespace: Namespace
  registre: Image access
  vertica: Vertica database
  secrets: Secrets
  postgres: PostgreSQL
  migrations: Database structure
  admin: Administrator
  applications: Applications
  verifier: Checks
  collecteurs: Collectors
---

This guide deploys **Neurons** on your own server and your own Kubernetes cluster, from the **official images provided by Confoline**. At the end, Neurons is available over HTTPS on your domain, connected to your Vertica database and ready to receive traces from your applications.

{{< callout type="warn" >}}Run **every command in the same terminal**, without closing it: values entered at one step are reused by the next ones. One command per block: copy and run the blocks one at a time.{{< /callout >}}

{{< callout >}}Faster: Confoline can also provide an automatic installer, `installer-neurones.sh`, which performs all these steps by asking a few questions.{{< /callout >}}

## Before you start: what you need {#prerequis}

**Provided by Confoline:** the image registry address and its credentials (read-only), and the **list of images** for your version (backend, frontend, apm-ingest).

**On your side:**

- a machine with **`kubectl`** (cluster administrator), **`vsql`** (the Vertica client), **`openssl`** and **`curl`**;
- a Kubernetes cluster, **version 1.27 or later**, with **ingress-nginx** and a default **StorageClass**;
- at least **1.5 CPU cores** and **3.5 GB** of free memory;
- a **Vertica administrator** account (`dbadmin`), and the Vertica port reachable from the cluster;
- the Neurons **domain**, and its **HTTPS certificate** with its private key (PEM files).

Values to replace are marked **`<TO FILL>`**.

## Step 1 — Download the deployment files {#fichiers}

| File | Content | Step |
|---|---|---|
| [`apm-tables.sql`](../../files/deployment/apm-tables.sql) | the `apm` schema and its 89 tables | 4 |
| [`vertica-comptes.sql`](../../files/deployment/vertica-comptes.sql) | the two Neurons Vertica accounts and their privileges | 4 |
| [`postgres.yaml`](../../files/deployment/postgres.yaml) | PostgreSQL | 6 |
| [`migrations.yaml`](../../files/deployment/migrations.yaml) | creation of the PostgreSQL tables | 7 |
| [`applications.yaml`](../../files/deployment/applications.yaml) | the 6 applications and their web routes | 9 |
{mono="1"}

They contain no password: only placeholders (`__DOMAINE__`…) that are automatically replaced with your values at deployment time. Click a file name to view it; the command below downloads all of them to the server.

Create a working directory:

```bash
mkdir neurons-deploiement && cd neurons-deploiement
```

Download the 5 files:

```bash
for f in apm-tables.sql vertica-comptes.sql postgres.yaml migrations.yaml applications.yaml; do curl -fsSLO "https://docs.confoline.com/neurons/files/deployment/$f"; done
```

Check that they are there:

```bash
ls
```

Expected: `apm-tables.sql  applications.yaml  migrations.yaml  postgres.yaml  vertica-comptes.sql`

## Step 2 — Create the Neurons namespace {#namespace}

All of Neurons will live in this namespace.

```bash
kubectl create namespace neurons
```

## Step 3 — Give the cluster access to the images {#registre}

This secret is used to download the images, at installation and on every restart: it **stays** in the cluster. Replace the three values with those provided by Confoline:

```bash
kubectl -n neurons create secret docker-registry neurones-registry --docker-server='<TO FILL: registry>' --docker-username='<TO FILL: username>' --docker-password='<TO FILL: password>'
```

## Step 4 — Prepare the Vertica database {#vertica}

### Your Vertica values

```bash
export VERTICA_HOST='<TO FILL: Vertica server>'
```

```bash
export VERTICA_DB='<TO FILL: Vertica database name>'
```

The passwords of the two accounts Neurons will use (nothing is displayed while typing). Avoid the characters `'`, `$`, `\` and the backtick in these passwords: they would break the following commands.

```bash
read -rs -p "Password to create for neurones_reader: " LECTEUR_MDP; echo
```

```bash
read -rs -p "Password to create for neurones_writer: " ECRIVAIN_MDP; echo
```

### Create the apm schema and its 89 tables

The `dbadmin` password is requested, on each of the three `vsql` commands of this step.

```bash
vsql -h "$VERTICA_HOST" -d "$VERTICA_DB" -U dbadmin -f apm-tables.sql
```

### Create the two Neurons accounts

A **reader** account and a **writer** account: Neurons never uses `dbadmin`.

```bash
vsql -h "$VERTICA_HOST" -d "$VERTICA_DB" -U dbadmin -v lecteur_mdp="'$LECTEUR_MDP'" -v ecrivain_mdp="'$ECRIVAIN_MDP'" -f vertica-comptes.sql
```

### Check

```bash
vsql -h "$VERTICA_HOST" -d "$VERTICA_DB" -U dbadmin -c "SELECT COUNT(*) FROM v_catalog.tables WHERE table_schema = 'apm';"
```

Expected: **89**.

## Step 5 — Create the application secrets {#secrets}

### Automatically generated values

The PostgreSQL password:

```bash
export POSTGRES_MDP=$(openssl rand -hex 16)
```

The ingestion token, which protects trace reception:

```bash
export JETON=$(openssl rand -hex 32)
```

### The HTTPS certificate of your domain

Give the **path of the file** (for example `/root/neurons.crt`), not its contents.

```bash
export CERTIFICAT='<TO FILL: certificate path, e.g. /root/neurons.crt>'
```

```bash
export CLE='<TO FILL: private key path, e.g. /root/neurons.key>'
```

### Create the 5 secrets

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

## Step 6 — Deploy PostgreSQL {#postgres}

```bash
kubectl -n neurons apply -f postgres.yaml
```

Wait until it is ready:

```bash
kubectl -n neurons rollout status statefulset/postgres --timeout=300s
```

## Step 7 — Create the PostgreSQL database structure {#migrations}

### The backend image

```bash
export IMAGE_BACKEND='<TO FILL: backend image from the Confoline list>'
```

### Run the migrations

```bash
sed -e "s|__IMAGE_BACKEND__|$IMAGE_BACKEND|" -e "s|__VERTICA_HOST__|$VERTICA_HOST|" -e "s|__VERTICA_DB__|$VERTICA_DB|" migrations.yaml | kubectl -n neurons apply -f -
```

Wait until they finish:

```bash
kubectl -n neurons wait --for=condition=complete job/neurones-migrations --timeout=600s
```

Check:

```bash
kubectl -n neurons logs job/neurones-migrations | tail -2
```

Expected: the last line shows the latest migration (`... -> 9a4f6b2e7c15`).

## Step 8 — Create the administrator and the Vertica connection {#admin}

{{< callout type="warn" >}}Do this **before** step 9: otherwise the application creates an incomplete Vertica connection by itself, and trace reception will not be able to write.{{< /callout >}}

### The first Neurons administrator

```bash
export ADMIN_EMAIL='<TO FILL: administrator email>'
```

Use a validly formed email address: reserved domains (`.test`, `.local`, `.invalid`) are accepted when stored, but **rejected at login**.

```bash
read -rs -p "Neurons administrator password: " ADMIN_MDP; echo
```

Same rule: no `'`, `$`, `\` or backtick in this password.

### Store them in PostgreSQL

Copy this block **as a whole**: it is a single call to PostgreSQL.

```bash
kubectl -n neurons exec -i postgres-0 -- psql -U postgres -d neurones -v ON_ERROR_STOP=1 <<EOF
CREATE EXTENSION IF NOT EXISTS pgcrypto;
INSERT INTO users (id, email, hashed_password, is_active, is_admin) VALUES (gen_random_uuid(), '$ADMIN_EMAIL', crypt('$ADMIN_MDP', gen_salt('bf', 12)), true, true);
INSERT INTO databases_config (name, db_type, host, port, username, password, database, is_active) VALUES ('neurones', 'postgresql', 'postgres', 5432, 'postgres', '$POSTGRES_MDP', 'neurones', true);
INSERT INTO databases_config (name, db_type, host, port, username, password, database, reader_username, reader_password, writer_username, writer_password, is_active) VALUES ('$VERTICA_DB', 'vertica', '$VERTICA_HOST', 5433, 'neurones_reader', '$LECTEUR_MDP', '$VERTICA_DB', 'neurones_reader', '$LECTEUR_MDP', 'neurones_writer', '$ECRIVAIN_MDP', true);
EOF
```

Expected: `CREATE EXTENSION`, then `INSERT 0 1` three times.

## Step 9 — Deploy the Neurons applications {#applications}

### Your domain and the two other images

```bash
export DOMAINE='<TO FILL: domain, e.g. neurons.your-domain.com>'
```

```bash
export IMAGE_FRONTEND='<TO FILL: frontend image from the Confoline list>'
```

```bash
export IMAGE_APM='<TO FILL: apm-ingest image from the Confoline list>'
```

### Deploy

```bash
sed -e "s|__DOMAINE__|$DOMAINE|g" -e "s|__VERTICA_HOST__|$VERTICA_HOST|g" -e "s|__VERTICA_DB__|$VERTICA_DB|g" -e "s|__IMAGE_BACKEND__|$IMAGE_BACKEND|g" -e "s|__IMAGE_FRONTEND__|$IMAGE_FRONTEND|g" -e "s|__IMAGE_APM__|$IMAGE_APM|g" applications.yaml | kubectl -n neurons apply -f -
```

Wait until the 6 applications are ready:

```bash
kubectl -n neurons wait --for=condition=available deployment --all --timeout=300s
```

## Step 10 — Check that Neurons is running {#verifier}

The pods:

```bash
kubectl -n neurons get pods
```

Expected: the 6 applications and `postgres-0` in `Running`.

The web routes:

```bash
kubectl -n neurons get ingress
```

Expected: an address in the `ADDRESS` column.

If the `ADDRESS` column is still empty, or if one of the following checks returns `503`, the routes are not active yet: wait a minute, then run it again.

The home page:

```bash
curl -k -s -o /dev/null -w '%{http_code}\n' "https://$DOMAINE/"
```

Expected: `200`.

The administration API, without logging in:

```bash
curl -k -s -o /dev/null -w '%{http_code}\n' "https://$DOMAINE/api/admin/databases/connected"
```

Expected: `401` (closed).

Trace reception, without a token:

```bash
curl -k -s -o /dev/null -w '%{http_code}\n' -X POST "https://$DOMAINE/v1/traces"
```

Expected: `401` (closed).

Finally, open `https://<your domain>` and log in with the administrator from step 8.

## Step 11 — Connect the OpenTelemetry collectors {#collecteurs}

The ingestion token (keep it secret):

```bash
echo "$JETON"
```

Add this exporter to your collectors' configuration, then restart them:

```yaml
exporters:
  otlphttp/neurones:
    endpoint: https://<your domain>
    encoding: json                 # required: Neurons only reads JSON
    headers:
      X-Neurones-Token: <ingestion token>
```

To find the token again later, from another terminal:

```bash
kubectl -n neurons get secret apm-secret -o jsonpath='{.data.NEURONES_INGEST_TOKEN}' | base64 -d; echo
```
