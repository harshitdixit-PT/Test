# Test

## Run Gravitee APIM on your Mac

Docker Compose runs the Gateway, Management API, Console, and Developer Portal. A dedicated local kind cluster runs MongoDB from the bundled Helm chart. Elasticsearch-backed analytics and request reporting are disabled.

### Prerequisites

- Install and start Docker Desktop.
- Install kind, Helm, and kubectl, for example with `brew install kind helm kubectl`.
- Free local ports 27017 and 8082–8085. The first startup downloads public images.

### Start

From the cloned repository:

```sh
make up
```

Open the [Console](http://localhost:8084) or the [Developer Portal](http://localhost:8085). Sign in with `admin` / `admin`.

`make up` reuses the `gravitee-local` kind cluster if it already exists. It uses a separate kubeconfig at `~/.kube/gravitee-local-kind.yaml` and starts a background loopback port-forward for MongoDB. For port-forward diagnostics, see `~/.kube/gravitee-local-mongodb-forward.log`.

### Stop and remove

```sh
make down
```

This removes the Compose services and network, stops the MongoDB port-forward, and deletes the dedicated kind cluster **including its MongoDB data**. The next `make up` starts with an empty database.
