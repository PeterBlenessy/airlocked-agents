# airlocked-agents

**Deterministic IaC for a private, self-hosted AI automation stack — untrusted content stays in the airlock.**

Idempotent setup for the architecture described in *The Recommended Setup — Architecture & Build Guide*: a local model + second brain on your Mac, an n8n automation glue and a sandboxed Suna research rig on a VPS, wired through a private tunnel, with Claude + MCP used cloud-side for public work only.

The whole point of this repo is to keep one rule true automatically: **no single component reads untrusted content, holds your credentials, and can send — all at once.**

> Architecture, trust zones, and data flows: see [`ARCHITECTURE.md`](ARCHITECTURE.md).
> Threat model and how to report issues: see [`SECURITY.md`](SECURITY.md).
> How to contribute: [`CONTRIBUTING.md`](CONTRIBUTING.md) · [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

**Topics** (set automatically by `make repo`, or add them in the GitHub UI):
`infrastructure-as-code` · `ansible` · `docker-compose` · `self-hosted` · `ai-agents` · `privacy` · `security` · `llm` · `local-first` · `n8n` · `mcp` · `homelab` · `prompt-injection` · `automation` · `llama-cpp`

Not to be confused with [`NevaMind-AI/airlock`](https://github.com/NevaMind-AI/airlock) — that's a Python egress-guard *library* you embed; this is a deployed *stack* you run.

---

## What is deterministic vs. what is manual (read this first)

Honest IaC draws the line clearly. This repo does too.

**Fully deterministic + idempotent (run as many times as you like):**
- All package installs (Homebrew on the Mac, Docker on the VPS).
- The container stacks (n8n, Khoj) via Docker Compose.
- Every config file, rendered from templates with your variables.
- Service enablement (launchd on Mac, systemd/Compose on VPS).
- The VPS firewall (ufw) and the Mac↔VPS WireGuard tunnel.
- n8n credential placeholders and workflow import scaffolding.

**Manual, one-time, by design (cannot be deterministic — interactive consent):**
- **Gmail OAuth** — Google requires browser consent; you create the OAuth app and paste client id/secret, then authorize once in the n8n UI.
- **Telegram bot token** — created interactively via `@BotFather`.
- **Supabase project** for Suna — create the project (cloud or self-hosted) and paste its keys.
- **Model download** — scriptable (`make model`) but it is a multi-GB file, so it is opt-in.
- **VPS provisioning** — bring your own host; an optional Terraform module is noted but not vendor-locked here.

Everything manual is reduced to filling `.env` and a 5-item checklist in `docs-MANUAL-STEPS.md`. Nothing secret is ever committed.

---

## Prerequisites

- A Mac (Apple Silicon assumed) with Homebrew, and Docker Desktop.
- A small Linux VPS you can SSH into (Debian/Ubuntu assumed), 2 GB RAM is enough for n8n; Suna wants ~16 GB or a separate box.
- `ansible` and `make` on the machine you run this from (`brew install ansible make`).
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
│   ├── inventory.ini        # localhost (mac) + your vps host
│   ├── mac.yml              # llama.cpp + tunnel proxy + Khoj + Open Interpreter + Cua* + launchd
│   └── vps.yml              # docker + n8n + firewall + wireguard + suna clone
├── compose/
│   ├── n8n.yml              # n8n Community Edition, locked down
│   └── khoj.yml             # Khoj pointed at your local model
├── mac/
│   ├── Brewfile             # declarative Mac packages
│   ├── com.local.llama-server.plist.tmpl    # the model, 127.0.0.1 only
│   ├── com.local.llama-tunnel.plist.tmpl    # socat proxy: model on the WG interface only
│   └── download-model.sh
├── n8n/
│   ├── allowlist.code.js    # canonical chat-id + recipient guard (embedded into the write path)
│   ├── workflow.read-path.json    # importable skeleton (verify in editor)
│   └── workflow.write-path.json   # write path with the guard inlined
├── wireguard/
│   ├── wg0.mac.conf.tmpl
│   └── wg0.vps.conf.tmpl
├── scripts/
│   ├── setup.sh             # the guided installer (`make setup`) — start here
│   ├── verify.sh            # health + boundary checks (binding, exact firewall, guard test)
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
install what's missing, collects config with live validation, **generates your WireGuard keys**,
and runs everything in the right order:

```bash
make setup                    # interactive, idempotent — start here
```

`make doctor` reports what's present/missing without changing anything. Re-run `make setup`
any time to change values or finish skipped steps.

<details>
<summary>Prefer to drive it yourself? The individual targets:</summary>

```bash
cp .env.example .env          # then edit .env with your values
make help                     # list targets
make mac                      # provision the Mac (idempotent)
make vps                      # provision the VPS (idempotent, over public SSH)
make tunnel                   # bring up the WireGuard link
make harden                   # lock VPS SSH to the tunnel (after the tunnel is up; recommended)
make workflows                # import the n8n workflow skeletons
make verify                   # run health + boundary checks
```
</details>

Each target is safe to re-run; Ansible converges to the declared state. To tear down the container stacks: `make down`.

What stays manual even with `make setup`: the interactive consent steps that *cannot* be
automated — clicking **Connect** on the Gmail OAuth credential in the n8n editor, creating the
Telegram bot in `@BotFather`, and running Suna's setup wizard. `make setup` walks you up to each
and validates what it can (e.g. it tests your Telegram token and auto-detects your chat id).

## The determinism guarantee, restated

`make mac && make vps && make tunnel` converges the same way every time from a clean host, given the same `.env`. The only things it cannot create for you are the three interactive secrets above — and that is a property of OAuth and bot registration, not a limitation of this repo. See `docs-MANUAL-STEPS.md`.

## Security notes baked in

- Local services (llama.cpp, Khoj) bind to `127.0.0.1`; the model is re-exposed to the VPS only on the WireGuard tunnel interface — verified by `make verify`.
- The VPS firewall allows exactly three inbound rules — SSH (22), HTTPS (443), WireGuard (UDP) — with HTTPS the only application ingress; `make verify` asserts the exact set. After `make harden`, SSH is locked to the WireGuard tunnel peer (no public SSH).
- The n8n write path is credential-isolated and human-gated; the allowlist guard is embedded directly in `n8n/workflow.write-path.json` (canonical source: `n8n/allowlist.code.js`), so an import is guarded out of the box.
- Sensitive research routes to the local model over the tunnel (via a socat proxy on the Mac); nothing private egresses to the cloud.
- `make verify` runs the allowlist guard self-test (`scripts/injection-selftest.sh`); the full end-to-end prompt-injection test is manual — see `scripts/injection-selftest.md`.

Commands and image tags drift; pin versions in `.env` and re-run `make verify` after upgrades.
