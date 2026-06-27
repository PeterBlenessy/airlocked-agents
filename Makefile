# airlocked-agents — Makefile entrypoint
# All targets are idempotent. Run `make help` for the list.

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Load .env if present so targets can reference variables.
ifneq (,$(wildcard ./.env))
include .env
export
endif

ANSIBLE := ansible-playbook -i ansible/inventory.ini

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[1m%-14s\033[0m %s\n", $$1, $$2}'

.PHONY: setup
setup: ## Guided, interactive setup — checks the system, collects config, provisions (start here)
	bash scripts/setup.sh

.PHONY: doctor
doctor: ## Report what's installed/missing for a setup, then exit
	bash scripts/setup.sh --doctor

.PHONY: setup-dryrun
setup-dryrun: ## Preview a setup: show exactly what would be installed/changed, touching nothing
	bash scripts/setup.sh --dry-run

.PHONY: teardown
teardown: ## Reverse what `make setup` did (replays the manifest; never touches tools you already had)
	bash scripts/teardown.sh

.PHONY: check-env
check-env: ## Fail early if .env is missing
	@test -f .env || { echo "Missing .env — run 'make setup' (guided) or: cp .env.example .env && edit it"; exit 1; }

.PHONY: mac
mac: check-env ## Provision the Mac mini: llama.cpp, Khoj+Postgres, n8n, Open Interpreter, Cua (idempotent)
	$(ANSIBLE) ansible/mac.yml --limit mac

.PHONY: model
model: check-env ## Download the local GGUF model (multi-GB, opt-in)
	bash mac/download-model.sh

.PHONY: workflows
workflows: check-env ## (Re)import the n8n workflow skeletons
	bash mac/n8n-runtime.sh up

.PHONY: down
down: ## Stop the container stacks (Khoj, n8n)
	$(ANSIBLE) ansible/mac.yml --limit mac --tags down || true

.PHONY: verify
verify: check-env ## Run health + security boundary checks
	bash scripts/verify.sh

.PHONY: repo
repo: ## Init git + create & push the GitHub repo (via gh). Usage: make repo [NAME=airlocked-agents] [VIS=private]
	bash scripts/bootstrap-repo.sh $(or $(NAME),airlocked-agents) $(or $(VIS),private)

.PHONY: lint
lint: ## Sanity-check Ansible and Compose files
	@command -v ansible-lint >/dev/null && ansible-lint ansible/*.yml || echo "ansible-lint not installed (optional)"
	@docker compose -f compose/n8n.yml config -q && echo "compose/n8n.yml OK"
	@docker compose -f compose/khoj.yml config -q && echo "compose/khoj.yml OK"
