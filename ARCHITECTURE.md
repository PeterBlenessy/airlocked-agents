# Architecture

airlocked-agents is the **local, no-inbound automation + capture layer for [Notesage](https://github.com/PeterBlenessy/note-sage)**. It does the two things Notesage doesn't (yet): run **scheduled / event-triggered jobs**, and let you **capture a URL or tweet from your phone** into your knowledge base — summarising both with a **local model** and dropping the result into a folder Notesage indexes.

It is **not** a second brain and does **not** bundle one — Notesage is that, and you install it yourself. This repo is the glue around it.

## The governing rule (unchanged)

> **No single component may simultaneously (a) read untrusted content, (b) hold credentials, and (c) send data outward.**

The "lethal trifecta" (Simon Willison, 2025). Everything below is arranged so the components that touch the untrusted internet hold no secrets and can't exfiltrate, and the component that holds secrets isn't a hijackable AI.

## The pieces (all on one Mac mini, except the cloud)

```
PHONE  ── share URL/tweet ──▶  Telegram bot          (capture from anywhere; zero inbound)
MAC MINI
  n8n            scheduled + event jobs AND Telegram capture (polls getUpdates — no inbound).
                 Reads the untrusted web, summarises via the local model, writes files.
                 Holds NO secrets. Egress only to fetch sources.
  llama.cpp      local model (Google Gemma, instruct) on 127.0.0.1:8080 — the summariser.
  broker         (future) native macOS helper: the ONLY reader of the Keychain; performs the
                 few credentialed actions (e.g. X API fetch) so secrets never enter n8n.
  ── writes ──▶  THE FOLDER  ◀── indexes ──  Notesage   (your second brain — separate app)
CLOUD (optional) Claude/MCP for public research only.
```

- **macOS Keychain** holds every secret. Neither n8n nor Notesage stores keys; the native **broker** is the only thing that reads Keychain and acts on them.
- **The folder is the airlock:** n8n only ever *writes* to it; Notesage only ever *reads* it. One-way, file-mediated.

## The two flows

**Capture (mobile → knowledge):**
```
phone Share → Telegram bot → n8n polls getUpdates → fetch URL + extract + summarise (local Gemma)
  → write {title, source, date, tags, summary, body}.md → THE FOLDER → Notesage indexes it
```

**Scheduled / event jobs:**
```
cron/RSS/market trigger (or a watched-folder change) → n8n fetch + summarise → file → THE FOLDER
```

## Trifecta audit

| Component | Reads untrusted? | Holds credentials? | Can send/exfiltrate? |
|---|---|---|---|
| n8n | yes (web, tweets) | **no** (broker does) | only *writes local files*; egress is fetch-only |
| llama.cpp (Gemma) | the text it's given | no | no (localhost) |
| broker (native) | no | yes (from Keychain) | yes — but **not an AI**; deterministic + allowlisted + approved |
| Notesage | yes (your notes + the ingested files) | no send creds | no (it's the reader of the airlock) |
| Claude/MCP (optional) | public only | vendor-managed | supervised |

No hijackable agent has all three. A poisoned article can at worst make a *summary* wrong; the thing that reads that summary (Notesage) can't send, and the thing that can send (broker) isn't an AI.

## Why Telegram

It's the **mobile capture transport**: your phone's Share Sheet → the bot → n8n *polls* it. That gives you "send this to my brain from anywhere" with **no public inbound port** — the whole reason it's here. (It can also carry notifications/approvals later.)

## What this repo installs vs. what you bring

- **Installs/runs:** n8n (container), llama.cpp + a local Gemma model, the folder contract, (later) the broker.
- **You bring:** Notesage (the brain/UI/indexer), and a Telegram bot token.

## Open questions (being decided)

1. **Local model:** which Gemma — version (3 vs 4 if available) and size (4B / 12B / 27B)? Summarising wants quality-per-RAM; 4B–12B instruct is the likely sweet spot. Exact GGUF repo/file TBD.
2. **One model or share Notesage's?** Notesage already bundles a `llama-server`. Do we run a *dedicated* llama.cpp here, or point n8n at Notesage's? (Avoids two model servers, but couples the two apps.)
3. **The folder contract:** where does it live (inside Notesage's indexed dir?), and what file/frontmatter format does Notesage index best?
4. **Broker now or later?** v1 could handle only public URLs (no secrets, no broker); tweets/X need the X API (→ broker). Ship plain-URL capture first?
5. **Event triggers:** "document changes" implies n8n watches the folder — requires mounting it into the n8n container.
6. **Does the guided installer/teardown still fit** now that scope is just n8n + model + folder, with Notesage external?

## Where to go next
- What each component is and why: [`COMPONENTS.md`](COMPONENTS.md).
- Build/run: [`README.md`](README.md).
- Threat model: [`SECURITY.md`](SECURITY.md).
