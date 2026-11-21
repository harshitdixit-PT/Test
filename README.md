# Test

## Run Gravitee APIM on your Mac

This local Community Edition setup runs the APIM Gateway, Management API, Console, and Developer Portal in Docker Compose. A bundled Helm chart installs MongoDB in Docker Desktop Kubernetes and stores its data in a persistent volume. Elasticsearch-backed analytics and request reporting are disabled. The first launch downloads public container images.

### Prerequisites

- Start Docker Desktop and enable its Kubernetes cluster.
- Install Helm and make sure `kubectl --context docker-desktop get nodes` shows a ready node.
- Free local ports 27017 and 8082–8085. Use a dedicated local cluster because MongoDB runs without authentication.

### Start the stack

From the repository root, install MongoDB into Docker Desktop's cluster.

```sh
helm upgrade --install mongodb ./charts/mongodb --kube-context docker-desktop \
  --namespace gravitee-local --create-namespace --wait --timeout 5m
```

Run the port-forward and leave this terminal open while using APIM. The Compose containers reach this Mac-side listener through Docker Desktop's `host.docker.internal` hostname.

```sh
kubectl --context docker-desktop --namespace gravitee-local \
  port-forward service/mongodb 27017:27017
```

In a second terminal, from the repository root, start APIM.

```sh
docker compose up -d
docker compose ps
```

Open the Console at [localhost:8084](http://localhost:8084) or the Developer Portal at [localhost:8085](http://localhost:8085). The default local login is `admin` / `admin`. The Gateway listens on port 8082 and the Management API listens on port 8083.

If the UI loads before the Management API is ready, wait for initialization and refresh. To diagnose startup or database connectivity issues, confirm that the port-forward is running and check `docker compose logs gateway management-api`.

### Stop the stack

Run `docker compose down` and stop the port-forward with Ctrl+C. MongoDB remains installed with its data so you can restart APIM by reopening the port-forward and running Compose again.
