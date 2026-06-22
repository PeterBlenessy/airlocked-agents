# Dev container

A Linux development environment that mirrors CI (`.github/workflows/ci.yml`), so you can
validate the IaC locally before pushing and get the same results CI will.

## What's inside

- **Python 3.12** + `ansible`, `ansible-lint`, and the `community.general` collection — same as CI.
- **docker-in-docker** — so `docker compose config` (the Compose validation gate) works.
- **node (LTS)** — runs the allowlist guard self-test (`scripts/injection-selftest.sh`) and `npm`.
- **shellcheck, jq, make, gh** — for `make lint`, `make verify`, and `make repo`.

## Using it

Open the repo in VS Code → **Reopen in Container** (Dev Containers extension), or use
GitHub Codespaces / the `devcontainer` CLI. Then, from the integrated terminal:

```bash
make lint                                              # ansible + compose sanity
ansible-playbook -i ansible/inventory.ini ansible/mac.yml --syntax-check
ansible-playbook -i ansible/inventory.ini ansible/vps.yml --syntax-check
bash scripts/injection-selftest.sh                     # the automated guard test
```

## What it is NOT for

This container validates and lints the IaC; it does **not** run the stack.

- `make mac` targets macOS (Homebrew, launchd) and cannot run in this Linux container — run it
  on the Mac itself.
- `make vps` / `make tunnel` provision your real VPS over SSH and need your `.env` + keys.

Treat the container as the place to catch syntax/lint/parse errors (like the kind CI gates on),
not as a substitute for the hosts the stack actually deploys to.
