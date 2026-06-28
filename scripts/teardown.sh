#!/usr/bin/env bash
# scripts/teardown.sh — reverse exactly what `make setup` did.
#
# It does NOT guess what to remove. It replays the transactional manifest that setup wrote
# (.airlocked/manifest.tsv) in reverse, undoing only the changes setup actually made. Packages
# are uninstalled only if setup installed them (i.e. they were absent beforehand) — anything you
# already had is left untouched. Every destructive step asks first.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
ENV_FILE="$ROOT/.env"
MANIFEST="$ROOT/.airlocked/manifest.tsv"

if [ -t 1 ]; then
  B="\033[1m"; DIM="\033[2m"; R="\033[0m"; G="\033[32m"; Y="\033[33m"; RED="\033[31m"; C="\033[36m"
else B=""; DIM=""; R=""; G=""; Y=""; RED=""; C=""; fi
say()  { printf "%b\n" "$*"; }
hdr()  { printf "\n%b== %s ==%b\n" "$B" "$1" "$R"; }
ok()   { printf "  %b✓%b %s\n" "$G" "$R" "$1"; }
warn() { printf "  %b!%b %s\n" "$Y" "$R" "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }
confirm() {
  local prompt="$1" def="${2:-n}" ans hint="[y/N]"
  [ "$def" = "y" ] && hint="[Y/n]"
  read -r -p "$(printf "%b?%b %s %s " "$C" "$R" "$prompt" "$hint")" ans || true
  ans="${ans:-$def}"; [[ "$ans" =~ ^[Yy]$ ]]
}

# Load .env (for any values referenced) before .env might be removed.
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  set -a; . "$ENV_FILE" 2>/dev/null || true; set +a
fi

reverse() { if have tac; then tac; else tail -r; fi; }

main() {
  say "${B}airlocked-agents — teardown (reverse of setup)${R}"
  if [ ! -f "$MANIFEST" ]; then
    warn "No manifest at $MANIFEST — nothing recorded to reverse."
    say "  ${DIM}If you set up before the manifest existed, use 'make down' and remove artifacts manually.${R}"
    exit 0
  fi
  say "  ${DIM}Replaying $MANIFEST in reverse. Each destructive step asks first.${R}"
  confirm "Start teardown?" n || { say "Aborted."; exit 0; }

  # Read the manifest on fd 3 so the confirm prompts below still read the user's terminal (fd 0).
  local kind a b
  while IFS=$'\t' read -r kind a b <&3; do
    [ -z "${kind:-}" ] && continue
    case "$kind" in
      \#*) continue ;;
      brew_formula)
        # Apple's container runtime must be stopped before its formula is removed.
        [ "$a" = "container" ] && command -v container >/dev/null 2>&1 && container system stop >/dev/null 2>&1
        have brew && confirm "Uninstall Homebrew formula '$a' (setup installed it)?" y \
          && { brew uninstall "$a" 2>/dev/null && ok "uninstalled $a" || warn "could not uninstall $a (maybe a dependency)"; } ;;
      brew_cask)
        have brew && confirm "Uninstall Homebrew cask '$a' (setup installed it)?" y \
          && { brew uninstall --cask "$a" 2>/dev/null && ok "uninstalled cask $a" || warn "could not uninstall cask $a"; } ;;
      pipx)
        have pipx && confirm "Uninstall pipx '$a'?" y && { pipx uninstall "$a" >/dev/null 2>&1 && ok "uninstalled $a"; } ;;
      npm_global)
        have npm && confirm "Uninstall global npm '$a'?" y && { npm uninstall -g "$a" >/dev/null 2>&1 && ok "uninstalled $a"; } ;;
      launchd)
        launchctl bootout "gui/$(id -u)/$a" 2>/dev/null && ok "unloaded $a" || true ;;
      compose)
        if have docker && [ -f "$a" ]; then
          confirm "Stop the stack and DELETE its data volume ($a)?" y \
            && { docker compose -f "$a" down -v 2>/dev/null && ok "compose down -v: $a" || warn "compose down failed (daemon running?)"; }
        fi ;;
      colima)
        # Processed AFTER compose (manifest reverse order) so container volumes are removed first.
        if have colima; then
          confirm "Stop & delete the Colima VM (and ~/.colima, ~/.lima)?" y \
            && { colima stop 2>/dev/null; colima delete -f 2>/dev/null; rm -rf "$HOME/.colima" "$HOME/.lima"; ok "Colima VM removed"; }
        fi ;;
      apple_container)
        if command -v container >/dev/null 2>&1; then
          container stop "$a" 2>/dev/null; container delete "$a" 2>/dev/null && ok "removed Apple container '$a'" || true
        fi ;;
      apple_network)
        if command -v container >/dev/null 2>&1; then
          container network delete "$a" 2>/dev/null && ok "removed container network '$a'" || true
        fi ;;
      apple_volume)
        if command -v container >/dev/null 2>&1; then
          confirm "Delete container volume '$a' (its data)?" y \
            && { container volume delete "$a" 2>/dev/null && ok "removed volume '$a'" || true; }
        fi ;;
      dir)
        [ -d "$a" ] && confirm "Delete directory $a?" y && { rm -rf "$a" && ok "removed $a"; } ;;
      model)
        [ -f "$a" ] && confirm "Delete model file $a (you'd re-download to reinstall)?" y \
          && { rm -f "$a" && ok "removed model $a"; } ;;
      env)
        [ -f "$a" ] && confirm "Delete $a? (contains your n8n encryption key — back it up if you may redeploy)" n \
          && { rm -f "$a" && ok "removed $a"; } ;;
      file)
        [ -e "$a" ] && { rm -f "$a" && ok "removed $a"; } || true ;;
      note)
        warn "Manual: $a" ;;
      *) warn "Unknown manifest entry: $kind $a" ;;
    esac
  done 3< <(reverse < "$MANIFEST")

  hdr "Done"
  if confirm "Remove the manifest itself ($MANIFEST)?" y; then rm -f "$MANIFEST"; rmdir "$(dirname "$MANIFEST")" 2>/dev/null || true; ok "manifest removed"; fi
  say "  ${DIM}Shared tools you already had were left untouched by design.${R}"
  say "  Re-check with: ${B}make doctor${R}"
}

main "$@"
