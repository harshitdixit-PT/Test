# Deploy Gravitee APIM manually on macOS

Run Gravitee APIM Community Edition on your Mac with Docker Desktop. The Gateway, Management API, Console, and Developer Portal run in Docker Compose. MongoDB runs in a dedicated kind cluster on the same Docker engine. The bundled Compose file defaults to APIM 4.8.0, and the bundled Helm chart uses MongoDB 7.0. The first run downloads public images. All runtime services are local. [Gravitee APIM 4.8 Docker Compose guide](https://documentation.gravitee.io/apim/4.8/self-hosted-installation-guides/docker/docker-compose)

## 1. Install the tools and start Docker Desktop

Install [Docker Desktop for Mac](https://docs.docker.com/desktop/setup/install/mac-install/) and open it. With [Homebrew](https://brew.sh/) installed, install the remaining tools in **Terminal 1**.

```sh
brew install kind helm kubectl
```

kind creates a Kubernetes cluster from Docker containers. Helm installs the MongoDB chart, and kubectl checks Kubernetes resources and forwards the database port. kind uses Docker Desktop's engine, so you can leave Docker Desktop's built-in Kubernetes feature disabled. [kind Quick Start](https://kind.sigs.k8s.io/docs/user/quick-start/)

Make the Docker Desktop CLI available and point it at the desktop engine. These exports apply to Terminal 1.

```sh
export PATH="$HOME/.docker/bin:$PATH"
unset DOCKER_CONTEXT
export DOCKER_HOST="unix://$HOME/.docker/run/docker.sock"

docker version
docker compose version
git --version
kind version
helm version
kubectl version --client
```

`docker version` should show a **Server** section, and `docker compose version` should report Compose v2. If Git is missing, use `xcode-select --install` to install Apple's Command Line Tools and retry. If Docker reports that Compose is unavailable, use the bundled executable at `/Applications/Docker.app/Contents/Resources/cli-plugins/docker-compose` in place of `docker compose` throughout this guide. For a user-local Docker Desktop install, use `$HOME/Applications/Docker.app/Contents/Resources/cli-plugins/docker-compose` instead.

The stack needs local ports **27017 and 8082–8085**. Check for listeners before continuing.

```sh
lsof -nP -iTCP:27017 -iTCP:8082-8085 -sTCP:LISTEN
```

No output means the required ports are free. If this repository's automated stack is already running, you can keep using that deployment. Before replacing it with a fresh manual deployment, back up any data you need. Stopping it with `make down` deletes its kind cluster and MongoDB data. [Docker Desktop permissions and local socket on Mac](https://docs.docker.com/desktop/setup/install/mac-permission-requirements/)

## 2. Clone the repository

Clone into a new directory. If you already have the repo, go to that checkout instead and use the same directory for Compose startup and teardown.

```sh
cd "$HOME/Documents"
git clone https://github.com/harshitdixit-PT/Test.git gravite-docker-stack
cd gravite-docker-stack
```

The repository root contains [`compose.yaml`](../compose.yaml) for APIM and [`charts/mongodb`](../charts/mongodb) for MongoDB.

## 3. Create a local kind cluster

Create the cluster and write its credentials to a dedicated kubeconfig. The explicit context in the verification commands keeps your regular Kubernetes context separate.

```sh
mkdir -p "$HOME/.kube"
export GRAVITEE_KUBECONFIG="$HOME/.kube/gravitee-local-kind.yaml"

kind create cluster --name gravitee-local \
  --kubeconfig "$GRAVITEE_KUBECONFIG" --wait 5m

kubectl --kubeconfig "$GRAVITEE_KUBECONFIG" \
  --context kind-gravitee-local get nodes

kubectl --kubeconfig "$GRAVITEE_KUBECONFIG" \
  --context kind-gravitee-local get storageclass
```

Wait for the node to show `Ready`. The default storage class provisions the persistent volume used by MongoDB. If a cluster named `gravitee-local` already exists and belongs to this project, retrieve its kubeconfig with `kind export kubeconfig --name gravitee-local --kubeconfig "$GRAVITEE_KUBECONFIG"` and run the verification commands. [kind Quick Start](https://kind.sigs.k8s.io/docs/user/quick-start/)

## 4. Install MongoDB with Helm

Run these commands from the repo root in Terminal 1.

```sh
helm lint ./charts/mongodb

helm upgrade --install mongodb ./charts/mongodb \
  --kubeconfig "$GRAVITEE_KUBECONFIG" --kube-context kind-gravitee-local \
  --namespace gravitee-local --create-namespace --wait --timeout 15m

kubectl --kubeconfig "$GRAVITEE_KUBECONFIG" --context kind-gravitee-local \
  --namespace gravitee-local get statefulset,pod,service,pvc
```

Lint checks the chart. The Helm command creates or updates the release in the `gravitee-local` namespace and waits for it to be ready. The chart creates one MongoDB replica, a Service on port 27017, and a 2 GiB persistent volume claim. Expect `mongodb-0` to be `1/1 Running` and its claim to be `Bound`. MongoDB runs without authentication in this dedicated local cluster. [Helm upgrade reference](https://helm.sh/docs/helm/helm_upgrade/) · [Gravitee APIM 4.8 repositories](https://documentation.gravitee.io/apim/4.8/prepare-a-production-environment/repositories)

## 5. Forward MongoDB to the Mac

Open **Terminal 2** and run the following in the foreground. Leave this terminal open while APIM is running.

```sh
kubectl --kubeconfig "$HOME/.kube/gravitee-local-kind.yaml" \
  --context kind-gravitee-local --namespace gravitee-local \
  port-forward --address 127.0.0.1 service/mongodb 27017:27017
```

Expect `Forwarding from 127.0.0.1:27017 -> 27017`. The forward exposes MongoDB on Mac loopback. The APIM containers reach it through Docker Desktop's `host.docker.internal` hostname. [kubectl port-forward reference](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_port-forward/) · [Docker Desktop host networking](https://docs.docker.com/desktop/features/networking/networking-how-tos/#connect-a-container-to-a-service-on-the-host)

## 6. Start Gravitee with Docker Compose

Return to **Terminal 1** in the repo root.

```sh
nc -z 127.0.0.1 27017
docker compose config --services
docker compose pull
docker compose up -d --wait --wait-timeout 180
docker compose ps
```

The first command checks the MongoDB listener. Compose validates the project, downloads the four APIM images, and starts the services in the background. `docker compose ps` shows container state and published ports. [Gravitee APIM 4.8 Docker Compose guide](https://documentation.gravitee.io/apim/4.8/self-hosted-installation-guides/docker/docker-compose) · [Docker Compose up reference](https://docs.docker.com/reference/cli/docker/compose/up/)

The repository's Compose configuration connects the Gateway and Management API to `mongodb://host.docker.internal:27017/gravitee?directConnection=true`. The Gateway also uses MongoDB for rate limits. The Management API sets `gravitee_analytics_type=none`, and the Gateway sets `gravitee_reporters_elasticsearch_enabled=false`. Elasticsearch-backed analytics and request reporting are unavailable in this setup. [Gravitee Management API configuration](https://documentation.gravitee.io/apim/4.8/configure-and-manage-the-platform/management-api) · [Gravitee Gateway configuration](https://documentation.gravitee.io/apim/4.8/configure-and-manage-the-platform/gravitee-gateway) · [Gravitee example disabling the Elasticsearch reporter](https://documentation.gravitee.io/apim/4.8/hybrid-installation-and-configuration-guides/classic-cloud/docker/docker-compose)

## 7. Open and verify Gravitee

| Component | Local address | Purpose |
| --- | --- | --- |
| Management Console | [http://localhost:8084](http://localhost:8084) | Create and manage APIs in the browser |
| Developer Portal | [http://localhost:8085](http://localhost:8085) | Browse published APIs |
| Management API | `http://localhost:8083` | Backend for the Console and Portal |
| API Gateway | `http://localhost:8082` | Serve deployed API routes |

Sign in to the Console with username `admin` and password `admin`. The Portal can also be opened with those local credentials. For a quick check from Terminal 1, run the following. The Console, Portal, and Portal configuration endpoint should return HTTP 200.

```sh
curl -sS -o /dev/null -w 'Console %{http_code}\n' http://localhost:8084/
curl -sS -o /dev/null -w 'Portal %{http_code}\n' http://localhost:8085/
curl -sS -o /dev/null -w 'Portal API %{http_code}\n' \
  http://localhost:8083/portal/environments/DEFAULT/configuration
```

The Gateway root can return HTTP 404 on a fresh deployment. To exercise the Gateway, create and deploy a test API and call its configured context path. [Gravitee APIM 4.8 local verification and credentials](https://documentation.gravitee.io/apim/4.8/getting-started/local-install-with-docker) · [Create and publish an API with Gravitee APIM 4.8](https://documentation.gravitee.io/apim/4.8/how-to-guides/use-case-tutorials/create-and-publish-an-api-using-the-management-api)

## 8. Diagnose startup problems

If a container stops or a browser page cannot reach the Management API, inspect the APIM logs in Terminal 1.

```sh
docker compose ps -a
docker compose logs --tail=100 management-api gateway
```

For MongoDB connection errors, check that Terminal 2 is still forwarding port 27017 and confirm the pod's state. If the forward has exited, restart it using step 5.

```sh
kubectl --kubeconfig "$GRAVITEE_KUBECONFIG" --context kind-gravitee-local \
  --namespace gravitee-local describe pod mongodb-0

kubectl --kubeconfig "$GRAVITEE_KUBECONFIG" --context kind-gravitee-local \
  --namespace gravitee-local logs mongodb-0
```

The pod events show scheduling, storage, and image pull status. MongoDB logs show database startup errors. [Gravitee APIM 4.8 Docker Compose guide](https://documentation.gravitee.io/apim/4.8/self-hosted-installation-guides/docker/docker-compose) · [Docker Compose logs reference](https://docs.docker.com/reference/cli/docker/compose/logs/)

## 9. Shut down or remove the stack

In Terminal 1, remove the APIM containers and their Compose network.

```sh
docker compose down
```

In Terminal 2, press **Ctrl+C** to stop the MongoDB port-forward. To keep your data, leave the kind cluster in place. To resume later, start Docker Desktop, restore the Terminal 1 environment from steps 1 and 3, then repeat steps 5 and 6.

For a full teardown, run the following in Terminal 1. **Deleting the cluster also deletes its MongoDB data.**

```sh
kind delete cluster --name gravitee-local --kubeconfig "$GRAVITEE_KUBECONFIG"
kind get clusters
docker compose ps -a
```

Confirm that `gravitee-local` is gone and Compose lists no APIM containers. [Docker Compose down reference](https://docs.docker.com/reference/cli/docker/compose/down/) · [kind cluster deletion](https://kind.sigs.k8s.io/docs/user/quick-start/#deleting-a-cluster)
