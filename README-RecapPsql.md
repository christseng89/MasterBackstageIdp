# Backstage IDP to Work with Local PostgreSQL

## Setup PostgreSQL for Backstage IDP

### Step 1 — Add the variables to `.env`

Open `D:\development\MasterBackstageIdp\.env` and append:

```bash
POSTGRES_HOST=host.docker.internal
POSTGRES_PORT=5432
POSTGRES_USER=backstage
POSTGRES_PASSWORD=<Your desired password here>
```

### Step 2 — Load `.env` in Git Bash

```bash
source .env

# sanity check
echo "user=$POSTGRES_USER"
echo "pass length=${#POSTGRES_PASSWORD}"
```

### Step 3 — Create the role

```bash
psql -U postgres \
  -c "CREATE ROLE $POSTGRES_USER WITH LOGIN PASSWORD '$POSTGRES_PASSWORD' CREATEDB;"
```

Enter the `postgres` superuser password when prompted.

### Step 4 — Verify

```bash
psql -U "$POSTGRES_USER" -d postgres -c "SELECT current_user;"
```

Type the `backstage` password — it should print `backstage`.

### If you ever need to change the password

```bash
source .env
psql -U postgres \
  -c "ALTER ROLE $POSTGRES_USER WITH PASSWORD '$POSTGRES_PASSWORD';"

psql -U "$POSTGRES_USER" -d postgres -c "SELECT current_user;"
```

## Setup Backstage IDP to Work with Local PostgreSQL

```yaml -> app-config.local.yaml 
backend:
  listen:
    host: 0.0.0.0
  # ↓ Add this — overrides the in-memory better-sqlite3 from app-config.yaml
  database:
    client: pg
    connection:
      host: ${POSTGRES_HOST}
      port: ${POSTGRES_PORT}
      user: ${POSTGRES_USER}
      password: ${POSTGRES_PASSWORD}
    # Optional: pin Backstage to one DB instead of letting each plugin create its own
    # pluginDivisionMode: schema   # or 'database' (default)
```

## Run Backstage IDP with Local PostgreSQL

```bash
cd backstage-app
mkdir techdocs-storage -p
source .env

docker run --rm --name backstage-local \
  -e GITHUB_TOKEN=$GITHUB_TOKEN \
  -e AUTH_GITHUB_CLIENT_ID=$AUTH_GITHUB_CLIENT_ID \
  -e AUTH_GITHUB_CLIENT_SECRET=$AUTH_GITHUB_CLIENT_SECRET \
  -e K8S_SA_TOKEN=$K8S_SA_TOKEN \
  -e POSTGRES_HOST=$POSTGRES_HOST \
  -e POSTGRES_PORT=$POSTGRES_PORT \
  -e POSTGRES_USER=$POSTGRES_USER \
  -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
  -e NODE_OPTIONS="--dns-result-order=ipv4first" \
  --add-host=host.docker.internal:host-gateway \
  -p 3000:3000 -ti -p 7007:7007 \
  -v //d/development/MasterBackstageIdp/backstage-app://app \
  -v //d/development/MasterBackstageIdp/backstage-app/techdocs-storage://app/techdocs-storage \
  -v //d/development/MasterBackstageIdp/backstage-app/templates://app/templates:ro \
  -w //app christseng89/node:24-bookwork-slim-pro bash
  ## Wait

  cd backstage
  yarn start
  # ▶ Backstage running at http://localhost:3000
```
