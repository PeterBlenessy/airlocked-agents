# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims to
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Added
- `bootstrap-repo.sh` now sets GitHub topics and the repo description automatically.
- Tunnel-only model proxy: `mac/com.local.llama-tunnel.plist.tmpl` (socat) re-exposes the
  localhost model on the WireGuard interface so the VPS can route sensitive research to the
  local model over the tunnel. `LOCAL_MODEL_BASE_URL` / `LOCAL_MODEL_API_KEY` added to `.env`.
- `scripts/injection-selftest.sh`: automated allowlist-guard unit test, now run by `make verify`.
- `.devcontainer/`: a Linux dev environment mirroring CI (Python 3.12, ansible + ansible-lint +
  community.general, docker compose, shellcheck, node) for validating the IaC locally.
- SSH hardening: `make harden` locks VPS SSH (22) to the WireGuard tunnel peer
  (`MAC_TUNNEL_IP/32`) plus an optional `ADMIN_IP` break-glass, removing public SSH. Driven by
  `SSH_HARDENED` in `.env`; ansible inventory and `make verify` then manage the box over
  `VPS_TUNNEL_IP`. A WireGuard-handshake safety gate aborts hardening if the tunnel isn't up,
  so it can't lock you out. `make verify` asserts SSH is tunnel-only when hardened.

### Changed
- The write-path workflow now embeds the allowlist guard inline (was a paste-me placeholder),
  so an import is guarded out of the box.
- `make verify` now allows the WireGuard tunnel interface for the model, asserts the VPS
  firewall is exactly {SSH, HTTPS, WireGuard}, and runs the guard self-test.

### Fixed
- Docs now match reality: the VPS firewall has three inbound rules (not one); `make verify`
  runs an automated guard test (the full injection test remains manual); the local-model-over-
  tunnel path is implemented rather than only described.
- `Brewfile`: add `socat` and `node`; drop the invalid `wireguard-tools` cask line.
- Removed a duplicate `bootstrap-repo.sh` at the repo root (canonical copy is `scripts/`).
- `make repo` no longer requires `.env` (you publish before configuring it).
- `bootstrap-repo.sh` now respects `gh`'s configured git protocol (was hardcoded to SSH,
  which broke HTTPS-only `gh` setups) and runs `gh auth setup-git` before pushing.

## [0.1.0] — 2026-06-21
### Added
- Initial infrastructure-as-code for the privacy-first automation stack.
- Ansible playbooks for the Mac private core (`mac.yml`) and the VPS glue/research rig (`vps.yml`).
- Docker Compose stacks for n8n and Khoj, locked to localhost.
- macOS `Brewfile`, launchd template for `llama-server`, and a model-download script.
- n8n workflow skeletons (read path, gated write path) and the allowlist guard Code node.
- WireGuard templates for the Mac↔VPS tunnel.
- `make verify` health and security-boundary checks; the prompt-injection self-test.
- GitHub Actions CI (syntax check, Compose validation, JSON/shell parsing, secret guard).
- `ARCHITECTURE.md`, `SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `docs-MANUAL-STEPS.md`.
- `gh`-based `bootstrap-repo.sh` and `make repo` target.

### Security
- Enforces the lethal-trifecta decomposition: no component reads untrusted content,
  holds credentials, and can send simultaneously. CI fails if a secret-like file is committed.

[Unreleased]: https://github.com/OWNER/airlocked-agents/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/OWNER/airlocked-agents/releases/tag/v0.1.0
