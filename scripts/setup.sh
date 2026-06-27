#!/usr/bin/env bash
# scripts/setup.sh — the guided, low-friction entrypoint for airlocked-agents.
#
# It inspects the machine, offers to install what's missing, walks you through every
# choice and secret with live validation, generates the secrets it can, writes
# .env, and runs the make targets in the correct order. Re-runnable and idempotent:
# anything already set is offered as the default, so a second run just fills gaps.
#
#   bash scripts/setup.sh            # full guided setup
#   bash scripts/setup.sh --doctor   # only report what's installed/missing, then exit
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
ENV_FILE="$ROOT/.env"
# Transactional manifest: every change setup makes is appended here so `make teardown` can
# replay it in reverse. Crucially, packages are recorded ONLY when setup actually installs
# them (i.e. they were absent before), so teardown never removes tools you already had.
MANIFEST="$ROOT/.airlocked/manifest.tsv"

# ---- pretty output ----------------------------------------------------------
if [ -t 1 ]; then
  B="\033[1m"; DIM="\033[2m"; R="\033[0m"; G="\033[32m"; Y="\033[33m"; RED="\033[31m"; C="\033[36m"
else
  B=""; DIM=""; R=""; G=""; Y=""; RED=""; C=""
fi
say()  { printf "%b\n" "$*"; }
hdr()  { printf "\n%b== %s ==%b\n" "$B" "$1" "$R"; }
ok()   { printf "  %b✓%b %s\n" "$G" "$R" "$1"; }
no()   { printf "  %b✗%b %s\n" "$RED" "$R" "$1"; }
warn() { printf "  %b!%b %s\n" "$Y" "$R" "$1"; }
die()  { printf "%b%s%b\n" "$RED" "$1" "$R" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# ---- dry run ----------------------------------------------------------------
DRY_RUN=0
is_dry() { [ "$DRY_RUN" = "1" ]; }
plan()   { printf "  %b•%b %s\n" "$C" "$R" "$*"; }

# ---- manifest (what teardown will reverse) ----------------------------------
rec() { mkdir -p "$(dirname "$MANIFEST")"; local IFS=$'\t'; printf '%s\n' "$*" >> "$MANIFEST"; }
rec_header() { mkdir -p "$(dirname "$MANIFEST")"; printf '# setup run %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> "$MANIFEST"; }

# Parse the Brewfile so the recorded names track the real package list.
brewfile_formulae() { sed -nE 's/^brew "([^"]+)".*/\1/p' "$ROOT/mac/Brewfile"; }
brewfile_casks()    { sed -nE 's/^cask "([^"]+)".*/\1/p' "$ROOT/mac/Brewfile"; }
brew_has_formula()  { brew list --formula --versions "$1" >/dev/null 2>&1; }
brew_has_cask()     { brew list --cask --versions "$1" >/dev/null 2>&1; }
pipx_has()          { pipx list 2>/dev/null | grep -qi -- "$1"; }
npm_has()           { npm ls -g --depth=0 "$1" >/dev/null 2>&1; }
expand_tilde()      { printf '%s' "${1/#\~/$HOME}"; }

# yes/no prompt, default No unless second arg is "y"
confirm() {
  local prompt="$1" def="${2:-n}" ans hint="[y/N]"
  [ "$def" = "y" ] && hint="[Y/n]"
  read -r -p "$(printf "%b?%b %s %s " "$C" "$R" "$prompt" "$hint")" ans || true
  ans="${ans:-$def}"
  [[ "$ans" =~ ^[Yy]$ ]]
}

# prompt with a default value; echoes the chosen value
ask() {
  local prompt="$1" def="${2:-}" ans
  if [ -n "$def" ]; then
    read -r -p "$(printf "%b?%b %s [%s]: " "$C" "$R" "$prompt" "$def")" ans || true
    printf '%s' "${ans:-$def}"
  else
    read -r -p "$(printf "%b?%b %s: " "$C" "$R" "$prompt")" ans || true
    printf '%s' "$ans"
  fi
}

# prompt for a secret (input hidden); keeps existing value if user just hits enter
ask_secret() {
  local prompt="$1" cur="${2:-}" ans note=""
  [ -n "$cur" ] && note=" (set — enter to keep)"
  read -r -s -p "$(printf "%b?%b %s%s: " "$C" "$R" "$prompt" "$note")" ans || true
  echo >&2
  printf '%s' "${ans:-$cur}"
}

# ---- .env helpers -----------------------------------------------------------
env_get() {  # env_get KEY -> value (from .env, stripping inline comments/quotes)
  local key="$1"
  [ -f "$ENV_FILE" ] || return 0
  awk -F= -v k="$key" '$1==k{ sub(/^[^=]*=/,""); sub(/[ \t]+#.*$/,""); gsub(/^[ \t]+|[ \t]+$/,""); print; exit }' "$ENV_FILE"
}
env_set() {  # env_set KEY VALUE  (replace in place or append; drops any inline comment)
  local key="$1" val="$2"
  if [ -f "$ENV_FILE" ] && grep -qE "^${key}=" "$ENV_FILE"; then
    awk -v k="$key" -v v="$val" 'BEGIN{FS=OFS="="} $1==k{print k"="v; next} {print}' "$ENV_FILE" > "$ENV_FILE.tmp" \
      && mv "$ENV_FILE.tmp" "$ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$val" >> "$ENV_FILE"
  fi
}
# ask for a plain var, persist to .env
set_var() { local key="$1" prompt="$2" def; def="$(env_get "$key")"; def="${def:-${3:-}}"; env_set "$key" "$(ask "$prompt" "$def")"; }
# ask for a secret var, persist to .env
set_secret() { local key="$1" prompt="$2" cur; cur="$(env_get "$key")"; env_set "$key" "$(ask_secret "$prompt" "$cur")"; }

# ---- doctor / preflight -----------------------------------------------------
# Populated by doctor(); read by offer_installs().
REQUIRED_MISSING=()

doctor() {
  REQUIRED_MISSING=()
  hdr "System check"
  say "  ${DIM}Platform: $(uname -s) $(uname -m)${R}"

  have brew && ok "Homebrew" || { no "Homebrew — required (https://brew.sh)"; REQUIRED_MISSING+=("brew"); }
  have make && ok "make"     || { no "make"; REQUIRED_MISSING+=("make"); }
  have git  && ok "git"      || { no "git";  REQUIRED_MISSING+=("git"); }

  if have ansible-playbook; then ok "ansible"; else no "ansible — needed to provision"; REQUIRED_MISSING+=("ansible"); fi
  if ansible-galaxy collection list community.general >/dev/null 2>&1; then
    ok "ansible collection community.general"
  else
    no "ansible collection community.general"; REQUIRED_MISSING+=("collection")
  fi

  # Container runtime for Khoj (Colima by default; Docker Desktop if you set CONTAINER_RUNTIME=docker).
  if command -v container >/dev/null 2>&1; then ok "Apple container installed"
  elif docker info >/dev/null 2>&1; then ok "container runtime (docker daemon reachable)"
  elif have colima; then warn "colima installed but not started — 'make setup' will start it"
  else say "  ${DIM}· container runtime — 'make setup' installs the configured one (default: Apple container)${R}"
  fi

  # Installed by 'make mac' via the Brewfile, but nice to report.
  for t in node jq socat huggingface-cli; do
    have "$t" && ok "$t" || say "  ${DIM}· $t — will be installed by 'make mac'${R}"
  done
  have gh && ok "gh (for make repo)" || say "  ${DIM}· gh — optional, only for publishing${R}"
}

# Offers to install whatever doctor() recorded in REQUIRED_MISSING.
offer_installs() {
  if [ "${#REQUIRED_MISSING[@]}" -eq 0 ]; then ok "All required tools present."; return 0; fi
  if is_dry; then warn "Would offer to install: ${REQUIRED_MISSING[*]}"; return 0; fi
  hdr "Install missing prerequisites"
  local m
  for m in "${REQUIRED_MISSING[@]}"; do
    case "$m" in
      brew) warn "Install Homebrew first: https://brew.sh — then re-run."; ;;
      ansible)
        if confirm "Install ansible via Homebrew?" y; then brew install ansible || warn "ansible install failed"; fi ;;
      collection)
        if confirm "Install the community.general ansible collection?" y; then
          ansible-galaxy collection install community.general || warn "collection install failed"; fi ;;
      docker)
        warn "Install Docker Desktop: https://www.docker.com/products/docker-desktop/ (or 'brew install --cask docker')." ;;
      make|git) warn "Install Xcode command line tools: xcode-select --install" ;;
    esac
  done
}

# ---- mode -------------------------------------------------------------------
choose_mode() {
  # All UI goes to stderr; only the chosen value goes to stdout (this fn is captured).
  { hdr "What do you want to set up?"
    say "  ${B}1${R}) Set up the local stack — llama.cpp, Khoj, n8n (everything on this Mac)."
    say "  ${B}2${R}) Doctor only — just check the system and exit."
  } >&2
  ask "Choose" "1"
}

# ---- secret collection ------------------------------------------------------
validate_telegram() {
  local token="$1"
  [ -z "$token" ] && return 1
  curl -fsS "https://api.telegram.org/bot${token}/getMe" 2>/dev/null | grep -q '"ok":true'
}
collect_telegram() {
  hdr "Telegram bot"
  say "  Create a bot: open Telegram → message ${B}@BotFather${R} → /newbot → copy the token."
  local token
  while true; do
    token="$(ask_secret "Bot token" "$(env_get TELEGRAM_BOT_TOKEN)")"
    if validate_telegram "$token"; then ok "Token valid — bot reachable."; env_set TELEGRAM_BOT_TOKEN "$token"; break; fi
    no "Telegram rejected that token."
    confirm "Try again?" y || { warn "Leaving token unset; set TELEGRAM_BOT_TOKEN later."; return; }
  done
  # Auto-discover the chat id.
  local cur; cur="$(env_get TELEGRAM_ALLOWED_CHAT_ID)"
  if confirm "Auto-detect your chat id now? (send your bot any message first)" y; then
    say "  ${DIM}Send your bot a message in Telegram, then press Enter...${R}"; read -r _ || true
    local id
    id="$(curl -fsS "https://api.telegram.org/bot${token}/getUpdates" 2>/dev/null \
          | grep -oE '"chat":\{"id":-?[0-9]+' | grep -oE -- '-?[0-9]+$' | tail -1)"
    if [ -n "$id" ]; then ok "Detected chat id: $id"; env_set TELEGRAM_ALLOWED_CHAT_ID "$id"; return; fi
    warn "Could not detect a chat id (no recent message?)."
  fi
  env_set TELEGRAM_ALLOWED_CHAT_ID "$(ask "Your numeric chat id" "$cur")"
}

collect_stack() {
  hdr "Local model"
  set_var MODEL_REPO "HuggingFace repo for the GGUF model" "Qwen/Qwen3-Coder-30B-A3B-Instruct-GGUF"
  set_var MODEL_FILE "Model file within that repo" "qwen3-coder-30b-a3b-instruct-q5_k_m.gguf"
  set_var MODEL_DIR  "Where to store models" "$HOME/models"
  set_var LLAMA_PORT "Local model port" "8080"

  hdr "Khoj (second brain over your docs)"
  set_var KHOJ_DOCS_DIR "Folder to index in Khoj (read-only)" "$HOME/Documents/research"
  if [ -z "$(env_get KHOJ_ADMIN_PASSWORD)" ] || [ "$(env_get KHOJ_ADMIN_PASSWORD)" = "__set_me__" ]; then
    env_set KHOJ_ADMIN_PASSWORD "$(openssl rand -base64 18)"; ok "Generated Khoj admin password (in .env)."
  fi

  hdr "n8n (automation orchestrator)"
  if [ -z "$(env_get N8N_ENCRYPTION_KEY)" ] || [ "$(env_get N8N_ENCRYPTION_KEY)" = "__set_me__" ]; then
    env_set N8N_ENCRYPTION_KEY "$(openssl rand -hex 24)"; ok "Generated n8n encryption key — BACK THIS UP (in .env)."
  fi
  say "  ${DIM}n8n's owner account is created once in the UI at http://127.0.0.1:$(env_get N8N_PORT || echo 5678).${R}"

  collect_telegram

  hdr "Mail allowlist (write path)"
  set_var MAIL_ALLOWLIST "Comma-separated recipients the bot may email" "$(env_get MAIL_ALLOWLIST)"

  hdr "Gmail OAuth (consent happens later, in the n8n editor)"
  say "  Google Cloud Console → create an OAuth 2.0 Client → copy id/secret."
  set_secret GMAIL_OAUTH_CLIENT_ID "Gmail OAuth client id"
  set_secret GMAIL_OAUTH_CLIENT_SECRET "Gmail OAuth client secret"

  hdr "Cloud (public research)"
  set_secret ANTHROPIC_API_KEY "Anthropic API key (for public/non-sensitive work)"
}

# ---- execution --------------------------------------------------------------
# Ensure the chosen container runtime is installed and running (Khoj needs it).
# Records the Colima VM + the compose-plugin symlink to the manifest for clean teardown.
ensure_container_runtime() {
  local rt; rt="$(env_get CONTAINER_RUNTIME)"; rt="${rt:-apple}"
  case "$rt" in
    apple)
      hdr "Container runtime: Apple container"
      if ! have container; then
        # Needs macOS 26+ on Apple Silicon; fall back to Colima if unavailable.
        if [ "$(uname -m)" != "arm64" ] || ! brew install container 2>/dev/null; then
          warn "Apple 'container' unavailable here — falling back to Colima."
          env_set CONTAINER_RUNTIME colima; ensure_container_runtime; return
        fi
        rec brew_formula container
      fi
      printf 'Y\n' | container system start >/dev/null 2>&1 || true
      rec dir "$HOME/Library/Application Support/com.apple.container"
      ok "Apple container ready (Khoj will run on a host-only network with no internet egress)." ;;
    colima)
      hdr "Container runtime: Colima"
      if ! have colima; then brew install colima docker docker-compose && { rec brew_formula colima; rec brew_formula docker; rec brew_formula docker-compose; }; fi
      mkdir -p "$HOME/.docker/cli-plugins"
      if [ ! -e "$HOME/.docker/cli-plugins/docker-compose" ] && have brew; then
        ln -sf "$(brew --prefix)/bin/docker-compose" "$HOME/.docker/cli-plugins/docker-compose" 2>/dev/null \
          && rec file "$HOME/.docker/cli-plugins/docker-compose"
      fi
      if ! colima status >/dev/null 2>&1; then
        local cpus mem; cpus="$(env_get COLIMA_CPUS)"; mem="$(env_get COLIMA_MEMORY)"
        colima start --cpu "${cpus:-2}" --memory "${mem:-4}" && rec colima
      fi
      ok "Colima ready." ;;
    docker)
      hdr "Container runtime: Docker Desktop"
      if docker info >/dev/null 2>&1; then ok "Docker Desktop is running."
      else warn "CONTAINER_RUNTIME=docker but Docker Desktop isn't running — start/install it, then re-run 'make mac'."; fi ;;
    *)
      warn "Unknown CONTAINER_RUNTIME='$rt' — using apple."; env_set CONTAINER_RUNTIME apple; ensure_container_runtime ;;
  esac
}

run_stack() {
  hdr "Provision the local stack"

  if confirm "Download the model now? (multi-GB — skip if you already have it)" n; then
    local mp; mp="$(expand_tilde "$(env_get MODEL_DIR)")/$(env_get MODEL_FILE)"
    local had=0; [ -f "$mp" ] && had=1
    make model
    [ "$had" -eq 0 ] && [ -f "$mp" ] && rec model "$mp"
  fi

  if confirm "Run 'make mac' to install and start the local stack (llama, Khoj, n8n)?" y; then
    # Snapshot package state BEFORE installing, so we record only what we add.
    local missing_f=() missing_c=() miss_pipx=0 miss_npm=0 f
    while IFS= read -r f; do [ -n "$f" ] && ! brew_has_formula "$f" && missing_f+=("$f"); done < <(brewfile_formulae)
    while IFS= read -r f; do [ -n "$f" ] && ! brew_has_cask "$f" && missing_c+=("$f"); done < <(brewfile_casks)
    pipx_has open-interpreter || miss_pipx=1
    npm_has @cua/cli || miss_npm=1

    # Install/start the container runtime BEFORE make mac (Khoj needs it). Done after the
    # snapshot above so any packages it installs (colima/docker) are captured in the delta.
    ensure_container_runtime

    make mac

    # Record only packages that were absent before and are present now.
    for f in "${missing_f[@]:-}"; do [ -n "$f" ] && brew_has_formula "$f" && rec brew_formula "$f"; done
    for f in "${missing_c[@]:-}"; do [ -n "$f" ] && brew_has_cask "$f" && rec brew_cask "$f"; done
    [ "$miss_pipx" -eq 1 ] && pipx_has open-interpreter && rec pipx open-interpreter
    [ "$miss_npm" -eq 1 ] && npm_has @cua/cli && rec npm_global @cua/cli
    # Native launchd artifacts make mac creates (removal is idempotent, so safe to always record).
    rec launchd com.local.llama-server
    rec file "$HOME/Library/LaunchAgents/com.local.llama-server.plist"
    rec file "$HOME/Library/Logs/llama-server.log"
    rec file "$HOME/Library/Logs/llama-server.err.log"
    # Container artifacts depend on the runtime.
    local rt; rt="$(env_get CONTAINER_RUNTIME)"; rt="${rt:-apple}"
    if [ "$rt" = "apple" ]; then
      rec apple_container khoj
      rec apple_container khoj-db
      rec apple_container n8n
      rec apple_network "$(env_get KHOJ_NETWORK || echo khojnet)"
      rec apple_volume "$(env_get KHOJ_DB_VOLUME || echo khoj_db)"
      rec apple_volume "$(env_get KHOJ_DATA_VOLUME || echo khoj_data)"
      rec apple_volume "$(env_get N8N_DATA_VOLUME || echo n8n_data)"
      rec launchd com.local.llama-khojbridge
      rec file "$HOME/Library/LaunchAgents/com.local.llama-khojbridge.plist"
    else
      rec compose "$ROOT/compose/khoj.yml"
      rec compose "$ROOT/compose/n8n.yml"
    fi
  fi

  hdr "Almost there"
  say "  Finish the inherently-interactive bits in the n8n editor (http://127.0.0.1:$(env_get N8N_PORT || echo 5678)):"
  say "  create the owner account, connect the Gmail OAuth credential (click Connect), and wire the"
  say "  Telegram-polling workflow. See docs-MANUAL-STEPS.md."
  confirm "Run 'make verify'?" y && make verify
}

# ---- dry-run plan -----------------------------------------------------------
preview_env() {  # print the (temp) .env, masking secret-looking values
  local line k v
  while IFS= read -r line; do
    case "$line" in ''|\#*) continue ;; esac
    k="${line%%=*}"; v="${line#*=}"
    if printf '%s' "$k" | grep -qiE 'TOKEN|KEY|SECRET|PASSWORD'; then [ -n "$v" ] && v="********"; fi
    printf "      %s=%s\n" "$k" "$v"
  done < "$ENV_FILE"
}

print_plan() {
  local f miss_f=() miss_c=()
  hdr "Plan — what a real run would do (nothing below has happened)"

  [ "${#REQUIRED_MISSING[@]}" -gt 0 ] && plan "Offer to install prerequisites: ${REQUIRED_MISSING[*]}"

  local rt; rt="$(env_get CONTAINER_RUNTIME)"; rt="${rt:-apple}"
  case "$rt" in
    apple)  plan "Container runtime: install Apple 'container'. Khoj + Postgres on a host-only network ($(env_get KHOJ_SUBNET || echo 192.168.66.0/24), no internet egress); n8n with egress. UIs via --publish to 127.0.0.1." ;;
    colima) plan "Container runtime: install + start Colima; run Khoj + n8n via docker compose" ;;
    docker) plan "Container runtime: use Docker Desktop; run Khoj + n8n via docker compose" ;;
  esac

  while IFS= read -r f; do [ -n "$f" ] && ! brew_has_formula "$f" && miss_f+=("$f"); done < <(brewfile_formulae)
  while IFS= read -r f; do [ -n "$f" ] && ! brew_has_cask "$f" && miss_c+=("$f"); done < <(brewfile_casks)
  plan "Run 'make mac', which would:"
  if [ "${#miss_f[@]}" -gt 0 ]; then say "      - brew install: ${miss_f[*]}"; else say "      - brew: all Brewfile formulae already present"; fi
  [ "${#miss_c[@]}" -gt 0 ] && say "      - brew install --cask: ${miss_c[*]}"
  pipx_has open-interpreter || say "      - pipx install open-interpreter"
  npm_has @cua/cli || say "      - npm install -g @cua/cli (best-effort)"
  say "      - load launchd agent: com.local.llama-server"
  say "      - start Khoj + Postgres (no egress) and n8n (egress, Telegram polling)"

  local mp; mp="$(expand_tilde "$(env_get MODEL_DIR)")/$(env_get MODEL_FILE)"
  if [ -f "$mp" ]; then say "      - model already present (no download): $mp"; else plan "Download the model (multi-GB) to $mp"; fi

  plan "Import the n8n workflow skeletons once n8n is healthy"
  plan "Run 'make verify' (health + boundary checks)"
  plan "Record every change to .airlocked/manifest.tsv so 'make teardown' can reverse it"

  hdr "Config that would be written to .env (secrets masked)"
  preview_env
}

# ---- main -------------------------------------------------------------------
main() {
  case "${1:-}" in
    --doctor) say "${B}airlocked-agents — system check${R}"; doctor; exit 0 ;;
    --dry-run|--plan) DRY_RUN=1 ;;
  esac

  say "${B}airlocked-agents — guided setup${R}"
  is_dry && say "  ${Y}DRY RUN — nothing will be installed, changed, or written; you'll get a plan only.${R}"

  doctor
  offer_installs

  local mode; mode="$(choose_mode)"
  [ "$mode" = "2" ] && exit 0
  [ "$mode" = "1" ] || die "Unknown choice: $mode"

  local tmpd=""
  if is_dry; then
    # Work on throwaway copies so config collection touches nothing real.
    tmpd="$(mktemp -d)"
    if [ -f "$ENV_FILE" ]; then cp "$ENV_FILE" "$tmpd/.env"; else cp "$ROOT/.env.example" "$tmpd/.env"; fi
    ENV_FILE="$tmpd/.env"; MANIFEST="$tmpd/manifest.tsv"
  else
    rec_header
    [ -f "$ENV_FILE" ] || { cp "$ROOT/.env.example" "$ENV_FILE"; ok "Created .env from template."; rec env "$ENV_FILE"; }
  fi

  collect_stack
  if is_dry; then print_plan; else run_stack; fi

  if is_dry; then
    [ -n "$tmpd" ] && rm -rf "$tmpd" 2>/dev/null
    hdr "Dry run complete"
    ok "Nothing was installed, changed, or written. Re-run without --dry-run to apply."
    exit 0
  fi

  hdr "Done"
  ok "Setup complete. Re-run 'make setup' any time to change values or finish skipped steps."
  say "  Verify anytime with: ${B}make verify${R}"
}

main "$@"
