# Architecture

A self-contained description of the system this repo provisions. The companion *Architecture & Build Guide* has the long-form rationale and rendered diagrams; this file is the version that lives with the code, so the repo is understandable on its own.

## The governing rule

> **No single component may simultaneously (a) read untrusted content, (b) hold credentials, and (c) send data outward.**

This is the "lethal trifecta" (Simon Willison, 2025): an agent with all three powers can be hijacked by a single poisoned input — an email, a web page, a message — to read your private data and ship it to an attacker, with no traditional bug involved. The entire architecture exists to keep those three powers in separate hands. Every other decision follows from this.

## Trust zones

The stack spans three zones with deliberately different privileges.

```
ZONE A — YOUR MAC  (private core · no network egress)
  llama.cpp         local model, OpenAI-compatible API on 127.0.0.1:8080
  llama-tunnel      socat proxy re-exposing the model on the WireGuard IP only (for the VPS)
  Khoj              second brain over your own docs (read-only, local)
  Open Interpreter  shell/code control, per-action approval
  Cua               computer-use driver, exposed over MCP

ZONE B — VPS  (automation glue + research sandbox · only inbound = 443)
  n8n               mail + Telegram orchestration; credentials in encrypted vault
  Suna              research → report; isolated sandbox, no credentials, no inbox

ZONE C — CLOUD  (public only · outbound)
  Claude + MCP      Gmail / Calendar / Drive / Quartr — non-sensitive content only
```

## How the zones connect

```
  Mac llama.cpp  ◀── WireGuard (private tunnel) ──▶  VPS n8n / Suna
      (sensitive research is routed to the LOCAL model over this link)

  You  ── Telegram ──▶  VPS n8n         commands; sender chat-id allowlisted
  VPS n8n  ── HTTPS:443 (only public ingress) ──  Telegram webhook
  VPS n8n / Suna  ── outbound ──▶  Claude API / MCP    public content only
```

The private core exposes no port to the internet — the model's only non-loopback listener is the socat proxy on the WireGuard interface, reachable solely by the VPS peer. The VPS has three inbound rules: HTTPS (443) for the Telegram webhook behind a reverse proxy — the only *application* ingress — plus SSH (22) for management and the WireGuard UDP port for the tunnel handshake. The cloud is reached outbound-only.

## The two data flows

**Private flow — never leaves the Mac:**

```
  your docs ──▶ local model (llama.cpp / Khoj) ──▶ YOU
              no credentials needed · no network egress
```

**Automation flow — the trifecta broken across steps:**

```
  inbox / web ──▶  AI step  ──▶  [ YOU approve ]  ──▶  deterministic send
  (untrusted)      summarize/      gate on every        Gmail/Telegram node
                   draft           irreversible          holds the credential
                   no creds ·      action                allowlist enforced
                   sandboxed
```

The AI step and the sending step are *different components*. The model drafts text; it never holds the credential and never triggers the send. Your approval and a recipient allowlist sit between them. That is the trifecta broken inside a single workflow.

## Component privileges (a trifecta audit)

| Component | Holds credentials? | Reads untrusted content? | Can send? | Runs where |
|---|---|---|---|---|
| llama.cpp | No | No | No | Mac (localhost) |
| Khoj | No | No (your docs) | No | Mac (localhost) |
| Open Interpreter | No | No | Approved code only | Mac (localhost) |
| Cua | No | No | Via orchestrator | Mac (localhost) |
| n8n | Yes (vault) | Yes (email/web) | Yes — human-gated | VPS |
| Suna | Per-task keys | Yes (web) | No (drafts only) | VPS (sandboxed) |
| Claude + MCP | Vendor-managed | Yes (public only) | Supervised | Cloud |

Read it as the audit it is: the only rows that hold credentials *and* can send (n8n) never let the model hold the credential or send unsupervised; the rows that freely read untrusted web content (Suna, Claude) cannot send. **No row has all three.**

## Invariants this repo enforces

These are the properties `make verify` and CI check for — break any of them and the design is compromised:

1. Local services (llama.cpp, Khoj) bind to `127.0.0.1`; the model is re-exposed to the VPS only on the WireGuard tunnel interface (`MAC_TUNNEL_IP`), never on a public one. `make verify` enforces this.
2. The VPS firewall allows exactly three inbound rules — SSH (22), HTTPS (443), and the WireGuard UDP port — and nothing else; HTTPS is the only application ingress. `make verify` asserts the exact set.
3. Credentials live in n8n's encrypted vault (or `secrets/`), never in a model's context or a tracked file.
4. The mail/Telegram write path keeps the model credential-free, gated by human approval and a recipient allowlist (embedded in the workflow, not a manual paste).
5. Sensitive research routes to the local model over the tunnel (via the socat proxy); nothing private egresses to the cloud.
6. The allowlist guard is unit-tested by `make verify` (`scripts/injection-selftest.sh`); the full end-to-end prompt-injection test (`scripts/injection-selftest.md`) produces a no-send outcome and is run manually after workflow changes.

## Where to go next

- Build it: `README.md` → `make` targets.
- The irreducible manual steps: `docs-MANUAL-STEPS.md`.
- The threat model and how to report issues: `SECURITY.md`.
- The standing safety test: `scripts/injection-selftest.md`.
