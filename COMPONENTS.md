# Components

What each part of the stack actually *is*, the job it does here, and why it was chosen over the
obvious alternatives. For how the parts connect (trust zones, data flows, the firewall posture),
see [`ARCHITECTURE.md`](ARCHITECTURE.md); for the threat model, [`SECURITY.md`](SECURITY.md).

**The selection principle.** Every component is open-source, self-hostable, and auditable — and,
crucially, each occupies exactly *one* corner of the "lethal trifecta" (read untrusted content /
hold credentials / send outward). Tools were chosen as much for **what they're not allowed to do**
as for what they do.

---

## Zone A — Your Mac (the private core)

### llama.cpp
- **What it is:** an open-source LLM inference engine (by Georgi Gerganov), written in C/C++. It
  runs quantized open-weight models (the GGUF format) efficiently on consumer hardware, including
  Apple Silicon via Metal, and ships a small `llama-server` with an **OpenAI-compatible API**.
- **Its job here:** the **local brain** — answers anything private, on your Mac, with nothing
  leaving the machine. Bound to `127.0.0.1` only.
- **Why it over alternatives:** Ollama and LM Studio are friendlier wrappers but heavier and more
  opinionated; vLLM is server-grade but CUDA/NVIDIA-centric, not Mac. llama.cpp is a single
  auditable native binary with the best Metal support, and its OpenAI-compatible endpoint means
  Khoj and Suna talk to it with **no custom code** (they think it's "OpenAI").

### Khoj
- **What it is:** an open-source "AI second brain." Point it at your own documents/notes/PDFs; it
  indexes them and lets you **search and chat with your own knowledge** (RAG — retrieval-augmented
  generation). Works with local or cloud models.
- **Its job here:** your private knowledge assistant — answers *from your documents* using the
  local llama.cpp model, so your files and queries never reach the cloud. Your docs are mounted
  **read-only**; it binds to `127.0.0.1` only.
- **Why it over alternatives:** rolling your own (Obsidian + a vector DB + glue) is a lot of
  assembly; cloud second brains (Mem, Notion AI) send your notes off-device — disqualifying here.
  Khoj is self-hostable, does indexing + RAG out of the box, and can point at a local model.
- **Why containerized (vs a pip venv):** Khoj ingests content and pulls a large dependency tree,
  so a container's *capability* isolation (read-only doc mount, no host access) serves the security
  goal — a venv would run it with your full user privileges.

### Open Interpreter
- **What it is:** an open-source tool that lets an LLM **write and run code/shell on your machine**
  from natural language — a local "code interpreter" that can actually touch your computer. It asks
  for confirmation before running.
- **Its job here:** the "do things on my Mac" hands — run scripts, automate local tasks — **gated
  by per-action approval**, which is its safety model.
- **Why it over alternatives:** most agent frameworks (e.g. LangChain) are libraries you build
  with; Open Interpreter is a ready-to-use local executor with a human-approval loop, fitting the
  "powerful but gated" slot.

### Cua
- **What it is:** a **computer-use agent** driver — software that lets an AI control a computer's
  GUI (mouse, keyboard) the way a person would. Exposed here over MCP so other components can drive
  it.
- **Its job here:** GUI automation for tasks that have no API.
- **Why it over alternatives:** computer-use is a young area and Cua is one of the few open
  drivers. Honest caveat: it's the **least mature** piece — installed "best-effort" and optional,
  precisely because the ecosystem isn't settled.

---

## Zone B — The VPS (automation glue + research sandbox)

### n8n
- **What it is:** an open-source **workflow automation** platform — a self-hosted alternative to
  Zapier/Make. You build flows visually as connected "nodes" (email arrives → summarize → ask me →
  send), and it has an **encrypted credential vault**.
- **Its job here:** the **orchestrator** tying mail, Telegram, and the models together — and the
  one component that legitimately *holds credentials and can send*. The design deliberately keeps
  the model out of that credential/send path. Bound to `127.0.0.1`, behind the reverse proxy.
- **Why it over alternatives:** Zapier/Make are cloud SaaS — your credentials would live on
  someone else's servers (disqualifying). Node-RED/Huginn are more DIY. n8n is self-hostable, has
  the credential vault, a big integration library, and a clean human-in-the-loop pattern — which is
  what lets "the AI drafts" and "a node sends" be *different* steps.

### Suna
- **What it is:** an open-source **generalist AI agent** (by Kortix AI) — give it a goal and it
  browses the web, gathers information, and produces a report. Often described as an open-source
  "Manus" alternative.
- **Its job here:** the **research rig** — reads the (untrusted) web, but runs **sandboxed with no
  inbox, no credentials, and no send path**, so a poisoned page can't make it exfiltrate. Public
  research goes to Claude; sensitive research is routed to your local model over the tunnel.
- **Why it over alternatives:** lighter research scripts (e.g. GPT-Researcher) are less
  full-featured; cloud agent products aren't self-hostable/sandboxable. Suna is open-source and can
  be isolated, fitting the "reads the web but can't leak" slot.

---

## Zone C — Cloud (public only, outbound)

### Claude + MCP
- **What it is:** **Claude** is Anthropic's family of LLMs (the strong cloud model). **MCP (Model
  Context Protocol)** is an open standard for connecting an LLM to external tools and data via
  "connector" servers — here Gmail, Calendar, Drive, Quartr.
- **Its job here:** the **public heavy-lifter** — the most capable model for *non-private* work,
  reached outbound-only, never shown private data and never allowed to act unsupervised.
- **Why it over alternatives:** for public tasks you want the strongest model; the safety isn't
  "trust the model," it's that this zone structurally never holds your secrets. MCP is chosen as the
  standardized, model-agnostic way to wire up tools.

---

## Supporting players

### Telegram (bot)
- **What it is:** a messaging app with a trivial, free **bot API** and webhook support.
- **Its job here:** your **command + notification channel** — you issue commands and receive
  drafts/alerts.
- **Why it / the catch:** chosen for the easy bot API and ubiquity. Because it's a *cloud* channel,
  the **chat-id allowlist** ensures only *you* can command the bot.

### Supabase
- **What it is:** an open-source "Firebase alternative" — Postgres + auth + storage.
- **Its job here:** **Suna's backend** (its supported dependency); can be cloud or self-hosted.

---

## The pattern, restated

| Component | Reads untrusted? | Holds credentials? | Can send? |
|---|---|---|---|
| llama.cpp | no | no | no |
| Khoj | your docs (sandboxed, read-only) | no | no |
| Open Interpreter | no | no | approved actions only |
| Cua | no | no | via orchestrator |
| n8n | yes (email/web) | yes (vault) | yes — human-gated + allowlisted |
| Suna | yes (web) | per-task only | no (drafts only) |
| Claude + MCP | yes (public only) | vendor-managed | supervised |

No row holds all three powers. llama.cpp/Khoj hold your private data but can't reach the internet;
Suna/Claude read the world but can't send; n8n can send but never lets the model hold its
credentials. That separation is the whole point.
