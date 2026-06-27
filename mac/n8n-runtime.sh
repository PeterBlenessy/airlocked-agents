#!/usr/bin/env bash
# mac/n8n-runtime.sh — bring n8n up/down on the chosen container runtime (single-box / local).
#
#   n8n-runtime.sh up      # start n8n + import the workflow skeletons
#   n8n-runtime.sh down    # stop/remove n8n
#
# n8n is the automation orchestrator: it holds credentials and sends, so it needs internet egress
# (Telegram polling + Gmail). It runs with a published UI on 127.0.0.1 and NO public inbound —
# Telegram is reached by polling (Schedule + getUpdates), not a webhook. The workflow import is run
# after n8n is healthy (the old VPS command pointed --input at a nonexistent path and never worked).
#
# Runtimes: apple (default, Apple `container`) | colima | docker (the compose file).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTION="${1:-up}"
RUNTIME="${CONTAINER_RUNTIME:-apple}"

N8N_IMAGE="${N8N_IMAGE:-docker.io/n8nio/n8n:latest}"
N8N_PORT="${N8N_PORT:-5678}"
N8N_DATA_VOLUME="${N8N_DATA_VOLUME:-n8n_data}"
GENERIC_TIMEZONE="${GENERIC_TIMEZONE:-Europe/Stockholm}"

die() { echo "n8n-runtime: $*" >&2; exit 1; }

wait_healthy() {
  local i
  for i in $(seq 1 60); do
    curl -fsS "http://127.0.0.1:$N8N_PORT/healthz" >/dev/null 2>&1 && return 0
    sleep 2
  done
  return 1
}

# ---- Apple `container` -------------------------------------------------------
up_apple() {
  command -v container >/dev/null 2>&1 || die "Apple 'container' not installed (run 'make setup')."
  container system status >/dev/null 2>&1 || printf 'Y\n' | container system start >/dev/null 2>&1 || true
  container volume inspect "$N8N_DATA_VOLUME" >/dev/null 2>&1 || container volume create "$N8N_DATA_VOLUME" >/dev/null
  if container inspect n8n >/dev/null 2>&1; then
    container start n8n >/dev/null 2>&1 || true
  else
    # Default network → has internet egress (n8n must reach Telegram/Gmail). UI published to
    # localhost; repo n8n/ mounted read-only so the CLI can import the workflows.
    # Apple-container named volumes are root-owned, but n8n runs as `node` — chown it first
    # (one-off, via the n8n image so no extra pull) or n8n can't write /home/node/.n8n.
    container run --rm --user 0 --entrypoint sh \
      -v "$N8N_DATA_VOLUME:/home/node/.n8n" "$N8N_IMAGE" \
      -c 'chown -R node:node /home/node/.n8n' >/dev/null 2>&1 || true
    container run -d --name n8n \
      -e N8N_PROTOCOL=http -e N8N_SECURE_COOKIE=false \
      -e "N8N_PORT=$N8N_PORT" -e N8N_LISTEN_ADDRESS=0.0.0.0 \
      -e N8N_DIAGNOSTICS_ENABLED=false -e N8N_PERSONALIZATION_ENABLED=false \
      -e "GENERIC_TIMEZONE=$GENERIC_TIMEZONE" \
      -p "127.0.0.1:$N8N_PORT:$N8N_PORT" \
      -v "$N8N_DATA_VOLUME:/home/node/.n8n" \
      -v "$ROOT/n8n:/workflows:ro" \
      "$N8N_IMAGE" >/dev/null
  fi
  import_workflows "container exec n8n"
  echo "n8n up (Apple container): UI on http://127.0.0.1:$N8N_PORT"
}
down_apple() {
  command -v container >/dev/null 2>&1 || return 0
  container stop n8n >/dev/null 2>&1; container delete n8n >/dev/null 2>&1
  echo "n8n down (Apple container). (Volume $N8N_DATA_VOLUME kept; 'make teardown' removes it.)"
}

# ---- Colima / Docker Desktop (compose) --------------------------------------
up_compose() {
  docker info >/dev/null 2>&1 || die "no container runtime reachable (run 'make setup')."
  docker compose -f "$ROOT/compose/n8n.yml" up -d
  import_workflows "docker exec n8n"
}
down_compose() { docker compose -f "$ROOT/compose/n8n.yml" down 2>/dev/null || true; }

# Import the workflow skeletons once n8n is healthy. The repo n8n/ dir is available in the
# container at /workflows (apple: ro mount; compose: see compose/n8n.yml).
import_workflows() {
  local exec_prefix="$1" f
  if ! wait_healthy; then echo "n8n not healthy yet — import skipped; re-run 'make workflows' later." >&2; return 0; fi
  for f in "$ROOT"/n8n/workflow.*.json; do
    [ -e "$f" ] || continue
    $exec_prefix n8n import:workflow --input="/workflows/$(basename "$f")" >/dev/null 2>&1 \
      && echo "  imported $(basename "$f")" \
      || echo "  import of $(basename "$f") needs review in the n8n editor"
  done
}

case "$ACTION:$RUNTIME" in
  up:apple)                up_apple ;;
  up:colima|up:docker)     up_compose ;;
  down:apple)              down_apple ;;
  down:colima|down:docker) down_compose ;;
  *) die "usage: n8n-runtime.sh up|down  (CONTAINER_RUNTIME=apple|colima|docker)";;
esac
