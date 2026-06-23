#!/usr/bin/env bash
# scripts/setup.sh — the guided, low-friction entrypoint for airlocked-agents.
#
# It inspects the machine, offers to install what's missing, walks you through every
# choice and secret with live validation, generates the WireGuard keys for you, writes
# .env, and runs the make targets in the correct order. Re-runnable and idempotent:
# anything already set is offered as the default, so a second run just fills gaps.
#
#   bash scripts/setup.sh            # full guided setup
#   bash scripts/setup.sh --doctor   # only report what's installed/missing, then exit
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
ENV_FILE="$ROOT/.env"

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

  if have docker; then
    if docker info >/dev/null 2>&1; then ok "docker (daemon running)"; else warn "docker installed but daemon not running — start Docker Desktop"; fi
  else
    no "docker"; REQUIRED_MISSING+=("docker")
  fi

  # Installed by 'make mac' via the Brewfile, but nice to report.
  for t in node jq socat wg huggingface-cli; do
    have "$t" && ok "$t" || say "  ${DIM}· $t — will be installed by 'make mac'${R}"
  done
  have gh && ok "gh (for make repo)" || say "  ${DIM}· gh — optional, only for publishing${R}"
}

# Offers to install whatever doctor() recorded in REQUIRED_MISSING.
offer_installs() {
  if [ "${#REQUIRED_MISSING[@]}" -eq 0 ]; then ok "All required tools present."; return 0; fi
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
    say "  ${B}1${R}) Local core only  — the Mac private brain (llama.cpp + Khoj). No VPS, no cloud accounts."
    say "  ${B}2${R}) Full stack       — Mac + VPS (n8n, Telegram, Suna) over the WireGuard tunnel."
    say "  ${B}3${R}) Doctor only      — just check the system and exit."
  } >&2
  ask "Choose" "1"
}

# ---- secret collection ------------------------------------------------------
collect_local() {
  hdr "Local model configuration"
  set_var MODEL_REPO "HuggingFace repo for the GGUF model" "Qwen/Qwen3-Coder-30B-A3B-Instruct-GGUF"
  set_var MODEL_FILE "Model file within that repo" "qwen3-coder-30b-a3b-instruct-q5_k_m.gguf"
  set_var MODEL_DIR  "Where to store models" "$HOME/models"
  set_var LLAMA_PORT "Local model port" "8080"
  set_var KHOJ_DOCS_DIR "Folder to index in Khoj (read-only)" "$HOME/Documents/research"
  # Local-only: make sure the VPS checks in `make verify` don't try to SSH anywhere.
  if [ -n "$(env_get VPS_HOST)" ] && [ "$(env_get VPS_HOST)" != "vps.example.com" ]; then :; else
    env_set VPS_HOST ""   # blank => verify.sh skips the VPS boundary checks
  fi
  ok ".env updated for a local-only run."
}

gen_wireguard_keys() {
  have wg || { if confirm "WireGuard tools needed to generate keys. Install wireguard-tools via brew?" y; then brew install wireguard-tools; fi; }
  have wg || { warn "wg not available — skipping key generation; fill WG_* in .env manually."; return; }
  if [ -n "$(env_get WG_MAC_PRIVATE_KEY)" ] && [[ "$(env_get WG_MAC_PRIVATE_KEY)" != __* ]]; then
    confirm "WireGuard keys already set. Regenerate (invalidates the current tunnel)?" n || { ok "Keeping existing WireGuard keys."; return; }
  fi
  local mpriv mpub vpriv vpub
  mpriv="$(wg genkey)"; mpub="$(printf '%s' "$mpriv" | wg pubkey)"
  vpriv="$(wg genkey)"; vpub="$(printf '%s' "$vpriv" | wg pubkey)"
  env_set WG_MAC_PRIVATE_KEY "$mpriv"; env_set WG_MAC_PUBLIC_KEY "$mpub"
  env_set WG_VPS_PRIVATE_KEY "$vpriv"; env_set WG_VPS_PUBLIC_KEY "$vpub"
  ok "Generated both WireGuard key pairs (the old manual step #4 — now automatic)."
}

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

collect_full() {
  collect_local
  hdr "VPS"
  set_var VPS_HOST "VPS hostname/IP (SSH-reachable)" "$(env_get VPS_HOST)"
  set_var VPS_USER "SSH user with sudo on the VPS" "deploy"
  local host user; host="$(env_get VPS_HOST)"; user="$(env_get VPS_USER)"
  if [ -n "$host" ] && [ "$host" != "vps.example.com" ]; then
    if ssh -o BatchMode=yes -o ConnectTimeout=6 "${user}@${host}" true 2>/dev/null; then
      ok "SSH to ${user}@${host} works."
    else
      warn "Could not SSH to ${user}@${host} non-interactively (set up a key, or you'll be prompted during provisioning)."
    fi
  fi

  collect_telegram

  hdr "Mail allowlist (write path)"
  set_var MAIL_ALLOWLIST "Comma-separated recipients the bot may email" "$(env_get MAIL_ALLOWLIST)"

  hdr "Gmail OAuth (consent happens later, in the n8n editor)"
  say "  Google Cloud Console → create an OAuth 2.0 Client → copy id/secret."
  set_secret GMAIL_OAUTH_CLIENT_ID "Gmail OAuth client id"
  set_secret GMAIL_OAUTH_CLIENT_SECRET "Gmail OAuth client secret"

  hdr "n8n"
  set_var N8N_HOST "Public HTTPS hostname for n8n (behind your reverse proxy)" "$(env_get N8N_HOST)"
  set_var N8N_BASIC_AUTH_USER "n8n admin user" "admin"
  if [ -z "$(env_get N8N_BASIC_AUTH_PASSWORD)" ] || [ "$(env_get N8N_BASIC_AUTH_PASSWORD)" = "__set_me__" ]; then
    if confirm "Generate a random n8n admin password?" y; then env_set N8N_BASIC_AUTH_PASSWORD "$(openssl rand -base64 18)"; ok "Generated n8n password (in .env)."; fi
  fi
  if [ -z "$(env_get N8N_ENCRYPTION_KEY)" ] || [ "$(env_get N8N_ENCRYPTION_KEY)" = "__set_me__" ]; then
    env_set N8N_ENCRYPTION_KEY "$(openssl rand -hex 24)"; ok "Generated n8n encryption key — BACK THIS UP (in .env)."
  fi

  hdr "Suna research rig"
  say "  Create a Supabase project (https://supabase.com) → copy URL + keys."
  set_var SUPABASE_URL "Supabase URL" "$(env_get SUPABASE_URL)"
  set_secret SUPABASE_ANON_KEY "Supabase anon key"
  set_secret SUPABASE_SERVICE_KEY "Supabase service key"
  set_secret ANTHROPIC_API_KEY "Anthropic API key (public research)"

  gen_wireguard_keys

  # Keep LOCAL_MODEL_BASE_URL consistent with the tunnel IP + port.
  local tip lport; tip="$(env_get MAC_TUNNEL_IP)"; lport="$(env_get LLAMA_PORT)"
  env_set LOCAL_MODEL_BASE_URL "http://${tip:-10.10.0.2}:${lport:-8080}/v1"
}

# ---- execution --------------------------------------------------------------
run_local() {
  hdr "Provision the local core"
  if confirm "Download the model now? (multi-GB — skip if you already have it)" n; then make model; fi
  confirm "Run 'make mac' to install and start the local core?" y && make mac
  confirm "Run 'make verify'?" y && make verify
}

run_full() {
  run_local
  hdr "Provision the VPS"
  confirm "Run 'make vps' (provisions the VPS over public SSH)?" y && make vps
  hdr "Tunnel"
  confirm "Run 'make tunnel'?" y && {
    make tunnel
    say "  ${Y}Now import the rendered wireguard/wg0.mac.conf into the WireGuard app and activate it.${R}"
    say "  ${DIM}(WireGuard's macOS app needs the GUI; this is the one bit we can't do for you.)${R}"
    confirm "Tunnel activated and connected?" n && {
      if confirm "Lock SSH to the tunnel now ('make harden')?" y; then make harden && env_set SSH_HARDENED true; fi
    }
  }
  confirm "Import the n8n workflows ('make workflows')?" y && make workflows
  hdr "Almost there"
  say "  Finish the inherently-interactive bits in the n8n editor: connect the Gmail OAuth"
  say "  credential (click Connect), and run Suna's setup wizard on the VPS (see docs-MANUAL-STEPS.md)."
}

# ---- main -------------------------------------------------------------------
main() {
  say "${B}airlocked-agents — guided setup${R}"
  if [ "${1:-}" = "--doctor" ]; then doctor; exit 0; fi

  doctor
  offer_installs

  local mode; mode="$(choose_mode)"
  [ "$mode" = "3" ] && exit 0

  [ -f "$ENV_FILE" ] || { cp "$ROOT/.env.example" "$ENV_FILE"; ok "Created .env from template."; }

  case "$mode" in
    1) collect_local; run_local ;;
    2) collect_full;  run_full  ;;
    *) die "Unknown choice: $mode" ;;
  esac

  hdr "Done"
  ok "Setup complete. Re-run 'make setup' any time to change values or finish skipped steps."
  say "  Verify anytime with: ${B}make verify${R}"
}

main "$@"
