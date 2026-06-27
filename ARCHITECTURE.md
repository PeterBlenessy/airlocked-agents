# Architecture

A self-contained description of the system this repo provisions: **one dedicated, always-on Mac
mini running everything locally**, plus the public cloud for non-sensitive work. This file lives
with the code so the repo is understandable on its own.

## The governing rule

> **No single component may simultaneously (a) read untrusted content, (b) hold credentials, and (c) send data outward.**

This is the "lethal trifecta" (Simon Willison, 2025): an agent with all three powers can be
hijacked by a single poisoned input — an email, a web page, a message — to read your private data
and ship it to an attacker, with no traditional bug involved. The architecture exists to keep those
three powers in separate hands. The "zones" of earlier designs were just a convenient way to enforce
this; here it is enforced at the **component** level, on one machine.

## The shape

```
YOUR MAC MINI  (dedicated appliance · no public inbound)
  llama.cpp         local model, OpenAI-compatible API on 127.0.0.1:8080  (native/launchd)
  Khoj + Postgres   second brain over your docs (read-only); HOST-ONLY network, NO internet egress
  n8n               mail + Telegram orchestration; credentials in its encrypted vault; egress
  Open Interpreter  shell/code control, per-action approval                (native)
  Cua               computer-use driver, over MCP                          (native, best-effort)
  (Suna)            research sandbox — deferred, not yet wired for single-box

CLOUD  (public only · outbound)
  Claude + MCP      Gmail / Calendar / Drive / Quartr — non-sensitive content only
```

Containerized services (Khoj, Postgres, n8n) run in **Apple `container`** (per-container micro-VM).
Khoj sits on a dedicated host-only network (`--internal`) so it has **no internet egress**; n8n has
egress because its job is to send. Each UI is published to `127.0.0.1` only.

## How it connects

```
  You  ── Telegram ──▶  n8n        commands; n8n POLLS Telegram (getUpdates), sender chat-id allowlisted
  n8n  ── outbound ──▶  Telegram / Gmail / Claude     (it holds the credentials; sends are human-gated)
  Khoj ── localhost ──▶ llama.cpp  (via a host-only bridge proxy; Khoj has no other network)
  containers ──▶ llama.cpp   over the host-only gateway; the model itself stays on 127.0.0.1
```

**There is zero public inbound.** Telegram is reached by *polling*, not a webhook — nothing listens
for the internet. The cloud is reached outbound-only, for public content.

## The two data flows

**Private flow — never leaves the mini:**

```
  your docs ──▶ local model (llama.cpp / Khoj) ──▶ YOU
              no credentials needed · no internet egress
```

**Automation flow — the trifecta broken across steps:**

```
  inbox / web ──▶  AI step  ──▶  [ YOU approve ]  ──▶  deterministic send
  (untrusted)      summarize/      gate on every        Gmail/Telegram node
                   draft           irreversible          holds the credential
                   no creds         action               allowlist enforced
```

The AI step and the sending step are *different components*. The model drafts text; it never holds
the credential and never triggers the send. Your approval and a recipient allowlist sit between
them. That is the trifecta broken inside a single workflow.

## Component privileges (a trifecta audit)

| Component | Holds credentials? | Reads untrusted? | Can send? | How it runs |
|---|---|---|---|---|
| llama.cpp | No | No | No | native, 127.0.0.1 |
| Khoj (+Postgres) | No | Your docs (sandboxed, read-only) | No (host-only net, no egress) | container |
| Open Interpreter | No | No | Approved code only | native |
| Cua | No | No | Via orchestrator | native |
| n8n | Yes (vault) | Yes (email/web) | Yes — human-gated + allowlisted | container (egress) |
| Claude + MCP | Vendor-managed | Yes (public only) | Supervised | cloud |

The only row that holds credentials *and* can send (n8n) never lets the model hold the credential or
send unsupervised; the rows that read untrusted content (Khoj, Claude) cannot send (Khoj literally
has no internet). **No row has all three.**

## Invariants this repo enforces

`make verify` and CI check these — break any and the design is compromised:

1. Services listen only on `127.0.0.1` or the host-only container-network gateway (the llama
   bridge) — never a public interface. There is **no public inbound**. `make verify` enforces this.
2. Khoj runs on a host-only (`--internal`) network → **no internet egress** (the "can send" leg is
   removed for the content-reader). `make verify` checks it.
3. Credentials live in n8n's encrypted vault (or `secrets/`), never in a model's context or a
   tracked file.
4. The mail/Telegram write path keeps the model credential-free, gated by human approval and a
   recipient allowlist (embedded in the workflow, not a manual paste).
5. Sensitive work routes to the local model; nothing private egresses to the cloud.
6. Telegram is reached by polling — no inbound webhook.
7. The allowlist guard is unit-tested by `make verify` (`scripts/injection-selftest.sh`); the full
   end-to-end prompt-injection test (`scripts/injection-selftest.md`) is run manually.

## Why one box (and the trade-off)

A single always-on mini is simpler, more deterministic, and has a smaller external surface (no
inbound) than a multi-host design. The honest trade-off: a multi-host model gave physical isolation
between the internet-facing automation and your private data; here that becomes **container
isolation** on one box. That is why the mini should be a **dedicated appliance**, not your
daily-driver with personal files.

## Where to go next

- What each component is and why it was chosen: [`COMPONENTS.md`](COMPONENTS.md).
- Build it: `README.md` → `make setup`.
- The irreducible manual steps: `docs-MANUAL-STEPS.md`.
- The threat model and how to report issues: `SECURITY.md`.
- The standing safety test: `scripts/injection-selftest.md`.
