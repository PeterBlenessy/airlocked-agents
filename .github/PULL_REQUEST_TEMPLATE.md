## What this changes

<!-- Brief description of the change and why. -->

## Security boundary check (required)

- [ ] This change does **not** let any single component read untrusted content, hold credentials, and send — all at once.
- [ ] If it touches mail/Telegram, model routing, or any send path, I explain below how the trifecta stays broken.
- [ ] No secrets committed (`git status` clean of `.env`, keys, `*.conf`).

<!-- If send paths changed, explain the decomposition here: -->

## Quality

- [ ] Code/comments in English.
- [ ] Tasks are idempotent; `make lint` passes.
- [ ] Versions pinned where reproducibility matters.
- [ ] If a workflow changed, the prompt-injection self-test still produces a no-send outcome.
