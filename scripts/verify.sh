#!/usr/bin/env bash
# scripts/verify.sh — health and SECURITY BOUNDARY checks.
# Confirms not just "is it up" but "do the trust boundaries hold."
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$ROOT/.env" ] && set -a && . "$ROOT/.env" && set +a

pass() { printf "  \033[32m✓\033[0m %s\n" "$1"; }
fail() { printf "  \033[31m✗\033[0m %s\n" "$1"; FAILED=1; }
FAILED=0

echo "== Health =="
# Local model up?
if curl -fsS "http://127.0.0.1:${LLAMA_PORT:-8080}/v1/models" \
     -H "Authorization: Bearer ${LLAMA_API_KEY:-local-only}" >/dev/null; then
  pass "llama.cpp responds on localhost:${LLAMA_PORT:-8080}"
else
  fail "llama.cpp not responding"
fi
# Khoj up?
curl -fsS "http://127.0.0.1:${KHOJ_PORT:-42110}/" >/dev/null \
  && pass "Khoj responds on localhost:${KHOJ_PORT:-42110}" \
  || fail "Khoj not responding"

echo "== Security boundaries =="
# Local services must listen ONLY on the loopback or the WireGuard tunnel interface.
# The model binds to 127.0.0.1; a socat proxy re-exposes it on MAC_TUNNEL_IP for the VPS.
if command -v lsof >/dev/null; then
  TUNNEL_IP="${MAC_TUNNEL_IP:-10.10.0.2}"
  ALLOWED_IFACE="$(printf '127\.0\.0\.1|%s' "$(echo "$TUNNEL_IP" | sed 's/\./\\./g')")"
  if lsof -nP -iTCP -sTCP:LISTEN | grep -E ":(${LLAMA_PORT:-8080}|${KHOJ_PORT:-42110})\b" \
       | grep -vqE "($ALLOWED_IFACE)"; then
    fail "A local service is listening on a non-local interface — must be 127.0.0.1 or ${TUNNEL_IP} (tunnel) only"
  else
    pass "Local services bound to 127.0.0.1 / ${TUNNEL_IP} (tunnel) only"
  fi
fi

# VPS firewall: inbound must be EXACTLY {22, 443, WG} — nothing else (checked over SSH).
if [ -n "${VPS_HOST:-}" ]; then
  WG_PORT="${WG_LISTEN_PORT:-51820}"
  RULES="$(ssh "${VPS_USER}@${VPS_HOST}" 'sudo ufw status' 2>/dev/null || true)"
  if echo "$RULES" | grep -q "Status: active"; then
    pass "VPS ufw active"
    echo "$RULES" | grep -qE "5678.*ALLOW" \
      && fail "n8n port 5678 is exposed on the VPS — it must be localhost + reverse proxy only" \
      || pass "n8n raw port not publicly exposed"
    EXPECTED="$(printf '22\n443\n%s\n' "$WG_PORT" | sort -u)"
    ACTUAL="$(echo "$RULES" | awk '/ALLOW/ {print $1}' | sed 's#/.*##' | grep -E '^[0-9]+$' | sort -u)"
    EXTRA="$(comm -13 <(printf '%s\n' "$EXPECTED") <(printf '%s\n' "$ACTUAL"))"
    if [ -n "$EXTRA" ]; then
      fail "VPS firewall has unexpected inbound port(s): $(echo "$EXTRA" | tr '\n' ' ')— allow only 22, 443, ${WG_PORT}"
    else
      pass "VPS firewall inbound is exactly 22 (SSH), 443 (HTTPS), ${WG_PORT} (WireGuard)"
    fi
  else
    fail "VPS ufw not active or unreachable"
  fi
fi

echo
echo "== Injection / guard self-test =="
if bash "$ROOT/scripts/injection-selftest.sh" >/tmp/aa-guard-test.log 2>&1; then
  pass "Allowlist guard blocks unauthorized chat + off-allowlist send"
else
  fail "Allowlist guard self-test FAILED"; cat /tmp/aa-guard-test.log
fi
if grep -q "not on allowlist" "$ROOT/n8n/workflow.write-path.json"; then
  pass "Write-path workflow embeds the allowlist guard"
else
  fail "Write-path workflow is missing the inline allowlist guard"
fi
echo "  Full end-to-end injection test (manual, after workflow changes): scripts/injection-selftest.md"
echo
[ "$FAILED" -eq 0 ] && { echo "All checks passed."; exit 0; } || { echo "Some checks FAILED — see above."; exit 1; }
