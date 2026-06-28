# Components

What each part *is*, the job it does here, and why it was chosen. For how the parts connect (data
flows, the airlock, the trifecta), see [`ARCHITECTURE.md`](ARCHITECTURE.md); for the threat model,
[`SECURITY.md`](SECURITY.md).

airlocked-agents is the **automation + capture layer for Notesage** — it does *not* bundle a second
brain. The selection principle: every component is open-source/auditable, and each occupies at most
*one* corner of the "lethal trifecta" (read untrusted / hold credentials / send outward).

---

## On the Mac mini (this repo installs these)

### llama.cpp
- **What it is:** an open-source LLM inference engine (Georgi Gerganov), C/C++, runs quantized
  GGUF models with Apple-Silicon Metal acceleration, and ships a small `llama-server` with an
  **OpenAI-compatible API**.
- **Its job here:** the **summariser** — n8n calls it to condense fetched articles/tweets. Bound to
  `127.0.0.1`; reachable by the n8n container via a small `socat` gateway bridge.
- **Model:** **Google Gemma 4 E4B (instruct)** — the small model Notesage's own catalog uses, so the
  mini runs the same thing. General instruct, not coding.
- **Why it over alternatives:** Ollama/LM Studio are heavier wrappers; vLLM is CUDA-centric. llama.cpp
  is a single auditable native binary with the best Metal support and an OpenAI-compatible endpoint
  (n8n talks to it with no custom code).

### n8n
- **What it is:** an open-source **workflow automation** platform (self-hosted Zapier/Make
  alternative) — visual node-based flows, scheduled + event triggers, an encrypted credential vault.
- **Its job here:** the engine for the **two needs** — (1) **scheduled / event-triggered jobs**
  (RSS/news/market pulls, folder-watch) and (2) **Telegram mobile capture**. It reads the untrusted
  web, summarises via the local model, and **writes files into the capture folder**. UI on
  `127.0.0.1`; **Telegram is polled (no webhook) → no public inbound.** Holds **no secrets** (those
  go to the future broker); its only "output" is writing local files.
- **Why it over alternatives:** Zapier/Make are cloud SaaS (credentials off-device — disqualifying);
  Node-RED/Huginn are more DIY. n8n is self-hostable with the triggers, integrations, and HTTP/HTML
  nodes this needs, plus a local-AI (custom base URL) node for the local model.

### Telegram (bot)
- **What it is:** a messaging app with a trivial, free **bot API**.
- **Its job here:** the **mobile capture transport** — share a URL/tweet from your phone's Share
  Sheet to the bot; n8n **polls** `getUpdates` (no inbound) and ingests it. Can also carry
  notifications/approvals later.
- **The catch:** it's a cloud channel, so a **chat-id allowlist** ensures only *you* can submit.

### Credential broker (future)
- **What it is:** a small **native macOS helper** — the only reader of the **Keychain**.
- **Its job here:** perform the few *credentialed* actions (e.g. the X API fetch for tweets, or any
  send) so secrets never enter n8n. Deterministic, allowlisted, approval-gated — **not** an AI.
- **Status:** not built yet. Plain-URL capture needs no secrets, so v1 ships without it.

---

## What you bring (not installed by this repo)

### Notesage — the second brain
- **What it is:** your local-first AI workspace (Tauri/Rust) — notes, a bundled local model, agents,
  MCP, an SQLite FTS5 index, and filesystem/network sandboxing. It is the "private core."
- **Its job here:** **reads and indexes the capture folder** (the airlock) and is the UI/brain. It
  holds no send credentials, so even a poisoned captured file can't exfiltrate through it.
- **Why external:** you already install it (possibly on a different Mac), so bundling it makes no
  sense. airlocked-agents integrates by writing files it indexes.

### Claude + MCP (optional cloud)
- The strong cloud model for *public, non-sensitive* work, reached outbound-only. Sensitive
  summarising stays on the local Gemma.

---

## The pattern, restated

| Component | Reads untrusted? | Holds credentials? | Can send/exfiltrate? |
|---|---|---|---|
| llama.cpp (Gemma) | the text it's given | no | no (localhost) |
| n8n | yes (web/tweets) | **no** (broker will) | only *writes local files*; egress is fetch-only |
| broker (future, native) | no | yes (Keychain) | yes — but deterministic + allowlisted + **not an AI** |
| Notesage (external) | yes (notes + captures) | no send creds | no (reads the airlock) |
| Claude + MCP (optional) | public only | vendor-managed | supervised |

No row holds all three. The web-reader (n8n) holds no secrets and only writes files; the brain
(Notesage) reads untrusted captures but can't send; the secret-holder (broker) isn't an AI. The
**capture folder is the airlock** between them.
