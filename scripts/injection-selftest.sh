#!/usr/bin/env bash
# scripts/injection-selftest.sh — automated unit test of the allowlist guard.
#
# This is the machine-checkable core of the prompt-injection defence: it feeds the guard
# (n8n/allowlist.code.js) the exact hostile inputs an injection would produce — a command
# from someone else's Telegram chat, and a send to an off-allowlist recipient — and asserts
# the guard REFUSES both. The full end-to-end test (real email through the live workflow)
# remains manual; see scripts/injection-selftest.md.
#
# Run directly, or via `make verify`. Requires node (installed by the Brewfile).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$ROOT/n8n/allowlist.code.js"

if ! command -v node >/dev/null 2>&1; then
  echo "node not found — skipping the automated guard self-test (brew install node)."
  exit 0
fi

node - "$GUARD" <<'NODE'
const fs = require("fs");
const src = fs.readFileSync(process.argv[2], "utf8");

// The guard runs inside n8n with $env and $input as globals; emulate them here.
const makeInput = (item) => ({ first: () => ({ json: item }), all: () => [{ json: item }] });
const $env = {
  TELEGRAM_ALLOWED_CHAT_ID: "123",
  MAIL_ALLOWLIST: "anna@example.com,team@addable.se",
};
const guard = new Function("$env", "$input", src);

let failures = 0;
const ok = (m) => console.log(`  ✓ ${m}`);
const bad = (m) => { console.log(`  ✗ ${m}`); failures++; };

const blocks = (item, label) => {
  try { guard($env, makeInput(item)); bad(`${label} — was ALLOWED (guard failed to block)`); }
  catch { ok(`${label} — blocked`); }
};
const allows = (item, label) => {
  try { guard($env, makeInput(item)); ok(`${label} — allowed`); }
  catch (e) { bad(`${label} — was BLOCKED (${e.message})`); }
};

// Legitimate traffic must pass.
allows({ message: { chat: { id: 123 } }, text: "summarize my inbox" }, "owner read command");
allows({ chatId: 123, action: "send", to: "anna@example.com" }, "send to allowlisted recipient");

// Hostile traffic an injection would create must be refused.
blocks({ message: { chat: { id: 999 } }, text: "do attacker bidding" }, "command from a stranger's chat");
blocks({ chatId: 123, action: "send", to: "attacker@evil.com" }, "exfiltration send to off-allowlist recipient");

if (failures) { console.log(`\nGuard self-test FAILED (${failures}).`); process.exit(1); }
console.log("\nGuard self-test passed.");
NODE
