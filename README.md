# airlocked-agents

**Deterministic IaC for a private, self-hosted AI automation stack — untrusted content stays in the airlock.**

Idempotent setup of a private, self-hosted AI stack on **one dedicated, always-on Mac mini**: a
local model + second brain (Khoj), an n8n automation orchestrator, and per-action computer control —
everything in Apple `container` or native launchd, with **no public inbound** (Telegram is polled).
Claude + MCP are used cloud-side for public work only.

The whole point of this repo is to keep one rule true automatically: **no single component reads untrusted content, holds your credentials, and can send — all at once.**

> What each component is and why it was chosen: see [`COMPONENTS.md`](COMPONENTS.md).
> Architecture and data flows (single-box): see [`ARCHITECTURE.md`](ARCHITECTURE.md).
> Threat model and how to report issues: see [`SECURITY.md`](SECURITY.md).
> How to contribute: [`CONTRIBUTING.md`](CONTRIBUTING.md) · [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

**Topics** (set automatically by `make repo`, or add them in the GitHub UI):
`infrastructure-as-code` · `ansible` · `docker-compose` · `self-hosted` · `ai-agents` · `privacy` · `security` · `llm` · `local-first` · `n8n` · `mcp` · `homelab` · `prompt-injection` · `automation` · `llama-cpp`

Not to be confused with [`NevaMind-AI/airlock`](https://github.com/NevaMind-AI/airlock) — that's a Python egress-guard *library* you embed; this is a deployed *stack* you run.

---

## What is deterministic vs. what is manual (read this first)

Honest IaC draws the line clearly. This repo does too.

**Fully deterministic + idempotent (run as many times as you like):**
- All package installs (Homebrew) and the container runtime (Apple `container`, or Colima).
- The containers (llama.cpp native; Khoj + Postgres + n8n) with fixed networks and named volumes.
- Khoj's host-only (no-egress) network; n8n's localhost-only UI; the llama bridge proxy.
- Service enablement (launchd) and the n8n workflow import.

**Manual, one-time, by design (cannot be deterministic — interactive consent):**
- **Telegram bot token** — created interactively via `@BotFather` (reached by polling, no webhook).
- **n8n owner account** — created once in the n8n UI on first visit (localhost).
- **Gmail OAuth** — Google requires browser consent; create the OAuth app, paste client id/secret, authorize once in the n8n UI.
- **Model download** — scriptable (`make model`) but a multi-GB file, so opt-in.

Everything manual is reduced to filling `.env` and the short checklist in `docs-MANUAL-STEPS.md`. Nothing secret is ever committed.

---

## Prerequisites

- A **dedicated, always-on Mac mini** (Apple Silicon) with Homebrew — ideally not your daily-driver with personal files. Enough RAM for the model + Khoj + Postgres + n8n (16 GB works; 24 GB+ comfortable).
- macOS 26+ for the default container runtime (**Apple `container`**, installed for you). On older macOS it falls back to **Colima**; set `CONTAINER_RUNTIME=docker` to use Docker Desktop instead.
- `ansible` and `make` (`brew install ansible make`) — or just run `make setup`, which installs what's missing.
- Your llama.cpp model file (or run `make model` to fetch one).

## Layout

```
airlocked-agents/
├── Makefile                 # the entrypoint — see `make help`
├── README.md
├── CONTRIBUTING.md          # the security-first contribution bar
├── LICENSE                  # MIT
├── docs-MANUAL-STEPS.md     # the irreducible interactive steps
├── .env.example             # copy to .env and fill in
├── .devcontainer/           # Linux dev env mirroring CI (lint/validate the IaC locally)
│   └── devcontainer.json
├── .github/workflows/
│   └── ci.yml               # syntax + compose + json/shell checks + secret guard
├── ansible/
│   ├── inventory.ini        # localhost (the Mac mini) only
│   └── mac.yml              # llama.cpp + Khoj + n8n + Open Interpreter + Cua* + launchd
├── compose/
│   ├── n8n.yml              # n8n, localhost-only (Colima/Docker fallback path)
│   └── khoj.yml             # Khoj + Postgres (Colima/Docker fallback path)
├── mac/
│   ├── Brewfile             # declarative Mac packages
│   ├── com.local.llama-server.plist.tmpl    # the model, 127.0.0.1 only
│   ├── khoj-runtime.sh      # Khoj + Postgres up/down (Apple container / compose)
│   ├── n8n-runtime.sh       # n8n up/down + workflow import (Apple container / compose)
│   └── download-model.sh
├── n8n/
│   ├── allowlist.code.js    # canonical chat-id + recipient guard (embedded into the write path)
│   ├── workflow.read-path.json    # importable skeleton (verify in editor)
│   └── workflow.write-path.json   # write path with the guard inlined
├── scripts/
│   ├── setup.sh             # the guided installer (`make setup`) — start here
│   ├── teardown.sh          # reverses setup via its manifest (`make teardown`)
│   ├── verify.sh            # health + boundary checks (binding, no-egress, guard test)
│   ├── injection-selftest.sh      # automated guard unit test (run by make verify)
│   ├── bootstrap-repo.sh    # git init + gh repo create + push (with secret guard)
│   └── injection-selftest.md      # the manual end-to-end injection test
└── secrets/                 # gitignored; your keys live here, never committed

* Cua install is best-effort (the npm package name is unverified upstream); see ansible/mac.yml.
```

## Publishing to GitHub

```bash
make repo                       # uses the gh CLI: init, commit, create, push
# or with options:
make repo NAME=my-stack VIS=public
```

The bootstrap script refuses to commit if any secret-like file (`.env`, keys, rendered
`*.conf`) is staged, and asks for confirmation before creating the remote. CI then runs on
every PR (`.github/workflows/ci.yml`).

## Quick start

The low-friction path is one command — a guided installer that checks your system, offers to
install what's missing, collects config with live validation, and brings up the whole local stack:

```bash
make setup                    # interactive, idempotent — start here
```

`make doctor` reports what's present/missing without changing anything. Re-run `make setup`
any time to change values or finish skipped steps.

Nervous about running it? **`make setup-dryrun`** runs the whole wizard and prints exactly what it
*would* install, change, and write to `.env` — installing nothing, writing nothing, touching nothing.

<details>
<summary>Prefer to drive it yourself? The individual targets:</summary>

```bash
cp .env.example .env          # then edit .env with your values
make help                     # list targets
make model                    # download the GGUF model (multi-GB, opt-in)
make mac                      # provision the mini: llama.cpp, Khoj+Postgres, n8n (idempotent)
make workflows                # (re)import the n8n workflow skeletons
make verify                   # health + boundary checks
```
</details>

Each target is safe to re-run; Ansible converges to the declared state. To stop the container stacks: `make down`.

### Uninstall / rollback

`make setup` writes a **transactional manifest** (`.airlocked/manifest.tsv`, gitignored) recording
every change it makes — and it records a package as installed *only if it was absent beforehand*.

```bash
make teardown     # replays the manifest in reverse, undoing only what setup did
```

Because it follows the manifest rather than guessing, `make teardown` removes the services,
containers, volumes, launchd agents, model file, and the container runtime that setup created — but
**never uninstalls tools you already had**. Every destructive step asks first. (`make down` just
stops the container stacks; `make teardown` is the full reversal.)

What stays manual even with `make setup`: the interactive consent steps that *cannot* be
automated — creating the Telegram bot in `@BotFather`, the n8n owner account, and clicking
**Connect** on the Gmail OAuth credential in the n8n editor. `make setup` walks you up to each and
validates what it can (e.g. it tests your Telegram token and auto-detects your chat id).

## The determinism guarantee, restated

`make mac` converges the same way every time from a clean mini, given the same `.env`. The only
things it cannot create for you are the interactive secrets above — a property of OAuth and bot
registration, not a limitation of this repo. See `docs-MANUAL-STEPS.md`.

## Security notes baked in

- All services listen on `127.0.0.1` or the host-only container-network gateway (the llama bridge) — **never a public interface, and no public inbound** (Telegram is polled). Verified by `make verify`.
- Khoj runs on a host-only (`--internal`) network → **no internet egress** — the "can send" trifecta leg is removed for the content-reader. `make verify` checks it.
- The n8n write path is credential-isolated and human-gated; the allowlist guard is embedded directly in `n8n/workflow.write-path.json` (canonical source: `n8n/allowlist.code.js`), so an import is guarded out of the box.
- Sensitive work routes to the local model; nothing private egresses to the cloud.
- `make verify` runs the allowlist guard self-test (`scripts/injection-selftest.sh`); the full end-to-end prompt-injection test is manual — see `scripts/injection-selftest.md`.

Commands and image tags drift; pin digests in `.env` and re-run `make verify` after upgrades.
