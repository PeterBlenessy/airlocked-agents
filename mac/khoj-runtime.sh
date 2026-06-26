#!/usr/bin/env bash
# mac/khoj-runtime.sh — bring Khoj (+ its Postgres DB) up/down on the chosen container runtime.
#
#   khoj-runtime.sh up      # start Khoj on $CONTAINER_RUNTIME
#   khoj-runtime.sh down    # stop/remove Khoj (and, for apple, its DB, network + proxies)
#
# Runtimes:
#   apple  (default) — Apple's native `container`. Khoj + Postgres run as two containers on a
#                      dedicated host-only (`--internal`, no internet egress) network. Container
#                      IPs are resolved at runtime (no name DNS), Postgres uses a named volume with
#                      a PGDATA subdir, and two localhost socat proxies keep the UX on 127.0.0.1
#                      (one bridges Khoj→llama via the host gateway, one exposes the Khoj UI).
#   colima | docker — the Khoj compose file (Khoj + Postgres), via `docker compose`.
#
# Values come from the environment (Makefile/ansible/setup export them from .env).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTION="${1:-up}"
RUNTIME="${CONTAINER_RUNTIME:-apple}"

KHOJ_IMAGE="${KHOJ_IMAGE:-ghcr.io/khoj-ai/khoj:latest}"
KHOJ_DB_IMAGE="${KHOJ_DB_IMAGE:-pgvector/pgvector:pg16}"
KHOJ_PORT="${KHOJ_PORT:-42110}"
KHOJ_DOCS_DIR="${KHOJ_DOCS_DIR:-$HOME/Documents/research}"
KHOJ_DOCS_DIR="${KHOJ_DOCS_DIR/#\~/$HOME}"; KHOJ_DOCS_DIR="${KHOJ_DOCS_DIR/\$HOME/$HOME}"
LLAMA_PORT="${LLAMA_PORT:-8080}"
LLAMA_API_KEY="${LLAMA_API_KEY:-local-only}"
KHOJ_DB_USER="${KHOJ_DB_USER:-khoj}"
KHOJ_DB_PASSWORD="${KHOJ_DB_PASSWORD:-khoj}"
KHOJ_DB_NAME="${KHOJ_DB_NAME:-khoj}"
# Khoj blocks on first boot asking for an admin login unless these are set.
KHOJ_ADMIN_EMAIL="${KHOJ_ADMIN_EMAIL:-admin@example.com}"
KHOJ_ADMIN_PASSWORD="${KHOJ_ADMIN_PASSWORD:-change-me-admin}"

# Apple-container network (host-only / no internet; fixed subnet → stable host gateway).
KHOJ_NETWORK="${KHOJ_NETWORK:-khojnet}"
KHOJ_SUBNET="${KHOJ_SUBNET:-192.168.66.0/24}"
KHOJ_GATEWAY="${KHOJ_GATEWAY:-192.168.66.1}"
KHOJ_DB_VOLUME="${KHOJ_DB_VOLUME:-khoj_db}"
KHOJ_DATA_VOLUME="${KHOJ_DATA_VOLUME:-khoj_data}"

LA="$HOME/Library/LaunchAgents"
SOCAT="$(command -v socat || echo /opt/homebrew/bin/socat)"
BRIDGE_LABEL="com.local.llama-khojbridge"   # gateway:LLAMA_PORT -> 127.0.0.1:LLAMA_PORT (local both ends)

die() { echo "khoj-runtime: $*" >&2; exit 1; }

load_proxy() {
  local label="$1" listen_bind="$2" listen_port="$3" target_ip="$4" target_port="$5"
  mkdir -p "$LA"
  cat > "$LA/$label.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array>
    <string>$SOCAT</string>
    <string>TCP-LISTEN:$listen_port,bind=$listen_bind,fork,reuseaddr</string>
    <string>TCP:$target_ip:$target_port</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/$label.err.log</string>
</dict></plist>
PLIST
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$LA/$label.plist" 2>/dev/null || true
}
unload_proxy() { launchctl bootout "gui/$(id -u)/$1" 2>/dev/null || true; rm -f "$LA/$1.plist"; }

# Resolve a container's IPv4 (Apple `container` has no name-based DNS, so we look it up).
container_ip() { container inspect "$1" 2>/dev/null | grep -m1 ipv4Address | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1; }

# ---- Apple `container` ------------------------------------------------------
up_apple() {
  command -v container >/dev/null 2>&1 || die "Apple 'container' not installed (run 'make setup')."
  container system status >/dev/null 2>&1 || printf 'Y\n' | container system start >/dev/null 2>&1 || true

  container network ls 2>/dev/null | awk '{print $1}' | grep -qx "$KHOJ_NETWORK" \
    || container network create --internal --subnet "$KHOJ_SUBNET" "$KHOJ_NETWORK" >/dev/null
  local v
  for v in "$KHOJ_DB_VOLUME" "$KHOJ_DATA_VOLUME"; do
    container volume inspect "$v" >/dev/null 2>&1 || container volume create "$v" >/dev/null
  done

  # Postgres (named volume + PGDATA subdir avoids the lost+found "not empty" + chown issues).
  if container inspect khoj-db >/dev/null 2>&1; then
    container start khoj-db >/dev/null 2>&1 || true
  else
    container run -d --name khoj-db --network "$KHOJ_NETWORK" \
      -e POSTGRES_USER="$KHOJ_DB_USER" -e POSTGRES_PASSWORD="$KHOJ_DB_PASSWORD" -e POSTGRES_DB="$KHOJ_DB_NAME" \
      -e PGDATA=/var/lib/postgresql/data/pgdata \
      -v "$KHOJ_DB_VOLUME:/var/lib/postgresql/data" \
      "$KHOJ_DB_IMAGE" >/dev/null
  fi
  local i; for i in $(seq 1 45); do
    container exec khoj-db pg_isready -U "$KHOJ_DB_USER" >/dev/null 2>&1 && break; sleep 2
  done
  local db_ip; db_ip="$(container_ip khoj-db)"; [ -n "$db_ip" ] || die "could not resolve khoj-db IP"

  # Khoj — points at the DB by resolved IP and at llama via the host gateway.
  if container inspect khoj >/dev/null 2>&1; then
    container start khoj >/dev/null 2>&1 || true
  else
    container run -d --name khoj --network "$KHOJ_NETWORK" \
      -e KHOJ_DEFAULT_CHAT_MODEL=local \
      -e "OPENAI_API_BASE=http://$KHOJ_GATEWAY:$LLAMA_PORT/v1" \
      -e "OPENAI_API_KEY=$LLAMA_API_KEY" \
      -e "KHOJ_ADMIN_EMAIL=$KHOJ_ADMIN_EMAIL" -e "KHOJ_ADMIN_PASSWORD=$KHOJ_ADMIN_PASSWORD" \
      -e KHOJ_NO_HTTPS=True \
      -e "POSTGRES_HOST=$db_ip" -e POSTGRES_PORT=5432 \
      -e POSTGRES_USER="$KHOJ_DB_USER" -e POSTGRES_PASSWORD="$KHOJ_DB_PASSWORD" -e POSTGRES_DB="$KHOJ_DB_NAME" \
      -p "127.0.0.1:$KHOJ_PORT:42110" \
      -v "$KHOJ_DATA_VOLUME:/root/.khoj" \
      -v "$KHOJ_DOCS_DIR:/data/research:ro" \
      "$KHOJ_IMAGE" \
      --host=0.0.0.0 --port=42110 --anonymous-mode --non-interactive >/dev/null
  fi

  # UI is exposed on 127.0.0.1 by Apple's native --publish (reliable). Only the llama bridge
  # needs a host proxy, and it binds/forwards entirely on local addresses (no vmnet route).
  load_proxy "$BRIDGE_LABEL" "$KHOJ_GATEWAY" "$LLAMA_PORT" "127.0.0.1" "$LLAMA_PORT"
  echo "Khoj up (Apple container): db=$db_ip; UI on http://127.0.0.1:$KHOJ_PORT"
}
down_apple() {
  command -v container >/dev/null 2>&1 || return 0
  local c
  for c in khoj khoj-db; do container stop "$c" >/dev/null 2>&1; container delete "$c" >/dev/null 2>&1; done
  container network delete "$KHOJ_NETWORK" >/dev/null 2>&1 || true
  unload_proxy "$BRIDGE_LABEL"
  echo "Khoj down (Apple container). (Volumes $KHOJ_DB_VOLUME/$KHOJ_DATA_VOLUME kept; 'make teardown' removes them.)"
}

# ---- Colima / Docker Desktop (compose) -------------------------------------
up_compose() {
  docker info >/dev/null 2>&1 || die "no container runtime reachable (start Colima/Docker, or run 'make setup')."
  docker compose -f "$ROOT/compose/khoj.yml" up -d
}
down_compose() { docker compose -f "$ROOT/compose/khoj.yml" down 2>/dev/null || true; }

case "$ACTION:$RUNTIME" in
  up:apple)                up_apple ;;
  up:colima|up:docker)     up_compose ;;
  down:apple)              down_apple ;;
  down:colima|down:docker) down_compose ;;
  *) die "usage: khoj-runtime.sh up|down  (CONTAINER_RUNTIME=apple|colima|docker)";;
esac
