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
# n8n up?
curl -fsS "http://127.0.0.1:${N8N_PORT:-5678}/healthz" >/dev/null \
  && pass "n8n responds on localhost:${N8N_PORT:-5678}" \
  || fail "n8n not responding"

echo "== Security boundaries =="
# Service ports must listen ONLY on loopback or the host-only container-network gateway
# (the llama bridge binds the gateway, a private host-only interface) — never a public one.
if command -v lsof >/dev/null; then
  GW="${CONTAINER_GATEWAY:-192.168.64.1}"
  ALLOWED="$(printf '127\.0\.0\.1|%s' "$(echo "$GW" | sed 's/\./\\./g')")"
  if lsof -nP -iTCP -sTCP:LISTEN \
       | grep -E ":(${LLAMA_PORT:-8080}|${N8N_PORT:-5678})\b" \
       | grep -vqE "($ALLOWED)"; then
    fail "A service is listening on a public interface — must be 127.0.0.1 or ${GW} (host-only) only"
  else
    pass "Services bound to 127.0.0.1 / ${GW} (host-only) only — no public inbound"
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
