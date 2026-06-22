# Contributing

Thanks for improving this stack. The bar here is unusual: changes are judged first on whether they preserve the security architecture, and only then on whether they work.

## The one rule that overrides everything

**No change may put a single component in a position to simultaneously (a) read untrusted content, (b) hold credentials, and (c) send data outward.** That decomposition is the whole point. A PR that merges the drafting agent with the sending credential, removes the approval gate, or drops the recipient allowlist will be rejected even if it "works."

If your change touches the mail/Telegram paths, the model routing, or any send capability, say in the PR description how the trifecta stays broken.

## Conventions

- **Code, comments, variable names: English.** No exceptions.
- **Secrets never enter the repo.** They live in `.env` (gitignored) and `secrets/`. Only `.env.example` is committed, with placeholders.
- **Idempotency.** Ansible tasks and scripts must converge to the same state on re-run. Prefer declarative modules over raw `shell`/`command`; when you must shell out, set `creates:`/`changed_when:` appropriately.
- **Pin versions** for reproducibility (image tags in `.env`, package versions in the `Brewfile`) rather than `latest` where it matters.
- **Localhost by default.** Anything that listens binds to `127.0.0.1` unless it has a deliberate reason not to.

## Before you open a PR

Run the local checks:

```bash
make lint      # ansible + compose sanity
make verify    # health + boundary checks (needs the stack running)
```

And, if you changed any workflow or send path, run the most important test by hand:

```bash
# See scripts/injection-selftest.md — the prompt-injection self-test.
```

CI (`.github/workflows/ci.yml`) will re-run syntax checks, Compose validation, JSON/shell
parsing, and a guard that fails if a secret file was committed. `ansible-lint` and `shellcheck`
run as advisory (non-blocking) — please still read their output and address what's reasonable.

## PR checklist

- [ ] Code/comments in English; no secrets committed (`git status` is clean of `.env`, keys, `*.conf`).
- [ ] Trifecta still broken — explained in the description if send paths changed.
- [ ] Tasks are idempotent; `make lint` passes.
- [ ] If applicable, the injection self-test still produces the correct (no-send) outcome.
- [ ] Versions pinned where reproducibility matters.

## Scope

This repo is deliberately small and single-purpose: deterministic setup of the documented stack. Large new components belong in their own modules or repos; here we keep the surface minimal and auditable.
