# Security Policy

This project is a security architecture as much as a setup. Its purpose is to contain the inherent risk of agentic AI by keeping the "lethal trifecta" broken (see `ARCHITECTURE.md`). This document states the threat model, the guarantees and non-guarantees, and how to report a problem.

## Reporting a vulnerability

Please **do not** open a public issue for a security problem. Report privately:

- Email: `peter.blenessy@gmail.com`
- Or use GitHub's private vulnerability reporting (Security → Report a vulnerability).

Include what you found, how to reproduce it, and the impact. Expect an acknowledgement within a few days. Coordinated disclosure is appreciated; credit is given unless you prefer otherwise.

## Threat model

The system is designed against four threats, in rough order of likelihood:

1. **Indirect prompt injection** — an attacker hides instructions in content the stack will read (email, web page, calendar invite, message). This is the primary threat. Mitigation: the reading/drafting agent holds no credentials and no send-path; sending is a separate, human-gated, allowlisted step.
2. **Credential / secret leakage** — secrets reaching a model's context or a tracked file. Mitigation: credentials live only in n8n's encrypted vault or the gitignored `secrets/`; CI fails if a secret-like file is committed; local model uses a throwaway token.
3. **Over-broad / irreversible action** — an unintended send, delete, or payment. Mitigation: every irreversible action pauses for explicit human approval; recipients are allowlisted; risky components are sandboxed.
4. **Supply-chain compromise** — a malicious dependency, MCP server, or community skill. Mitigation: pinned versions, least privilege per component, and a preference for auditable open-source pieces. Review anything you add.

### Explicitly out of scope (you own these)

- The security of the cloud providers themselves (Anthropic, Google) and your accounts with them.
- Physical access to your Mac or VPS, and OS-level compromise of those hosts.
- Secrets you choose to place outside the vault, or workflows you modify to violate the invariants.

## What this repo does and does not guarantee

**Does:** make the secure configuration the default and the easy path; enforce the structural invariants in `ARCHITECTURE.md` via `make verify` and CI; keep the trifecta broken across components as shipped.

**Does not:** make agentic AI "safe" in an absolute sense. Prompt injection has no complete fix; content filters top out around 97% on known patterns. The protection here is structural — no single component can complete an exfiltration on its own — not a promise that no model will ever follow a malicious instruction. If you merge components or remove a gate, the guarantees do not hold.

## Operating securely

- Run `make verify` after every change (it runs the automated allowlist-guard self-test); run the full end-to-end prompt-injection test (`scripts/injection-selftest.md`) by hand after any workflow change.
- Keep local services bound to `127.0.0.1` (the model is re-exposed to the VPS only on the WireGuard interface); keep the VPS firewall at its three inbound rules — SSH, HTTPS, WireGuard — with 443 the only application ingress. Consider restricting SSH (22) to the tunnel or a known admin IP to shrink the public surface further.
- Route anything client-confidential to the local model; never to a cloud model.
- Back up the n8n encryption key offline; rotate OAuth scopes to the minimum needed.
- Pin image tags and package versions; review Dependabot PRs for the GitHub Actions you use.

## Supported versions

This is a template repository; security fixes are applied to `main`. Pin and track `main` for updates.
