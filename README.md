# Test

## Run Gravitee APIM on your Mac

Docker Compose defaults to Gravitee APIM `4.12.27` and runs the Gateway, Management API, Console, and Developer Portal. A dedicated local kind cluster runs MongoDB from the bundled Helm chart. Elasticsearch-backed analytics and request reporting are disabled.

For a step-by-step setup without Make, see the [manual deployment guide](manual/README.md).

### Prerequisites

- Install and start Docker Desktop.
- Install kind, Helm, and kubectl, for example with `brew install kind helm kubectl`.
- Free local ports 27017 and 8082–8085. The first startup downloads public images.

### Start

For a lab with an existing 4.10.38 database, follow the [in-place upgrade procedure](#upgrade-an-existing-41038-lab) first.

From the cloned repository:

```sh
make up
```

Open the [Console](http://localhost:8084) or the [Developer Portal](http://localhost:8085). Sign in with `admin` / `admin`.

`make up` reuses the `gravitee-local` kind cluster if it already exists. It uses a separate kubeconfig at `~/.kube/gravitee-local-kind.yaml` and starts a background loopback port-forward for MongoDB. For port-forward diagnostics, see `~/.kube/gravitee-local-mongodb-forward.log`.

### Upgrade an existing 4.10.38 lab

Review your APIs and portal content while 4.10.38 is still running. Migrate any V1 APIs before starting 4.12.27. Record a working Gateway route and its expected response, and inventory New Developer Portal navigation and documentation for verification and republication. [4.11 release notes](https://github.com/gravitee-io/gravitee-platform-docs/blob/main/docs/apim/4.11/release-information/release-notes/apim-4.11.md) · [4.12 release notes](https://github.com/gravitee-io/gravitee-platform-docs/blob/main/docs/apim/4.12/release-information/release-notes/apim-4.12.md)

Run the upgrade from the existing Compose project directory with the MongoDB port-forward active. This procedure upgrades the lab to 4.12.27. Pull the upgrade and rollback images before starting downtime. Keep the same shell for the commands below.

```sh
APIM_VERSION=4.10.38 docker compose pull &&
APIM_VERSION=4.12.27 docker compose pull
```

After the pulls succeed, stop APIM and back up its MongoDB database. The local kind cluster and port-forward must stay up throughout. `make down` deletes the cluster and its MongoDB data.

```sh
lab_mongo() {
  kubectl --kubeconfig "$HOME/.kube/gravitee-local-kind.yaml" \
    --context kind-gravitee-local --namespace gravitee-local exec mongodb-0 "$@"
}

umask 077
backup_dir=$(mktemp -d "${TMPDIR:-/tmp}/gravitee-apim.XXXXXXXX") &&
backup="$backup_dir/gravitee-4.10.38.archive.gz" &&
docker compose stop &&
lab_mongo -- mongodump --db gravitee --archive --gzip > "$backup" &&
test -s "$backup" &&
gzip -t "$backup" &&
lab_mongo -i -- mongorestore --archive --gzip --dryRun --nsInclude 'gravitee.*' < "$backup" &&
printf 'Backup verified at %s\n' "$backup"
```

Continue only after the backup check succeeds. Move the archive to a private, durable location and set `backup` to its new path before proceeding. Start the Management API on 4.12.27.

```sh
export APIM_VERSION=4.12.27
docker compose up -d --no-deps management-api
docker compose logs --tail=150 management-api
curl -fsS http://localhost:8083/portal/environments/DEFAULT/configuration >/dev/null
```

Wait for the Management API to finish starting, review its logs for migration errors, and confirm that the Portal API check succeeds. Then start the remaining services and verify the lab.

```sh
docker compose up -d --wait --wait-timeout 180 gateway console portal
docker compose ps
curl -fsS http://localhost:8084/ >/dev/null
curl -fsS http://localhost:8085/ >/dev/null
```

Sign in to the Console, check that your APIs and applications are present, and call your recorded Gateway route. Republish affected New Developer Portal content through **Navigation items**, then verify subscriptions and documentation links you use. Complete these checks on 4.12.27 before preparing the next upgrade to 4.13.6.

#### Roll back to 4.10.38

If you decide to roll back after migrations start, first stop APIM and verify that the original archive still passes the dry run. The database drop below removes all changes made since the backup. It targets only the `gravitee` database in this lab. Wait for the restore to succeed before starting the old images.

```sh
docker compose stop &&
test -s "$backup" &&
gzip -t "$backup" &&
lab_mongo -i -- mongorestore --archive --gzip --dryRun --nsInclude 'gravitee.*' < "$backup" &&
lab_mongo -- mongosh gravitee --quiet --eval 'quit(db.dropDatabase().ok === 1 ? 0 : 1)' &&
lab_mongo -i -- mongorestore --archive --gzip --stopOnError --nsInclude 'gravitee.*' < "$backup"
```

Set `export APIM_VERSION=4.10.38` and repeat the Management API startup and smoke checks above. Keep the override set when starting the rolled-back lab.

### Stop and remove

```sh
make down
```

This removes the Compose services and network, stops the MongoDB port-forward, and deletes the dedicated kind cluster **including its MongoDB data**. The next `make up` starts with an empty database.
