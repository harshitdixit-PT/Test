#!/usr/bin/env bash

cd "$(dirname "$0")/.." || exit 1
export PATH="$HOME/.local/bin:$HOME/.docker/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

cluster=gravitee-local
namespace=gravitee-local
kubeconfig="$HOME/.kube/gravitee-local-kind.yaml"
forward_label=local.gravitee.mongodb-forward
forward_log="$HOME/.kube/gravitee-local-mongodb-forward.log"

docker_app=/Applications/Docker.app
if [[ ! -d "$docker_app" ]]; then
  docker_app="$HOME/Applications/Docker.app"
fi
if [[ -x "$docker_app/Contents/Resources/bin/docker" ]]; then
  export PATH="$docker_app/Contents/Resources/bin:$PATH"
fi

if [[ ! -S "$HOME/.docker/run/docker.sock" ]]; then
  echo "Start Docker Desktop before running make $1." >&2
  exit 1
fi
export DOCKER_HOST="unix://$HOME/.docker/run/docker.sock"
unset DOCKER_CONTEXT

compose() {
  local bundled_compose="$docker_app/Contents/Resources/cli-plugins/docker-compose"
  if [[ -x "$bundled_compose" ]]; then
    "$bundled_compose" "$@"
  else
    docker compose "$@"
  fi
}

require_tools() {
  local tool
  for tool in "$@"; do
    if ! command -v "$tool" >/dev/null; then
      echo "Missing $tool. Install the prerequisites in README.md." >&2
      return 1
    fi
  done
}

stop_forward() {
  if launchctl list "$forward_label" >/dev/null 2>&1; then
    launchctl remove "$forward_label"
  fi
}

start_forward() {
  if launchctl list "$forward_label" 2>/dev/null | grep -q '"PID"' &&
    nc -z 127.0.0.1 27017; then
    return 0
  fi

  stop_forward || return 1
  if nc -z 127.0.0.1 27017; then
    echo "Port 27017 is already in use." >&2
    return 1
  fi

  launchctl submit -l "$forward_label" -o "$forward_log" -e "$forward_log" -- \
    "$(command -v kubectl)" --kubeconfig "$kubeconfig" --context "kind-$cluster" \
    --namespace "$namespace" port-forward --address 127.0.0.1 service/mongodb 27017:27017 || return 1

  local attempt
  for ((attempt = 0; attempt < 30; attempt++)); do
    if nc -z 127.0.0.1 27017; then
      return 0
    fi
    sleep 1
  done
  echo "MongoDB port-forward failed. See $forward_log." >&2
  return 1
}

up() {
  require_tools docker kind helm kubectl || return 1

  mkdir -p "$(dirname "$kubeconfig")" || return 1

  local clusters
  clusters=$(kind get clusters) || return 1
  if printf '%s\n' "$clusters" | grep -Fxq "$cluster"; then
    kind export kubeconfig --name "$cluster" --kubeconfig "$kubeconfig" || return 1
  else
    kind create cluster --name "$cluster" --kubeconfig "$kubeconfig" --wait 5m || return 1
  fi

  helm upgrade --install mongodb ./charts/mongodb --kubeconfig "$kubeconfig" \
    --kube-context "kind-$cluster" --namespace "$namespace" --create-namespace \
    --wait --timeout 15m || return 1
  start_forward || return 1
  compose up -d --wait --wait-timeout 180 || return 1
  printf 'Console: http://localhost:8084\nDeveloper Portal: http://localhost:8085\n'
}

down() {
  require_tools docker kind || return 1
  compose down || return 1
  stop_forward || return 1
  kind delete cluster --name "$cluster" --kubeconfig "$kubeconfig"
}

case "${1:-}" in
  up) up ;;
  down) down ;;
  *) echo "Usage: make up or make down" >&2; exit 2 ;;
esac
